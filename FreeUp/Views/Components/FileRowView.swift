//
//  FileRowView.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - FileRowView

/// Equatable file row for optimized List rendering.
struct FileRowView: View, Equatable {
    let file: ScannedFileInfo
    let isSelected: Bool
    let isClone: Bool
    let index: Int
    let onToggleSelection: () -> Void
    let onRevealInFinder: () -> Void

    @State private var isHovered = false

    static func == (lhs: FileRowView, rhs: FileRowView) -> Bool {
        lhs.file == rhs.file &&
        lhs.isSelected == rhs.isSelected &&
        lhs.isClone == rhs.isClone &&
        lhs.index == rhs.index
    }

    // MARK: - Background

    private var rowBackground: Color {
        if isSelected {
            return FUColors.accentDim
        }
        if isHovered {
            return FUColors.bgHover
        }
        // Odd rows get a subtly darker tint for alternating stripe
        if index.isMultiple(of: 2) {
            return .clear
        }
        return FUColors.bg.opacity(0.35)
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 12) {
            selectionCheckbox
            FileIconView(contentType: file.contentType)
            fileInfo
            Spacer(minLength: 4)
            lastAccessLabel
            fileSizeLabel
            contextMenuButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowBackground)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    // MARK: - Subviews

    private var selectionCheckbox: some View {
        Button(action: onToggleSelection) {
            ZStack {
                Circle()
                    .strokeBorder(
                        isSelected ? FUColors.accent : FUColors.textTertiary,
                        lineWidth: 1.5
                    )
                    .frame(width: 20, height: 20)

                if isSelected {
                    Circle()
                        .fill(FUColors.accent)
                        .frame(width: 20, height: 20)

                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(FUColors.bg)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
    }

    private var fileInfo: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(file.fileName)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(FUColors.textPrimary)
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
                .font(.system(size: 11))
                .foregroundStyle(FUColors.textSecondary)
                .lineLimit(1)
                .truncationMode(.head)
        }
    }

    @ViewBuilder
    private var lastAccessLabel: some View {
        if let lastAccess = file.lastAccessDate {
            Text(lastAccess, style: .relative)
                .font(.system(size: 11))
                .foregroundStyle(FUColors.textTertiary)
                .frame(width: 90, alignment: .trailing)
        }
    }

    private var fileSizeLabel: some View {
        Text(ByteFormatter.format(file.allocatedSize))
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(FUColors.textPrimary)
            .monospacedDigit()
            .frame(width: 80, alignment: .trailing)
    }

    private var contextMenuButton: some View {
        Menu {
            Button("Reveal in Finder", action: onRevealInFinder)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.url.path, forType: .string)
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12))
                .foregroundStyle(FUColors.textTertiary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .frame(width: 28)
        .opacity(isHovered ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - FileIconView

/// File icon with UTType-based SF Symbol and color tinting.
struct FileIconView: View {
    let contentType: UTType?

    private var iconConfig: (name: String, color: Color) {
        guard let type = contentType else {
            return ("doc", FUColors.textSecondary)
        }

        if type.conforms(to: .image) {
            return ("photo", FUColors.photosColor)
        }
        if type.conforms(to: .movie) || type.conforms(to: .video) {
            return ("film", FUColors.videosColor)
        }
        if type.conforms(to: .audio) {
            return ("waveform", FUColors.audioColor)
        }
        if type.conforms(to: .archive) {
            return ("archivebox", FUColors.archivesColor)
        }
        if type.conforms(to: .pdf) {
            return ("doc.text", FUColors.systemJunkColor)
        }
        if type.conforms(to: .folder) {
            return ("folder.fill", FUColors.downloadsColor)
        }
        if type.conforms(to: .application) {
            return ("app", FUColors.accent)
        }

        return ("doc", FUColors.downloadsColor)
    }

    var body: some View {
        let config = iconConfig

        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(config.color.opacity(0.12))
                .frame(width: 32, height: 32)

            Image(systemName: config.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(config.color)
        }
    }
}

// MARK: - CloneBadge

/// Badge indicating file is an APFS clone.
struct CloneBadge: View {
    var body: some View {
        Text("Clone")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(FUColors.audioColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(
                Capsule()
                    .fill(FUColors.audioColor.opacity(0.12))
            )
    }
}

// MARK: - PurgeableBadge

/// Badge indicating file is purgeable by the system.
struct PurgeableBadge: View {
    var body: some View {
        Text("Purgeable")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(FUColors.developerColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(
                Capsule()
                    .fill(FUColors.developerColor.opacity(0.12))
            )
    }
}
