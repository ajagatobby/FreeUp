//
//  DashboardView.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import SwiftUI

/// Main dashboard view — dark, teal-accented, gradient-driven.
struct DashboardView: View {
    @Bindable var viewModel: ScanViewModel
    @State private var selectedCategory: FileCategory?
    @State private var showingPermissionsSheet = false
    @State private var showingDuplicates = false
    @State private var expandedCategories: Set<FileCategory> = [.cache]
    @State private var showCleanupConfirmation = false
    @State private var heroGlowPhase = false

    // MARK: - Derived state

    private var isScanning: Bool {
        if case .scanning = viewModel.scanState { return true }
        if case .detectingDuplicates = viewModel.scanState { return true }
        return false
    }

    private var sortedCategories: [FileCategory] {
        FileCategory.allCases.filter {
            viewModel.categoryStats[$0] != nil && viewModel.categoryStats[$0]!.count > 0
        }.sorted {
            (viewModel.categoryStats[$0]?.totalSize ?? 0) > (viewModel.categoryStats[$1]?.totalSize ?? 0)
        }
    }

    private var hasResults: Bool {
        !sortedCategories.isEmpty
    }

    private func hasSubCategories(_ category: FileCategory) -> Bool {
        viewModel.subCategoryStats(for: category).count > 1
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                // Deep dark background — fills entire window
                FUColors.bg
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // --- Storage bar ---
                        StorageBar(
                            volumeInfo: viewModel.volumeInfo,
                            reclaimableSpace: viewModel.reclaimableSpace
                        )

                        // --- Warning banners ---
                        if let warning = viewModel.snapshotWarning {
                            WarningBanner(
                                icon: "clock.arrow.circlepath",
                                message: warning,
                                tintColor: .orange
                            )
                        }

                        if viewModel.fullDiskAccessStatus == .denied {
                            WarningBanner(
                                icon: "lock.shield",
                                message: "Grant Full Disk Access to scan protected folders",
                                tintColor: .yellow,
                                action: ("Open Settings", {
                                    viewModel.openFullDiskAccessSettings()
                                })
                            )
                        }

                        // --- Duplicate detection progress ---
                        if case .detectingDuplicates(let progress) = viewModel.scanState {
                            HStack(spacing: 12) {
                                ProgressView(value: progress)
                                    .progressViewStyle(.linear)
                                    .tint(FUColors.accent)

                                Text("Finding duplicates...")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(FUColors.textSecondary)
                            }
                            .padding(.horizontal, 4)
                        }

                        // --- Hero scan button OR category grid ---
                        if !hasResults && !isScanning {
                            heroScanSection
                        } else {
                            categoryGridSection
                        }

                        // --- Reclaimable summary ---
                        if viewModel.reclaimableSpace > 0 && !isScanning {
                            ReclaimableSummary(
                                reclaimableSpace: viewModel.reclaimableSpace,
                                onCleanup: {
                                    showCleanupConfirmation = true
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .scrollContentBackground(.hidden)

                // --- Scanning overlay (only early scan) ---
                if isScanning && viewModel.totalFilesScanned < 100 {
                    Color.black.opacity(0.55)
                        .ignoresSafeArea()

                    ScanProgressView(
                        state: viewModel.scanState,
                        filesScanned: viewModel.totalFilesScanned,
                        sizeScanned: viewModel.totalSizeScanned,
                        onCancel: {
                            viewModel.cancelScan()
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .navigationTitle("FreeUp")
            .toolbarBackground(FUColors.bg, for: .windowToolbar)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if isScanning {
                        Button {
                            viewModel.cancelScan()
                        } label: {
                            Text("Cancel")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(FUColors.danger)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            Task {
                                await viewModel.startScan()
                            }
                        } label: {
                            Label("Scan", systemImage: "magnifyingglass")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(FUColors.accent)
                        }
                        .buttonStyle(.plain)

                        Menu {
                            Button("Smart Scan") {
                                Task { await viewModel.startScan() }
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
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(FUColors.textSecondary)
                        }
                        .menuStyle(.borderlessButton)
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
            // Cleanup confirmation
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
            // Deletion result
            .alert(
                viewModel.lastDeletionResult?.allSuccessful == true ? "Cleanup Complete" : "Cleanup Result",
                isPresented: Binding(
                    get: { viewModel.showDeletionResult },
                    set: { if !$0 { viewModel.dismissDeletionResult() } }
                )
            ) {
                Button("OK") { viewModel.dismissDeletionResult() }
                if viewModel.lastDeletionResult?.failureCount ?? 0 > 0 && viewModel.lastDeletionResult?.successCount == 0 {
                    Button("Open Privacy Settings") {
                        viewModel.openFullDiskAccessSettings()
                        viewModel.dismissDeletionResult()
                    }
                }
            } message: {
                if let result = viewModel.lastDeletionResult {
                    if result.successCount > 0 && result.failureCount == 0 {
                        Text("Freed \(ByteFormatter.format(result.freedSpace)). \(result.successCount) files removed.")
                    } else if result.successCount == 0 && result.failureCount > 0 {
                        Text("All \(result.failureCount) files failed to delete. Grant Full Disk Access in System Settings > Privacy & Security to allow FreeUp to remove protected files.")
                    } else {
                        Text("Freed \(ByteFormatter.format(result.freedSpace)). \(result.successCount) removed, \(result.failureCount) failed (may need Full Disk Access).")
                    }
                }
            }
            // Permissions sheet
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
                if viewModel.fullDiskAccessStatus == .denied {
                    showingPermissionsSheet = true
                }
            }
        }
    }

    // MARK: - Hero scan section (idle, no results)

    private var heroScanSection: some View {
        VStack(spacing: 24) {
            Spacer()
                .frame(height: 32)

            // Pulsing glow behind button
            ZStack {
                // Outer glow ring
                Circle()
                    .fill(FUColors.accent.opacity(heroGlowPhase ? 0.12 : 0.04))
                    .frame(width: 120, height: 120)
                    .blur(radius: 20)

                // Gradient circle button
                Button {
                    Task { await viewModel.startScan() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(FUColors.accentGradient)
                            .frame(width: 80, height: 80)
                            .shadow(
                                color: FUColors.accent.opacity(heroGlowPhase ? 0.45 : 0.2),
                                radius: heroGlowPhase ? 24 : 12,
                                y: 4
                            )

                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
            }
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 2.0)
                    .repeatForever(autoreverses: true)
                ) {
                    heroGlowPhase = true
                }
            }

            VStack(spacing: 6) {
                Text("Start Smart Scan")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(FUColors.textPrimary)

                Text("Analyze your storage and find reclaimable space")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(FUColors.textSecondary)
            }

            Spacer()
                .frame(height: 32)
        }
        .frame(maxWidth: .infinity)
        .fuCard(cornerRadius: 16, padding: 24)
    }

    // MARK: - Category grid section (results exist)

    private var categoryGridSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack(alignment: .firstTextBaseline) {
                Text("Found Items")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FUColors.textPrimary)

                if !sortedCategories.isEmpty {
                    let totalCount = sortedCategories.reduce(0) {
                        $0 + (viewModel.categoryStats[$1]?.count ?? 0)
                    }
                    Text("\(totalCount)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(FUColors.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(FUColors.accentDim)
                        )
                }

                Spacer()

                if case .completed(let files, let size, let duration) = viewModel.scanState {
                    Text("\(files) files  \(ByteFormatter.format(size))  \(formatDuration(duration))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(FUColors.textTertiary)
                }

                if isScanning {
                    InlineScanProgress(
                        state: viewModel.scanState,
                        filesScanned: viewModel.totalFilesScanned
                    )
                }
            }

            if sortedCategories.isEmpty && isScanning {
                // Placeholder during initial scan
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.1)
                        .tint(FUColors.accent)
                    Text("Finding junk files...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(FUColors.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                // Expandable categories first, then grid for the rest
                let expandableCategories = sortedCategories.filter { hasSubCategories($0) }
                let gridCategories = sortedCategories.filter { !hasSubCategories($0) }

                // Expandable sections
                ForEach(expandableCategories) { category in
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
                }

                // Grid of remaining category cards
                if !gridCategories.isEmpty {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(gridCategories) { category in
                            CategoryCard(
                                category: category,
                                stats: viewModel.categoryStats[category],
                                isScanning: false
                            ) {
                                selectedCategory = category
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? ""
    }
}

// MARK: - Warning Banner (dark themed)

struct WarningBanner: View {
    let icon: String
    let message: String
    let tintColor: Color
    var action: (title: String, handler: () -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            // Colored left accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(tintColor)
                .frame(width: 3)
                .padding(.vertical, 6)

            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tintColor)

                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(FUColors.textPrimary)

                Spacer()

                if let action {
                    Button(action: action.handler) {
                        Text(action.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tintColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(tintColor.opacity(0.12))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(tintColor.opacity(0.25), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(FUColors.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(FUColors.border, lineWidth: 1)
                )
        )
    }
}

// MARK: - Expandable Category Section (dark themed)

struct ExpandableCategorySection: View {
    let category: FileCategory
    let stats: CategoryStats?
    let subCategories: [(source: String, count: Int, totalSize: Int64)]
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onCategoryTap: () -> Void

    private var themeColor: Color { category.themeColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Category header
            HStack(spacing: 12) {
                Button(action: onToggleExpand) {
                    HStack(spacing: 10) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(FUColors.textTertiary)
                            .frame(width: 12)

                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(themeColor.opacity(0.12))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Image(systemName: category.iconName)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(themeColor)
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.rawValue)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(FUColors.textPrimary)

                            Text("\(subCategories.count) sources")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(FUColors.textSecondary)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                if let stats {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(ByteFormatter.format(stats.totalSize))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(themeColor)

                        Text("\(stats.formattedCount) items")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(FUColors.textSecondary)
                    }
                }

                Button(action: onCategoryTap) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(FUColors.textTertiary)
                        .padding(8)
                        .background(
                            Circle()
                                .fill(FUColors.bgHover)
                                .overlay(
                                    Circle()
                                        .stroke(FUColors.border, lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
                .help("View all \(category.rawValue) files")
            }
            .fuCard(cornerRadius: 14, padding: 14)

            // Sub-categories grid (when expanded)
            if isExpanded {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(subCategories, id: \.source) { subCat in
                        SubCategoryCard(
                            source: subCat.source,
                            count: subCat.count,
                            totalSize: subCat.totalSize,
                            color: themeColor
                        )
                    }
                }
                .padding(.leading, 24)
            }
        }
    }
}

// MARK: - Sub-Category Card (dark themed)

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
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(source)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FUColors.textPrimary)
                    .lineLimit(1)

                Text("\(count) files")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(FUColors.textTertiary)
            }

            Spacer()

            Text(ByteFormatter.format(totalSize))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? color.opacity(0.08) : FUColors.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isHovered ? color.opacity(0.25) : FUColors.border, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Reclaimable Summary (dark themed, gradient accent)

struct ReclaimableSummary: View {
    let reclaimableSpace: Int64
    let onCleanup: () -> Void

    @State private var isHoveredCleanup = false

    var body: some View {
        HStack(spacing: 16) {
            // Left: gradient accent strip
            RoundedRectangle(cornerRadius: 3)
                .fill(FUColors.accentGradient)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("Reclaimable Space")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FUColors.textPrimary)

                Text("Free up \(ByteFormatter.format(reclaimableSpace)) by removing cache, logs, and system junk.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(FUColors.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            // Prominent reclaimable size
            Text(ByteFormatter.format(reclaimableSpace))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(FUColors.accent)

            // Clean Up button with gradient
            Button(action: onCleanup) {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Clean Up")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(FUColors.accentGradient)
                        .shadow(
                            color: FUColors.accent.opacity(isHoveredCleanup ? 0.4 : 0.15),
                            radius: isHoveredCleanup ? 12 : 6,
                            y: 2
                        )
                )
                .scaleEffect(isHoveredCleanup ? 1.03 : 1.0)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.2)) {
                    isHoveredCleanup = hovering
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(FUColors.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(FUColors.border, lineWidth: 1)
                )
        )
    }
}
