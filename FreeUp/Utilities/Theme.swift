//
//  Theme.swift
//  FreeUp
//
//  Design system inspired by premium macOS utilities.
//  Dark, confident, depth-driven aesthetic.
//

import SwiftUI

// MARK: - Color Palette

enum FUColors {
    // Backgrounds — deep, layered
    static let bg = Color(nsColor: NSColor(red: 0.078, green: 0.078, blue: 0.098, alpha: 1))        // #141419
    static let bgElevated = Color(nsColor: NSColor(red: 0.110, green: 0.110, blue: 0.137, alpha: 1)) // #1C1C23
    static let bgCard = Color(nsColor: NSColor(red: 0.137, green: 0.137, blue: 0.169, alpha: 1))     // #23232B
    static let bgHover = Color(nsColor: NSColor(red: 0.169, green: 0.169, blue: 0.208, alpha: 1))    // #2B2B35

    // Text
    static let textPrimary = Color(nsColor: NSColor(red: 0.933, green: 0.933, blue: 0.953, alpha: 1)) // #EEF
    static let textSecondary = Color(nsColor: NSColor(red: 0.553, green: 0.553, blue: 0.616, alpha: 1)) // #8D8D9D
    static let textTertiary = Color(nsColor: NSColor(red: 0.373, green: 0.373, blue: 0.427, alpha: 1)) // #5F5F6D

    // Accent — teal/cyan
    static let accent = Color(nsColor: NSColor(red: 0.282, green: 0.820, blue: 0.800, alpha: 1))       // #48D1CC
    static let accentDim = Color(nsColor: NSColor(red: 0.282, green: 0.820, blue: 0.800, alpha: 0.15))

    // Gradients
    static let accentGradient = LinearGradient(
        colors: [
            Color(nsColor: NSColor(red: 0.282, green: 0.820, blue: 0.800, alpha: 1)),
            Color(nsColor: NSColor(red: 0.361, green: 0.569, blue: 0.957, alpha: 1))
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let scanGradient = LinearGradient(
        colors: [
            Color(nsColor: NSColor(red: 0.282, green: 0.820, blue: 0.800, alpha: 1)),
            Color(nsColor: NSColor(red: 0.180, green: 0.620, blue: 0.900, alpha: 1))
        ],
        startPoint: .top, endPoint: .bottom
    )

    // Category colors — rich, saturated
    static let cacheColor = Color(nsColor: NSColor(red: 1.0, green: 0.749, blue: 0.2, alpha: 1))      // Amber
    static let logsColor = Color(nsColor: NSColor(red: 0.600, green: 0.580, blue: 0.686, alpha: 1))   // Muted purple
    static let systemJunkColor = Color(nsColor: NSColor(red: 0.976, green: 0.380, blue: 0.380, alpha: 1)) // Coral red
    static let developerColor = Color(nsColor: NSColor(red: 0.380, green: 0.820, blue: 0.490, alpha: 1))  // Green
    static let downloadsColor = Color(nsColor: NSColor(red: 0.361, green: 0.569, blue: 0.957, alpha: 1))  // Blue
    static let duplicatesColor = Color(nsColor: NSColor(red: 0.282, green: 0.820, blue: 0.800, alpha: 1)) // Teal
    static let photosColor = Color(nsColor: NSColor(red: 0.937, green: 0.451, blue: 0.612, alpha: 1))     // Pink
    static let videosColor = Color(nsColor: NSColor(red: 0.667, green: 0.400, blue: 0.906, alpha: 1))     // Purple
    static let audioColor = Color(nsColor: NSColor(red: 0.976, green: 0.600, blue: 0.282, alpha: 1))      // Orange
    static let documentsColor = Color(nsColor: NSColor(red: 0.361, green: 0.569, blue: 0.957, alpha: 1))  // Blue
    static let archivesColor = Color(nsColor: NSColor(red: 0.686, green: 0.533, blue: 0.380, alpha: 1))   // Brown
    static let orphanedColor = Color(nsColor: NSColor(red: 0.478, green: 0.412, blue: 0.831, alpha: 1))   // Indigo

    // Borders
    static let border = Color.white.opacity(0.06)
    static let borderSubtle = Color.white.opacity(0.03)

    // Danger
    static let danger = Color(nsColor: NSColor(red: 0.976, green: 0.380, blue: 0.380, alpha: 1))
    static let dangerDim = Color(nsColor: NSColor(red: 0.976, green: 0.380, blue: 0.380, alpha: 0.12))
}

// MARK: - Category Color Extension

extension FileCategory {
    /// Rich, saturated color for the redesigned UI
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

// MARK: - Common View Modifiers

struct FUCardStyle: ViewModifier {
    var cornerRadius: CGFloat = 14
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(FUColors.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(FUColors.border, lineWidth: 1)
                    )
            )
    }
}

extension View {
    func fuCard(cornerRadius: CGFloat = 14, padding: CGFloat = 16) -> some View {
        modifier(FUCardStyle(cornerRadius: cornerRadius, padding: padding))
    }
}
