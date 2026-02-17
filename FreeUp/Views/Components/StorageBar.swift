//
//  StorageBar.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import SwiftUI

/// Visual storage breakdown bar showing used, available, and reclaimable space
struct StorageBar: View {
    let volumeInfo: VolumeInfo?
    let reclaimableSpace: Int64

    @State private var animateProgress = false

    // MARK: - Computed Ratios

    private var usedRatio: Double {
        guard let info = volumeInfo, info.totalCapacity > 0 else { return 0 }
        let netUsed = max(info.usedCapacity - reclaimableSpace, 0)
        return Double(netUsed) / Double(info.totalCapacity)
    }

    private var reclaimableRatio: Double {
        guard let info = volumeInfo, info.totalCapacity > 0 else { return 0 }
        return Double(min(reclaimableSpace, info.usedCapacity)) / Double(info.totalCapacity)
    }

    private var availableRatio: Double {
        guard let info = volumeInfo, info.totalCapacity > 0 else { return 1 }
        return Double(info.availableCapacity) / Double(info.totalCapacity)
    }

    // MARK: - Segment Colors

    private var usedGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(nsColor: NSColor(red: 0.30, green: 0.56, blue: 0.95, alpha: 1)),
                Color(nsColor: NSColor(red: 0.36, green: 0.67, blue: 1.0, alpha: 1))
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var reclaimableGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(nsColor: NSColor(red: 0.96, green: 0.65, blue: 0.14, alpha: 1)),
                Color(nsColor: NSColor(red: 1.0, green: 0.78, blue: 0.28, alpha: 1))
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            bar
            legend
        }
        .fuCard()
        .onAppear {
            withAnimation(.easeOut(duration: 1.0).delay(0.15)) {
                animateProgress = true
            }
        }
        .onChange(of: volumeInfo?.usedCapacity) {
            animateProgress = false
            withAnimation(.easeOut(duration: 0.6)) {
                animateProgress = true
            }
        }
        .onChange(of: reclaimableSpace) {
            animateProgress = false
            withAnimation(.easeOut(duration: 0.6)) {
                animateProgress = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 7) {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FUColors.accent)

                Text(volumeInfo?.name ?? "Storage")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FUColors.textPrimary)
            }

            Spacer()

            if let info = volumeInfo {
                Text("\(ByteFormatter.format(info.usedCapacity)) of \(info.formattedTotal) used")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FUColors.textSecondary)
            }
        }
    }

    // MARK: - Segmented Bar

    private var bar: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let usedWidth = totalWidth * usedRatio
            let reclaimWidth = reclaimableSpace > 0 ? totalWidth * reclaimableRatio : 0
            let gap: CGFloat = (reclaimableSpace > 0 && usedRatio > 0) ? 1.5 : 0
            let gap2: CGFloat = (reclaimableRatio > 0 || usedRatio > 0) ? 1.5 : 0

            HStack(spacing: 0) {
                // Used segment
                if usedRatio > 0 {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(usedGradient)
                        .frame(width: animateProgress ? usedWidth : 0)
                }

                if gap > 0 { Spacer().frame(width: gap) }

                // Reclaimable segment
                if reclaimableSpace > 0 && reclaimableRatio > 0 {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(reclaimableGradient)
                        .frame(width: animateProgress ? reclaimWidth : 0)
                }

                if gap2 > 0 { Spacer().frame(width: gap2) }

                // Available segment (fills remaining)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.06))

            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 10)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 18) {
            StorageBarLegendDot(
                gradient: usedGradient,
                label: "Used",
                value: volumeInfo.map { ByteFormatter.format(max($0.usedCapacity - reclaimableSpace, 0)) }
            )

            if reclaimableSpace > 0 {
                StorageBarLegendDot(
                    gradient: reclaimableGradient,
                    label: "Reclaimable",
                    value: ByteFormatter.format(reclaimableSpace)
                )
            }

            StorageBarLegendDot(
                solidColor: Color.white.opacity(0.20),
                label: "Available",
                value: volumeInfo?.formattedAvailable
            )
        }
    }
}

// MARK: - Legend Dot

private struct StorageBarLegendDot: View {
    var gradient: LinearGradient?
    var solidColor: Color?
    let label: String
    let value: String?

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(gradient.map { AnyShapeStyle($0) } ?? AnyShapeStyle(solidColor ?? Color.clear))
                .frame(width: 7, height: 7)

            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(FUColors.textTertiary)

            if let value {
                Text(value)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FUColors.textSecondary)
            }
        }
    }
}
