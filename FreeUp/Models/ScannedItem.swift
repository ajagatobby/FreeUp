//
//  ScannedItem.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Represents a single scanned file with its metadata
@Model
final class ScannedItem {
    /// Unique identifier
    var id: UUID
    
    /// File path stored as string (URL not directly supported by SwiftData)
    var filePath: String
    
    /// Physical size allocated on disk (accounts for block size)
    var allocatedSize: Int64
    
    /// Logical file size
    var fileSize: Int64
    
    /// UTType identifier string
    var contentTypeIdentifier: String?
    
    /// Category for grouping
    var categoryRawValue: String
    
    /// Last access date for identifying stale files
    var lastAccessDate: Date?
    
    /// File content identifier for APFS clone detection
    var fileContentIdentifier: Int64?
    
    /// Whether this file is an APFS clone
    var isClone: Bool
    
    /// Whether the file is marked as purgeable by the system
    var isPurgeable: Bool
    
    /// Whether the user has selected this item for deletion
    var isSelected: Bool
    
    /// Parent directory path for hierarchy reconstruction
    var parentPath: String
    
    /// File name for display
    var fileName: String
    
    /// Relationship to scan session
    var session: ScanSession?
    
    /// Computed property for URL
    var url: URL {
        URL(fileURLWithPath: filePath)
    }
    
    /// Computed property for category
    var category: FileCategory {
        get { FileCategory(rawValue: categoryRawValue) ?? .other }
        set { categoryRawValue = newValue.rawValue }
    }
    
    /// Computed property for UTType
    var contentType: UTType? {
        guard let identifier = contentTypeIdentifier else { return nil }
        return UTType(identifier)
    }
    
    init(
        url: URL,
        allocatedSize: Int64,
        fileSize: Int64,
        contentType: UTType?,
        category: FileCategory,
        lastAccessDate: Date?,
        fileContentIdentifier: Int64?,
        isClone: Bool = false,
        isPurgeable: Bool = false
    ) {
        self.id = UUID()
        self.filePath = url.path
        self.allocatedSize = allocatedSize
        self.fileSize = fileSize
        self.contentTypeIdentifier = contentType?.identifier
        self.categoryRawValue = category.rawValue
        self.lastAccessDate = lastAccessDate
        self.fileContentIdentifier = fileContentIdentifier
        self.isClone = isClone
        self.isPurgeable = isPurgeable
        self.isSelected = false
        self.parentPath = url.deletingLastPathComponent().path
        self.fileName = url.lastPathComponent
    }
}

// MARK: - Display Helpers
extension ScannedItem {
    /// Check if file hasn't been accessed in over a year
    var isStale: Bool {
        guard let lastAccess = lastAccessDate else { return false }
        let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        return lastAccess < oneYearAgo
    }
    
    /// Formatted file size for display
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: allocatedSize, countStyle: .file)
    }
    
    /// Warning message if deleting won't free space
    var deletionWarning: String? {
        if isClone {
            return "This file is an APFS clone. Deleting it may not free disk space."
        }
        return nil
    }
}
