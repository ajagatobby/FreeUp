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
    case completed(totalFiles: Int, totalSize: Int64, duration: TimeInterval)
    case error(String)
    
    static func == (lhs: ScanState, rhs: ScanState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case (.scanning(let p1, let d1), .scanning(let p2, let d2)):
            return p1 == p2 && d1 == d2
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
    
    /// Selected items for deletion
    var selectedItems: Set<UUID> = []
    
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
    
    // MARK: - Computed Properties
    
    var reclaimableSpace: Int64 {
        let reclaimableCategories: [FileCategory] = [.cache, .logs, .systemJunk, .developerFiles]
        return reclaimableCategories.reduce(0) { sum, category in
            sum + (categoryStats[category]?.totalSize ?? 0)
        }
    }
    
    var isScanning: Bool {
        if case .scanning = scanState { return true }
        return false
    }
    
    // MARK: - Public Methods
    
    /// Start a scan - uses SmartScanner for system cleanup, UltraScanner for custom directories
    /// SmartScanner achieves CleanMyMac-level speed by only scanning known junk locations
    func startScan(directory: URL? = nil) async {
        // Reset state
        scanState = .scanning(progress: 0, currentDirectory: nil)
        totalFilesScanned = 0
        totalSizeScanned = 0
        categoryStats = [:]
        scannedFiles = [:]
        selectedItems = []
        
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
                print("🚀 Using UltraScanner for custom directory: \(customDirectory.path)")
            } else {
                scanStream = await turboScanner.scan(directory: customDirectory)
                scannerName = "TurboScanner"
                print("⚡ Using TurboScanner for custom directory: \(customDirectory.path)")
            }
        } else {
            // Default system scan - use SmartScanner for CleanMyMac-level speed
            scanStream = await smartScanner.scan()
            scannerName = "SmartScanner"
            print("⚡ Using SmartScanner (targeting known junk locations)")
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
                scanState = .completed(totalFiles: files, totalSize: size, duration: duration)
                print("✅ \(scannerName) completed: \(files) files, \(ByteFormatter.format(size)) in \(String(format: "%.2f", duration))s")
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
            print("⚠️ Access denied: \(url.path)")
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
}

// MARK: - Full Disk Access Status Alias

/// Alias for compatibility with views that expect FullDiskAccessStatus
typealias FullDiskAccessStatus = PermissionStatus
