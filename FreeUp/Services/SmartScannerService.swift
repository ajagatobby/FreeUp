//
//  SmartScannerService.swift
//  FreeUp
//
//  Lightning-fast scanner that targets KNOWN junk locations only
//  This is how CleanMyMac achieves 30-second scans
//
//  Strategy:
//  1. Pre-defined list of ~30 known junk locations
//  2. Scan ALL locations in parallel simultaneously
//  3. No UTType detection needed - category known from path
//  4. Use fts for fast traversal within each location
//  5. Minimal metadata collection (just size)
//

import Foundation
import UniformTypeIdentifiers

// MARK: - Scan Target

/// A specific directory to scan with its known category
private struct ScanTarget: Sendable {
    let url: URL
    let category: FileCategory
    let description: String
}

// MARK: - SmartScannerService

/// Lightning-fast scanner that only scans known junk locations
actor SmartScannerService {
    
    // MARK: - Configuration
    
    /// Batch size for yielding results
    private let batchSize: Int = 500
    
    private var isCancelled = false
    
    // MARK: - Known Junk Locations
    
    /// All known locations where cleanable files accumulate
    private static func getScanTargets() -> [ScanTarget] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library")
        
        var targets: [ScanTarget] = []
        
        // ============ CACHE (typically largest) ============
        // Scan ~/Library/Caches with smart source detection (sub-categorizes by app)
        // NOTE: Do NOT add individual browser cache targets -- they overlap with this
        targets.append(ScanTarget(
            url: library.appendingPathComponent("Caches"),
            category: .cache,
            description: "User Caches"
        ))
        targets.append(ScanTarget(
            url: URL(fileURLWithPath: "/Library/Caches"),
            category: .cache,
            description: "System Caches"
        ))
        
        // ============ LOGS ============
        targets.append(ScanTarget(
            url: library.appendingPathComponent("Logs"),
            category: .logs,
            description: "User Logs"
        ))
        targets.append(ScanTarget(
            url: URL(fileURLWithPath: "/Library/Logs"),
            category: .logs,
            description: "System Logs"
        ))
        targets.append(ScanTarget(
            url: URL(fileURLWithPath: "/var/log"),
            category: .logs,
            description: "Unix Logs"
        ))
        
        // ============ SYSTEM JUNK ============
        targets.append(ScanTarget(
            url: home.appendingPathComponent(".Trash"),
            category: .systemJunk,
            description: "Trash"
        ))
        targets.append(ScanTarget(
            url: library.appendingPathComponent("Saved Application State"),
            category: .systemJunk,
            description: "Saved App State"
        ))
        
        // ============ DEVELOPER FILES (often HUGE) ============
        targets.append(ScanTarget(
            url: library.appendingPathComponent("Developer/Xcode/DerivedData"),
            category: .developerFiles,
            description: "Xcode DerivedData"
        ))
        targets.append(ScanTarget(
            url: library.appendingPathComponent("Developer/Xcode/iOS DeviceSupport"),
            category: .developerFiles,
            description: "iOS Device Support"
        ))
        targets.append(ScanTarget(
            url: library.appendingPathComponent("Developer/Xcode/watchOS DeviceSupport"),
            category: .developerFiles,
            description: "watchOS Device Support"
        ))
        targets.append(ScanTarget(
            url: library.appendingPathComponent("Developer/CoreSimulator/Devices"),
            category: .developerFiles,
            description: "iOS Simulators"
        ))
        targets.append(ScanTarget(
            url: library.appendingPathComponent("Developer/Xcode/Archives"),
            category: .developerFiles,
            description: "Xcode Archives"
        ))
        targets.append(ScanTarget(
            url: home.appendingPathComponent(".npm"),
            category: .developerFiles,
            description: "NPM Cache"
        ))
        targets.append(ScanTarget(
            url: home.appendingPathComponent(".gradle"),
            category: .developerFiles,
            description: "Gradle Cache"
        ))
        targets.append(ScanTarget(
            url: home.appendingPathComponent(".cocoapods"),
            category: .developerFiles,
            description: "CocoaPods Cache"
        ))
        targets.append(ScanTarget(
            url: home.appendingPathComponent(".cargo"),
            category: .developerFiles,
            description: "Cargo Cache"
        ))
        targets.append(ScanTarget(
            url: home.appendingPathComponent(".pub-cache"),
            category: .developerFiles,
            description: "Dart/Flutter Cache"
        ))
        targets.append(ScanTarget(
            url: home.appendingPathComponent(".nuget"),
            category: .developerFiles,
            description: "NuGet Cache"
        ))
        targets.append(ScanTarget(
            url: home.appendingPathComponent(".m2"),
            category: .developerFiles,
            description: "Maven Cache"
        ))
        targets.append(ScanTarget(
            url: library.appendingPathComponent("Android/sdk"),
            category: .developerFiles,
            description: "Android SDK"
        ))
        // NOTE: CocoaPods Cache and Homebrew Cache are under ~/Library/Caches
        // and already covered by the general Caches target. Don't duplicate.
        
        // ============ DOWNLOADS ============
        targets.append(ScanTarget(
            url: home.appendingPathComponent("Downloads"),
            category: .downloads,
            description: "Downloads"
        ))
        targets.append(ScanTarget(
            url: library.appendingPathComponent("Mail Downloads"),
            category: .downloads,
            description: "Mail Downloads"
        ))
        
        // ============ iOS BACKUPS (can be HUGE) ============
        targets.append(ScanTarget(
            url: library.appendingPathComponent("Application Support/MobileSync/Backup"),
            category: .systemJunk,
            description: "iOS Backups"
        ))
        
        // NOTE: Language Models (Caches/com.apple.LanguageModeling) is already covered
        // by the ~/Library/Caches target. Spotlight Index is system-managed and should
        // not be offered for deletion.
        
        // NOTE: ~/Library/Application Support and ~/Library/Containers are intentionally
        // NOT scanned here. They contain active app data (often 100k+ files, multi-GB)
        // and scanning them causes 99% CPU, 3+ GB memory, and multi-minute stalls.
        // Orphaned app detection should use a shallow top-level-only approach instead.
        
        return targets
    }
    
    // MARK: - Public API
    
    func cancel() {
        isCancelled = true
    }
    
    private func resetCancellation() {
        isCancelled = false
    }
    
    /// Lightning-fast smart scan - only scans known junk locations
    func scan(directory: URL? = nil) -> AsyncStream<ScanResult> {
        AsyncStream { [weak self] continuation in
            guard let self = self else {
                continuation.finish()
                return
            }
            
            Task.detached(priority: .userInitiated) {
                await self.resetCancellation()
                await self.performSmartScan(continuation: continuation)
            }
        }
    }
    
    // MARK: - Core Smart Scan
    
    private func performSmartScan(
        continuation: AsyncStream<ScanResult>.Continuation
    ) async {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let targets = Self.getScanTargets()
        
        // Track totals
        var totalFiles = 0
        var totalSize: Int64 = 0
        
        // Scan ALL targets in parallel - this is the key to speed
        await withTaskGroup(of: (Int, Int64).self) { group in
            for target in targets {
                group.addTask { [weak self] in
                    guard let self = self else { return (0, 0) }
                    return await self.scanTarget(target, continuation: continuation)
                }
            }
            
            // Collect results as they complete
            for await (count, size) in group {
                totalFiles += count
                totalSize += size
                
                if self.isCancelled {
                    continuation.yield(.error(.cancelled))
                    continuation.finish()
                    return
                }
            }
        }
        
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let formattedSize = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
        print("⚡ SmartScanner: Scanned \(totalFiles) files (\(formattedSize)) in \(String(format: "%.2f", elapsed))s")
        
        continuation.yield(.completed(totalFiles: totalFiles, totalSize: totalSize))
        continuation.finish()
    }
    
    /// Scan a single target location using fts for speed
    private func scanTarget(
        _ target: ScanTarget,
        continuation: AsyncStream<ScanResult>.Continuation
    ) async -> (Int, Int64) {
        // Check if directory exists
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.url.path, isDirectory: &isDir),
              isDir.boolValue else {
            return (0, 0)
        }
        
        // Check if we can read it
        guard FileManager.default.isReadableFile(atPath: target.url.path) else {
            return (0, 0)
        }
        
        continuation.yield(.directoryStarted(target.url))
        
        var totalCount = 0
        var totalSize: Int64 = 0
        var batch: [ScannedFileInfo] = []
        batch.reserveCapacity(batchSize)
        
        // Use fts for fast traversal
        let path = target.url.path
        guard let pathCString = strdup(path) else {
            return (0, 0)
        }
        defer { free(pathCString) }
        
        var pathArray: [UnsafeMutablePointer<CChar>?] = [pathCString, nil]
        guard let fts = fts_open(&pathArray, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else {
            // Fallback to simple enumeration
            return await scanTargetFallback(target, continuation: continuation)
        }
        defer { fts_close(fts) }
        
        while let entry = fts_read(fts) {
            // Check cancellation every 500 files
            if totalCount % 500 == 0 && isCancelled {
                break
            }
            
            let info = entry.pointee.fts_info
            
            // Skip directories in results (but traverse them)
            guard info == FTS_F else { continue }
            
            // Get file info from fts stat (already populated - no extra syscall!)
            if let stat = entry.pointee.fts_statp {
                let allocatedSize = Int64(stat.pointee.st_blocks) * 512
                let fileSize = Int64(stat.pointee.st_size)
                let filePath = String(cString: entry.pointee.fts_path)
                let fileURL = URL(fileURLWithPath: filePath)
                
                // Category is already known from target - no UTType lookup needed!
                let fileInfo = ScannedFileInfo(
                    url: fileURL,
                    allocatedSize: allocatedSize,
                    fileSize: fileSize,
                    contentType: nil, // Skip UTType for speed
                    category: target.category,
                    lastAccessDate: nil, // Skip for speed
                    fileContentIdentifier: nil,
                    isPurgeable: false,
                    source: target.description
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
        }
        
        // Yield remaining files
        if !batch.isEmpty {
            continuation.yield(.batch(batch))
        }
        
        return (totalCount, totalSize)
    }
    
    /// Fallback using FileManager when fts fails
    private func scanTargetFallback(
        _ target: ScanTarget,
        continuation: AsyncStream<ScanResult>.Continuation
    ) async -> (Int, Int64) {
        var totalCount = 0
        var totalSize: Int64 = 0
        var batch: [ScannedFileInfo] = []
        batch.reserveCapacity(batchSize)
        
        let fm = FileManager.default
        let resourceKeys: Set<URLResourceKey> = [
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .isRegularFileKey,
            .isDirectoryKey
        ]
        
        guard let enumerator = fm.enumerator(
            at: target.url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return (0, 0)
        }
        
        while let fileURL = enumerator.nextObject() as? URL {
            if totalCount % 500 == 0 && isCancelled {
                break
            }
            
            guard let values = try? fileURL.resourceValues(forKeys: resourceKeys) else {
                continue
            }
            
            guard values.isRegularFile == true, values.isDirectory != true else {
                continue
            }
            
            let allocatedSize = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            
            let fileInfo = ScannedFileInfo(
                url: fileURL,
                allocatedSize: allocatedSize,
                fileSize: allocatedSize,
                contentType: nil,
                category: target.category,
                lastAccessDate: nil,
                fileContentIdentifier: nil,
                isPurgeable: false,
                source: target.description
            )
            
            batch.append(fileInfo)
            totalCount += 1
            totalSize += allocatedSize
            
            if batch.count >= batchSize {
                continuation.yield(.batch(batch))
                batch.removeAll(keepingCapacity: true)
            }
        }
        
        if !batch.isEmpty {
            continuation.yield(.batch(batch))
        }
        
        return (totalCount, totalSize)
    }
    
    // MARK: - Quick Stats (even faster - just sizes)
    
    /// Ultra-fast scan that only returns category totals (no file list)
    func quickStats() async -> [FileCategory: (count: Int, size: Int64)] {
        var results: [FileCategory: (count: Int, size: Int64)] = [:]
        
        let targets = Self.getScanTargets()
        
        await withTaskGroup(of: (FileCategory, Int, Int64).self) { group in
            for target in targets {
                group.addTask {
                    let (count, size) = await self.getDirectoryStats(target.url)
                    return (target.category, count, size)
                }
            }
            
            // Results are processed sequentially here - no lock needed
            for await (category, count, size) in group {
                var current = results[category] ?? (0, 0)
                current.count += count
                current.size += size
                results[category] = current
            }
        }
        
        return results
    }
    
    /// Get just count and size for a directory (no file enumeration)
    private func getDirectoryStats(_ url: URL) async -> (Int, Int64) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
              isDir.boolValue,
              FileManager.default.isReadableFile(atPath: url.path) else {
            return (0, 0)
        }
        
        var totalCount = 0
        var totalSize: Int64 = 0
        
        guard let pathCString = strdup(url.path) else {
            return (0, 0)
        }
        defer { free(pathCString) }
        
        var pathArray: [UnsafeMutablePointer<CChar>?] = [pathCString, nil]
        guard let fts = fts_open(&pathArray, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else {
            return (0, 0)
        }
        defer { fts_close(fts) }
        
        while let entry = fts_read(fts) {
            guard entry.pointee.fts_info == FTS_F else { continue }
            
            if let stat = entry.pointee.fts_statp {
                totalCount += 1
                totalSize += Int64(stat.pointee.st_blocks) * 512
            }
        }
        
        return (totalCount, totalSize)
    }
}
