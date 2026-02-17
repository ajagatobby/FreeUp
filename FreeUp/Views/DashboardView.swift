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
    @State private var showingDuplicates = false
    @State private var expandedCategories: Set<FileCategory> = [.cache] // Cache expanded by default
    @State private var showCleanupConfirmation = false
    
    private var isScanning: Bool {
        if case .scanning = viewModel.scanState { return true }
        if case .detectingDuplicates = viewModel.scanState { return true }
        return false
    }
    
    private var sortedCategories: [FileCategory] {
        // Only show categories that have found items, sorted by size
        FileCategory.allCases.filter {
            viewModel.categoryStats[$0] != nil && viewModel.categoryStats[$0]!.count > 0
        }.sorted {
            (viewModel.categoryStats[$0]?.totalSize ?? 0) > (viewModel.categoryStats[$1]?.totalSize ?? 0)
        }
    }
    
    /// Categories that should show sub-categories (have multiple sources)
    private func hasSubCategories(_ category: FileCategory) -> Bool {
        let subStats = viewModel.subCategoryStats(for: category)
        return subStats.count > 1
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
                                message: "Grant Full Disk Access to scan protected folders",
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
                        
                        // Duplicate detection progress
                        if case .detectingDuplicates(let progress) = viewModel.scanState {
                            HStack(spacing: 12) {
                                ProgressView(value: progress)
                                    .progressViewStyle(.linear)
                                
                                Text("Finding duplicates...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                        }
                        
                        // Category grid
                        if sortedCategories.isEmpty && isScanning {
                            // Show placeholder during initial scan
                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(1.2)
                                Text("Finding junk files...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 200)
                        } else {
                            VStack(spacing: 16) {
                                ForEach(sortedCategories) { category in
                                    if hasSubCategories(category) {
                                        // Expandable category with sub-categories
                                        ExpandableCategorySection(
                                            category: category,
                                            stats: viewModel.categoryStats[category],
                                            subCategories: viewModel.subCategoryStats(for: category),
                                            isExpanded: expandedCategories.contains(category),
                                            onToggleExpand: {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    if expandedCategories.contains(category) {
                                                        expandedCategories.remove(category)
                                                    } else {
                                                        expandedCategories.insert(category)
                                                    }
                                                }
                                            },
                                            onCategoryTap: {
                                                selectedCategory = category
                                            }
                                        )
                                    } else {
                                        // Regular category card in a grid-like layout
                                        HStack {
                                            CategoryCard(
                                                category: category,
                                                stats: viewModel.categoryStats[category],
                                                isScanning: false
                                            ) {
                                                selectedCategory = category
                                            }
                                            .frame(maxWidth: 220)
                                            Spacer()
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Reclaimable space summary
                        if viewModel.reclaimableSpace > 0 && !isScanning {
                            ReclaimableSummary(
                                reclaimableSpace: viewModel.reclaimableSpace,
                                onCleanup: {
                                    showCleanupConfirmation = true
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
                            Label("Smart Scan", systemImage: "magnifyingglass")
                        }
                        
                        Menu {
                            Button("Smart Scan") {
                                Task {
                                    await viewModel.startScan()
                                }
                            }
                            
                            Divider()
                            
                            Button("Scan Custom Folder...") {
                                Task {
                                    if let url = await viewModel.selectDirectory() {
                                        await viewModel.startScan(directory: url)
                                    }
                                }
                            }
                            
                            Divider()
                            
                            Button("Privacy Settings...") {
                                viewModel.openFullDiskAccessSettings()
                            }
                        } label: {
                            Label("Options", systemImage: "ellipsis.circle")
                        }
                    }
                }
            }
            .navigationDestination(item: $selectedCategory) { category in
                if category == .duplicates {
                    DuplicatesView(viewModel: viewModel)
                } else {
                    CategoryDetailView(
                        category: category,
                        viewModel: viewModel
                    )
                }
            }
            .alert("Clean Up", isPresented: $showCleanupConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clean Up", role: .destructive) {
                    Task {
                        await viewModel.cleanUpReclaimableFiles()
                    }
                }
            } message: {
                Text("This will \(viewModel.currentDeleteMode == .moveToTrash ? "move to Trash" : "permanently delete") cache files, logs, and system junk to free up \(ByteFormatter.format(viewModel.reclaimableSpace)). Continue?")
            }
            .alert("Cleanup Complete", isPresented: Binding(
                get: { viewModel.showDeletionResult },
                set: { if !$0 { viewModel.dismissDeletionResult() } }
            )) {
                Button("OK") { viewModel.dismissDeletionResult() }
            } message: {
                if let result = viewModel.lastDeletionResult {
                    Text("Freed \(ByteFormatter.format(result.freedSpace)). \(result.successCount) files removed\(result.failureCount > 0 ? ", \(result.failureCount) failed" : "").")
                }
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

/// Expandable category section with sub-categories
struct ExpandableCategorySection: View {
    let category: FileCategory
    let stats: CategoryStats?
    let subCategories: [(source: String, count: Int, totalSize: Int64)]
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onCategoryTap: () -> Void
    
    private var color: Color { category.color }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Category header
            HStack(spacing: 12) {
                Button(action: onToggleExpand) {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 12)
                        
                        ZStack {
                            Circle()
                                .fill(color.opacity(0.15))
                                .frame(width: 40, height: 40)
                            
                            Image(systemName: category.iconName)
                                .font(.title3)
                                .foregroundStyle(color)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.rawValue)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            
                            Text("\(subCategories.count) sources")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                if let stats = stats {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(ByteFormatter.format(stats.totalSize))
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(color)
                        
                        Text("\(stats.count) items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Button(action: onCategoryTap) {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(8)
                        .background(Circle().fill(Color(.controlBackgroundColor)))
                }
                .buttonStyle(.plain)
                .help("View all \(category.rawValue) files")
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
            )
            
            // Sub-categories grid (when expanded)
            if isExpanded {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 160, maximum: 200))],
                    spacing: 10
                ) {
                    ForEach(subCategories, id: \.source) { subCat in
                        SubCategoryCard(
                            source: subCat.source,
                            count: subCat.count,
                            totalSize: subCat.totalSize,
                            color: color
                        )
                    }
                }
                .padding(.leading, 24)
            }
        }
    }
}

/// Small card for sub-category display
struct SubCategoryCard: View {
    let source: String
    let count: Int
    let totalSize: Int64
    let color: Color
    
    @State private var isHovered = false
    
    private var iconName: String {
        switch source.lowercased() {
        case let s where s.contains("safari"): return "safari"
        case let s where s.contains("chrome"): return "globe"
        case let s where s.contains("firefox"): return "flame"
        case let s where s.contains("edge"): return "globe"
        case let s where s.contains("brave"): return "shield"
        case let s where s.contains("xcode"): return "hammer"
        case let s where s.contains("simulator"): return "iphone"
        case let s where s.contains("npm"): return "shippingbox"
        case let s where s.contains("homebrew"): return "mug"
        case let s where s.contains("gradle"): return "g.circle"
        case let s where s.contains("cocoapods"): return "leaf"
        case let s where s.contains("cargo"): return "shippingbox"
        case let s where s.contains("spotlight"): return "magnifyingglass"
        case let s where s.contains("language"): return "character.book.closed"
        case let s where s.contains("container"): return "shippingbox"
        case let s where s.contains("system"): return "gear"
        case let s where s.contains("user"): return "person"
        case let s where s.contains("trash"): return "trash"
        case let s where s.contains("download"): return "arrow.down.circle"
        case let s where s.contains("log"): return "doc.text"
        case let s where s.contains("backup"): return "externaldrive"
        default: return "folder"
        }
    }
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(source)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Text("\(count) files")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(ByteFormatter.format(totalSize))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovered ? color.opacity(0.08) : Color(.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isHovered ? color.opacity(0.3) : .clear, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
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

#Preview("Dashboard") {
    DashboardView(viewModel: ScanViewModel())
}

#Preview("Expandable Section") {
    VStack(spacing: 20) {
        ExpandableCategorySection(
            category: .cache,
            stats: CategoryStats(count: 15000, totalSize: 2_500_000_000),
            subCategories: [
                (source: "Chrome Cache", count: 5000, totalSize: 800_000_000),
                (source: "Safari Cache", count: 3000, totalSize: 500_000_000),
                (source: "User Caches", count: 4000, totalSize: 450_000_000),
                (source: "Homebrew Cache", count: 200, totalSize: 400_000_000),
                (source: "Spotlight Index", count: 2800, totalSize: 350_000_000)
            ],
            isExpanded: true,
            onToggleExpand: {},
            onCategoryTap: {}
        )
        
        SubCategoryCard(
            source: "Safari Cache",
            count: 3000,
            totalSize: 500_000_000,
            color: .yellow
        )
    }
    .padding()
    .background(Color(.windowBackgroundColor))
}
