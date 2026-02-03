//
//  ByteFormatter.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import Foundation

/// Utilities for formatting byte counts in human-readable form
enum ByteFormatter {
    /// Shared formatter configured for file sizes
    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        return formatter
    }()
    
    /// Format bytes to human-readable string (e.g., "4.5 GB")
    static func format(_ bytes: Int64) -> String {
        formatter.string(fromByteCount: bytes)
    }
    
    /// Format bytes with specific precision
    static func format(_ bytes: Int64, precision: Int) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var size = Double(bytes)
        var unitIndex = 0
        
        while size >= 1024 && unitIndex < units.count - 1 {
            size /= 1024
            unitIndex += 1
        }
        
        if unitIndex == 0 {
            return "\(Int(size)) \(units[unitIndex])"
        }
        
        return String(format: "%.\(precision)f %@", size, units[unitIndex])
    }
    
    /// Format bytes as abbreviated (e.g., "4.5G")
    static func formatAbbreviated(_ bytes: Int64) -> String {
        let units = ["B", "K", "M", "G", "T", "P"]
        var size = Double(bytes)
        var unitIndex = 0
        
        while size >= 1024 && unitIndex < units.count - 1 {
            size /= 1024
            unitIndex += 1
        }
        
        if unitIndex == 0 {
            return "\(Int(size))\(units[unitIndex])"
        }
        
        if size >= 100 {
            return "\(Int(size))\(units[unitIndex])"
        } else if size >= 10 {
            return String(format: "%.1f%@", size, units[unitIndex])
        } else {
            return String(format: "%.2f%@", size, units[unitIndex])
        }
    }
}

// MARK: - Int64 Extension
extension Int64 {
    /// Formatted as file size string
    var formattedAsFileSize: String {
        ByteFormatter.format(self)
    }
    
    /// Formatted as abbreviated file size
    var abbreviatedFileSize: String {
        ByteFormatter.formatAbbreviated(self)
    }
}
