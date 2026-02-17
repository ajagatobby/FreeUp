//
//  Theme.swift
//  FreeUp
//
//  Thin design-token layer over system colors.
//  Uses NSColor/Color system APIs so the app inherits macOS appearance
//  (dark mode, accent color, vibrancy) automatically.
//

import SwiftUI

// MARK: - FUColors

enum FUColors {
    // Backgrounds — system materials
    static let bg = Color(.windowBackgroundColor)
    static let bgElevated = Color(.controlBackgroundColor)
    static let bgCard = Color(.unemphasizedSelectedContentBackgroundColor)
    static let bgHover = Color(.quaternaryLabelColor)

    // Text — system semantic colors
    static let textPrimary = Color(.labelColor)
    static let textSecondary = Color(.secondaryLabelColor)
    static let textTertiary = Color(.tertiaryLabelColor)

    // Accent — the user's system accent, with an app-specific teal fallback
    static let accent = Color.accentColor
    static let accentDim = Color.accentColor.opacity(0.12)

    // Gradients — kept minimal, only for the scan button and progress
    static let accentGradient = LinearGradient(
        colors: [.accentColor, .accentColor.opacity(0.7)],
        startPoint: .top, endPoint: .bottom
    )
    static let scanGradient = LinearGradient(
        colors: [.accentColor, .accentColor.opacity(0.6)],
        startPoint: .leading, endPoint: .trailing
    )

    // Category colors — muted to not compete with content
    static let cacheColor = Color.orange
    static let logsColor = Color.gray
    static let systemJunkColor = Color.red
    static let developerColor = Color.green
    static let downloadsColor = Color.blue
    static let duplicatesColor = Color.teal
    static let photosColor = Color.pink
    static let videosColor = Color.purple
    static let audioColor = Color.orange
    static let documentsColor = Color.blue
    static let archivesColor = Color.brown
    static let orphanedColor = Color.indigo

    // Borders — system separator
    static let border = Color(.separatorColor)
    static let borderSubtle = Color(.separatorColor).opacity(0.5)

    // Danger
    static let danger = Color.red
    static let dangerDim = Color.red.opacity(0.12)
}

// MARK: - Category Color Extension

extension FileCategory {
    var themeColor: Color {
        switch self {
        case .cache: return FUColors.cacheColor
        case .logs: return FUColors.logsColor
        case .systemJunk: return FUColors.systemJunkColor
        case .developerFiles: return FUColors.developerColor
        case .downloads: return FUColors.downloadsColor
        case .duplicates: return FUColors.duplicatesColor
        case .photos: return FUColors.photosColor
        case .videos: return FUColors.videosColor
        case .audio: return FUColors.audioColor
        case .documents: return FUColors.documentsColor
        case .archives: return FUColors.archivesColor
        case .orphanedAppData: return FUColors.orphanedColor
        case .applications: return FUColors.accent
        case .other: return FUColors.textSecondary
        }
    }
}

// MARK: - Convenience modifier

struct FUCardStyle: ViewModifier {
    var cornerRadius: CGFloat = 8
    var padding: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    func fuCard(cornerRadius: CGFloat = 8, padding: CGFloat = 12) -> some View {
        modifier(FUCardStyle(cornerRadius: cornerRadius, padding: padding))
    }
}
