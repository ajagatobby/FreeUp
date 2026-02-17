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

// MARK: - Fast Hex Conversion

/// Pre-computed hex lookup table for fast SHA256 -> hex string conversion
private nonisolated(unsafe) let hexLookup: [UInt8] = Array("0123456789abcdef".utf8)

/// Convert SHA256 digest to hex string without String(format:) overhead
@inline(__always)
private nonisolated func fastHexString(from digest: SHA256.Digest) -> String {
    var result = [UInt8](repeating: 0, count: 64)
    for (i, byte) in digest.enumerated() {
        result[i &* 2] = hexLookup[Int(byte >> 4)]
        result[i &* 2 &+ 1] = hexLookup[Int(byte & 0x0F)]
    }
    return String(bytes: result, encoding: .ascii)!
}

// MARK: - Standalone Hashing Functions (nonisolated for parallel execution)

/// Compute SHA256 of first N bytes (fast pre-filter) - runs off actor
private nonisolated func computePartialHashStatic(for url: URL, size: Int) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    
    let data = handle.readData(ofLength: size)
    guard !data.isEmpty else { return nil }
    
    let hash = SHA256.hash(data: data)
    return fastHexString(from: hash)
}

/// Compute full SHA256 hash of entire file (streaming) - runs off actor
private nonisolated func computeFullHashStatic(for url: URL) -> String? {
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
    return fastHexString(from: hash)
}

/// High-performance duplicate file detection service
/// Strategy:
/// 1. Group files by size (instant - O(n))
/// 2. Filter groups with only one file (can't be duplicates)
/// 3. For remaining groups, hash first 4KB in parallel (fast pre-filter)
/// 4. For files with matching partial hashes, compute full SHA256 in parallel
/// 5. Group by full hash to identify exact duplicates
actor DuplicateDetectionService {
    
    /// Minimum file size to consider for duplicate detection (skip tiny files)
    private let minimumFileSize: Int64 = 4096 // 4KB
    
    /// Size of partial hash sample (first N bytes)
    private let partialHashSize: Int = 4096 // 4KB
    
    private var isCancelled = false
    
    /// Stored result from last detection run (avoids running twice)
    private var lastResult: [DuplicateGroup] = []
    
    func cancel() {
        isCancelled = true
    }
    
    private func resetCancellation() {
        isCancelled = false
    }
    
    /// Detect duplicate files with progress updates, stores result for retrieval
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
    
    /// Retrieve the result from the last detectDuplicates() call (no re-scan)
    func getLastResult() -> [DuplicateGroup] {
        lastResult
    }
    
    // MARK: - Core Detection Logic
    
    private func performDetection(
        files: [ScannedFileInfo],
        continuation: AsyncStream<DuplicateDetectionProgress>.Continuation
    ) async {
        continuation.yield(DuplicateDetectionProgress(
            phase: .groupingBySize, current: 0, total: files.count, currentFile: nil
        ))
        
        lastResult = await findDuplicates(in: files, progressContinuation: continuation)
        
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
            guard file.fileSize >= minimumFileSize else { continue }
            if sizeGroups[file.fileSize] == nil {
                sizeGroups[file.fileSize] = []
            }
            sizeGroups[file.fileSize]!.append(file)
        }
        
        // Remove groups with only one file (can't have duplicates)
        let candidateGroups = sizeGroups.filter { $0.value.count > 1 }
        
        if candidateGroups.isEmpty { return [] }
        
        // Flatten candidates for parallel processing
        let allCandidates: [(Int64, ScannedFileInfo)] = candidateGroups.flatMap { (size, files) in
            files.map { (size, $0) }
        }
        let totalToHash = allCandidates.count
        
        progressContinuation?.yield(DuplicateDetectionProgress(
            phase: .hashing, current: 0, total: totalToHash, currentFile: nil
        ))
        
        // Phase 2: Parallel partial hash (first 4KB) to quickly eliminate non-duplicates
        let hashSize = partialHashSize
        var partialHashGroups: [String: [ScannedFileInfo]] = [:]
        var hashesCompleted = 0
        
        // Process in parallel chunks using TaskGroup
        await withTaskGroup(of: (String, ScannedFileInfo)?.self) { group in
            for (fileSize, file) in allCandidates {
                group.addTask {
                    guard let hash = computePartialHashStatic(for: file.url, size: hashSize) else {
                        return nil
                    }
                    return ("\(fileSize)_\(hash)", file)
                }
            }
            
            for await result in group {
                if isCancelled { break }
                
                if let (key, file) = result {
                    if partialHashGroups[key] == nil {
                        partialHashGroups[key] = []
                    }
                    partialHashGroups[key]!.append(file)
                }
                
                hashesCompleted += 1
                if hashesCompleted % 100 == 0 {
                    progressContinuation?.yield(DuplicateDetectionProgress(
                        phase: .hashing,
                        current: hashesCompleted,
                        total: totalToHash,
                        currentFile: nil
                    ))
                }
            }
        }
        
        if isCancelled { return [] }
        
        // Remove non-matching partial hashes
        let partialCandidates = partialHashGroups.filter { $0.value.count > 1 }
        if partialCandidates.isEmpty { return [] }
        
        // Phase 3: Parallel full SHA256 hash for final confirmation
        let fullCandidates = partialCandidates.values.flatMap { $0 }
        let totalFullHash = fullCandidates.count
        var fullHashGroups: [String: [ScannedFileInfo]] = [:]
        var fullHashCompleted = 0
        
        await withTaskGroup(of: (String, ScannedFileInfo)?.self) { group in
            for file in fullCandidates {
                group.addTask {
                    guard let hash = computeFullHashStatic(for: file.url) else { return nil }
                    return (hash, file)
                }
            }
            
            for await result in group {
                if isCancelled { break }
                
                if let (hash, file) = result {
                    if fullHashGroups[hash] == nil {
                        fullHashGroups[hash] = []
                    }
                    fullHashGroups[hash]!.append(file)
                }
                
                fullHashCompleted += 1
                if fullHashCompleted % 20 == 0 {
                    progressContinuation?.yield(DuplicateDetectionProgress(
                        phase: .hashing,
                        current: hashesCompleted + fullHashCompleted,
                        total: totalToHash + totalFullHash,
                        currentFile: nil
                    ))
                }
            }
        }
        
        if isCancelled { return [] }
        
        // Build duplicate groups (only groups with 2+ files)
        var duplicateGroups: [DuplicateGroup] = []
        duplicateGroups.reserveCapacity(fullHashGroups.count)
        
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
}
