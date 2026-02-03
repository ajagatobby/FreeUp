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
    
    private var usedRatio: Double {
        guard let info = volumeInfo, info.totalCapacity > 0 else { return 0 }
        return Double(info.usedCapacity - reclaimableSpace) / Double(info.totalCapacity)
    }
    
    private var reclaimableRatio: Double {
        guard let info = volumeInfo, info.totalCapacity > 0 else { return 0 }
        return Double(reclaimableSpace) / Double(info.totalCapacity)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                if let info = volumeInfo {
                    Label(info.name, systemImage: "internaldrive")
                        .font(.headline)
                } else {
                    Label("Storage", systemImage: "internaldrive")
                        .font(.headline)
                }
                
                Spacer()
                
                if let info = volumeInfo {
                    Text("\(info.formattedAvailable) available")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Storage bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.2))
                    
                    // Used space (excluding reclaimable)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [.blue, .blue.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: animateProgress ? geometry.size.width * (usedRatio + reclaimableRatio) : 0)
                    
                    // Reclaimable space overlay
                    if reclaimableSpace > 0 {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                LinearGradient(
                                    colors: [.orange, .yellow],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: animateProgress ? geometry.size.width * reclaimableRatio : 0)
                            .offset(x: geometry.size.width * usedRatio)
                    }
                }
            }
            .frame(height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
            // Legend
            HStack(spacing: 20) {
                LegendItem(color: .blue, label: "Used", value: volumeInfo?.formattedUsed)
                
                if reclaimableSpace > 0 {
                    LegendItem(color: .orange, label: "Reclaimable", value: ByteFormatter.format(reclaimableSpace))
                }
                
                LegendItem(color: Color.secondary.opacity(0.3), label: "Available", value: volumeInfo?.formattedAvailable)
            }
            .font(.caption)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
        )
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                animateProgress = true
            }
        }
        .onChange(of: volumeInfo?.usedCapacity) {
            animateProgress = false
            withAnimation(.easeOut(duration: 0.5)) {
                animateProgress = true
            }
        }
    }
}

/// Legend item for storage bar
struct LegendItem: View {
    let color: Color
    let label: String
    let value: String?
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            
            Text(label)
                .foregroundStyle(.secondary)
            
            if let value = value {
                Text(value)
                    .fontWeight(.medium)
            }
        }
    }
}

#Preview {
    StorageBar(
        volumeInfo: VolumeInfo(
            name: "Macintosh HD",
            totalCapacity: 500_000_000_000,
            availableCapacity: 150_000_000_000,
            availableForImportantUsage: 140_000_000_000,
            availableForOpportunisticUsage: 160_000_000_000,
            isLocal: true
        ),
        reclaimableSpace: 25_000_000_000
    )
    .padding()
    .frame(width: 500)
}
