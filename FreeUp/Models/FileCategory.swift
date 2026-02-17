//
//  FileCategory.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Categories for organizing scanned files based on UTI conformance and path heuristics
@preconcurrency
enum FileCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case photos = "Photos"
    case videos = "Videos"
    case audio = "Audio"
    case documents = "Documents"
    case archives = "Archives"
    case applications = "Applications"
    case cache = "Cache"
    case logs = "Logs"
    case downloads = "Downloads"
    case systemJunk = "System Junk"
    case orphanedAppData = "Orphaned App Data"
    case developerFiles = "Developer Files"
    case duplicates = "Duplicates"
    case other = "Other"
    
    var id: String { rawValue }
    
    /// SF Symbol name for category icon
    var iconName: String {
        switch self {
        case .photos: return "photo.stack"
        case .videos: return "film.stack"
        case .audio: return "waveform"
        case .documents: return "doc.text"
        case .archives: return "archivebox"
        case .applications: return "app.badge"
        case .cache: return "externaldrive"
        case .logs: return "doc.text.magnifyingglass"
        case .downloads: return "arrow.down.circle"
        case .systemJunk: return "trash"
        case .orphanedAppData: return "questionmark.folder"
        case .developerFiles: return "hammer"
        case .duplicates: return "doc.on.doc"
        case .other: return "folder"
        }
    }
    
    /// Color for category visualization
    var colorName: String {
        switch self {
        case .photos: return "pink"
        case .videos: return "purple"
        case .audio: return "orange"
        case .documents: return "blue"
        case .archives: return "brown"
        case .applications: return "cyan"
        case .cache: return "yellow"
        case .logs: return "gray"
        case .downloads: return "green"
        case .systemJunk: return "red"
        case .orphanedAppData: return "indigo"
        case .developerFiles: return "mint"
        case .duplicates: return "teal"
        case .other: return "secondary"
        }
    }
    
    /// SwiftUI Color for category visualization (single source of truth)
    var color: Color {
        switch self {
        case .photos: return .pink
        case .videos: return .purple
        case .audio: return .orange
        case .documents: return .blue
        case .archives: return .brown
        case .applications: return .cyan
        case .cache: return .yellow
        case .logs: return .gray
        case .downloads: return .green
        case .systemJunk: return .red
        case .orphanedAppData: return .indigo
        case .developerFiles: return .mint
        case .duplicates: return .teal
        case .other: return .secondary
        }
    }
    
    /// Categorize a file based on its UTType and path
    /// - Parameters:
    ///   - contentType: The UTType of the file
    ///   - url: The file URL for path-based heuristics
    /// - Returns: The appropriate FileCategory
    nonisolated static func categorize(contentType: UTType?, url: URL) -> FileCategory {
        let path = url.path
        
        // Path-based heuristics first (more specific)
        if path.contains("/Caches/") || path.contains("/Cache/") {
            return .cache
        }
        
        if path.contains("/Logs/") || path.hasSuffix(".log") {
            return .logs
        }
        
        if path.contains("/Downloads/") || path.contains("/Downloads") {
            return .downloads
        }
        
        if path.contains("/Application Support/") {
            // Could be orphaned - let caller determine
            return .orphanedAppData
        }
        
        if path.contains("/.Trash/") || path.contains("/Trash/") {
            return .systemJunk
        }
        
        if path.contains("/DerivedData/") || 
           path.contains("/Xcode/") ||
           path.contains("/.npm/") ||
           path.contains("/node_modules/") ||
           path.contains("/.gradle/") ||
           path.contains("/Pods/") {
            return .developerFiles
        }
        
        // UTType-based categorization
        guard let type = contentType else {
            return .other
        }
        
        if type.conforms(to: .image) {
            return .photos
        }
        
        if type.conforms(to: .movie) || type.conforms(to: .video) {
            return .videos
        }
        
        if type.conforms(to: .audio) {
            return .audio
        }
        
        if type.conforms(to: .archive) || type.conforms(to: .zip) || type.conforms(to: .gzip) {
            return .archives
        }
        
        if type.conforms(to: .application) || type.conforms(to: .applicationBundle) {
            return .applications
        }
        
        if type.conforms(to: .pdf) || 
           type.conforms(to: .text) ||
           type.conforms(to: .spreadsheet) ||
           type.conforms(to: .presentation) {
            return .documents
        }
        
        return .other
    }
    
    /// Priority for display ordering (lower = higher priority)
    var displayPriority: Int {
        switch self {
        case .cache: return 0
        case .systemJunk: return 1
        case .logs: return 2
        case .duplicates: return 3
        case .developerFiles: return 4
        case .downloads: return 5
        case .videos: return 6
        case .photos: return 7
        case .audio: return 8
        case .archives: return 9
        case .orphanedAppData: return 10
        case .documents: return 11
        case .applications: return 12
        case .other: return 13
        }
    }
}
