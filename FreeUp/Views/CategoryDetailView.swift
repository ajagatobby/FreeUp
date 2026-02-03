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
    
    private var selectedCount: Int {
        files.filter { file in
            let id = generateId(for: file)
            return viewModel.selectedItems.contains(id)
        }.count
    }
    
    private var selectedSize: Int64 {
        files.filter { file in
            let id = generateId(for: file)
            return viewModel.selectedItems.contains(id)
        }.reduce(0) { $0 + $1.allocatedSize }
    }
    
    private var categoryColor: Color {
        switch category.colorName {
        case "pink": return .pink
        case "purple": return .purple
        case "orange": return .orange
        case "blue": return .blue
        case "brown": return .brown
        case "cyan": return .cyan
        case "yellow": return .yellow
        case "gray": return .gray
        case "green": return .green
        case "red": return .red
        case "indigo": return .indigo
        case "mint": return .mint
        default: return .secondary
        }
    }
    
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
            } else {
                List {
                    ForEach(sortedFiles, id: \.url) { file in
                        let id = generateId(for: file)
                        let isSelected = viewModel.selectedItems.contains(id)
                        let isClone = file.fileContentIdentifier != nil
                        
                        FileRowView(
                            file: file,
                            isSelected: isSelected,
                            isClone: isClone,
                            onToggleSelection: {
                                if viewModel.selectedItems.contains(id) {
                                    viewModel.selectedItems.remove(id)
                                } else {
                                    viewModel.selectedItems.insert(id)
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
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            
            // Bottom action bar
            if selectedCount > 0 {
                SelectionActionBar(
                    selectedCount: selectedCount,
                    selectedSize: selectedSize,
                    onDelete: {
                        // Delete action
                    },
                    onDeselect: {
                        for file in files {
                            let id = generateId(for: file)
                            viewModel.selectedItems.remove(id)
                        }
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
                        // Deselect all
                        for file in files {
                            let id = generateId(for: file)
                            viewModel.selectedItems.remove(id)
                        }
                    } else {
                        // Select all
                        for file in files {
                            let id = generateId(for: file)
                            viewModel.selectedItems.insert(id)
                        }
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
    
    private func generateId(for file: ScannedFileInfo) -> UUID {
        // Generate consistent UUID from file URL path
        let hash = file.url.path.hashValue
        let uuidString = String(format: "%08X-%04X-%04X-%04X-%012X",
                               UInt32(truncatingIfNeeded: hash),
                               UInt16(truncatingIfNeeded: hash >> 32),
                               UInt16(truncatingIfNeeded: hash >> 48),
                               UInt16(truncatingIfNeeded: hash >> 16),
                               UInt64(truncatingIfNeeded: hash))
        return UUID(uuidString: uuidString) ?? UUID()
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

// MARK: - Selection Action Bar

struct SelectionActionBar: View {
    let selectedCount: Int
    let selectedSize: Int64
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
            
            Button("Deselect", action: onDeselect)
                .buttonStyle(.bordered)
            
            Button(action: onDelete) {
                Label("Move to Trash", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}

#Preview {
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
                    isPurgeable: false
                ),
                ScannedFileInfo(
                    url: URL(fileURLWithPath: "/Users/test/Movies/video2.mov"),
                    allocatedSize: 1_500_000_000,
                    fileSize: 1_450_000_000,
                    contentType: .movie,
                    category: .videos,
                    lastAccessDate: Date().addingTimeInterval(-86400 * 60),
                    fileContentIdentifier: 12345,
                    isPurgeable: false
                )
            ],
            viewModel: ScanViewModel()
        )
    }
}
