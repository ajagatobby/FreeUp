//
//  CategoryCard.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import SwiftUI

/// Premium dark-themed category card for the dashboard grid.
struct CategoryCard: View {
    let category: FileCategory
    let stats: CategoryDisplayStats?
    let isScanning: Bool
    let action: () -> Void

    @State private var isHovered = false

    private var themeColor: Color { category.themeColor }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                // --- Icon badge ---
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(themeColor.opacity(0.12))
                    .frame(width: 38, height: 38)
                    .overlay(
                        Image(systemName: category.iconName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(themeColor)
                    )

                Spacer(minLength: 0)

                // --- Category name ---
                Text(category.rawValue)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(FUColors.textPrimary)
                    .lineLimit(1)

                // --- Size + count ---
                if let stats {
                    Text(ByteFormatter.format(stats.totalSize))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(themeColor)
                        .lineLimit(1)

                    Text("\(stats.formattedCount) items")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(FUColors.textSecondary)
                        .lineLimit(1)
                } else if isScanning {
                    scanningPlaceholder
                } else {
                    Text("No items")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(FUColors.textSecondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 130)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isHovered ? FUColors.bgHover : FUColors.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isHovered ? themeColor.opacity(0.20) : FUColors.border,
                        lineWidth: 1
                    )
            )
            .shadow(
                color: isHovered ? themeColor.opacity(0.10) : .black.opacity(0.15),
                radius: isHovered ? 12 : 4,
                y: isHovered ? 4 : 2
            )
            .offset(y: isHovered ? -2 : 0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }

    // MARK: - Scanning placeholder

    @ViewBuilder
    private var scanningPlaceholder: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            Text("Scanning...")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(FUColors.textSecondary)
        }
    }
}
