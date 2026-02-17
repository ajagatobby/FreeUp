//
//  CategoryDetailView.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Lightweight display model

/// Pre-computed group for display — built once off main thread, not per-render
private struct DisplayGroup: Identifiable, Sendable {
    let id: String
    let source: String
    let fileCount: Int
    let totalSize: Int64
    /// Only the top N files for display — avoids holding 20k structs in view state
    let previewFiles: [ScannedFileInfo]
    /// All file IDs in this group (for select-all, lightweight)
    let allFileIDs: [UUID]
}

/// Detail view for a specific file category.
/// Performance strategy:
/// - Don't accept a files array prop (avoids 20k element copy on navigation)
/// - Sort/group off main thread via Task
/// - Track selection count incrementally, not by iterating all files
/// - Show only top 200 files per section; load more on demand
struct CategoryDetailView: View {
    let category: FileCategory
    @Bindable var viewModel: ScanViewModel

    @State private var sortOrder: SortOrder = .sizeDescending
    @State private var searchText = ""
    @State private var showCloneWarning = false
    @State private var expandedSections: Set<String> = []

    // Pre-computed display data (built off main thread)
    @State private var displayGroups: [DisplayGroup] = []
    @State private var displayFlatFiles: [ScannedFileInfo] = []
    @State private var hasMultipleSources = false
    @State private var totalFileCount: Int = 0
    @State private var totalSize: Int64 = 0
    @State private var isLoading = true

    // Selection tracking — updated incrementally, NOT by iterating all files
    @State private var localSelectedCount: Int = 0
    @State private var localSelectedSize: Int64 = 0

    /// Max files to show per section (pagination)
    private let pageSize = 200

    var body: some View {
        VStack(spacing: 0) {
            // Header
            CategoryHeader(
                category: category,
                totalFiles: totalFileCount,
                totalSize: totalSize,
                selectedCount: localSelectedCount,
                selectedSize: localSelectedSize
            )

            // Inline toolbar: search + sort + select all
            HStack(spacing: 8) {
                // Search field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(FUColors.textTertiary)
                    TextField("Search files...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(FUColors.textPrimary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(FUColors.bgCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(FUColors.border, lineWidth: 1)
                        )
                )

                sortMenu
                    .font(.system(size: 11, weight: .medium))

                selectAllButton
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(FUColors.bgElevated)

            Rectangle()
                .fill(FUColors.border)
                .frame(height: 1)

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(FUColors.textSecondary)
                    Text("Loading files...")
                        .font(.subheadline)
                        .foregroundStyle(FUColors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(FUColors.bg)
            } else if displayFlatFiles.isEmpty && displayGroups.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Files" : "No Results",
                    systemImage: searchText.isEmpty ? "folder" : "magnifyingglass",
                    description: Text(searchText.isEmpty ? "No files found in this category" : "Try a different search term")
                )
            } else if hasMultipleSources {
                groupedListView
                    .background(FUColors.bg)
            } else {
                flatListView
                    .background(FUColors.bg)
            }

            // Bottom action bar
            if localSelectedCount > 0 {
                SelectionActionBar(
                    selectedCount: localSelectedCount,
                    selectedSize: localSelectedSize,
                    isDeleting: viewModel.isDeletingFiles,
                    onDelete: {
                        Task {
                            await viewModel.deleteSelectedFiles(from: category)
                            recomputeSelectionFromScratch()
                        }
                    },
                    onDeselect: {
                        deselectAll()
                    }
                )
            }
        }
        .background(FUColors.bg)
        .alert("Clone Warning", isPresented: $showCloneWarning) {
            Button("OK") { }
        } message: {
            Text("This file appears to be an APFS clone. Deleting it may not free disk space if other files share the same data blocks.")
        }
        .task(id: SortSearchKey(sort: sortOrder, search: searchText)) {
            await rebuildDisplayData()
        }
    }

    // MARK: - Grouped List

    private var groupedListView: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(displayGroups) { group in
                    Section {
                        if expandedSections.contains(group.source) {
                            ForEach(Array(group.previewFiles.enumerated()), id: \.element.id) { index, file in
                                fileRow(for: file, index: index)
                            }
                            if group.fileCount > group.previewFiles.count {
                                Text("\(group.fileCount - group.previewFiles.count) more files...")
                                    .font(.caption)
                                    .foregroundStyle(FUColors.textTertiary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                        }
                    } header: {
                        SourceSectionHeader(
                            source: group.source,
                            fileCount: group.fileCount,
                            totalSize: group.totalSize,
                            isCollapsed: !expandedSections.contains(group.source),
                            color: category.themeColor,
                            onToggle: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if expandedSections.contains(group.source) {
                                        expandedSections.remove(group.source)
                                    } else {
                                        expandedSections.insert(group.source)
                                    }
                                }
                            },
                            onSelectAll: {
                                selectFiles(ids: group.allFileIDs, files: group.previewFiles)
                            }
                        )
                        .background(FUColors.bgElevated)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
    }

    // MARK: - Flat List

    private var flatListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(displayFlatFiles.enumerated()), id: \.element.id) { index, file in
                    fileRow(for: file, index: index)
                }
            }
            .padding(.horizontal, 8)
        }
    }

    // MARK: - File Row

    @ViewBuilder
    private func fileRow(for file: ScannedFileInfo, index: Int) -> some View {
        let isSelected = viewModel.selectedItems.contains(file.id)
        let isClone = file.fileContentIdentifier != nil

        FileRowView(
            file: file,
            isSelected: isSelected,
            isClone: isClone,
            index: index,
            onToggleSelection: {
                toggleSelection(file: file)
            },
            onRevealInFinder: {
                NSWorkspace.shared.selectFile(file.url.path, inFileViewerRootedAtPath: file.parentPath)
            }
        )
        .equatable()
    }

    // MARK: - Selection (incremental — O(1) per toggle, not O(n))

    private func toggleSelection(file: ScannedFileInfo) {
        if viewModel.selectedItems.contains(file.id) {
            viewModel.selectedItems.remove(file.id)
            localSelectedCount -= 1
            localSelectedSize -= file.allocatedSize
        } else {
            viewModel.selectedItems.insert(file.id)
            localSelectedCount += 1
            localSelectedSize += file.allocatedSize
            if file.fileContentIdentifier != nil {
                showCloneWarning = true
            }
        }
    }

    private func selectFiles(ids: [UUID], files: [ScannedFileInfo]) {
        // Build new set in one shot, then assign (single @Observable mutation)
        var updated = viewModel.selectedItems
        for id in ids {
            updated.insert(id)
        }
        viewModel.selectedItems = updated
        recomputeSelectionFromScratch()
    }

    private func selectAll() {
        let allFiles = viewModel.files(for: category)
        var updated = viewModel.selectedItems
        for file in allFiles {
            updated.insert(file.id)
        }
        viewModel.selectedItems = updated
        localSelectedCount = allFiles.count
        localSelectedSize = allFiles.reduce(0) { $0 + $1.allocatedSize }
    }

    private func deselectAll() {
        let allFiles = viewModel.files(for: category)
        var updated = viewModel.selectedItems
        for file in allFiles {
            updated.remove(file.id)
        }
        viewModel.selectedItems = updated
        localSelectedCount = 0
        localSelectedSize = 0
    }

    /// Full recompute — only called after deletion or bulk select where incremental is impractical
    private func recomputeSelectionFromScratch() {
        let allFiles = viewModel.files(for: category)
        var count = 0
        var size: Int64 = 0
        for file in allFiles {
            if viewModel.selectedItems.contains(file.id) {
                count += 1
                size += file.allocatedSize
            }
        }
        localSelectedCount = count
        localSelectedSize = size
    }

    // MARK: - Toolbar

    private var sortMenu: some View {
        Menu {
            Section("Size") {
                Button { sortOrder = .sizeDescending } label: {
                    Label("Largest First", systemImage: sortOrder == .sizeDescending ? "checkmark" : "")
                }
                Button { sortOrder = .sizeAscending } label: {
                    Label("Smallest First", systemImage: sortOrder == .sizeAscending ? "checkmark" : "")
                }
            }
            Section("Name") {
                Button { sortOrder = .nameAscending } label: {
                    Label("A to Z", systemImage: sortOrder == .nameAscending ? "checkmark" : "")
                }
                Button { sortOrder = .nameDescending } label: {
                    Label("Z to A", systemImage: sortOrder == .nameDescending ? "checkmark" : "")
                }
            }
            Section("Date Accessed") {
                Button { sortOrder = .dateOldest } label: {
                    Label("Oldest First", systemImage: sortOrder == .dateOldest ? "checkmark" : "")
                }
                Button { sortOrder = .dateNewest } label: {
                    Label("Newest First", systemImage: sortOrder == .dateNewest ? "checkmark" : "")
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
    }

    private var selectAllButton: some View {
        Button {
            if localSelectedCount == totalFileCount {
                deselectAll()
            } else {
                selectAll()
            }
        } label: {
            Label(
                localSelectedCount == totalFileCount ? "Deselect All" : "Select All",
                systemImage: localSelectedCount == totalFileCount ? "checkmark.circle" : "circle"
            )
        }
    }

    // MARK: - Build display data OFF main thread

    private func rebuildDisplayData() async {
        isLoading = true

        let cat = category
        let sort = sortOrder
        let query = searchText
        let limit = pageSize

        // Read files from viewModel (on main actor since viewModel is @MainActor)
        let allFiles = viewModel.files(for: cat)

        // Do ALL heavy work off main thread
        let result: (
            groups: [DisplayGroup],
            flat: [ScannedFileInfo],
            multi: Bool,
            count: Int,
            size: Int64
        ) = await Task.detached(priority: .userInitiated) {
            var filtered = allFiles

            // Search filter
            if !query.isEmpty {
                filtered = filtered.filter {
                    $0.fileName.localizedCaseInsensitiveContains(query) ||
                    $0.parentPath.localizedCaseInsensitiveContains(query) ||
                    ($0.source?.localizedCaseInsensitiveContains(query) ?? false)
                }
            }

            let totalCount = filtered.count
            var totalSize: Int64 = 0
            for f in filtered { totalSize += f.allocatedSize }

            // Check for multiple sources (early exit)
            var sourceSet = Set<String>()
            for f in filtered {
                sourceSet.insert(f.source ?? "Other")
                if sourceSet.count > 1 { break }
            }
            let hasMultiple = sourceSet.count > 1

            if hasMultiple {
                // Group by source
                var groups: [String: [ScannedFileInfo]] = [:]
                for file in filtered {
                    let source = file.source ?? "Other"
                    groups[source, default: []].append(file)
                }

                let displayGroups: [DisplayGroup] = groups.map { key, value in
                    // Sort within group
                    let sorted = Self.sortFiles(value, by: sort)
                    let preview = Array(sorted.prefix(limit))
                    let groupSize = value.reduce(0 as Int64) { $0 + $1.allocatedSize }
                    let allIDs = value.map(\.id)
                    return DisplayGroup(
                        id: key, source: key,
                        fileCount: value.count, totalSize: groupSize,
                        previewFiles: preview, allFileIDs: allIDs
                    )
                }.sorted { $0.totalSize > $1.totalSize }

                return (displayGroups, [], true, totalCount, totalSize)
            } else {
                // Flat — sort and take first page
                let sorted = Self.sortFiles(filtered, by: sort)
                let page = Array(sorted.prefix(limit))
                return ([], page, false, totalCount, totalSize)
            }
        }.value

        // Single main-thread update
        displayGroups = result.groups
        displayFlatFiles = result.flat
        hasMultipleSources = result.multi
        totalFileCount = result.count
        totalSize = result.size
        isLoading = false

        // Recompute selection state from current viewModel
        recomputeSelectionFromScratch()
    }

    /// Sort files — nonisolated static so it can run on any thread
    private nonisolated static func sortFiles(_ files: [ScannedFileInfo], by order: SortOrder) -> [ScannedFileInfo] {
        switch order {
        case .sizeDescending:
            return files.sorted { $0.allocatedSize > $1.allocatedSize }
        case .sizeAscending:
            return files.sorted { $0.allocatedSize < $1.allocatedSize }
        case .nameAscending:
            return files.sorted { $0.fileName.localizedCompare($1.fileName) == .orderedAscending }
        case .nameDescending:
            return files.sorted { $0.fileName.localizedCompare($1.fileName) == .orderedDescending }
        case .dateOldest:
            return files.sorted { ($0.lastAccessDate ?? .distantPast) < ($1.lastAccessDate ?? .distantPast) }
        case .dateNewest:
            return files.sorted { ($0.lastAccessDate ?? .distantPast) > ($1.lastAccessDate ?? .distantPast) }
        }
    }
}

// MARK: - Sort/Search Key for .task(id:)

private struct SortSearchKey: Equatable {
    let sort: SortOrder
    let search: String
}

// MARK: - Sort Order

enum SortOrder: Equatable {
    case sizeDescending, sizeAscending
    case nameAscending, nameDescending
    case dateOldest, dateNewest
}

// MARK: - Category Header

struct CategoryHeader: View {
    let category: FileCategory
    let totalFiles: Int
    let totalSize: Int64
    let selectedCount: Int
    let selectedSize: Int64

    private var themeColor: Color { category.themeColor }

    var body: some View {
        HStack {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(themeColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: category.iconName)
                    .font(.title2)
                    .foregroundStyle(themeColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("\(totalFiles) files")
                    .font(.headline)
                    .foregroundStyle(FUColors.textPrimary)
                Text(ByteFormatter.format(totalSize))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(themeColor)
            }

            Spacer()

            if selectedCount > 0 {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(selectedCount) selected")
                        .font(.subheadline)
                        .foregroundStyle(FUColors.textSecondary)
                    Text(ByteFormatter.format(selectedSize))
                        .font(.headline)
                        .foregroundStyle(FUColors.accent)
                }
            }
        }
        .padding()
        .background(FUColors.bgElevated)
    }
}

// MARK: - Source Section Header

struct SourceSectionHeader: View {
    let source: String
    let fileCount: Int
    let totalSize: Int64
    let isCollapsed: Bool
    let color: Color
    let onToggle: () -> Void
    let onSelectAll: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(FUColors.textTertiary)
                        .frame(width: 12)
                    Text(source)
                        .font(.headline)
                        .foregroundStyle(FUColors.textPrimary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Text("\(fileCount) files")
                .font(.caption)
                .foregroundStyle(FUColors.textSecondary)

            Text(ByteFormatter.format(totalSize))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(color)

            Button {
                onSelectAll()
            } label: {
                Image(systemName: "checkmark.circle")
                    .font(.body)
                    .foregroundStyle(FUColors.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Select all in \(source)")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(FUColors.bgElevated)
    }
}

// MARK: - Selection Action Bar

struct SelectionActionBar: View {
    let selectedCount: Int
    let selectedSize: Int64
    var isDeleting: Bool = false
    let onDelete: () -> Void
    let onDeselect: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(selectedCount) items selected")
                    .font(.headline)
                    .foregroundStyle(FUColors.textPrimary)
                Text(ByteFormatter.format(selectedSize))
                    .font(.subheadline)
                    .foregroundStyle(FUColors.textSecondary)
            }

            Spacer()

            if isDeleting {
                ProgressView()
                    .scaleEffect(0.8)
                    .padding(.horizontal)
            }

            Button("Deselect", action: onDeselect)
                .buttonStyle(.bordered)
                .tint(FUColors.textSecondary)

            Button(action: onDelete) {
                Label("Move to Trash", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(isDeleting)
        }
        .padding()
        .overlay(alignment: .top) {
            FUColors.border
                .frame(height: 1)
        }
        .background(FUColors.bgCard)
    }
}
