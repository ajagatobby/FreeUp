//
//  StorageBar.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import SwiftUI

/// Simple, native-feeling storage breakdown bar.
struct StorageBar: View {
    let volumeInfo: VolumeInfo?
    let reclaimableSpace: Int64

    @State private var animateProgress = false

    private var usedRatio: Double {
        guard let info = volumeInfo, info.totalCapacity > 0 else { return 0 }
        let netUsed = max(info.usedCapacity - reclaimableSpace, 0)
        return Double(netUsed) / Double(info.totalCapacity)
    }

    private var reclaimableRatio: Double {
        guard let info = volumeInfo, info.totalCapacity > 0 else { return 0 }
        return Double(min(reclaimableSpace, info.usedCapacity)) / Double(info.totalCapacity)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Label(volumeInfo?.name ?? "Storage", systemImage: "internaldrive")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                if let info = volumeInfo {
                    Text("\(ByteFormatter.format(info.availableCapacity)) available of \(info.formattedTotal)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Bar
            GeometryReader { geo in
                let w = geo.size.width
                HStack(spacing: 1.5) {
                    // Used
                    if usedRatio > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.blue)
                            .frame(width: animateProgress ? w * usedRatio : 0)
                    }
                    // Reclaimable
                    if reclaimableSpace > 0, reclaimableRatio > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.orange)
                            .frame(width: animateProgress ? w * reclaimableRatio : 0)
                    }
                    // Free
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(.separatorColor))
                }
            }
            .frame(height: 8)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            // Legend
            HStack(spacing: 16) {
                LegendDot(color: .blue, label: "Used",
                          value: volumeInfo.map { ByteFormatter.format(max($0.usedCapacity - reclaimableSpace, 0)) })
                if reclaimableSpace > 0 {
                    LegendDot(color: .orange, label: "Reclaimable",
                              value: ByteFormatter.format(reclaimableSpace))
                }
                LegendDot(color: Color(.separatorColor), label: "Available",
                          value: volumeInfo?.formattedAvailable)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.1)) {
                animateProgress = true
            }
        }
        .onChange(of: volumeInfo?.usedCapacity) {
            animateProgress = false
            withAnimation(.easeOut(duration: 0.5)) { animateProgress = true }
        }
        .onChange(of: reclaimableSpace) {
            animateProgress = false
            withAnimation(.easeOut(duration: 0.5)) { animateProgress = true }
        }
    }
}

private struct LegendDot: View {
    let color: Color
    let label: String
    let value: String?

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
            if let value {
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
