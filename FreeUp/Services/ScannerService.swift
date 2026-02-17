//
//  ScannerService.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import Foundation
import UniformTypeIdentifiers

/// Result types for scan progress streaming
enum ScanResult: Sendable {
    case progress(ScannedFileInfo)
    case batch([ScannedFileInfo])
    case directoryStarted(URL)
    case directoryCompleted(URL, fileCount: Int, totalSize: Int64)
    case error(ScanError)
    case completed(totalFiles: Int, totalSize: Int64)
}

/// Lightweight struct for streaming (not persisted)
struct ScannedFileInfo: Sendable, Identifiable {
    /// Stable identity derived from file path hash (computed once at init, not per-access)
    nonisolated let id: UUID
    let url: URL
    let allocatedSize: Int64
    let fileSize: Int64
    let contentType: UTType?
    let category: FileCategory
    let lastAccessDate: Date?
    let fileContentIdentifier: Int64?
    let isPurgeable: Bool
    /// Source identifier for sub-categorization (e.g., "Safari Cache", "Chrome Cache")
    let source: String?
    /// Pre-computed file name (avoids repeated URL decomposition)
    let fileName: String
    /// Pre-computed parent path (avoids repeated URL decomposition)
    let parentPath: String
    
    nonisolated init(
        url: URL,
        allocatedSize: Int64,
        fileSize: Int64,
        contentType: UTType?,
        category: FileCategory,
        lastAccessDate: Date?,
        fileContentIdentifier: Int64?,
        isPurgeable: Bool,
        source: String?
    ) {
        self.id = UUID()
        self.url = url
        self.allocatedSize = allocatedSize
        self.fileSize = fileSize
        self.contentType = contentType
        self.category = category
        self.lastAccessDate = lastAccessDate
        self.fileContentIdentifier = fileContentIdentifier
        self.isPurgeable = isPurgeable
        self.source = source
        // Compute fileName/parentPath from path string directly (avoids URL object creation)
        let path = url.path
        if let lastSlash = path.lastIndex(of: "/") {
            self.fileName = String(path[path.index(after: lastSlash)...])
            self.parentPath = String(path[..<lastSlash])
        } else {
            self.fileName = path
            self.parentPath = ""
        }
    }
}

extension ScannedFileInfo: Equatable {
    nonisolated static func == (lhs: ScannedFileInfo, rhs: ScannedFileInfo) -> Bool {
        lhs.id == rhs.id
    }
}

extension ScannedFileInfo: Hashable {
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Scanning errors
enum ScanError: Error, Sendable {
    case accessDenied(URL)
    case invalidPath(String)
    case cancelled
    case unknown(String)
}

/// High-performance file system scanner using DirectoryEnumerator with URLResourceKey pre-fetching
actor ScannerService {
    /// Resource keys to pre-fetch during enumeration (avoids expensive per-file kernel calls)
    private static let resourceKeys: Set<URLResourceKey> = [
        .fileAllocatedSizeKey,
        .totalFileAllocatedSizeKey,
        .fileSizeKey,
        .totalFileSizeKey,
        .isPurgeableKey,
        .contentTypeKey,
        .contentAccessDateKey,
        .fileContentIdentifierKey,
        .isDirectoryKey,
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .isHiddenKey
    ]
    
    /// Batch size for streaming results to reduce UI update frequency (increased for better performance)
    private let batchSize: Int = 2000
    
    /// Directory names to skip during scanning (O(1) Set lookup)
    private static let excludedDirNames: Set<String> = [
        ".Spotlight-V100",
        ".fseventsd",
        ".Trashes",
        ".vol",
        "System",
        "bin",
        "sbin",
        "usr",
        "Volumes",
        ".git",
        ".svn",
        ".hg",
        "node_modules",
        ".npm"
    ]
    
    /// Track if scan is cancelled
    private var isCancelled = false
    
    /// Cancel the current scan
    func cancel() {
        isCancelled = true
    }
    
    /// Reset cancellation flag for new scan
    private func resetCancellation() {
        isCancelled = false
    }
    
    /// Scan a directory and stream results via AsyncStream
    /// - Parameter directory: Root directory to scan
    /// - Returns: AsyncStream of ScanResult for progressive UI updates
    func scan(directory: URL) -> AsyncStream<ScanResult> {
        AsyncStream { [weak self] continuation in
            guard let self = self else {
                continuation.finish()
                return
            }
            
            Task {
                await self.resetCancellation()
                await self.performScan(directory: directory, continuation: continuation)
            }
        }
    }
    
    /// Internal scan implementation with parallelization
    private func performScan(
        directory: URL,
        continuation: AsyncStream<ScanResult>.Continuation
    ) async {
        let fileManager = FileManager.default
        
        // Verify directory exists and is accessible
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            continuation.yield(.error(.invalidPath(directory.path)))
            continuation.finish()
            return
        }
        
        // Get top-level directories for parallel scanning
        let topLevelURLs: [URL]
        do {
            topLevelURLs = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ).filter { url in
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let name = url.lastPathComponent
                // O(1) Set lookup for exclusion check
                return isDir && !Self.excludedDirNames.contains(name)
            }
        } catch {
            continuation.yield(.error(.accessDenied(directory)))
            continuation.finish()
            return
        }
        
        var totalFiles = 0
        var totalSize: Int64 = 0
        
        // Capture batch threshold for task group
        let batchThreshold = batchSize
        
        // Parallel scan using TaskGroup
        await withTaskGroup(of: ([ScannedFileInfo], Int, Int64).self) { group in
            for topLevelURL in topLevelURLs {
                group.addTask {
                    return Self.scanDirectoryStatic(
                        topLevelURL,
                        continuation: continuation,
                        batchThreshold: batchThreshold
                    )
                }
            }
            
            // Also scan files in root directory (not in subdirectories)
            group.addTask {
                return Self.scanRootFilesStatic(
                    directory,
                    continuation: continuation
                )
            }
            
            // Collect results from all parallel tasks
            for await (batch, fileCount, size) in group {
                if !batch.isEmpty {
                    continuation.yield(.batch(batch))
                }
                totalFiles += fileCount
                totalSize += size
                
                if self.isCancelled {
                    continuation.yield(.error(.cancelled))
                    continuation.finish()
                    return
                }
            }
        }
        
        continuation.yield(.completed(totalFiles: totalFiles, totalSize: totalSize))
        continuation.finish()
    }
    
    /// Scan a single directory tree
    private static func scanDirectoryStatic(
        _ directory: URL,
        continuation: AsyncStream<ScanResult>.Continuation,
        batchThreshold: Int
    ) -> ([ScannedFileInfo], Int, Int64) {
        continuation.yield(.directoryStarted(directory))
        
        let fileManager = FileManager.default
        var batch: [ScannedFileInfo] = []
        batch.reserveCapacity(batchThreshold)
        var fileCount = 0
        var totalSize: Int64 = 0
        
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(Self.resourceKeys),
            options: [.skipsPackageDescendants],
            errorHandler: { url, error in
                // Log but continue on errors
                return true
            }
        ) else {
            return (batch, fileCount, totalSize)
        }
        
        var iterCount = 0
        
        while let fileURL = enumerator.nextObject() as? URL {
            iterCount += 1
            
            // O(1) Set lookup for directory exclusion - check lastPathComponent only
            let name = fileURL.lastPathComponent
            if Self.excludedDirNames.contains(name) {
                enumerator.skipDescendants()
                continue
            }
            
            // Get resource values
            guard let resourceValues = try? fileURL.resourceValues(forKeys: Self.resourceKeys) else {
                continue
            }
            
            // Skip directories and symbolic links
            if resourceValues.isDirectory == true || resourceValues.isSymbolicLink == true {
                continue
            }
            
            // Only process regular files
            guard resourceValues.isRegularFile == true else {
                continue
            }
            
            // Extract file info
            let allocatedSize = Int64(resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize ?? 0)
            let fileSize = Int64(resourceValues.totalFileSize ?? resourceValues.fileSize ?? 0)
            let contentType = resourceValues.contentType
            let lastAccessDate = resourceValues.contentAccessDate
            let fileContentIdentifier = resourceValues.fileContentIdentifier
            let isPurgeable = resourceValues.isPurgeable ?? false
            
            // Categorize file
            let category = FileCategory.categorize(contentType: contentType, url: fileURL)
            
            let fileInfo = ScannedFileInfo(
                url: fileURL,
                allocatedSize: allocatedSize,
                fileSize: fileSize,
                contentType: contentType,
                category: category,
                lastAccessDate: lastAccessDate,
                fileContentIdentifier: fileContentIdentifier,
                isPurgeable: isPurgeable,
                source: nil
            )
            
            batch.append(fileInfo)
            fileCount += 1
            totalSize += allocatedSize
            
            // Yield batch when threshold reached
            if batch.count >= batchThreshold {
                continuation.yield(.batch(batch))
                batch.removeAll(keepingCapacity: true)
            }
        }
        
        continuation.yield(.directoryCompleted(directory, fileCount: fileCount, totalSize: totalSize))
        
        return (batch, fileCount, totalSize)
    }
    
    /// Scan only files in root directory (not subdirectories)
    private static func scanRootFilesStatic(
        _ directory: URL,
        continuation: AsyncStream<ScanResult>.Continuation
    ) -> ([ScannedFileInfo], Int, Int64) {
        let fileManager = FileManager.default
        var batch: [ScannedFileInfo] = []
        batch.reserveCapacity(500) // Pre-allocate for typical root directory
        var fileCount = 0
        var totalSize: Int64 = 0
        
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(Self.resourceKeys),
            options: []
        ) else {
            return (batch, fileCount, totalSize)
        }
        
        for fileURL in contents {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: Self.resourceKeys) else {
                continue
            }
            
            // Only process regular files
            guard resourceValues.isRegularFile == true,
                  resourceValues.isDirectory != true,
                  resourceValues.isSymbolicLink != true else {
                continue
            }
            
            let allocatedSize = Int64(resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize ?? 0)
            let fileSize = Int64(resourceValues.totalFileSize ?? resourceValues.fileSize ?? 0)
            let contentType = resourceValues.contentType
            let lastAccessDate = resourceValues.contentAccessDate
            let fileContentIdentifier = resourceValues.fileContentIdentifier
            let isPurgeable = resourceValues.isPurgeable ?? false
            
            let category = FileCategory.categorize(contentType: contentType, url: fileURL)
            
            let fileInfo = ScannedFileInfo(
                url: fileURL,
                allocatedSize: allocatedSize,
                fileSize: fileSize,
                contentType: contentType,
                category: category,
                lastAccessDate: lastAccessDate,
                fileContentIdentifier: fileContentIdentifier,
                isPurgeable: isPurgeable,
                source: nil
            )
            
            batch.append(fileInfo)
            fileCount += 1
            totalSize += allocatedSize
        }
        
        return (batch, fileCount, totalSize)
    }
    
    /// Quick scan for storage overview (top-level only)
    func quickScan(directory: URL) async -> [FileCategory: (count: Int, size: Int64)] {
        var results: [FileCategory: (count: Int, size: Int64)] = [:]
        
        for await result in scan(directory: directory) {
            switch result {
            case .batch(let files):
                for file in files {
                    var current = results[file.category] ?? (0, 0)
                    current.count += 1
                    current.size += file.allocatedSize
                    results[file.category] = current
                }
            case .progress(let file):
                var current = results[file.category] ?? (0, 0)
                current.count += 1
                current.size += file.allocatedSize
                results[file.category] = current
            default:
                break
            }
        }
        
        return results
    }
}
