//
//  CategoryCard.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import SwiftUI

/// Dashboard category card showing file type statistics
struct CategoryCard: View {
    let category: FileCategory
    let stats: CategoryDisplayStats?
    let isScanning: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    private var color: Color {
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
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                // Icon and title
                HStack {
                    ZStack {
                        Circle()
                            .fill(color.opacity(0.15))
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: category.iconName)
                            .font(.title2)
                            .foregroundStyle(color)
                    }
                    
                    Spacer()
                    
                    if isScanning {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else if let stats = stats, stats.count > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                
                Spacer()
                
                // Category name and stats
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.rawValue)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    if let stats = stats {
                        HStack {
                            Text(stats.formattedSize)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundStyle(color)
                            
                            Spacer()
                            
                            Text("\(stats.formattedCount) items")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(isScanning ? "Scanning..." : "No items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .frame(minHeight: 140)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.background)
                    .shadow(
                        color: isHovered ? color.opacity(0.2) : .black.opacity(0.08),
                        radius: isHovered ? 10 : 5,
                        y: isHovered ? 4 : 2
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isHovered ? color.opacity(0.3) : .clear, lineWidth: 2)
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

/// Compact category card for smaller displays
struct CompactCategoryCard: View {
    let category: FileCategory
    let stats: CategoryDisplayStats?
    let action: () -> Void
    
    private var color: Color {
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
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: category.iconName)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.rawValue)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if let stats = stats {
                        Text("\(stats.formattedCount) items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                if let stats = stats {
                    Text(stats.formattedSize)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(color)
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.background)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: 20) {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 16) {
            CategoryCard(
                category: .cache,
                stats: CategoryDisplayStats(count: 1234, totalSize: 5_000_000_000),
                isScanning: false
            ) {}
            
            CategoryCard(
                category: .videos,
                stats: CategoryDisplayStats(count: 56, totalSize: 25_000_000_000),
                isScanning: false
            ) {}
            
            CategoryCard(
                category: .photos,
                stats: nil,
                isScanning: true
            ) {}
        }
        
        CompactCategoryCard(
            category: .logs,
            stats: CategoryDisplayStats(count: 500, totalSize: 500_000_000)
        ) {}
    }
    .padding()
    .background(Color(.windowBackgroundColor))
}
