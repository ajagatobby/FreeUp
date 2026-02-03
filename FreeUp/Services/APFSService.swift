//
//  APFSService.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import Foundation

/// Information about an APFS snapshot
struct APFSSnapshot: Identifiable, Sendable {
    let id: UUID
    let name: String
    let date: Date?
    let size: Int64?
    
    nonisolated init(name: String, date: Date? = nil, size: Int64? = nil) {
        self.id = UUID()
        self.name = name
        self.date = date
        self.size = size
    }
}

/// Information about APFS clone status
struct CloneInfo: Sendable {
    let fileContentIdentifier: Int64
    let referenceCount: Int
    let isLastReference: Bool
    
    /// Whether deleting this file will actually free space
    var willFreeSpace: Bool { isLastReference }
}

/// Service for APFS-specific operations: clone detection and snapshot handling
actor APFSService {
    /// Cache of file content identifiers for clone detection
    private var contentIdentifierCache: [Int64: Set<String>] = [:]
    
    /// Detected snapshots on the volume
    private var detectedSnapshots: [APFSSnapshot] = []
    
    /// Whether snapshots have been checked
    private var snapshotsChecked = false
    
    // MARK: - Clone Detection
    
    /// Register a file's content identifier for clone tracking
    /// - Parameters:
    ///   - identifier: The file content identifier from URLResourceValues
    ///   - path: The file path
    func registerFileIdentifier(_ identifier: Int64, for path: String) {
        var paths = contentIdentifierCache[identifier] ?? []
        paths.insert(path)
        contentIdentifierCache[identifier] = paths
    }
    
    /// Register multiple files for batch processing
    func registerFiles(_ files: [(identifier: Int64, path: String)]) {
        for (identifier, path) in files {
            var paths = contentIdentifierCache[identifier] ?? []
            paths.insert(path)
            contentIdentifierCache[identifier] = paths
        }
    }
    
    /// Check if a file is a clone (shares content with other files)
    /// - Parameter identifier: The file content identifier
    /// - Returns: CloneInfo with reference count and space reclaim status
    func checkCloneStatus(identifier: Int64) -> CloneInfo {
        let paths = contentIdentifierCache[identifier] ?? []
        return CloneInfo(
            fileContentIdentifier: identifier,
            referenceCount: paths.count,
            isLastReference: paths.count <= 1
        )
    }
    
    /// Get all clone groups (files sharing the same content)
    /// - Returns: Dictionary mapping content identifiers to arrays of file paths
    func getCloneGroups() -> [Int64: [String]] {
        contentIdentifierCache
            .filter { $0.value.count > 1 }
            .mapValues { Array($0) }
    }
    
    /// Calculate actual space savings if specific files are deleted
    /// - Parameter files: Array of (identifier, size) tuples for files to delete
    /// - Returns: Actual bytes that will be freed (accounting for clones)
    func calculateActualSavings(files: [(identifier: Int64?, size: Int64)]) -> Int64 {
        var identifiersToDelete: [Int64: Int64] = [:]
        var savings: Int64 = 0
        
        for (identifier, size) in files {
            if let id = identifier {
                // Track the size for each identifier
                if identifiersToDelete[id] == nil {
                    identifiersToDelete[id] = size
                }
            } else {
                // No identifier means not a clone, will free space
                savings += size
            }
        }
        
        // For each unique identifier, check if it's the last reference
        for (identifier, size) in identifiersToDelete {
            let cloneInfo = checkCloneStatus(identifier: identifier)
            if cloneInfo.isLastReference {
                savings += size
            }
        }
        
        return savings
    }
    
    /// Clear the clone cache (call when starting a new scan)
    func clearCache() {
        contentIdentifierCache.removeAll()
    }
    
    // MARK: - Snapshot Detection
    
    /// Check for local Time Machine snapshots
    /// - Parameter volumePath: Path to the volume (defaults to root)
    /// - Returns: Array of detected snapshots
    func checkSnapshots(volumePath: String = "/") async -> [APFSSnapshot] {
        if snapshotsChecked {
            return detectedSnapshots
        }
        
        detectedSnapshots = await listSnapshots(volumePath: volumePath)
        snapshotsChecked = true
        return detectedSnapshots
    }
    
    /// List APFS snapshots using tmutil
    private func listSnapshots(volumePath: String) async -> [APFSSnapshot] {
        // Use tmutil to list local snapshots
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["listlocalsnapshots", volumePath]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return []
            }
            
            // Parse output: each line is a snapshot name
            // Format: com.apple.TimeMachine.2024-01-15-123456.local
            return output
                .components(separatedBy: .newlines)
                .filter { $0.hasPrefix("com.apple.TimeMachine") }
                .compactMap { parseSnapshotName($0) }
        } catch {
            return []
        }
    }
    
    /// Parse snapshot name to extract date
    private func parseSnapshotName(_ name: String) -> APFSSnapshot? {
        // Format: com.apple.TimeMachine.YYYY-MM-DD-HHMMSS.local
        let components = name.components(separatedBy: ".")
        guard components.count >= 3 else {
            return APFSSnapshot(name: name)
        }
        
        let dateString = components[2] // YYYY-MM-DD-HHMMSS
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let date = formatter.date(from: dateString)
        
        return APFSSnapshot(name: name, date: date)
    }
    
    /// Check if there are any snapshots that might prevent space reclamation
    var hasSnapshots: Bool {
        get async {
            if !snapshotsChecked {
                _ = await checkSnapshots()
            }
            return !detectedSnapshots.isEmpty
        }
    }
    
    /// Get warning message if snapshots exist
    var snapshotWarning: String? {
        get async {
            guard await hasSnapshots else { return nil }
            let count = detectedSnapshots.count
            return "Found \(count) local Time Machine snapshot\(count == 1 ? "" : "s"). Deleting files may not immediately free space until snapshots are removed."
        }
    }
    
    /// Attempt to thin local snapshots (requires elevated privileges)
    /// - Parameter urgentGB: Amount of space needed in GB
    /// - Returns: Success status and any error message
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
                // Refresh snapshot list
                snapshotsChecked = false
                _ = await checkSnapshots()
                return (true, "Successfully thinned local snapshots")
            } else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                return (false, "Failed to thin snapshots: \(errorMessage)")
            }
        } catch {
            return (false, "Error executing tmutil: \(error.localizedDescription)")
        }
    }
    
    /// Reset snapshot check status (call when user wants to refresh)
    func resetSnapshotCheck() {
        snapshotsChecked = false
        detectedSnapshots = []
    }
    
    // MARK: - Volume Information
    
    /// Get APFS volume information
    func getVolumeInfo(for path: String = "/") async -> VolumeInfo? {
        let url = URL(fileURLWithPath: path)
        
        do {
            let resourceValues = try url.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityForOpportunisticUsageKey,
                .volumeIsLocalKey,
                .volumeNameKey
            ])
            
            return VolumeInfo(
                name: resourceValues.volumeName ?? "Macintosh HD",
                totalCapacity: Int64(resourceValues.volumeTotalCapacity ?? 0),
                availableCapacity: Int64(resourceValues.volumeAvailableCapacity ?? 0),
                availableForImportantUsage: Int64(resourceValues.volumeAvailableCapacityForImportantUsage ?? 0),
                availableForOpportunisticUsage: Int64(resourceValues.volumeAvailableCapacityForOpportunisticUsage ?? 0),
                isLocal: resourceValues.volumeIsLocal ?? true
            )
        } catch {
            return nil
        }
    }
}

/// Volume capacity information
struct VolumeInfo: Sendable {
    let name: String
    let totalCapacity: Int64
    let availableCapacity: Int64
    let availableForImportantUsage: Int64
    let availableForOpportunisticUsage: Int64
    let isLocal: Bool
    
    /// Used capacity
    var usedCapacity: Int64 {
        totalCapacity - availableCapacity
    }
    
    /// Usage percentage (0-100)
    var usagePercentage: Double {
        guard totalCapacity > 0 else { return 0 }
        return Double(usedCapacity) / Double(totalCapacity) * 100
    }
    
    /// Purgeable space (difference between opportunistic and important usage)
    var purgeableSpace: Int64 {
        availableForOpportunisticUsage - availableForImportantUsage
    }
    
    /// Formatted strings for display
    var formattedTotal: String { ByteFormatter.format(totalCapacity) }
    var formattedAvailable: String { ByteFormatter.format(availableCapacity) }
    var formattedUsed: String { ByteFormatter.format(usedCapacity) }
    var formattedPurgeable: String { ByteFormatter.format(purgeableSpace) }
}
