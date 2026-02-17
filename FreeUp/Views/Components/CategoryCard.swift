//
//  CategoryCard.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import SwiftUI

/// Native-feeling sidebar row for a file category.
struct SidebarCategoryRow: View {
    let category: FileCategory
    let stats: CategoryDisplayStats?
    let isSelected: Bool
    let action: () -> Void

    private var themeColor: Color { category.themeColor }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: category.iconName)
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? .white : themeColor)
                    .frame(width: 22)

                Text(category.rawValue)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)

                Spacer(minLength: 2)

                if let stats, stats.totalSize > 0 {
                    Text(ByteFormatter.format(stats.totalSize))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}
