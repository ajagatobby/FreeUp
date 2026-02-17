//
//  DuplicateDetectionService.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import Foundation
import CryptoKit

/// A group of duplicate files sharing the same content
struct DuplicateGroup: Identifiable, Sendable {
    let id: UUID
    let hash: String
    let fileSize: Int64
    let files: [ScannedFileInfo]
    
    /// Space that can be reclaimed by keeping only one copy
    nonisolated var wastedSpace: Int64 {
        guard files.count > 1 else { return 0 }
        return fileSize * Int64(files.count - 1)
    }
    
    /// Number of duplicate copies (total - 1 original)
    nonisolated var duplicateCount: Int {
        max(0, files.count - 1)
    }
    
    /// Total space consumed by all copies
    nonisolated var totalSpace: Int64 {
        fileSize * Int64(files.count)
    }
    
    nonisolated init(id: UUID, hash: String, fileSize: Int64, files: [ScannedFileInfo]) {
        self.id = id
        self.hash = hash
        self.fileSize = fileSize
        self.files = files
    }
}

/// Progress update during duplicate detection
struct DuplicateDetectionProgress: Sendable {
    let phase: Phase
    let current: Int
    let total: Int
    let currentFile: String?
    
    enum Phase: Sendable {
        case groupingBySize
        case hashing
        case completed
    }
    
    nonisolated var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }
    
    nonisolated init(phase: Phase, current: Int, total: Int, currentFile: String?) {
        self.phase = phase
        self.current = current
        self.total = total
        self.currentFile = currentFile
    }
}

/// High-performance duplicate file detection service
/// Strategy:
/// 1. Group files by size (instant - O(n))
/// 2. Filter groups with only one file (can't be duplicates)
/// 3. For remaining groups, hash first 4KB of each file (fast pre-filter)
/// 4. For files with matching partial hashes, compute full SHA256 hash
/// 5. Group by full hash to identify exact duplicates
actor DuplicateDetectionService {
    
    /// Minimum file size to consider for duplicate detection (skip tiny files)
    private let minimumFileSize: Int64 = 4096 // 4KB
    
    /// Size of partial hash sample (first N bytes)
    private let partialHashSize: Int = 4096 // 4KB
    
    private var isCancelled = false
    
    func cancel() {
        isCancelled = true
    }
    
    private func resetCancellation() {
        isCancelled = false
    }
    
    /// Detect duplicate files from a flat list of scanned files
    /// Returns duplicate groups via AsyncStream for progressive UI updates
    func detectDuplicates(
        from files: [ScannedFileInfo]
    ) -> AsyncStream<DuplicateDetectionProgress> {
        AsyncStream { continuation in
            Task {
                await self.resetCancellation()
                await self.performDetection(files: files, continuation: continuation)
            }
        }
    }
    
    /// Detect duplicates and return groups directly
    func detectDuplicatesSync(from files: [ScannedFileInfo]) async -> [DuplicateGroup] {
        resetCancellation()
        return await findDuplicates(in: files)
    }
    
    // MARK: - Core Detection Logic
    
    private func performDetection(
        files: [ScannedFileInfo],
        continuation: AsyncStream<DuplicateDetectionProgress>.Continuation
    ) async {
        // Phase 1: Group by size
        continuation.yield(DuplicateDetectionProgress(
            phase: .groupingBySize, current: 0, total: files.count, currentFile: nil
        ))
        
        let _ = await findDuplicates(in: files, progressContinuation: continuation)
        
        continuation.yield(DuplicateDetectionProgress(
            phase: .completed, current: 1, total: 1, currentFile: nil
        ))
        continuation.finish()
    }
    
    private func findDuplicates(
        in files: [ScannedFileInfo],
        progressContinuation: AsyncStream<DuplicateDetectionProgress>.Continuation? = nil
    ) async -> [DuplicateGroup] {
        // Phase 1: Group by size (instant filter - files must be same size to be duplicates)
        var sizeGroups: [Int64: [ScannedFileInfo]] = [:]
        for file in files {
            // Skip files below minimum size
            guard file.fileSize >= minimumFileSize else { continue }
            sizeGroups[file.fileSize, default: []].append(file)
        }
        
        // Remove groups with only one file (can't have duplicates)
        let candidateGroups = sizeGroups.filter { $0.value.count > 1 }
        
        if candidateGroups.isEmpty {
            return []
        }
        
        // Count total files to hash for progress
        let totalToHash = candidateGroups.values.reduce(0) { $0 + $1.count }
        var hashesCompleted = 0
        
        progressContinuation?.yield(DuplicateDetectionProgress(
            phase: .hashing, current: 0, total: totalToHash, currentFile: nil
        ))
        
        // Phase 2: Partial hash (first 4KB) to quickly eliminate non-duplicates
        var partialHashGroups: [String: [ScannedFileInfo]] = [:]
        
        for (_, groupFiles) in candidateGroups {
            if isCancelled { return [] }
            
            for file in groupFiles {
                if isCancelled { return [] }
                
                if let partialHash = computePartialHash(for: file.url) {
                    let key = "\(file.fileSize)_\(partialHash)"
                    partialHashGroups[key, default: []].append(file)
                }
                
                hashesCompleted += 1
                if hashesCompleted % 50 == 0 {
                    progressContinuation?.yield(DuplicateDetectionProgress(
                        phase: .hashing,
                        current: hashesCompleted,
                        total: totalToHash,
                        currentFile: file.url.lastPathComponent
                    ))
                }
            }
        }
        
        // Remove non-matching partial hashes
        let partialCandidates = partialHashGroups.filter { $0.value.count > 1 }
        
        if partialCandidates.isEmpty {
            return []
        }
        
        // Phase 3: Full SHA256 hash for final confirmation
        var fullHashGroups: [String: [ScannedFileInfo]] = [:]
        let totalFullHash = partialCandidates.values.reduce(0) { $0 + $1.count }
        var fullHashCompleted = 0
        
        for (_, groupFiles) in partialCandidates {
            if isCancelled { return [] }
            
            for file in groupFiles {
                if isCancelled { return [] }
                
                if let fullHash = computeFullHash(for: file.url) {
                    fullHashGroups[fullHash, default: []].append(file)
                }
                
                fullHashCompleted += 1
                if fullHashCompleted % 10 == 0 {
                    progressContinuation?.yield(DuplicateDetectionProgress(
                        phase: .hashing,
                        current: hashesCompleted + fullHashCompleted,
                        total: totalToHash + totalFullHash,
                        currentFile: file.url.lastPathComponent
                    ))
                }
            }
        }
        
        // Build duplicate groups (only groups with 2+ files)
        var duplicateGroups: [DuplicateGroup] = []
        for (hash, groupFiles) in fullHashGroups {
            guard groupFiles.count > 1 else { continue }
            
            let group = DuplicateGroup(
                id: UUID(),
                hash: hash,
                fileSize: groupFiles[0].fileSize,
                files: groupFiles.sorted { $0.url.path < $1.url.path }
            )
            duplicateGroups.append(group)
        }
        
        // Sort by wasted space (largest first)
        duplicateGroups.sort { $0.wastedSpace > $1.wastedSpace }
        
        return duplicateGroups
    }
    
    // MARK: - Hashing
    
    /// Compute SHA256 of first N bytes (fast pre-filter)
    private func computePartialHash(for url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        
        let data = handle.readData(ofLength: partialHashSize)
        guard !data.isEmpty else { return nil }
        
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Compute full SHA256 hash of entire file (streaming for large files)
    private func computeFullHash(for url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        
        var hasher = SHA256()
        let bufferSize = 1024 * 1024 // 1MB chunks
        
        while true {
            let data = handle.readData(ofLength: bufferSize)
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        
        let hash = hasher.finalize()
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
