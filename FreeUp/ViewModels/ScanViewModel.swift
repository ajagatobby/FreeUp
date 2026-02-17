//
//  ScanViewModel.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import Foundation
import SwiftUI
import AppKit

/// State of the scanning process
enum ScanState: Equatable {
    case idle
    case scanning(progress: Double, currentDirectory: String?)
    case detectingDuplicates(progress: Double)
    case completed(totalFiles: Int, totalSize: Int64, duration: TimeInterval)
    case error(String)
    
    static func == (lhs: ScanState, rhs: ScanState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case (.scanning(let p1, let d1), .scanning(let p2, let d2)):
            return p1 == p2 && d1 == d2
        case (.detectingDuplicates(let p1), .detectingDuplicates(let p2)):
            return p1 == p2
        case (.completed(let f1, let s1, let d1), .completed(let f2, let s2, let d2)):
            return f1 == f2 && s1 == s2 && d1 == d2
        case (.error(let e1), .error(let e2)):
            return e1 == e2
        default:
            return false
        }
    }
}

/// Main view model for scanning operations
/// Uses SmartScannerService for CleanMyMac-level speed (targets known junk locations only)
@MainActor
@Observable
final class ScanViewModel {
    
    // MARK: - Published State
    
    private(set) var scanState: ScanState = .idle
    private(set) var totalFilesScanned: Int = 0
    private(set) var totalSizeScanned: Int64 = 0
    private(set) var categoryStats: [FileCategory: CategoryStats] = [:]
    private(set) var volumeInfo: VolumeInfo?
    private(set) var snapshotWarning: String?
    private(set) var fullDiskAccessStatus: PermissionStatus = .notDetermined
    
    /// All scanned files grouped by category
    private(set) var scannedFiles: [FileCategory: [ScannedFileInfo]] = [:]
    
    /// Detected duplicate file groups
    private(set) var duplicateGroups: [DuplicateGroup] = []
    
    /// Selected items for deletion
    var selectedItems: Set<UUID> = []
    
    /// Whether deletion is in progress
    private(set) var isDeletingFiles = false
    
    /// Last deletion result for display
    private(set) var lastDeletionResult: DeletionResult?
    private(set) var showDeletionResult = false
    
    // MARK: - Services
    
    /// Lightning-fast scanner targeting known junk locations - PRIMARY (CleanMyMac-style)
    private let smartScanner = SmartScannerService()
    
    /// Ultra-fast scanner using BSD APIs - for custom directory scans
    private let ultraScanner = UltraScannerService()
    
    /// High-performance scanner using FileManager - FALLBACK
    private let turboScanner = TurboScannerService()
    
    /// Standard scanner - SECONDARY FALLBACK
    private let standardScanner = ScannerService()
    
    /// APFS service for clone detection and snapshots
    private let apfsService = APFSService()
    
    /// Permission service
    private let permissionService = PermissionService()
    
    /// Duplicate detection service
    private let duplicateService = DuplicateDetectionService()
    
    /// Deletion service
    private let deletionService = DeletionService()
    
    // MARK: - Computed Properties
    
    var reclaimableSpace: Int64 {
        let reclaimableCategories: [FileCategory] = [.cache, .logs, .systemJunk, .developerFiles, .duplicates]
        return reclaimableCategories.reduce(0) { sum, category in
            sum + (categoryStats[category]?.totalSize ?? 0)
        }
    }
    
    var isScanning: Bool {
        if case .scanning = scanState { return true }
        if case .detectingDuplicates = scanState { return true }
        return false
    }
    
    /// Total wasted space from duplicates
    var duplicateWastedSpace: Int64 {
        duplicateGroups.reduce(0) { $0 + $1.wastedSpace }
    }
    
    /// Total number of duplicate files (excluding originals)
    var totalDuplicateCount: Int {
        duplicateGroups.reduce(0) { $0 + $1.duplicateCount }
    }
    
    // MARK: - Settings
    
    var currentDeleteMode: DeletionService.DeleteMode {
        let mode = UserDefaults.standard.string(forKey: "deleteMode") ?? "trash"
        return mode == "permanent" ? .permanent : .moveToTrash
    }
    
    var showHiddenFiles: Bool {
        UserDefaults.standard.bool(forKey: "showHiddenFiles")
    }
    
    // MARK: - Public Methods
    
    /// Start a scan - uses SmartScanner for system cleanup, UltraScanner for custom directories
    func startScan(directory: URL? = nil) async {
        // Reset state
        scanState = .scanning(progress: 0, currentDirectory: nil)
        totalFilesScanned = 0
        totalSizeScanned = 0
        categoryStats = [:]
        scannedFiles = [:]
        selectedItems = []
        duplicateGroups = []
        
        // Clear APFS cache
        await apfsService.clearCache()
        
        // Get volume info
        volumeInfo = await apfsService.getVolumeInfo()
        
        // Check for snapshots (async, non-blocking)
        Task {
            snapshotWarning = await apfsService.snapshotWarning
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Choose scanner based on whether a specific directory is provided
        let scanStream: AsyncStream<ScanResult>
        let scannerName: String
        
        if let customDirectory = directory {
            // Custom directory scan - use UltraScanner or TurboScanner
            if await ultraScanner.canUseBSDAPIs(for: customDirectory) {
                scanStream = await ultraScanner.scan(directory: customDirectory)
                scannerName = "UltraScanner"
                print("Using UltraScanner for custom directory: \(customDirectory.path)")
            } else {
                scanStream = await turboScanner.scan(directory: customDirectory)
                scannerName = "TurboScanner"
                print("Using TurboScanner for custom directory: \(customDirectory.path)")
            }
        } else {
            // Default system scan - use SmartScanner for CleanMyMac-level speed
            scanStream = await smartScanner.scan()
            scannerName = "SmartScanner"
            print("Using SmartScanner (targeting known junk locations)")
        }
        
        // Process scan results
        for await result in scanStream {
            switch result {
            case .batch(let files):
                processBatch(files)
                
            case .progress(let file):
                processFile(file)
                
            case .directoryStarted(let url):
                let relativePath = url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
                scanState = .scanning(progress: estimateProgress(), currentDirectory: relativePath)
                
            case .directoryCompleted(_, fileCount: _, totalSize: _):
                // Update progress estimation
                scanState = .scanning(progress: estimateProgress(), currentDirectory: nil)
                
            case .error(let error):
                handleError(error)
                
            case .completed(totalFiles: let files, totalSize: let size):
                let duration = CFAbsoluteTimeGetCurrent() - startTime
                print("\(scannerName) completed: \(files) files, \(ByteFormatter.format(size)) in \(String(format: "%.2f", duration))s")
                
                // Now detect duplicates
                await detectDuplicates()
                
                // Filter orphaned app data (check if apps are still installed)
                filterOrphanedAppData()
                
                let totalDuration = CFAbsoluteTimeGetCurrent() - startTime
                scanState = .completed(totalFiles: totalFilesScanned, totalSize: totalSizeScanned, duration: totalDuration)
            }
        }
    }
    
    /// Cancel the current scan
    func cancelScan() {
        Task {
            await smartScanner.cancel()
            await ultraScanner.cancel()
            await turboScanner.cancel()
            await standardScanner.cancel()
            await duplicateService.cancel()
        }
        scanState = .idle
    }
    
    /// Get files for a specific category
    func files(for category: FileCategory) -> [ScannedFileInfo] {
        return scannedFiles[category] ?? []
    }
    
    /// Get sub-category stats for a category (grouped by source)
    func subCategoryStats(for category: FileCategory) -> [(source: String, count: Int, totalSize: Int64)] {
        let files = scannedFiles[category] ?? []
        var groups: [String: (count: Int, size: Int64)] = [:]
        
        for file in files {
            let source = file.source ?? "Other"
            var current = groups[source] ?? (0, 0)
            current.count += 1
            current.size += file.allocatedSize
            groups[source] = current
        }
        
        return groups.map { (source: $0.key, count: $0.value.count, totalSize: $0.value.size) }
            .sorted { $0.totalSize > $1.totalSize }
    }
    
    /// Check permissions status
    func checkPermissions() {
        fullDiskAccessStatus = permissionService.checkFullDiskAccess()
    }
    
    /// Open Full Disk Access settings
    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Select a directory using open panel
    func selectDirectory() async -> URL? {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.canCreateDirectories = false
                panel.title = "Select Folder to Scan"
                panel.prompt = "Scan"
                
                if panel.runModal() == .OK {
                    continuation.resume(returning: panel.url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    // MARK: - Deletion Methods
    
    /// Delete selected files
    func deleteSelectedFiles(from category: FileCategory) async {
        let files = scannedFiles[category] ?? []
        let selectedFiles = files.filter { file in
            let id = generateId(for: file)
            return selectedItems.contains(id)
        }
        
        guard !selectedFiles.isEmpty else { return }
        
        isDeletingFiles = true
        
        let result = await deletionService.deleteFilesSync(selectedFiles, mode: currentDeleteMode)
        
        // Remove deleted files from our data
        if result.successCount > 0 {
            removeDeletedFiles(selectedFiles, from: category)
        }
        
        lastDeletionResult = result
        showDeletionResult = true
        isDeletingFiles = false
    }
    
    /// Delete all reclaimable files (cache, logs, system junk, developer files)
    func cleanUpReclaimableFiles() async {
        let reclaimableCategories: [FileCategory] = [.cache, .logs, .systemJunk]
        var allFiles: [ScannedFileInfo] = []
        
        for category in reclaimableCategories {
            allFiles.append(contentsOf: scannedFiles[category] ?? [])
        }
        
        guard !allFiles.isEmpty else { return }
        
        isDeletingFiles = true
        
        let result = await deletionService.deleteFilesSync(allFiles, mode: currentDeleteMode)
        
        // Remove deleted files
        if result.successCount > 0 {
            for category in reclaimableCategories {
                let categoryFiles = scannedFiles[category] ?? []
                removeDeletedFiles(categoryFiles, from: category)
            }
        }
        
        lastDeletionResult = result
        showDeletionResult = true
        isDeletingFiles = false
    }
    
    /// Delete specific files (used by DuplicatesView)
    func deleteFiles(_ files: [ScannedFileInfo]) async {
        guard !files.isEmpty else { return }
        
        isDeletingFiles = true
        
        let result = await deletionService.deleteFilesSync(files, mode: currentDeleteMode)
        
        // Remove from duplicate groups and scanned files
        if result.successCount > 0 {
            let deletedURLs = Set(files.map { $0.url })
            
            // Update duplicate groups
            duplicateGroups = duplicateGroups.compactMap { group in
                let remaining = group.files.filter { !deletedURLs.contains($0.url) }
                if remaining.count <= 1 { return nil } // No longer a duplicate group
                return DuplicateGroup(
                    id: group.id,
                    hash: group.hash,
                    fileSize: group.fileSize,
                    files: remaining
                )
            }
            
            // Update category stats for duplicates
            updateDuplicateStats()
            
            // Also remove from original categories
            for file in files {
                removeDeletedFiles([file], from: file.category)
            }
        }
        
        lastDeletionResult = result
        showDeletionResult = true
        isDeletingFiles = false
    }
    
    /// Dismiss deletion result
    func dismissDeletionResult() {
        showDeletionResult = false
        lastDeletionResult = nil
    }
    
    /// Select all files in a category
    func selectAllFiles(in category: FileCategory) {
        let files = scannedFiles[category] ?? []
        for file in files {
            let id = generateId(for: file)
            selectedItems.insert(id)
        }
    }
    
    /// Deselect all files in a category
    func deselectAllFiles(in category: FileCategory) {
        let files = scannedFiles[category] ?? []
        for file in files {
            let id = generateId(for: file)
            selectedItems.remove(id)
        }
    }
    
    /// Generate consistent UUID from file URL
    func generateId(for file: ScannedFileInfo) -> UUID {
        let hash = file.url.path.hashValue
        let uuidString = String(format: "%08X-%04X-%04X-%04X-%012X",
                               UInt32(truncatingIfNeeded: hash),
                               UInt16(truncatingIfNeeded: hash >> 32),
                               UInt16(truncatingIfNeeded: hash >> 48),
                               UInt16(truncatingIfNeeded: hash >> 16),
                               UInt64(truncatingIfNeeded: hash))
        return UUID(uuidString: uuidString) ?? UUID()
    }
    
    // MARK: - Private Methods
    
    private func processBatch(_ files: [ScannedFileInfo]) {
        for file in files {
            processFile(file)
        }
        
        // Update state periodically (not on every file for performance)
        if totalFilesScanned % 1000 == 0 {
            scanState = .scanning(progress: estimateProgress(), currentDirectory: nil)
        }
    }
    
    private func processFile(_ file: ScannedFileInfo) {
        totalFilesScanned += 1
        totalSizeScanned += file.allocatedSize
        
        // Update category stats
        var stats = categoryStats[file.category] ?? CategoryStats(count: 0, totalSize: 0)
        stats.count += 1
        stats.totalSize += file.allocatedSize
        categoryStats[file.category] = stats
        
        // Store file reference
        var categoryFiles = scannedFiles[file.category] ?? []
        categoryFiles.append(file)
        scannedFiles[file.category] = categoryFiles
        
        // Register for clone detection
        if let identifier = file.fileContentIdentifier {
            Task {
                await apfsService.registerFileIdentifier(identifier, for: file.url.path)
            }
        }
    }
    
    private func handleError(_ error: ScanError) {
        switch error {
        case .accessDenied(let url):
            print("Access denied: \(url.path)")
        case .cancelled:
            scanState = .idle
        case .invalidPath(let path):
            scanState = .error("Invalid path: \(path)")
        case .unknown(let message):
            scanState = .error(message)
        }
    }
    
    private func estimateProgress() -> Double {
        // Rough progress estimation based on typical home directory size
        // Most home directories are 10-100K files
        let estimatedTotal = 50_000.0
        return min(0.99, Double(totalFilesScanned) / estimatedTotal)
    }
    
    // MARK: - Duplicate Detection
    
    private func detectDuplicates() async {
        scanState = .detectingDuplicates(progress: 0)
        
        // Collect all scanned files across all categories for duplicate detection
        // Exclude system junk and cache since duplicates there are expected
        let excludedCategories: Set<FileCategory> = [.cache, .logs, .systemJunk]
        var allFiles: [ScannedFileInfo] = []
        
        for (category, files) in scannedFiles {
            if !excludedCategories.contains(category) {
                allFiles.append(contentsOf: files)
            }
        }
        
        guard allFiles.count > 1 else { return }
        
        // Run duplicate detection with progress
        for await progress in await duplicateService.detectDuplicates(from: allFiles) {
            switch progress.phase {
            case .groupingBySize:
                scanState = .detectingDuplicates(progress: 0.1)
            case .hashing:
                scanState = .detectingDuplicates(progress: 0.1 + progress.percentage * 0.85)
            case .completed:
                scanState = .detectingDuplicates(progress: 1.0)
            }
        }
        
        // Get the final results
        duplicateGroups = await duplicateService.detectDuplicatesSync(from: allFiles)
        
        // Update stats for duplicates category
        updateDuplicateStats()
        
        if !duplicateGroups.isEmpty {
            print("Found \(duplicateGroups.count) duplicate groups, \(totalDuplicateCount) duplicate files, \(ByteFormatter.format(duplicateWastedSpace)) wasted")
        }
    }
    
    private func updateDuplicateStats() {
        if !duplicateGroups.isEmpty {
            // Create flat list of duplicate files for the category view
            var duplicateFiles: [ScannedFileInfo] = []
            for group in duplicateGroups {
                // Mark all files except the first as duplicates (first is the "original")
                for file in group.files.dropFirst() {
                    let dupFile = ScannedFileInfo(
                        url: file.url,
                        allocatedSize: file.allocatedSize,
                        fileSize: file.fileSize,
                        contentType: file.contentType,
                        category: .duplicates,
                        lastAccessDate: file.lastAccessDate,
                        fileContentIdentifier: file.fileContentIdentifier,
                        isPurgeable: file.isPurgeable,
                        source: "Duplicate of \(group.files.first?.fileName ?? "unknown")"
                    )
                    duplicateFiles.append(dupFile)
                }
            }
            
            scannedFiles[.duplicates] = duplicateFiles
            categoryStats[.duplicates] = CategoryStats(
                count: duplicateFiles.count,
                totalSize: duplicateWastedSpace
            )
        } else {
            scannedFiles.removeValue(forKey: .duplicates)
            categoryStats.removeValue(forKey: .duplicates)
        }
    }
    
    // MARK: - Orphaned App Data Filtering
    
    /// Filter orphaned app data to only include data for apps that are no longer installed
    private func filterOrphanedAppData() {
        guard var orphanedFiles = scannedFiles[.orphanedAppData], !orphanedFiles.isEmpty else { return }
        
        // Get list of installed applications
        let installedApps = getInstalledAppBundleIdentifiers()
        
        // Filter to only truly orphaned files
        let originalCount = orphanedFiles.count
        let originalSize = orphanedFiles.reduce(Int64(0)) { $0 + $1.allocatedSize }
        
        orphanedFiles = orphanedFiles.filter { file in
            let pathComponents = file.url.pathComponents
            // Look for bundle identifier in the path (e.g., com.apple.Safari)
            guard let appSupportIndex = pathComponents.firstIndex(of: "Application Support"),
                  appSupportIndex + 1 < pathComponents.count else {
                return true // Keep if we can't determine the app
            }
            
            let folderName = pathComponents[appSupportIndex + 1]
            
            // Check if this looks like a bundle identifier or app name
            // If the corresponding app is installed, this is NOT orphaned
            if installedApps.contains(folderName) {
                return false // App is installed, not orphaned
            }
            
            // Check if any installed app's bundle ID contains this folder name
            let folderLower = folderName.lowercased()
            for bundleId in installedApps {
                if bundleId.lowercased().contains(folderLower) || folderLower.contains(bundleId.lowercased()) {
                    return false
                }
            }
            
            return true // Truly orphaned
        }
        
        // Update the stored data
        scannedFiles[.orphanedAppData] = orphanedFiles
        let newSize = orphanedFiles.reduce(Int64(0)) { $0 + $1.allocatedSize }
        categoryStats[.orphanedAppData] = CategoryStats(count: orphanedFiles.count, totalSize: newSize)
        
        let filtered = originalCount - orphanedFiles.count
        if filtered > 0 {
            print("Filtered \(filtered) active app support entries (not orphaned)")
        }
    }
    
    /// Get bundle identifiers and names of all installed applications
    private func getInstalledAppBundleIdentifiers() -> Set<String> {
        var identifiers = Set<String>()
        
        let appDirs = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]
        
        let fm = FileManager.default
        for appDir in appDirs {
            guard let contents = try? fm.contentsOfDirectory(at: appDir, includingPropertiesForKeys: nil) else {
                continue
            }
            
            for item in contents {
                if item.pathExtension == "app" {
                    // Add the app name (without .app extension)
                    identifiers.insert(item.deletingPathExtension().lastPathComponent)
                    
                    // Try to read the bundle identifier from Info.plist
                    let plistURL = item.appendingPathComponent("Contents/Info.plist")
                    if let plistData = try? Data(contentsOf: plistURL),
                       let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
                       let bundleId = plist["CFBundleIdentifier"] as? String {
                        identifiers.insert(bundleId)
                        // Also add the last component of the bundle ID (e.g., "Safari" from "com.apple.Safari")
                        if let lastComponent = bundleId.split(separator: ".").last {
                            identifiers.insert(String(lastComponent))
                        }
                    }
                }
            }
        }
        
        return identifiers
    }
    
    // MARK: - File Removal After Deletion
    
    private func removeDeletedFiles(_ deletedFiles: [ScannedFileInfo], from category: FileCategory) {
        let deletedURLs = Set(deletedFiles.map { $0.url })
        
        // Remove from scanned files
        if var files = scannedFiles[category] {
            files.removeAll { deletedURLs.contains($0.url) }
            scannedFiles[category] = files
            
            // Update stats
            let newSize = files.reduce(Int64(0)) { $0 + $1.allocatedSize }
            categoryStats[category] = CategoryStats(count: files.count, totalSize: newSize)
        }
        
        // Remove from selected items
        for file in deletedFiles {
            let id = generateId(for: file)
            selectedItems.remove(id)
        }
    }
}

// MARK: - Full Disk Access Status Alias

/// Alias for compatibility with views that expect FullDiskAccessStatus
typealias FullDiskAccessStatus = PermissionStatus
