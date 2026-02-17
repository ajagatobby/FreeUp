//
//  DashboardView.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import SwiftUI

// MARK: - Dashboard (Sidebar + Detail Split)

/// CleanMyMac-style layout: fixed left sidebar with categories, right detail pane.
struct DashboardView: View {
    @Bindable var viewModel: ScanViewModel
    @State private var selectedCategory: FileCategory?
    @State private var showingPermissionsSheet = false
    @State private var showCleanupConfirmation = false

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

    private var hasResults: Bool { !sortedCategories.isEmpty }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            // ── Left sidebar ──
            sidebar
                .frame(width: 220)

            // Vertical divider
            Rectangle()
                .fill(FUColors.border)
                .frame(width: 1)

            // ── Right detail pane ──
            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(FUColors.bg)
        .preferredColorScheme(.dark)
        // Cleanup confirmation
        .alert("Clean Up", isPresented: $showCleanupConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clean Up", role: .destructive) {
                Task { await viewModel.cleanUpReclaimableFiles() }
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
                onOpenSettings: { viewModel.openFullDiskAccessSettings() },
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

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // App title area
            HStack(spacing: 8) {
                Image(systemName: "externaldrive.badge.checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FUColors.accent)

                Text("FreeUp")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(FUColors.textPrimary)

                Spacer()

                // Scan button
                Button {
                    Task { await viewModel.startScan() }
                } label: {
                    Image(systemName: isScanning ? "stop.fill" : "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isScanning ? FUColors.danger : FUColors.accent)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isScanning ? FUColors.dangerDim : FUColors.accentDim)
                        )
                }
                .buttonStyle(.plain)
                .help(isScanning ? "Stop scan" : "Start scan")
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Inline scan progress
            if isScanning {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(FUColors.accent)

                    Text("Scanning...")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(FUColors.textTertiary)

                    Spacer()

                    Text("\(viewModel.totalFilesScanned)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(FUColors.accent)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }

            Rectangle()
                .fill(FUColors.border)
                .frame(height: 1)

            // Category list
            ScrollView {
                LazyVStack(spacing: 2) {
                    if sortedCategories.isEmpty && !isScanning {
                        // Empty state
                        VStack(spacing: 8) {
                            Spacer().frame(height: 40)
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 20))
                                .foregroundStyle(FUColors.textTertiary)
                            Text("Run a scan to find files")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(FUColors.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        ForEach(sortedCategories) { category in
                            SidebarCategoryRow(
                                category: category,
                                stats: viewModel.categoryStats[category],
                                isSelected: selectedCategory == category,
                                action: {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        selectedCategory = category
                                    }
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .scrollContentBackground(.hidden)

            Spacer(minLength: 0)

            // Bottom: storage summary + clean up
            sidebarFooter
        }
        .background(FUColors.bgElevated)
    }

    // MARK: - Sidebar Footer

    private var sidebarFooter: some View {
        VStack(spacing: 8) {
            Rectangle()
                .fill(FUColors.border)
                .frame(height: 1)

            // Mini storage bar
            if let info = viewModel.volumeInfo {
                VStack(spacing: 4) {
                    HStack {
                        Text(info.name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(FUColors.textTertiary)
                        Spacer()
                        Text("\(ByteFormatter.format(info.availableCapacity)) free")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(FUColors.textTertiary)
                    }

                    // Tiny bar
                    GeometryReader { geo in
                        let ratio = Double(info.usedCapacity) / Double(max(info.totalCapacity, 1))
                        HStack(spacing: 1) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(FUColors.accent)
                                .frame(width: geo.size.width * CGFloat(min(ratio, 1.0)))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(FUColors.border)
                        }
                    }
                    .frame(height: 4)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                }
            }

            // Reclaimable + Clean Up
            if viewModel.reclaimableSpace > 0 && !isScanning {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Reclaimable")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(FUColors.textTertiary)
                            .textCase(.uppercase)
                        Text(ByteFormatter.format(viewModel.reclaimableSpace))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(FUColors.accent)
                    }

                    Spacer()

                    Button {
                        showCleanupConfirmation = true
                    } label: {
                        Text("Clean Up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(FUColors.accentGradient)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Settings link
            HStack(spacing: 6) {
                if viewModel.fullDiskAccessStatus == .denied {
                    Button {
                        viewModel.openFullDiskAccessSettings()
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(FUColors.cacheColor)
                                .frame(width: 5, height: 5)
                            Text("Grant Full Disk Access")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(FUColors.cacheColor)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .padding(.top, 4)
    }

    // MARK: - Detail Pane

    @ViewBuilder
    private var detailPane: some View {
        ZStack {
            FUColors.bg
                .ignoresSafeArea()

            if isScanning && !hasResults {
                // Full scan overlay when no results yet
                ScanProgressView(
                    state: viewModel.scanState,
                    filesScanned: viewModel.totalFilesScanned,
                    sizeScanned: viewModel.totalSizeScanned,
                    onCancel: { viewModel.cancelScan() }
                )
            } else if let category = selectedCategory {
                // Show category detail or duplicates
                if category == .duplicates {
                    DuplicatesView(viewModel: viewModel)
                } else {
                    CategoryDetailView(category: category, viewModel: viewModel)
                }
            } else {
                // Hero / overview pane
                overviewPane
            }
        }
    }

    // MARK: - Overview Pane (no category selected)

    private var overviewPane: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Storage bar
                StorageBar(
                    volumeInfo: viewModel.volumeInfo,
                    reclaimableSpace: viewModel.reclaimableSpace
                )

                // Warning banners
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
                        action: ("Open Settings", { viewModel.openFullDiskAccessSettings() })
                    )
                }

                // Duplicate detection progress
                if case .detectingDuplicates(let progress) = viewModel.scanState {
                    HStack(spacing: 12) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(FUColors.accent)
                        Text("Finding duplicates...")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(FUColors.textSecondary)
                    }
                }

                if !hasResults && !isScanning {
                    heroScanSection
                } else if hasResults {
                    scanSummarySection
                }

                // Reclaimable summary
                if viewModel.reclaimableSpace > 0 && !isScanning {
                    ReclaimableSummary(
                        reclaimableSpace: viewModel.reclaimableSpace,
                        onCleanup: { showCleanupConfirmation = true }
                    )
                }
            }
            .padding(24)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Hero Scan Section

    @State private var heroGlowPhase = false

    private var heroScanSection: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 40)

            ZStack {
                Circle()
                    .fill(FUColors.accent.opacity(heroGlowPhase ? 0.12 : 0.04))
                    .frame(width: 120, height: 120)
                    .blur(radius: 20)

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
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    heroGlowPhase = true
                }
            }

            VStack(spacing: 6) {
                Text("Start Smart Scan")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(FUColors.textPrimary)
                Text("Analyze your storage and find reclaimable space")
                    .font(.system(size: 13))
                    .foregroundStyle(FUColors.textSecondary)
            }

            Spacer().frame(height: 40)
        }
        .frame(maxWidth: .infinity)
        .fuCard(cornerRadius: 16, padding: 24)
    }

    // MARK: - Scan Summary (after scan, no category selected)

    private var scanSummarySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Text("Scan Results")
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
                        .background(Capsule().fill(FUColors.accentDim))
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

            // Category summary cards — compact horizontal rows
            VStack(spacing: 6) {
                ForEach(sortedCategories) { category in
                    SummaryCategoryRow(
                        category: category,
                        stats: viewModel.categoryStats[category],
                        action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedCategory = category
                            }
                        }
                    )
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

// MARK: - Summary Category Row (overview pane)

private struct SummaryCategoryRow: View {
    let category: FileCategory
    let stats: CategoryDisplayStats?
    let action: () -> Void

    @State private var isHovered = false

    private var themeColor: Color { category.themeColor }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(themeColor.opacity(0.10))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: category.iconName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(themeColor)
                    )

                Text(category.rawValue)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(FUColors.textPrimary)

                Spacer()

                if let stats {
                    Text("\(stats.formattedCount) items")
                        .font(.system(size: 11))
                        .foregroundStyle(FUColors.textTertiary)

                    Text(ByteFormatter.format(stats.totalSize))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(themeColor)
                        .frame(minWidth: 60, alignment: .trailing)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(FUColors.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovered ? FUColors.bgHover : FUColors.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isHovered ? themeColor.opacity(0.15) : FUColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Warning Banner

struct WarningBanner: View {
    let icon: String
    let message: String
    let tintColor: Color
    var action: (title: String, handler: () -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
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

// MARK: - Reclaimable Summary

struct ReclaimableSummary: View {
    let reclaimableSpace: Int64
    let onCleanup: () -> Void

    @State private var isHoveredCleanup = false

    var body: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 3)
                .fill(FUColors.accentGradient)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("Reclaimable Space")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FUColors.textPrimary)

                Text("Free up \(ByteFormatter.format(reclaimableSpace)) by removing cache, logs, and system junk.")
                    .font(.system(size: 12))
                    .foregroundStyle(FUColors.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Text(ByteFormatter.format(reclaimableSpace))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(FUColors.accent)

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
