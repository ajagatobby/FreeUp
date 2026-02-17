//
//  CategoryCard.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import SwiftUI

/// Compact sidebar row for a file category — used in the left sidebar.
struct SidebarCategoryRow: View {
    let category: FileCategory
    let stats: CategoryDisplayStats?
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    private var themeColor: Color { category.themeColor }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Icon
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(themeColor.opacity(isSelected ? 0.20 : 0.10))
                    .frame(width: 30, height: 30)
                    .overlay(
                        Image(systemName: category.iconName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(themeColor)
                    )

                // Name
                Text(category.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? FUColors.textPrimary : FUColors.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                // Size badge
                if let stats {
                    Text(ByteFormatter.format(stats.totalSize))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? themeColor : FUColors.textTertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isSelected
                            ? themeColor.opacity(0.10)
                            : (isHovered ? FUColors.bgHover : Color.clear)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isSelected ? themeColor.opacity(0.20) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}
