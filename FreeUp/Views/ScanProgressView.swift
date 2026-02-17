//
//  ScanProgressView.swift
//  FreeUp
//
//  CleanMyMac-style scan progress with animated orbital ring + glow.
//

import SwiftUI

// MARK: - Orbital Ring

/// Animated ring that orbits around a center point — CleanMyMac-inspired.
private struct OrbitalRing: View {
    let progress: Double

    @State private var rotation: Double = 0
    @State private var appeared = false

    var body: some View {
        ZStack {
            // Background track
            Circle()
                .stroke(Color(.separatorColor).opacity(0.3), lineWidth: 4)

            // Progress arc
            Circle()
                .trim(from: 0, to: min(progress, 1.0))
                .stroke(
                    AngularGradient(
                        colors: [
                            Color.accentColor.opacity(0),
                            Color.accentColor,
                            Color.accentColor
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Glow layer
            Circle()
                .trim(from: 0, to: min(progress, 1.0))
                .stroke(
                    Color.accentColor.opacity(0.3),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .blur(radius: 8)
                .rotationEffect(.degrees(-90))

            // Orbiting dot
            Circle()
                .fill(Color.accentColor)
                .frame(width: 8, height: 8)
                .shadow(color: Color.accentColor.opacity(0.7), radius: 6)
                .offset(y: -48)
                .rotationEffect(.degrees(rotation))
        }
        .frame(width: 96, height: 96)
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// MARK: - ScanProgressView

/// Full scan progress overlay — centered card with orbital ring.
struct ScanProgressView: View {
    let state: ScanState
    let filesScanned: Int
    let sizeScanned: Int64
    let onCancel: () -> Void

    private var progress: Double {
        switch state {
        case .scanning(let p, _): return p
        case .detectingDuplicates(let p): return p
        default: return 0
        }
    }

    private var currentDirectory: String? {
        if case .scanning(_, let dir) = state { return dir }
        return nil
    }

    private var title: String {
        switch state {
        case .detectingDuplicates: return "Finding Duplicates..."
        default: return "Scanning Your Mac..."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Ring + icon
            ZStack {
                OrbitalRing(progress: progress)

                Image(systemName: "magnifyingglass")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 24)

            // Title
            Text(title)
                .font(.title3.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.bottom, 4)

            // Directory
            if let dir = currentDirectory {
                Text(dir)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 280)
                    .padding(.bottom, 12)
            }

            // Stats
            HStack(spacing: 24) {
                VStack(spacing: 2) {
                    Text(formatNumber(filesScanned))
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                    Text("files found")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                
                Divider().frame(height: 30)

                VStack(spacing: 2) {
                    Text(ByteFormatter.format(sizeScanned))
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                    Text("analyzed")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.bottom, 20)

            // Progress bar
            ProgressView(value: progress)
                .tint(Color.accentColor)
                .frame(width: 200)
                .padding(.bottom, 6)

            Text("\(Int(progress * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .padding(.bottom, 20)

            // Cancel
            Button("Cancel", action: onCancel)
                .buttonStyle(.bordered)
                .controlSize(.small)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .animation(.easeInOut(duration: 0.3), value: progress)
        .animation(.easeInOut(duration: 0.3), value: filesScanned)
    }

    private func formatNumber(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

// MARK: - InlineScanProgress

struct InlineScanProgress: View {
    let state: ScanState
    let filesScanned: Int

    var body: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)

            switch state {
            case .scanning:
                Text("\(filesScanned) files...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .detectingDuplicates:
                Text("Finding duplicates...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            default:
                EmptyView()
            }
        }
    }
}
