//
//  FreeUpApp.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import SwiftUI
import SwiftData

@main
struct FreeUpApp: App {
    
    init() {
        // Register app for Full Disk Access by attempting to access protected files
        // This will make the app appear in System Settings > Privacy & Security > Full Disk Access
        registerForFullDiskAccess()
        
        // Debug: Print FDA status on launch
        #if DEBUG
        let permissionService = PermissionService()
        let status = permissionService.checkFullDiskAccess()
        let detailed = permissionService.checkFullDiskAccessDetailed()
        print("=== Full Disk Access Status ===")
        print("Status: \(status)")
        print("Tested path: \(detailed.testedPath ?? "none")")
        print("Error: \(detailed.error ?? "none")")
        print("================================")
        #endif
    }
    
    /// Attempt to access protected files to register app in Full Disk Access list
    private func registerForFullDiskAccess() {
        let fileManager = FileManager.default
        
        // These paths require FDA - accessing them registers the app in the FDA list
        let protectedPaths = [
            NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db",
            NSHomeDirectory() + "/Library/Safari/History.db",
            NSHomeDirectory() + "/Library/Safari/CloudTabs.db",
            NSHomeDirectory() + "/Library/Messages/chat.db",
            NSHomeDirectory() + "/Library/Mail"
        ]
        
        for path in protectedPaths {
            // Attempting to read triggers FDA registration
            _ = fileManager.isReadableFile(atPath: path)
            
            // Also try to actually open the file (more aggressive registration)
            if let handle = FileHandle(forReadingAtPath: path) {
                handle.closeFile()
            }
        }
    }
    
    /// Shared model container for SwiftData persistence (in-memory for now)
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ScannedItem.self,
            ScanSession.self
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true  // Use in-memory to avoid schema migration issues
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    /// Main scan view model
    @State private var scanViewModel = ScanViewModel()
    
    /// Deletion view model
    @State private var deletionViewModel = DeletionViewModel()

    var body: some Scene {
        WindowGroup {
            DashboardView(viewModel: scanViewModel)
                .environment(deletionViewModel)
                .frame(minWidth: 800, minHeight: 600)
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            // File menu commands
            CommandGroup(replacing: .newItem) {
                Button("New Scan") {
                    Task {
                        await scanViewModel.startScan()
                    }
                }
                .keyboardShortcut("n", modifiers: .command)
                
                Button("Scan Custom Folder...") {
                    Task {
                        if let url = await scanViewModel.selectDirectory() {
                            await scanViewModel.startScan(directory: url)
                        }
                    }
                }
                .keyboardShortcut("o", modifiers: .command)
                
                Divider()
            }
            
            // Edit menu - selection commands
            CommandGroup(after: .pasteboard) {
                Divider()
                
                Button("Select All") {
                    // Select all in current category
                }
                .keyboardShortcut("a", modifiers: .command)
                
                Button("Deselect All") {
                    scanViewModel.selectedItems.removeAll()
                }
                .keyboardShortcut("d", modifiers: .command)
            }
            
            // View menu commands
            CommandGroup(replacing: .sidebar) {
                Button("Refresh") {
                    scanViewModel.checkPermissions()
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            
            // Help menu
            CommandGroup(replacing: .help) {
                Button("FreeUp Help") {
                    if let url = URL(string: "https://example.com/help") {
                        NSWorkspace.shared.open(url)
                    }
                }
                
                Divider()
                
                Button("Full Disk Access Settings...") {
                    scanViewModel.openFullDiskAccessSettings()
                }
            }
        }
        
        // Settings window
        Settings {
            SettingsView()
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @AppStorage("deleteMode") private var deleteMode = "trash"
    @AppStorage("showHiddenFiles") private var showHiddenFiles = false
    @AppStorage("autoScanOnLaunch") private var autoScanOnLaunch = false
    @AppStorage("batchSize") private var batchSize = 100
    
    var body: some View {
        TabView {
            GeneralSettingsView(
                deleteMode: $deleteMode,
                showHiddenFiles: $showHiddenFiles,
                autoScanOnLaunch: $autoScanOnLaunch
            )
            .tabItem {
                Label("General", systemImage: "gear")
            }
            
            PerformanceSettingsView(batchSize: $batchSize)
                .tabItem {
                    Label("Performance", systemImage: "speedometer")
                }
            
            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 300)
    }
}

struct GeneralSettingsView: View {
    @Binding var deleteMode: String
    @Binding var showHiddenFiles: Bool
    @Binding var autoScanOnLaunch: Bool
    
    var body: some View {
        Form {
            Section {
                Picker("When deleting files:", selection: $deleteMode) {
                    Text("Move to Trash").tag("trash")
                    Text("Delete Permanently").tag("permanent")
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text("Deletion")
            }
            
            Section {
                Toggle("Show hidden files in scan results", isOn: $showHiddenFiles)
                Toggle("Automatically scan on launch", isOn: $autoScanOnLaunch)
            } header: {
                Text("Behavior")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct PerformanceSettingsView: View {
    @Binding var batchSize: Int
    
    var body: some View {
        Form {
            Section {
                Picker("UI Update Batch Size:", selection: $batchSize) {
                    Text("50 files").tag(50)
                    Text("100 files (recommended)").tag(100)
                    Text("200 files").tag(200)
                    Text("500 files").tag(500)
                }
                
                Text("Larger batch sizes reduce UI updates during scanning but may feel less responsive.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Scanning Performance")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "externaldrive.badge.checkmark")
                .font(.system(size: 60))
                .foregroundStyle(Color.accentColor)
            
            Text("FreeUp")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Version 1.0")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Text("A high-performance macOS storage cleaner")
                .font(.body)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text("© 2026 Your Company")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
    }
}
