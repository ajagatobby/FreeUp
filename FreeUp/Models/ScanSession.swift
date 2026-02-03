//
//  ScanSession.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import Foundation
import SwiftData

/// Represents a scanning session with aggregated statistics
@Model
final class ScanSession {
    /// Unique identifier
    var id: UUID
    
    /// When the scan started
    var startDate: Date
    
    /// When the scan completed (nil if still in progress)
    var endDate: Date?
    
    /// Root directory that was scanned
    var rootPath: String
    
    /// Total number of files scanned
    var totalFilesScanned: Int
    
    /// Total size of all scanned files
    var totalSize: Int64
    
    /// Potentially reclaimable space (cache + logs + junk)
    var reclaimableSize: Int64
    
    /// Whether the scan completed successfully
    var isComplete: Bool
    
    /// Error message if scan failed
    var errorMessage: String?
    
    /// Scanned items belonging to this session
    @Relationship(deleteRule: .cascade, inverse: \ScannedItem.session)
    var items: [ScannedItem]?
    
    /// Category breakdown stored as JSON
    var categoryBreakdownData: Data?
    
    init(rootPath: String) {
        self.id = UUID()
        self.startDate = Date()
        self.rootPath = rootPath
        self.totalFilesScanned = 0
        self.totalSize = 0
        self.reclaimableSize = 0
        self.isComplete = false
        self.items = []
    }
    
    /// Computed property for root URL
    var rootURL: URL {
        URL(fileURLWithPath: rootPath)
    }
    
    /// Duration of the scan
    var duration: TimeInterval? {
        guard let end = endDate else { return nil }
        return end.timeIntervalSince(startDate)
    }
    
    /// Formatted duration string
    var formattedDuration: String? {
        guard let duration = duration else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration)
    }
}

// MARK: - Category Breakdown
extension ScanSession {
    /// Category breakdown dictionary
    var categoryBreakdown: [FileCategory: CategoryStats] {
        get {
            guard let data = categoryBreakdownData,
                  let decoded = try? JSONDecoder().decode([String: CategoryStats].self, from: data) else {
                return [:]
            }
            var result: [FileCategory: CategoryStats] = [:]
            for (key, value) in decoded {
                if let category = FileCategory(rawValue: key) {
                    result[category] = value
                }
            }
            return result
        }
        set {
            var encoded: [String: CategoryStats] = [:]
            for (key, value) in newValue {
                encoded[key.rawValue] = value
            }
            categoryBreakdownData = try? JSONEncoder().encode(encoded)
        }
    }
    
    /// Update statistics for a category
    func updateCategory(_ category: FileCategory, size: Int64, count: Int = 1) {
        var breakdown = categoryBreakdown
        var stats = breakdown[category] ?? CategoryStats(count: 0, totalSize: 0)
        stats.count += count
        stats.totalSize += size
        breakdown[category] = stats
        categoryBreakdown = breakdown
        
        totalFilesScanned += count
        totalSize += size
        
        // Update reclaimable size for junk categories
        if category == .cache || category == .logs || category == .systemJunk || category == .developerFiles {
            reclaimableSize += size
        }
    }
    
    /// Mark scan as complete
    func complete() {
        endDate = Date()
        isComplete = true
    }
    
    /// Mark scan as failed
    func fail(with error: Error) {
        endDate = Date()
        isComplete = false
        errorMessage = error.localizedDescription
    }
}

/// Statistics for a single category
struct CategoryStats: Codable, Sendable {
    var count: Int
    var totalSize: Int64
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    var formattedCount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }
}

/// Alias for UI components that expect CategoryDisplayStats
typealias CategoryDisplayStats = CategoryStats
