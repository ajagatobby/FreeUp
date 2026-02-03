//
//  TurboScannerService.swift
//  FreeUp
//
//  High-performance file scanner optimized for speed
//  Uses parallel processing and optimized FileManager APIs
//
//  Performance optimizations:
//  1. Parallel directory scanning across CPU cores
//  2. Pre-fetched resource keys (single syscall per file)
//  3. Large batch sizes to reduce UI overhead
//  4. Pre-allocated arrays to minimize allocations
//

import Foundation
import UniformTypeIdentifiers

// MARK: - TurboScannerService

/// High-performance file scanner using parallel processing
actor TurboScannerService {
    
    // MARK: - Configuration
    
    /// Number of concurrent directory scanners
    private static let concurrentScanners: Int = max(ProcessInfo.processInfo.activeProcessorCount, 4)
    
    /// Batch size for yielding results (larger = fewer UI updates = faster)
    private let batchSize: Int = 1000
    
    /// Resource keys to pre-fetch (single syscall)
    private static let resourceKeys: Set<URLResourceKey> = [
        .fileSizeKey,
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        .contentTypeKey,
        .contentAccessDateKey,
        .isRegularFileKey,
        .isDirectoryKey,
        .isSymbolicLinkKey
    ]
    
    /// Directories to skip
    private static let excludedDirNames: Set<String> = [
        ".Spotlight-V100", ".fseventsd", ".Trashes", ".vol",
        "System", "bin", "sbin", "usr", "Volumes",
        ".git", ".svn", ".hg", "node_modules", ".npm"
    ]
    
    private var isCancelled = false
    
    func cancel() {
        isCancelled = true
    }
    
    private func resetCancellation() {
        isCancelled = false
    }
    
    // MARK: - Public API
    
    /// High-performance parallel scan
    func scan(directory: URL) -> AsyncStream<ScanResult> {
        AsyncStream { [weak self] continuation in
            guard let self = self else {
                continuation.finish()
                return
            }
            
            Task.detached(priority: .userInitiated) {
                await self.resetCancellation()
                await self.performParallelScan(directory: directory, continuation: continuation)
            }
        }
    }
    
    // MARK: - Core Scanning
    
    private func performParallelScan(
        directory: URL,
        continuation: AsyncStream<ScanResult>.Continuation
    ) async {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Verify directory exists
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDir),
              isDir.boolValue else {
            continuation.yield(.error(.invalidPath(directory.path)))
            continuation.finish()
            return
        }
        
        // Collect top-level directories for parallel processing
        let topLevelDirs = collectTopLevelDirectories(root: directory)
        
        // Use concurrent processing with DispatchQueue for true parallelism
        let results = await withCheckedContinuation { (cont: CheckedContinuation<(Int, Int64), Never>) in
            let group = DispatchGroup()
            let queue = DispatchQueue(label: "turbo.scanner", qos: .userInitiated, attributes: .concurrent)
            
            let totalFiles = UnsafeMutablePointer<Int>.allocate(capacity: 1)
            let totalSize = UnsafeMutablePointer<Int64>.allocate(capacity: 1)
            totalFiles.initialize(to: 0)
            totalSize.initialize(to: 0)
            let lock = NSLock()
            
            // Process each top-level directory in parallel
            for dir in topLevelDirs {
                group.enter()
                queue.async {
                    let (count, size) = self.scanDirectoryTree(dir, continuation: continuation)
                    lock.lock()
                    totalFiles.pointee += count
                    totalSize.pointee += size
                    lock.unlock()
                    group.leave()
                }
            }
            
            // Also scan files in root directory
            group.enter()
            queue.async {
                let (count, size) = self.scanSingleDirectory(directory, continuation: continuation)
                lock.lock()
                totalFiles.pointee += count
                totalSize.pointee += size
                lock.unlock()
                group.leave()
            }
            
            group.notify(queue: .main) {
                let files = totalFiles.pointee
                let size = totalSize.pointee
                totalFiles.deallocate()
                totalSize.deallocate()
                cont.resume(returning: (files, size))
            }
        }
        
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let formattedSize = ByteCountFormatter.string(fromByteCount: results.1, countStyle: .file)
        print("TurboScanner: Scanned \(results.0) files (\(formattedSize)) in \(String(format: "%.2f", elapsed))s")
        
        continuation.yield(.completed(totalFiles: results.0, totalSize: results.1))
        continuation.finish()
    }
    
    /// Collect top-level directories for parallel processing
    private nonisolated func collectTopLevelDirectories(root: URL) -> [URL] {
        let fm = FileManager.default
        
        guard let contents = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        
        return contents.filter { url in
            let name = url.lastPathComponent
            guard !Self.excludedDirNames.contains(name) else { return false }
            
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return isDir
        }
    }
    
    /// Scan an entire directory tree recursively
    private nonisolated func scanDirectoryTree(
        _ directory: URL,
        continuation: AsyncStream<ScanResult>.Continuation
    ) -> (Int, Int64) {
        var totalCount = 0
        var totalSize: Int64 = 0
        var batch: [ScannedFileInfo] = []
        batch.reserveCapacity(batchSize)
        
        let fm = FileManager.default
        
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(Self.resourceKeys),
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return (0, 0)
        }
        
        while let fileURL = enumerator.nextObject() as? URL {
            // Skip excluded directories
            let name = fileURL.lastPathComponent
            if Self.excludedDirNames.contains(name) {
                enumerator.skipDescendants()
                continue
            }
            
            // Get resource values
            guard let values = try? fileURL.resourceValues(forKeys: Self.resourceKeys) else {
                continue
            }
            
            // Skip non-regular files
            guard values.isRegularFile == true,
                  values.isDirectory != true,
                  values.isSymbolicLink != true else {
                continue
            }
            
            // Extract file info
            let allocatedSize = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            let fileSize = Int64(values.fileSize ?? 0)
            let contentType = values.contentType
            let lastAccess = values.contentAccessDate
            
            // Categorize
            let category = FileCategory.categorize(contentType: contentType, url: fileURL)
            
            let fileInfo = ScannedFileInfo(
                url: fileURL,
                allocatedSize: allocatedSize,
                fileSize: fileSize,
                contentType: contentType,
                category: category,
                lastAccessDate: lastAccess,
                fileContentIdentifier: nil,
                isPurgeable: false
            )
            
            batch.append(fileInfo)
            totalCount += 1
            totalSize += allocatedSize
            
            // Yield batch when full
            if batch.count >= batchSize {
                continuation.yield(.batch(batch))
                batch.removeAll(keepingCapacity: true)
            }
        }
        
        // Yield remaining files
        if !batch.isEmpty {
            continuation.yield(.batch(batch))
        }
        
        return (totalCount, totalSize)
    }
    
    /// Scan only immediate children of a directory (not recursive)
    private nonisolated func scanSingleDirectory(
        _ directory: URL,
        continuation: AsyncStream<ScanResult>.Continuation
    ) -> (Int, Int64) {
        var totalCount = 0
        var totalSize: Int64 = 0
        var batch: [ScannedFileInfo] = []
        
        let fm = FileManager.default
        
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(Self.resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return (0, 0)
        }
        
        for fileURL in contents {
            guard let values = try? fileURL.resourceValues(forKeys: Self.resourceKeys) else {
                continue
            }
            
            // Only process regular files (not directories)
            guard values.isRegularFile == true,
                  values.isDirectory != true else {
                continue
            }
            
            let allocatedSize = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            let fileSize = Int64(values.fileSize ?? 0)
            let contentType = values.contentType
            let lastAccess = values.contentAccessDate
            
            let category = FileCategory.categorize(contentType: contentType, url: fileURL)
            
            let fileInfo = ScannedFileInfo(
                url: fileURL,
                allocatedSize: allocatedSize,
                fileSize: fileSize,
                contentType: contentType,
                category: category,
                lastAccessDate: lastAccess,
                fileContentIdentifier: nil,
                isPurgeable: false
            )
            
            batch.append(fileInfo)
            totalCount += 1
            totalSize += allocatedSize
        }
        
        if !batch.isEmpty {
            continuation.yield(.batch(batch))
        }
        
        return (totalCount, totalSize)
    }
    
    // MARK: - Quick Scan
    
    /// Quick category scan for dashboard overview
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
