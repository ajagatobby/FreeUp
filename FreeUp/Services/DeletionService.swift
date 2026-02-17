//
//  DeletionService.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import Foundation
import AppKit

/// Result of a deletion operation
struct DeletionResult: Sendable {
    let successCount: Int
    let failureCount: Int
    let freedSpace: Int64
    let errors: [DeletionError]
    
    var totalAttempted: Int { successCount + failureCount }
    var allSuccessful: Bool { failureCount == 0 }
}

/// Error during deletion
struct DeletionError: Sendable, Identifiable {
    let id = UUID()
    let url: URL
    let error: String
}

/// Progress update during batch deletion
struct DeletionProgress: Sendable {
    let current: Int
    let total: Int
    let currentFile: String
    let bytesFreed: Int64
    
    var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }
}

/// Service for fast file deletion with parallel batch support
actor DeletionService {
    /// Delete mode preference
    enum DeleteMode: Sendable {
        case moveToTrash
        case permanent
    }
    
    private var isCancelled = false
    
    func cancel() {
        isCancelled = true
    }
    
    private func resetCancellation() {
        isCancelled = false
    }
    
    /// Fast batch deletion — runs file I/O in parallel chunks off the actor
    func deleteFilesFast(
        _ files: [ScannedFileInfo],
        mode: DeleteMode = .moveToTrash
    ) async -> DeletionResult {
        guard !files.isEmpty else {
            return DeletionResult(successCount: 0, failureCount: 0, freedSpace: 0, errors: [])
        }
        
        isCancelled = false
        
        // For large batches (>1000), always use parallel removeItem regardless of mode.
        // NSWorkspace.recycle involves IPC with Finder per-chunk and is far too slow
        // for thousands of files. For small batches, respect the user's Trash preference.
        if files.count > 1000 || mode == .permanent {
            return await deleteFilesBatchParallel(files)
        } else {
            return await trashFilesBatch(files)
        }
    }
    
    // MARK: - Batch Trash via NSWorkspace.recycle (fast — Finder batches internally)
    
    /// Use NSWorkspace.recycle to trash files in one Finder call
    private func trashFilesBatch(_ files: [ScannedFileInfo]) async -> DeletionResult {
        let urls = files.map(\.url)
        
        // NSWorkspace.recycle handles batching internally and is MUCH faster than
        // individual trashItem calls for large numbers of files
        // Process in chunks of 500 to avoid overwhelming Finder and to allow cancellation
        let chunkSize = 500
        var totalSuccess = 0
        var totalFailure = 0
        var totalFreed: Int64 = 0
        var allErrors: [DeletionError] = []
        
        for chunkStart in stride(from: 0, to: urls.count, by: chunkSize) {
            if isCancelled { break }
            
            let chunkEnd = min(chunkStart + chunkSize, urls.count)
            let chunkURLs = Array(urls[chunkStart..<chunkEnd])
            let chunkFiles = Array(files[chunkStart..<chunkEnd])
            
            let result = await recycleChunk(chunkURLs, files: chunkFiles)
            totalSuccess += result.successCount
            totalFailure += result.failureCount
            totalFreed += result.freedSpace
            allErrors.append(contentsOf: result.errors)
        }
        
        return DeletionResult(
            successCount: totalSuccess,
            failureCount: totalFailure,
            freedSpace: totalFreed,
            errors: allErrors
        )
    }
    
    /// Recycle a chunk of URLs via NSWorkspace
    private nonisolated func recycleChunk(
        _ urls: [URL],
        files: [ScannedFileInfo]
    ) async -> DeletionResult {
        await withCheckedContinuation { continuation in
            NSWorkspace.shared.recycle(urls) { trashedURLs, error in
                let trashedSet = Set(trashedURLs.keys.map(\.path))
                var successCount = 0
                var freedSpace: Int64 = 0
                var errors: [DeletionError] = []
                
                for file in files {
                    if trashedSet.contains(file.url.path) {
                        successCount += 1
                        freedSpace += file.allocatedSize
                    } else {
                        errors.append(DeletionError(
                            url: file.url,
                            error: error?.localizedDescription ?? "Failed to move to Trash"
                        ))
                    }
                }
                
                let failureCount = files.count - successCount
                continuation.resume(returning: DeletionResult(
                    successCount: successCount,
                    failureCount: failureCount,
                    freedSpace: freedSpace,
                    errors: errors
                ))
            }
        }
    }
    
    // MARK: - Parallel Permanent Deletion
    
    /// Delete files permanently using parallel TaskGroup
    private func deleteFilesBatchParallel(_ files: [ScannedFileInfo]) async -> DeletionResult {
        let maxConcurrency = 16
        var successCount = 0
        var failureCount = 0
        var freedSpace: Int64 = 0
        var errors: [DeletionError] = []
        
        await withTaskGroup(of: (Bool, Int64, DeletionError?).self) { group in
            var submitted = 0
            
            for file in files {
                if isCancelled { break }
                
                // Limit concurrency
                if submitted >= maxConcurrency {
                    if let result = await group.next() {
                        if result.0 {
                            successCount += 1
                            freedSpace += result.1
                        } else {
                            failureCount += 1
                            if let err = result.2 {
                                errors.append(err)
                            }
                        }
                    }
                }
                
                let fileURL = file.url
                let fileSize = file.allocatedSize
                group.addTask {
                    do {
                        try FileManager.default.removeItem(at: fileURL)
                        return (true, fileSize, nil)
                    } catch {
                        return (false, Int64(0), DeletionError(url: fileURL, error: error.localizedDescription))
                    }
                }
                submitted += 1
            }
            
            // Drain remaining
            for await result in group {
                if result.0 {
                    successCount += 1
                    freedSpace += result.1
                } else {
                    failureCount += 1
                    if let err = result.2 {
                        errors.append(err)
                    }
                }
            }
        }
        
        return DeletionResult(
            successCount: successCount,
            failureCount: failureCount,
            freedSpace: freedSpace,
            errors: errors
        )
    }
    
    // MARK: - Utilities
    
    /// Empty the Trash
    nonisolated func emptyTrash() async -> Bool {
        let script = NSAppleScript(source: "tell application \"Finder\" to empty trash")
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        return error == nil
    }
    
    /// Get Trash size
    func getTrashSize() async -> Int64 {
        let fileManager = FileManager.default
        guard let trashURL = fileManager.urls(for: .trashDirectory, in: .userDomainMask).first else {
            return 0
        }
        return calculateDirectorySize(trashURL)
    }
    
    private func calculateDirectorySize(_ url: URL) -> Int64 {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0
        
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  resourceValues.isRegularFile == true,
                  let fileSize = resourceValues.fileSize else {
                continue
            }
            totalSize += Int64(fileSize)
        }
        
        return totalSize
    }
    
    /// Thin local Time Machine snapshots
    func thinLocalSnapshots(urgentGB: Int = 10) async -> (success: Bool, message: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["thinlocalsnapshots", "/", "\(urgentGB * 1_000_000_000)", "1"]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                return (true, "Thinned local snapshots. \(output)")
            } else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                return (false, "Failed: \(errorMessage)")
            }
        } catch {
            return (false, "Error: \(error.localizedDescription)")
        }
    }
    
    /// Purge purgeable space
    func purgePurgeableSpace() async -> (success: Bool, freedBytes: Int64) {
        guard let initialInfo = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityKey]) else {
            return (false, 0)
        }
        let initialAvailable = Int64(initialInfo.volumeAvailableCapacity ?? 0)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/purge")
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // purge might fail without admin
        }
        
        guard let finalInfo = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityKey]) else {
            return (false, 0)
        }
        let finalAvailable = Int64(finalInfo.volumeAvailableCapacity ?? 0)
        
        let freed = finalAvailable - initialAvailable
        return (freed > 0, max(0, freed))
    }
}

// MARK: - Deletion ViewModel

@MainActor
@Observable
final class DeletionViewModel {
    private(set) var isDeleting = false
    private(set) var progress: DeletionProgress?
    private(set) var result: DeletionResult?
    private(set) var showResult = false
    
    private let deletionService = DeletionService()
    
    /// Delete files with progress tracking
    func deleteFiles(_ files: [ScannedFileInfo], mode: DeletionService.DeleteMode = .moveToTrash) async {
        guard !files.isEmpty else { return }
        
        isDeleting = true
        progress = nil
        result = nil
        
        let deletionResult = await deletionService.deleteFilesFast(files, mode: mode)
        result = deletionResult
        isDeleting = false
        showResult = true
    }
    
    func cancel() {
        Task {
            await deletionService.cancel()
        }
        isDeleting = false
    }
    
    func dismissResult() {
        showResult = false
        result = nil
    }
    
    func emptyTrash() async -> Bool {
        await deletionService.emptyTrash()
    }
    
    func getTrashSize() async -> Int64 {
        await deletionService.getTrashSize()
    }
}
