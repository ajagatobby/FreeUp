//
//  DashboardView.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import SwiftUI

/// Main dashboard view with storage overview and category cards
struct DashboardView: View {
    @Bindable var viewModel: ScanViewModel
    @State private var selectedCategory: FileCategory?
    @State private var showingPermissionsSheet = false
    
    private var isScanning: Bool {
        if case .scanning = viewModel.scanState { return true }
        return false
    }
    
    private var sortedCategories: [FileCategory] {
        // Show categories with items first, sorted by size
        let withItems = FileCategory.allCases.filter {
            viewModel.categoryStats[$0] != nil && viewModel.categoryStats[$0]!.count > 0
        }.sorted {
            (viewModel.categoryStats[$0]?.totalSize ?? 0) > (viewModel.categoryStats[$1]?.totalSize ?? 0)
        }
        
        // Then show categories without items (for scanning state)
        let withoutItems = FileCategory.allCases.filter {
            viewModel.categoryStats[$0] == nil || viewModel.categoryStats[$0]!.count == 0
        }.sorted { $0.displayPriority < $1.displayPriority }
        
        return withItems + withoutItems
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(.windowBackgroundColor)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Storage bar
                        StorageBar(
                            volumeInfo: viewModel.volumeInfo,
                            reclaimableSpace: viewModel.reclaimableSpace
                        )
                        
                        // Snapshot warning
                        if let warning = viewModel.snapshotWarning {
                            WarningBanner(
                                icon: "clock.arrow.circlepath",
                                message: warning,
                                color: .orange
                            )
                        }
                        
                        // FDA warning if needed
                        if viewModel.fullDiskAccessStatus == .denied {
                            WarningBanner(
                                icon: "lock.shield",
                                message: "Grant Full Disk Access for a complete scan",
                                color: .yellow,
                                action: ("Open Settings", {
                                    viewModel.openFullDiskAccessSettings()
                                })
                            )
                        }
                        
                        // Scan controls
                        HStack {
                            Text("Categories")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Spacer()
                            
                            if case .completed(let files, let size, let duration) = viewModel.scanState {
                                Text("\(files) files • \(ByteFormatter.format(size)) • \(formatDuration(duration))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            if isScanning {
                                InlineScanProgress(
                                    state: viewModel.scanState,
                                    filesScanned: viewModel.totalFilesScanned
                                )
                            }
                        }
                        
                        // Category grid
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 180, maximum: 220))],
                            spacing: 16
                        ) {
                            ForEach(sortedCategories) { category in
                                CategoryCard(
                                    category: category,
                                    stats: viewModel.categoryStats[category],
                                    isScanning: isScanning && viewModel.categoryStats[category] == nil
                                ) {
                                    if let stats = viewModel.categoryStats[category], stats.count > 0 {
                                        selectedCategory = category
                                    }
                                }
                            }
                        }
                        
                        // Reclaimable space summary
                        if viewModel.reclaimableSpace > 0 && !isScanning {
                            ReclaimableSummary(
                                reclaimableSpace: viewModel.reclaimableSpace,
                                onCleanup: {
                                    // Navigate to cleanup confirmation
                                }
                            )
                        }
                    }
                    .padding()
                }
                
                // Scanning overlay
                if isScanning && viewModel.totalFilesScanned < 100 {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    ScanProgressView(
                        state: viewModel.scanState,
                        filesScanned: viewModel.totalFilesScanned,
                        sizeScanned: viewModel.totalSizeScanned,
                        onCancel: {
                            viewModel.cancelScan()
                        }
                    )
                }
            }
            .navigationTitle("FreeUp")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if isScanning {
                        Button("Cancel") {
                            viewModel.cancelScan()
                        }
                    } else {
                        Button {
                            Task {
                                await viewModel.startScan()
                            }
                        } label: {
                            Label("Scan", systemImage: "magnifyingglass")
                        }
                        
                        Menu {
                            Button("Scan Home Folder") {
                                Task {
                                    await viewModel.startScan()
                                }
                            }
                            
                            Button("Scan Custom Folder...") {
                                Task {
                                    if let url = await viewModel.selectDirectory() {
                                        await viewModel.startScan(directory: url)
                                    }
                                }
                            }
                            
                            Divider()
                            
                            Button("Full Disk Access Settings...") {
                                viewModel.openFullDiskAccessSettings()
                            }
                        } label: {
                            Label("Options", systemImage: "ellipsis.circle")
                        }
                    }
                }
            }
            .navigationDestination(item: $selectedCategory) { category in
                CategoryDetailView(
                    category: category,
                    files: viewModel.files(for: category),
                    viewModel: viewModel
                )
            }
            .sheet(isPresented: $showingPermissionsSheet) {
                PermissionsView(
                    fdaStatus: viewModel.fullDiskAccessStatus,
                    onOpenSettings: {
                        viewModel.openFullDiskAccessSettings()
                    },
                    onDismiss: {
                        showingPermissionsSheet = false
                        viewModel.checkPermissions()
                    }
                )
            }
            .onAppear {
                viewModel.checkPermissions()
                
                // Only show permissions sheet if FDA is explicitly denied
                // Don't show if granted or if we couldn't determine status
                if viewModel.fullDiskAccessStatus == .denied {
                    showingPermissionsSheet = true
                }
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? ""
    }
}

/// Warning banner for important messages
struct WarningBanner: View {
    let icon: String
    let message: String
    let color: Color
    var action: (title: String, handler: () -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
            
            Text(message)
                .font(.subheadline)
            
            Spacer()
            
            if let action = action {
                Button(action.title, action: action.handler)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.1))
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}

/// Summary of reclaimable space with cleanup action
struct ReclaimableSummary: View {
    let reclaimableSpace: Int64
    let onCleanup: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Reclaimable Space")
                    .font(.headline)
                
                Text("You can free up \(ByteFormatter.format(reclaimableSpace)) by removing cache, logs, and system junk.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button(action: onCleanup) {
                Label("Clean Up", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.1))
        )
    }
}

#Preview {
    DashboardView(viewModel: ScanViewModel())
}
