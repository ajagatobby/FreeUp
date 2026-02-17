//
//  CategoryDetailView.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Detail view for a specific file category with virtualized list
struct CategoryDetailView: View {
    let category: FileCategory
    let files: [ScannedFileInfo]
    @Bindable var viewModel: ScanViewModel
    
    @State private var sortOrder: SortOrder = .sizeDescending
    @State private var searchText = ""
    @State private var showCloneWarning = false
    @State private var collapsedSections: Set<String> = []
    
    /// Group files by source (sub-category)
    private var groupedFiles: [(source: String, files: [ScannedFileInfo], totalSize: Int64)] {
        var filtered = files
        
        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter {
                $0.fileName.localizedCaseInsensitiveContains(searchText) ||
                $0.parentPath.localizedCaseInsensitiveContains(searchText) ||
                ($0.source?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        // Group by source
        var groups: [String: [ScannedFileInfo]] = [:]
        for file in filtered {
            let source = file.source ?? "Other"
            groups[source, default: []].append(file)
        }
        
        // Sort files within each group
        let sortedGroups = groups.mapValues { files -> [ScannedFileInfo] in
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
        
        // Convert to array and sort groups by total size (largest first)
        return sortedGroups.map { (source: $0.key, files: $0.value, totalSize: $0.value.reduce(0) { $0 + $1.allocatedSize }) }
            .sorted { $0.totalSize > $1.totalSize }
    }
    
    /// Check if we should show grouped view (has multiple sources)
    private var hasMultipleSources: Bool {
        let sources = Set(files.compactMap { $0.source })
        return sources.count > 1
    }
    
    private var sortedFiles: [ScannedFileInfo] {
        var filtered = files
        
        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter {
                $0.fileName.localizedCaseInsensitiveContains(searchText) ||
                $0.parentPath.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Apply sort
        switch sortOrder {
        case .sizeDescending:
            return filtered.sorted { $0.allocatedSize > $1.allocatedSize }
        case .sizeAscending:
            return filtered.sorted { $0.allocatedSize < $1.allocatedSize }
        case .nameAscending:
            return filtered.sorted { $0.fileName.localizedCompare($1.fileName) == .orderedAscending }
        case .nameDescending:
            return filtered.sorted { $0.fileName.localizedCompare($1.fileName) == .orderedDescending }
        case .dateOldest:
            return filtered.sorted { ($0.lastAccessDate ?? .distantPast) < ($1.lastAccessDate ?? .distantPast) }
        case .dateNewest:
            return filtered.sorted { ($0.lastAccessDate ?? .distantPast) > ($1.lastAccessDate ?? .distantPast) }
        }
    }
    
    /// Combined selected count and size (single pass instead of two)
    private var selectedInfo: (count: Int, size: Int64) {
        var count = 0
        var size: Int64 = 0
        for file in files {
            if viewModel.selectedItems.contains(file.id) {
                count += 1
                size += file.allocatedSize
            }
        }
        return (count, size)
    }
    
    private var selectedCount: Int { selectedInfo.count }
    private var selectedSize: Int64 { selectedInfo.size }
    
    private var categoryColor: Color { category.color }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with stats
            CategoryHeader(
                category: category,
                totalFiles: files.count,
                totalSize: files.reduce(0) { $0 + $1.allocatedSize },
                selectedCount: selectedCount,
                selectedSize: selectedSize,
                color: categoryColor
            )
            
            Divider()
            
            // File list
            if sortedFiles.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Files" : "No Results",
                    systemImage: searchText.isEmpty ? "folder" : "magnifyingglass",
                    description: Text(searchText.isEmpty ? "No files found in this category" : "Try a different search term")
                )
            } else if hasMultipleSources {
                // Grouped view with sub-categories
                List {
                    ForEach(groupedFiles, id: \.source) { group in
                        Section {
                            if !collapsedSections.contains(group.source) {
                                ForEach(group.files, id: \.url) { file in
                                    fileRow(for: file)
                                }
                            }
                        } header: {
                            SourceSectionHeader(
                                source: group.source,
                                fileCount: group.files.count,
                                totalSize: group.totalSize,
                                isCollapsed: collapsedSections.contains(group.source),
                                color: categoryColor,
                                onToggle: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if collapsedSections.contains(group.source) {
                                            collapsedSections.remove(group.source)
                                        } else {
                                            collapsedSections.insert(group.source)
                                        }
                                    }
                                },
                                onSelectAll: {
                                    for file in group.files {
                                        viewModel.selectedItems.insert(file.id)
                                    }
                                }
                            )
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            } else {
                // Flat list for single source
                List {
                    ForEach(sortedFiles, id: \.url) { file in
                        fileRow(for: file)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
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
                // Sort menu
                Menu {
                    Section("Size") {
                        Button {
                            sortOrder = .sizeDescending
                        } label: {
                            Label("Largest First", systemImage: sortOrder == .sizeDescending ? "checkmark" : "")
                        }
                        
                        Button {
                            sortOrder = .sizeAscending
                        } label: {
                            Label("Smallest First", systemImage: sortOrder == .sizeAscending ? "checkmark" : "")
                        }
                    }
                    
                    Section("Name") {
                        Button {
                            sortOrder = .nameAscending
                        } label: {
                            Label("A to Z", systemImage: sortOrder == .nameAscending ? "checkmark" : "")
                        }
                        
                        Button {
                            sortOrder = .nameDescending
                        } label: {
                            Label("Z to A", systemImage: sortOrder == .nameDescending ? "checkmark" : "")
                        }
                    }
                    
                    Section("Date Accessed") {
                        Button {
                            sortOrder = .dateOldest
                        } label: {
                            Label("Oldest First", systemImage: sortOrder == .dateOldest ? "checkmark" : "")
                        }
                        
                        Button {
                            sortOrder = .dateNewest
                        } label: {
                            Label("Newest First", systemImage: sortOrder == .dateNewest ? "checkmark" : "")
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                
                // Select all
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
        }
        .alert("Clone Warning", isPresented: $showCloneWarning) {
            Button("OK") { }
        } message: {
            Text("This file appears to be an APFS clone. Deleting it may not free disk space if other files share the same data blocks.")
        }
    }
    
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
                revealInFinder(file.url)
            }
        )
        .equatable()
        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
        .listRowSeparator(.hidden)
    }
    
    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
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
            // Category icon
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

#Preview("Videos - Flat") {
    NavigationStack {
        CategoryDetailView(
            category: .videos,
            files: [
                ScannedFileInfo(
                    url: URL(fileURLWithPath: "/Users/test/Movies/video1.mp4"),
                    allocatedSize: 2_500_000_000,
                    fileSize: 2_400_000_000,
                    contentType: .movie,
                    category: .videos,
                    lastAccessDate: Date().addingTimeInterval(-86400 * 30),
                    fileContentIdentifier: nil,
                    isPurgeable: false,
                    source: nil
                ),
                ScannedFileInfo(
                    url: URL(fileURLWithPath: "/Users/test/Movies/video2.mov"),
                    allocatedSize: 1_500_000_000,
                    fileSize: 1_450_000_000,
                    contentType: .movie,
                    category: .videos,
                    lastAccessDate: Date().addingTimeInterval(-86400 * 60),
                    fileContentIdentifier: 12345,
                    isPurgeable: false,
                    source: nil
                )
            ],
            viewModel: ScanViewModel()
        )
    }
}

#Preview("Cache - Grouped") {
    NavigationStack {
        CategoryDetailView(
            category: .cache,
            files: [
                ScannedFileInfo(
                    url: URL(fileURLWithPath: "/Users/test/Library/Caches/com.apple.Safari/data1.cache"),
                    allocatedSize: 500_000_000,
                    fileSize: 490_000_000,
                    contentType: .data,
                    category: .cache,
                    lastAccessDate: Date().addingTimeInterval(-86400 * 7),
                    fileContentIdentifier: nil,
                    isPurgeable: false,
                    source: "Safari Cache"
                ),
                ScannedFileInfo(
                    url: URL(fileURLWithPath: "/Users/test/Library/Caches/com.apple.Safari/data2.cache"),
                    allocatedSize: 300_000_000,
                    fileSize: 290_000_000,
                    contentType: .data,
                    category: .cache,
                    lastAccessDate: Date().addingTimeInterval(-86400 * 14),
                    fileContentIdentifier: nil,
                    isPurgeable: false,
                    source: "Safari Cache"
                ),
                ScannedFileInfo(
                    url: URL(fileURLWithPath: "/Users/test/Library/Caches/Google/Chrome/cache1.db"),
                    allocatedSize: 800_000_000,
                    fileSize: 780_000_000,
                    contentType: .data,
                    category: .cache,
                    lastAccessDate: Date().addingTimeInterval(-86400 * 3),
                    fileContentIdentifier: nil,
                    isPurgeable: false,
                    source: "Chrome Cache"
                ),
                ScannedFileInfo(
                    url: URL(fileURLWithPath: "/Users/test/Library/Caches/Homebrew/downloads/pkg.tar.gz"),
                    allocatedSize: 200_000_000,
                    fileSize: 195_000_000,
                    contentType: .data,
                    category: .cache,
                    lastAccessDate: Date().addingTimeInterval(-86400 * 30),
                    fileContentIdentifier: nil,
                    isPurgeable: false,
                    source: "Homebrew Cache"
                ),
                ScannedFileInfo(
                    url: URL(fileURLWithPath: "/Users/test/Library/Caches/Other/misc.cache"),
                    allocatedSize: 100_000_000,
                    fileSize: 95_000_000,
                    contentType: .data,
                    category: .cache,
                    lastAccessDate: Date().addingTimeInterval(-86400 * 60),
                    fileContentIdentifier: nil,
                    isPurgeable: false,
                    source: "User Caches"
                )
            ],
            viewModel: ScanViewModel()
        )
    }
}
