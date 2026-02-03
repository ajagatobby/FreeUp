//
//  ScanProgressView.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import SwiftUI

/// View showing real-time scan progress
struct ScanProgressView: View {
    let state: ScanState
    let filesScanned: Int
    let sizeScanned: Int64
    let onCancel: () -> Void
    
    @State private var pulseAnimation = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Animated icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 100, height: 100)
                    .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                    .opacity(pulseAnimation ? 0 : 1)
                
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.accentColor)
                    .rotationEffect(.degrees(pulseAnimation ? 20 : -20))
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever()) {
                    pulseAnimation = true
                }
            }
            
            // Status text
            VStack(spacing: 8) {
                if case .scanning(_, let currentDir) = state {
                    Text("Scanning...")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    if let dir = currentDir {
                        Text(dir)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            
            // Statistics
            HStack(spacing: 40) {
                StatItem(
                    value: formatNumber(filesScanned),
                    label: "Files Scanned"
                )
                
                StatItem(
                    value: ByteFormatter.format(sizeScanned),
                    label: "Data Analyzed"
                )
            }
            
            // Progress bar
            if case .scanning(let progress, _) = state {
                VStack(spacing: 4) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(width: 200)
                    
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Cancel button
            Button("Cancel Scan", action: onCancel)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
    }
    
    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}

/// Single statistic item
private struct StatItem: View {
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .monospacedDigit()
            
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Inline progress indicator for toolbar
struct InlineScanProgress: View {
    let state: ScanState
    let filesScanned: Int
    
    var body: some View {
        HStack(spacing: 8) {
            if case .scanning = state {
                ProgressView()
                    .scaleEffect(0.7)
                
                Text("Scanning \(filesScanned) files...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    ScanProgressView(
        state: .scanning(progress: 0.45, currentDirectory: "Library/Caches"),
        filesScanned: 12345,
        sizeScanned: 5_000_000_000,
        onCancel: {}
    )
    .padding()
    .background(Color(.windowBackgroundColor))
}
