//
//  CategoryDetailView.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Lightweight display model (avoids re-sorting on every render)

/// Pre-computed group for display — built once, not per-render
private struct DisplayGroup: Identifiable {
    let id: String // source name
    let source: String
    let files: [ScannedFileInfo]
    let totalSize: Int64
}

/// Detail view for a specific file category
/// Uses ScrollView + LazyVStack for performance with large file lists.
/// Sections are collapsed by default so SwiftUI never has to diff 20k+ rows.
struct CategoryDetailView: View {
    let category: FileCategory
    let files: [ScannedFileInfo]
    @Bindable var viewModel: ScanViewModel

    @State private var sortOrder: SortOrder = .sizeDescending
    @State private var searchText = ""
    @State private var showCloneWarning = false
    /// All sections collapsed by default — critical for performance
    @State private var expandedSections: Set<String> = []

    // Cached computed data — rebuilt only when inputs change
    @State private var cachedGroups: [DisplayGroup] = []
    @State private var cachedFlatFiles: [ScannedFileInfo] = []
    @State private var cachedHasMultipleSources = false
    @State private var cachedTotalSize: Int64 = 0

    private var categoryColor: Color { category.color }

    /// Selected count / size — iterates only the (smaller) selected set, not all files
    private var selectedCount: Int {
        guard !viewModel.selectedItems.isEmpty else { return 0 }
        let fileIDs = Set(files.lazy.map(\.id))
        return viewModel.selectedItems.filter { fileIDs.contains($0) }.count
    }

    private var selectedSize: Int64 {
        guard !viewModel.selectedItems.isEmpty else { return 0 }
        var size: Int64 = 0
        for file in files {
            if viewModel.selectedItems.contains(file.id) {
                size += file.allocatedSize
            }
        }
        return size
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            CategoryHeader(
                category: category,
                totalFiles: files.count,
                totalSize: cachedTotalSize,
                selectedCount: selectedCount,
                selectedSize: selectedSize,
                color: categoryColor
            )

            Divider()

            // File list
            if cachedFlatFiles.isEmpty && cachedGroups.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Files" : "No Results",
                    systemImage: searchText.isEmpty ? "folder" : "magnifyingglass",
                    description: Text(searchText.isEmpty ? "No files found in this category" : "Try a different search term")
                )
            } else if cachedHasMultipleSources {
                groupedListView
            } else {
                flatListView
            }

            // Bottom action bar
            if selectedCount > 0 {
                SelectionActionBar(
                    selectedCount: selectedCount,
                    selectedSize: selectedSize,
                    isDeleting: viewModel.isDeletingFiles,
                    onDelete: {
                        Task {
                            await viewModel.deleteSelectedFiles(from: category)
                        }
                    },
                    onDeselect: {
                        viewModel.deselectAllFiles(in: category)
                    }
                )
            }
        }
        .navigationTitle(category.rawValue)
        .searchable(text: $searchText, prompt: "Search files")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                sortMenu
                selectAllButton
            }
        }
        .alert("Clone Warning", isPresented: $showCloneWarning) {
            Button("OK") { }
        } message: {
            Text("This file appears to be an APFS clone. Deleting it may not free disk space if other files share the same data blocks.")
        }
        .onAppear { rebuildCache() }
        .onChange(of: sortOrder) { rebuildCache() }
        .onChange(of: searchText) { rebuildCache() }
    }

    // MARK: - Grouped List (sections collapsed by default)

    private var groupedListView: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(cachedGroups) { group in
                    Section {
                        if expandedSections.contains(group.source) {
                            ForEach(group.files) { file in
                                fileRow(for: file)
                            }
                        }
                    } header: {
                        SourceSectionHeader(
                            source: group.source,
                            fileCount: group.files.count,
                            totalSize: group.totalSize,
                            isCollapsed: !expandedSections.contains(group.source),
                            color: categoryColor,
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
                                for file in group.files {
                                    viewModel.selectedItems.insert(file.id)
                                }
                            }
                        )
                        .background(Color(.windowBackgroundColor))
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
                ForEach(cachedFlatFiles) { file in
                    fileRow(for: file)
                }
            }
            .padding(.horizontal, 8)
        }
    }

    // MARK: - File Row

    @ViewBuilder
    private func fileRow(for file: ScannedFileInfo) -> some View {
        let isSelected = viewModel.selectedItems.contains(file.id)
        let isClone = file.fileContentIdentifier != nil

        FileRowView(
            file: file,
            isSelected: isSelected,
            isClone: isClone,
            onToggleSelection: {
                if viewModel.selectedItems.contains(file.id) {
                    viewModel.selectedItems.remove(file.id)
                } else {
                    viewModel.selectedItems.insert(file.id)
                    if isClone {
                        showCloneWarning = true
                    }
                }
            },
            onRevealInFinder: {
                NSWorkspace.shared.selectFile(file.url.path, inFileViewerRootedAtPath: file.parentPath)
            }
        )
        .equatable()
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
            if selectedCount == files.count {
                viewModel.deselectAllFiles(in: category)
            } else {
                viewModel.selectAllFiles(in: category)
            }
        } label: {
            Label(
                selectedCount == files.count ? "Deselect All" : "Select All",
                systemImage: selectedCount == files.count ? "checkmark.circle" : "circle"
            )
        }
    }

    // MARK: - Cache Rebuild (only on sort/search change, not per-render)

    private func rebuildCache() {
        var filtered = files

        // Search filter
        if !searchText.isEmpty {
            let query = searchText
            filtered = filtered.filter {
                $0.fileName.localizedCaseInsensitiveContains(query) ||
                $0.parentPath.localizedCaseInsensitiveContains(query) ||
                ($0.source?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }

        // Sort
        filtered = sortFiles(filtered)

        // Check for multiple sources
        var sourceSet = Set<String>()
        for f in filtered {
            sourceSet.insert(f.source ?? "Other")
            if sourceSet.count > 1 { break }
        }
        let hasMultiple = sourceSet.count > 1

        cachedTotalSize = filtered.reduce(0) { $0 + $1.allocatedSize }
        cachedHasMultipleSources = hasMultiple

        if hasMultiple {
            // Build groups
            var groups: [String: [ScannedFileInfo]] = [:]
            for file in filtered {
                let source = file.source ?? "Other"
                groups[source, default: []].append(file)
            }
            cachedGroups = groups.map { key, value in
                DisplayGroup(
                    id: key,
                    source: key,
                    files: value,
                    totalSize: value.reduce(0) { $0 + $1.allocatedSize }
                )
            }.sorted { $0.totalSize > $1.totalSize }
            cachedFlatFiles = []
        } else {
            cachedFlatFiles = filtered
            cachedGroups = []
        }
    }

    private func sortFiles(_ files: [ScannedFileInfo]) -> [ScannedFileInfo] {
        switch sortOrder {
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

// MARK: - Sort Order

enum SortOrder {
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
    let color: Color

    var body: some View {
        HStack {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 50, height: 50)
                Image(systemName: category.iconName)
                    .font(.title2)
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("\(totalFiles) files")
                    .font(.headline)
                Text(ByteFormatter.format(totalSize))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(color)
            }

            Spacer()

            if selectedCount > 0 {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(selectedCount) selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(ByteFormatter.format(selectedSize))
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding()
        .background(Color(.windowBackgroundColor))
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
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    Text(source)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Text("\(fileCount) files")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(ByteFormatter.format(totalSize))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(color)

            Button {
                onSelectAll()
            } label: {
                Image(systemName: "checkmark.circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Select all in \(source)")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
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
                Text(ByteFormatter.format(selectedSize))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isDeleting {
                ProgressView()
                    .scaleEffect(0.8)
                    .padding(.horizontal)
            }

            Button("Deselect", action: onDeselect)
                .buttonStyle(.bordered)

            Button(action: onDelete) {
                Label("Move to Trash", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(isDeleting)
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}
