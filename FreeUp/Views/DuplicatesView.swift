//
//  DuplicatesView.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import SwiftUI

/// View for browsing and managing duplicate file groups
struct DuplicatesView: View {
    @Bindable var viewModel: ScanViewModel
    @State private var searchText = ""
    @State private var sortOrder: DuplicateSortOrder = .sizeDescending
    @State private var selectedForDeletion: Set<URL> = []
    @State private var showDeleteConfirmation = false
    @State private var expandedGroups: Set<UUID> = []
    
    private var filteredGroups: [DuplicateGroup] {
        var groups = viewModel.duplicateGroups
        
        // Apply search filter
        if !searchText.isEmpty {
            groups = groups.filter { group in
                group.files.contains { file in
                    file.fileName.localizedCaseInsensitiveContains(searchText) ||
                    file.parentPath.localizedCaseInsensitiveContains(searchText)
                }
            }
        }
        
        // Apply sort
        switch sortOrder {
        case .sizeDescending:
            groups.sort { $0.wastedSpace > $1.wastedSpace }
        case .sizeAscending:
            groups.sort { $0.wastedSpace < $1.wastedSpace }
        case .countDescending:
            groups.sort { $0.files.count > $1.files.count }
        case .nameAscending:
            groups.sort { ($0.files.first?.fileName ?? "") < ($1.files.first?.fileName ?? "") }
        }
        
        return groups
    }
    
    private var totalSelectedSize: Int64 {
        var size: Int64 = 0
        for group in viewModel.duplicateGroups {
            for file in group.files {
                if selectedForDeletion.contains(file.url) {
                    size += file.allocatedSize
                }
            }
        }
        return size
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            DuplicatesHeader(
                totalGroups: viewModel.duplicateGroups.count,
                totalDuplicates: viewModel.totalDuplicateCount,
                wastedSpace: viewModel.duplicateWastedSpace,
                selectedCount: selectedForDeletion.count,
                selectedSize: totalSelectedSize
            )
            
            Divider()
            
            if filteredGroups.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Duplicates Found" : "No Results",
                    systemImage: searchText.isEmpty ? "checkmark.circle" : "magnifyingglass",
                    description: Text(searchText.isEmpty ? "Great! No duplicate files were found on your system." : "Try a different search term")
                )
            } else {
                // Duplicate groups list
                List {
                    ForEach(filteredGroups) { group in
                        DuplicateGroupRow(
                            group: group,
                            selectedForDeletion: $selectedForDeletion,
                            isExpanded: expandedGroups.contains(group.id),
                            onToggleExpand: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if expandedGroups.contains(group.id) {
                                        expandedGroups.remove(group.id)
                                    } else {
                                        expandedGroups.insert(group.id)
                                    }
                                }
                            }
                        )
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
            
            // Bottom action bar
            if !selectedForDeletion.isEmpty {
                DuplicateActionBar(
                    selectedCount: selectedForDeletion.count,
                    selectedSize: totalSelectedSize,
                    isDeleting: viewModel.isDeletingFiles,
                    onDelete: {
                        showDeleteConfirmation = true
                    },
                    onAutoSelect: {
                        autoSelectDuplicates()
                    },
                    onDeselect: {
                        selectedForDeletion.removeAll()
                    }
                )
            } else {
                // Show auto-select button when nothing is selected
                HStack {
                    Spacer()
                    
                    Button {
                        autoSelectDuplicates()
                    } label: {
                        Label("Auto-Select Duplicates", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                    .help("Automatically select duplicate copies, keeping the oldest file in each group")
                    
                    Spacer()
                }
                .padding()
                .background(.ultraThinMaterial)
            }
        }
        .navigationTitle("Duplicates")
        .searchable(text: $searchText, prompt: "Search duplicates")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Section("Sort By") {
                        Button {
                            sortOrder = .sizeDescending
                        } label: {
                            Label("Largest Waste First", systemImage: sortOrder == .sizeDescending ? "checkmark" : "")
                        }
                        
                        Button {
                            sortOrder = .sizeAscending
                        } label: {
                            Label("Smallest Waste First", systemImage: sortOrder == .sizeAscending ? "checkmark" : "")
                        }
                        
                        Button {
                            sortOrder = .countDescending
                        } label: {
                            Label("Most Copies First", systemImage: sortOrder == .countDescending ? "checkmark" : "")
                        }
                        
                        Button {
                            sortOrder = .nameAscending
                        } label: {
                            Label("Name A-Z", systemImage: sortOrder == .nameAscending ? "checkmark" : "")
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
        }
        .alert("Delete Duplicates", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete \(selectedForDeletion.count) Files", role: .destructive) {
                Task {
                    await deleteDuplicates()
                }
            }
        } message: {
            Text("This will \(viewModel.currentDeleteMode == .moveToTrash ? "move" : "permanently delete") \(selectedForDeletion.count) duplicate files (\(ByteFormatter.format(totalSelectedSize))) to free up space. This action cannot be undone.")
        }
        .onAppear {
            // Auto-expand all groups if there are few
            if viewModel.duplicateGroups.count <= 10 {
                expandedGroups = Set(viewModel.duplicateGroups.map { $0.id })
            }
        }
    }
    
    /// Auto-select all duplicate copies, keeping the oldest file in each group
    private func autoSelectDuplicates() {
        selectedForDeletion.removeAll()
        
        for group in viewModel.duplicateGroups {
            // Keep the file with the earliest access date (or first alphabetically)
            let sorted = group.files.sorted { file1, file2 in
                let date1 = file1.lastAccessDate ?? .distantPast
                let date2 = file2.lastAccessDate ?? .distantPast
                return date1 < date2
            }
            
            // Select all except the first (the "original" to keep)
            for file in sorted.dropFirst() {
                selectedForDeletion.insert(file.url)
            }
        }
    }
    
    /// Delete selected duplicate files
    private func deleteDuplicates() async {
        var filesToDelete: [ScannedFileInfo] = []
        
        for group in viewModel.duplicateGroups {
            for file in group.files {
                if selectedForDeletion.contains(file.url) {
                    filesToDelete.append(file)
                }
            }
        }
        
        await viewModel.deleteFiles(filesToDelete)
        selectedForDeletion.removeAll()
    }
}

// MARK: - Sort Order

enum DuplicateSortOrder {
    case sizeDescending, sizeAscending, countDescending, nameAscending
}

// MARK: - Header

struct DuplicatesHeader: View {
    let totalGroups: Int
    let totalDuplicates: Int
    let wastedSpace: Int64
    let selectedCount: Int
    let selectedSize: Int64
    
    var body: some View {
        HStack {
            ZStack {
                Circle()
                    .fill(Color.teal.opacity(0.15))
                    .frame(width: 50, height: 50)
                
                Image(systemName: "doc.on.doc")
                    .font(.title2)
                    .foregroundStyle(.teal)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\(totalGroups) duplicate groups")
                    .font(.headline)
                
                HStack(spacing: 8) {
                    Text("\(totalDuplicates) extra copies")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Text("~")
                        .foregroundStyle(.tertiary)
                    
                    Text(ByteFormatter.format(wastedSpace) + " wasted")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.teal)
                }
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

// MARK: - Duplicate Group Row

struct DuplicateGroupRow: View {
    let group: DuplicateGroup
    @Binding var selectedForDeletion: Set<URL>
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Group header
            Button(action: onToggleExpand) {
                HStack(spacing: 12) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    
                    // File icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.teal.opacity(0.15))
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.teal)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.files.first?.fileName ?? "Unknown")
                            .font(.body)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        
                        Text("\(group.files.count) copies")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(ByteFormatter.format(group.wastedSpace))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.teal)
                        
                        Text("wasted")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            
            // Expanded file list
            if isExpanded {
                VStack(spacing: 4) {
                    ForEach(Array(group.files.enumerated()), id: \.element.url) { index, file in
                        DuplicateFileRow(
                            file: file,
                            isOriginal: index == 0,
                            isSelectedForDeletion: selectedForDeletion.contains(file.url),
                            onToggle: {
                                if selectedForDeletion.contains(file.url) {
                                    selectedForDeletion.remove(file.url)
                                } else {
                                    selectedForDeletion.insert(file.url)
                                }
                            },
                            onRevealInFinder: {
                                NSWorkspace.shared.selectFile(
                                    file.url.path,
                                    inFileViewerRootedAtPath: file.url.deletingLastPathComponent().path
                                )
                            }
                        )
                    }
                }
                .padding(.leading, 24)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Individual Duplicate File Row

struct DuplicateFileRow: View {
    let file: ScannedFileInfo
    let isOriginal: Bool
    let isSelectedForDeletion: Bool
    let onToggle: () -> Void
    let onRevealInFinder: () -> Void
    
    var body: some View {
        HStack(spacing: 10) {
            // Selection checkbox
            Button(action: onToggle) {
                Image(systemName: isSelectedForDeletion ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(isSelectedForDeletion ? Color.red : .secondary)
            }
            .buttonStyle(.plain)
            
            // Original badge or copy indicator
            if isOriginal {
                Text("Keep")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.green.opacity(0.2))
                    )
                    .foregroundStyle(.green)
            }
            
            // File path
            VStack(alignment: .leading, spacing: 1) {
                Text(file.fileName)
                    .font(.subheadline)
                    .lineLimit(1)
                
                Text(file.parentPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            
            Spacer()
            
            // Size
            Text(ByteFormatter.format(file.allocatedSize))
                .font(.caption)
                .fontWeight(.medium)
                .monospacedDigit()
            
            // Context menu
            Button(action: onRevealInFinder) {
                Image(systemName: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelectedForDeletion ? Color.red.opacity(0.08) : Color.clear)
        )
    }
}

// MARK: - Action Bar

struct DuplicateActionBar: View {
    let selectedCount: Int
    let selectedSize: Int64
    let isDeleting: Bool
    let onDelete: () -> Void
    let onAutoSelect: () -> Void
    let onDeselect: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(selectedCount) duplicates selected")
                    .font(.headline)
                
                Text(ByteFormatter.format(selectedSize) + " to free")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if isDeleting {
                ProgressView()
                    .scaleEffect(0.8)
                    .padding(.horizontal)
            }
            
            Button("Deselect All", action: onDeselect)
                .buttonStyle(.bordered)
            
            Button(action: onDelete) {
                Label("Delete Duplicates", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(isDeleting)
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}

#Preview("Duplicates View") {
    NavigationStack {
        DuplicatesView(viewModel: ScanViewModel())
    }
}
