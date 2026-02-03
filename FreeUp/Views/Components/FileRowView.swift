//
//  FileRowView.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import SwiftUI

/// Equatable file row for optimized List rendering
struct FileRowView: View, Equatable {
    let file: ScannedFileInfo
    let isSelected: Bool
    let isClone: Bool
    let onToggleSelection: () -> Void
    let onRevealInFinder: () -> Void
    
    static func == (lhs: FileRowView, rhs: FileRowView) -> Bool {
        lhs.file == rhs.file &&
        lhs.isSelected == rhs.isSelected &&
        lhs.isClone == rhs.isClone
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Selection checkbox
            Button(action: onToggleSelection) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            
            // File icon
            FileIconView(contentType: file.contentType)
            
            // File info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(file.fileName)
                        .font(.body)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    if isClone {
                        CloneBadge()
                    }
                    
                    if file.isPurgeable {
                        PurgeableBadge()
                    }
                }
                
                Text(file.parentPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            
            Spacer()
            
            // Last accessed
            if let lastAccess = file.lastAccessDate {
                Text(lastAccess, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .trailing)
            }
            
            // File size
            Text(ByteFormatter.format(file.allocatedSize))
                .font(.body)
                .fontWeight(.medium)
                .monospacedDigit()
                .frame(width: 80, alignment: .trailing)
            
            // Context menu button
            Menu {
                Button("Reveal in Finder", action: onRevealInFinder)
                
                Button("Quick Look") {
                    // QuickLook preview
                }
                
                Divider()
                
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(file.url.path, forType: .string)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 30)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

/// File icon based on UTType
struct FileIconView: View {
    let contentType: UTType?
    
    private var iconName: String {
        guard let type = contentType else { return "doc" }
        
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return "film" }
        if type.conforms(to: .audio) { return "waveform" }
        if type.conforms(to: .archive) { return "archivebox" }
        if type.conforms(to: .pdf) { return "doc.text" }
        if type.conforms(to: .folder) { return "folder" }
        if type.conforms(to: .application) { return "app" }
        
        return "doc"
    }
    
    private var iconColor: Color {
        guard let type = contentType else { return .secondary }
        
        if type.conforms(to: .image) { return .pink }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .purple }
        if type.conforms(to: .audio) { return .orange }
        if type.conforms(to: .archive) { return .brown }
        if type.conforms(to: .pdf) { return .red }
        if type.conforms(to: .application) { return .cyan }
        
        return .blue
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(iconColor.opacity(0.15))
                .frame(width: 36, height: 36)
            
            Image(systemName: iconName)
                .font(.system(size: 16))
                .foregroundStyle(iconColor)
        }
    }
}

/// Badge indicating file is an APFS clone
struct CloneBadge: View {
    var body: some View {
        Text("Clone")
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.orange.opacity(0.2))
            )
            .foregroundStyle(.orange)
    }
}

/// Badge indicating file is purgeable by system
struct PurgeableBadge: View {
    var body: some View {
        Text("Purgeable")
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.green.opacity(0.2))
            )
            .foregroundStyle(.green)
    }
}

/// Stale file indicator (not accessed in > 1 year)
struct StaleBadge: View {
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "clock")
            Text("> 1 year")
        }
        .font(.caption2)
        .fontWeight(.medium)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(Color.yellow.opacity(0.2))
        )
        .foregroundStyle(.yellow)
    }
}

import UniformTypeIdentifiers

#Preview {
    VStack(spacing: 0) {
        FileRowView(
            file: ScannedFileInfo(
                url: URL(fileURLWithPath: "/Users/test/Downloads/video.mp4"),
                allocatedSize: 1_500_000_000,
                fileSize: 1_450_000_000,
                contentType: .movie,
                category: .videos,
                lastAccessDate: Date().addingTimeInterval(-86400 * 30),
                fileContentIdentifier: nil,
                isPurgeable: false,
                source: nil
            ),
            isSelected: true,
            isClone: false,
            onToggleSelection: {},
            onRevealInFinder: {}
        )
        .equatable()
        
        FileRowView(
            file: ScannedFileInfo(
                url: URL(fileURLWithPath: "/Users/test/Library/Caches/com.app/data.cache"),
                allocatedSize: 500_000_000,
                fileSize: 490_000_000,
                contentType: .data,
                category: .cache,
                lastAccessDate: Date().addingTimeInterval(-86400 * 400),
                fileContentIdentifier: 12345,
                isPurgeable: true,
                source: "Safari Cache"
            ),
            isSelected: false,
            isClone: true,
            onToggleSelection: {},
            onRevealInFinder: {}
        )
        .equatable()
    }
    .padding()
}
