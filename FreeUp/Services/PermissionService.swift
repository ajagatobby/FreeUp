//
//  PermissionService.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import Foundation
import AppKit

/// Permission status for various access levels
enum PermissionStatus: Sendable {
    case granted
    case denied
    case notDetermined
    case restricted
}

/// Service for managing permissions, Full Disk Access checks, and security-scoped bookmarks
@MainActor
final class PermissionService {
    /// UserDefaults key for storing bookmarks
    private let bookmarksKey = "com.freeup.securityScopedBookmarks"
    
    /// Currently accessing URLs (for security scope management)
    private var accessingURLs: Set<URL> = []
    
    // MARK: - Full Disk Access
    
    /// Check if the app has Full Disk Access
    /// Uses multiple methods to reliably detect FDA status
    nonisolated func checkFullDiskAccess() -> PermissionStatus {
        let fileManager = FileManager.default
        
        // Method 1: Try to read the user's TCC database (most reliable)
        // This file ALWAYS exists and ALWAYS requires FDA to read
        let userTCCPath = NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db"
        
        if fileManager.fileExists(atPath: userTCCPath) {
            // Try to actually read the file, not just check if readable
            if let _ = try? Data(contentsOf: URL(fileURLWithPath: userTCCPath), options: .mappedIfSafe) {
                return .granted
            } else {
                return .denied
            }
        }
        
        // Method 2: Try to list the TCC directory contents
        let tccDir = NSHomeDirectory() + "/Library/Application Support/com.apple.TCC"
        do {
            _ = try fileManager.contentsOfDirectory(atPath: tccDir)
            return .granted
        } catch let error as NSError {
            if error.code == NSFileReadNoPermissionError || error.code == 257 {
                return .denied
            }
        }
        
        // Method 3: Fallback - try other protected locations
        let fallbackPaths = [
            NSHomeDirectory() + "/Library/Safari/CloudTabs.db",
            NSHomeDirectory() + "/Library/Safari/History.db",
            NSHomeDirectory() + "/Library/Messages/chat.db",
            NSHomeDirectory() + "/Library/Mail/V10"  // Mail database location
        ]
        
        for path in fallbackPaths {
            if fileManager.fileExists(atPath: path) {
                // Try to read the first byte
                if let handle = FileHandle(forReadingAtPath: path) {
                    handle.closeFile()
                    return .granted
                } else {
                    return .denied
                }
            }
        }
        
        // If we can't find any test files, assume not determined
        // This could happen on a fresh macOS install with no Safari/Mail usage
        return .notDetermined
    }
    
    /// More detailed FDA check that returns diagnostic info
    nonisolated func checkFullDiskAccessDetailed() -> (status: PermissionStatus, testedPath: String?, error: String?) {
        let fileManager = FileManager.default
        let userTCCPath = NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db"
        
        if fileManager.fileExists(atPath: userTCCPath) {
            do {
                _ = try Data(contentsOf: URL(fileURLWithPath: userTCCPath), options: .mappedIfSafe)
                return (.granted, userTCCPath, nil)
            } catch {
                return (.denied, userTCCPath, error.localizedDescription)
            }
        }
        
        return (.notDetermined, nil, "TCC database not found")
    }
    
    /// Open System Settings to Full Disk Access pane
    func openFullDiskAccessSettings() {
        // macOS 13+ uses new System Settings app
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Register app in Full Disk Access list (triggers by attempting to access protected file)
    nonisolated func registerForFullDiskAccess() {
        // Simply attempting to read a protected file will register the app
        // in System Settings > Privacy & Security > Full Disk Access (unchecked)
        let testPath = NSHomeDirectory() + "/Library/Safari/History.db"
        _ = FileManager.default.isReadableFile(atPath: testPath)
    }
    
    // MARK: - Security-Scoped Bookmarks
    
    /// Store a security-scoped bookmark for a URL
    /// - Parameter url: The URL to create a bookmark for
    /// - Returns: Success status
    nonisolated func storeBookmark(for url: URL) -> Bool {
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            
            var bookmarks = loadBookmarks()
            bookmarks[url.path] = bookmarkData
            saveBookmarks(bookmarks)
            
            return true
        } catch {
            print("Failed to create bookmark for \(url): \(error)")
            return false
        }
    }
    
    /// Resolve a stored bookmark to a URL and start accessing it
    /// - Parameter path: The original path the bookmark was created for
    /// - Returns: The resolved URL if successful
    nonisolated func resolveBookmark(for path: String) -> URL? {
        let bookmarks = loadBookmarks()
        
        guard let bookmarkData = bookmarks[path] else {
            return nil
        }
        
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            if isStale {
                // Bookmark is stale, try to recreate it
                _ = storeBookmark(for: url)
            }
            
            return url
        } catch {
            print("Failed to resolve bookmark for \(path): \(error)")
            return nil
        }
    }
    
    /// Start accessing a security-scoped URL
    /// - Parameter url: The URL to start accessing
    /// - Returns: Whether access was successfully started
    func startAccessingSecurityScopedResource(_ url: URL) -> Bool {
        guard url.startAccessingSecurityScopedResource() else {
            return false
        }
        accessingURLs.insert(url)
        return true
    }
    
    /// Stop accessing a security-scoped URL
    /// - Parameter url: The URL to stop accessing
    func stopAccessingSecurityScopedResource(_ url: URL) {
        if accessingURLs.contains(url) {
            url.stopAccessingSecurityScopedResource()
            accessingURLs.remove(url)
        }
    }
    
    /// Stop accessing all security-scoped resources
    func stopAccessingAllResources() {
        for url in accessingURLs {
            url.stopAccessingSecurityScopedResource()
        }
        accessingURLs.removeAll()
    }
    
    /// Get all stored bookmark paths
    nonisolated func getStoredBookmarkPaths() -> [String] {
        Array(loadBookmarks().keys)
    }
    
    /// Remove a stored bookmark
    nonisolated func removeBookmark(for path: String) {
        var bookmarks = loadBookmarks()
        bookmarks.removeValue(forKey: path)
        saveBookmarks(bookmarks)
    }
    
    // MARK: - Private Helpers
    
    private nonisolated func loadBookmarks() -> [String: Data] {
        UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] ?? [:]
    }
    
    private nonisolated func saveBookmarks(_ bookmarks: [String: Data]) {
        UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)
    }
    
    // MARK: - Directory Selection
    
    /// Present an open panel to select a directory
    /// - Parameter suggestedDirectory: Optional suggested starting directory
    /// - Returns: Selected URL if user made a selection
    func selectDirectory(suggestedDirectory: URL? = nil) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Select Folder to Scan"
        panel.message = "Choose a folder to scan for reclaimable storage"
        
        if let suggestedDir = suggestedDirectory {
            panel.directoryURL = suggestedDir
        } else {
            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        }
        
        let response = await panel.begin()
        
        guard response == .OK, let url = panel.url else {
            return nil
        }
        
        return url
    }
    
    /// Select directory and store bookmark for it
    func selectAndBookmarkDirectory() async -> URL? {
        guard let url = await selectDirectory() else {
            return nil
        }
        
        // Create bookmark for persistent access
        _ = storeBookmark(for: url)
        
        return url
    }
    
    // MARK: - Scan Permission Checks
    
    /// Check if we can scan a specific directory
    nonisolated func canScanDirectory(_ url: URL) -> Bool {
        let fileManager = FileManager.default
        return fileManager.isReadableFile(atPath: url.path)
    }
    
    /// Get directories we can scan without FDA
    nonisolated func getAccessibleDirectories() -> [URL] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        
        var accessible: [URL] = []
        
        let commonDirs = [
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Movies"),
            home.appendingPathComponent("Music"),
            home.appendingPathComponent("Pictures")
        ]
        
        for dir in commonDirs {
            if fileManager.isReadableFile(atPath: dir.path) {
                accessible.append(dir)
            }
        }
        
        return accessible
    }
    
    /// Directories that require FDA to scan
    nonisolated func getRestrictedDirectories() -> [URL] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        
        return [
            home.appendingPathComponent("Library"),
            URL(fileURLWithPath: "/Library"),
            URL(fileURLWithPath: "/System"),
            URL(fileURLWithPath: "/Applications")
        ]
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let fullDiskAccessGranted = Notification.Name("com.freeup.fullDiskAccessGranted")
    static let fullDiskAccessDenied = Notification.Name("com.freeup.fullDiskAccessDenied")
}
