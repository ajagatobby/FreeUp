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

/// Service for safe file deletion with Trash support
actor DeletionService {
    /// Delete mode preference
    enum DeleteMode: Sendable {
        case moveToTrash
        case permanent
    }
    
    private var isCancelled = false
    
    /// Cancel ongoing deletion
    func cancel() {
        isCancelled = true
    }
    
    /// Reset cancellation flag
    private func resetCancellation() {
        isCancelled = false
    }
    
    /// Delete files with progress reporting
    /// - Parameters:
    ///   - files: Array of file info to delete
    ///   - mode: Whether to move to trash or delete permanently
    ///   - progress: Async stream for progress updates
    /// - Returns: Result of the deletion operation
    func deleteFiles(
        _ files: [ScannedFileInfo],
        mode: DeleteMode = .moveToTrash
    ) -> AsyncStream<DeletionProgress> {
        AsyncStream { continuation in
            Task {
                await self.resetCancellation()
                await self.performDeletion(files: files, mode: mode, continuation: continuation)
            }
        }
    }
    
    /// Perform the actual deletion
    private func performDeletion(
        files: [ScannedFileInfo],
        mode: DeleteMode,
        continuation: AsyncStream<DeletionProgress>.Continuation
    ) async {
        let fileManager = FileManager.default
        var bytesFreed: Int64 = 0
        
        for (index, file) in files.enumerated() {
            if isCancelled {
                continuation.finish()
                return
            }
            
            do {
                switch mode {
                case .moveToTrash:
                    var resultURL: NSURL?
                    try fileManager.trashItem(at: file.url, resultingItemURL: &resultURL)
                    
                case .permanent:
                    try fileManager.removeItem(at: file.url)
                }
                
                bytesFreed += file.allocatedSize
                
            } catch {
                // Continue with next file on error
                print("Failed to delete \(file.url): \(error)")
            }
            
            continuation.yield(DeletionProgress(
                current: index + 1,
                total: files.count,
                currentFile: file.url.lastPathComponent,
                bytesFreed: bytesFreed
            ))
        }
        
        continuation.finish()
    }
    
    /// Delete files synchronously with result
    func deleteFilesSync(
        _ files: [ScannedFileInfo],
        mode: DeleteMode = .moveToTrash
    ) async -> DeletionResult {
        let fileManager = FileManager.default
        var successCount = 0
        var failureCount = 0
        var freedSpace: Int64 = 0
        var errors: [DeletionError] = []
        
        for file in files {
            if isCancelled {
                break
            }
            
            do {
                switch mode {
                case .moveToTrash:
                    var resultURL: NSURL?
                    try fileManager.trashItem(at: file.url, resultingItemURL: &resultURL)
                    
                case .permanent:
                    try fileManager.removeItem(at: file.url)
                }
                
                successCount += 1
                freedSpace += file.allocatedSize
                
            } catch {
                failureCount += 1
                errors.append(DeletionError(url: file.url, error: error.localizedDescription))
            }
        }
        
        return DeletionResult(
            successCount: successCount,
            failureCount: failureCount,
            freedSpace: freedSpace,
            errors: errors
        )
    }
    
    /// Empty the Trash
    func emptyTrash() async -> Bool {
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
    
    /// Calculate directory size recursively
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
    /// - Parameter urgentGB: Space needed in GB (triggers more aggressive thinning)
    /// - Returns: Success status and message
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
    
    /// Purge purgeable space (triggers system cleanup)
    func purgePurgeableSpace() async -> (success: Bool, freedBytes: Int64) {
        // Get initial available space
        guard let initialInfo = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityKey]) else {
            return (false, 0)
        }
        let initialAvailable = Int64(initialInfo.volumeAvailableCapacity ?? 0)
        
        // Run purge command (requires admin privileges in most cases)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/purge")
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // purge might fail without admin, but that's ok
        }
        
        // Check available space after
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
        
        var lastProgress: DeletionProgress?
        
        for await update in await deletionService.deleteFiles(files, mode: mode) {
            progress = update
            lastProgress = update
        }
        
        // Create result from final progress
        if let final = lastProgress {
            result = DeletionResult(
                successCount: final.current,
                failureCount: files.count - final.current,
                freedSpace: final.bytesFreed,
                errors: []
            )
        }
        
        isDeleting = false
        showResult = true
    }
    
    /// Cancel deletion
    func cancel() {
        Task {
            await deletionService.cancel()
        }
        isDeleting = false
    }
    
    /// Dismiss result
    func dismissResult() {
        showResult = false
        result = nil
    }
    
    /// Empty trash
    func emptyTrash() async -> Bool {
        await deletionService.emptyTrash()
    }
    
    /// Get trash size
    func getTrashSize() async -> Int64 {
        await deletionService.getTrashSize()
    }
}
