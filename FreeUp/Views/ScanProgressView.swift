//
//  ScanProgressView.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import SwiftUI

// MARK: - Circular Progress Ring

/// An animated circular progress ring with gradient stroke.
private struct CircularProgressRing: View {
    let progress: Double
    let lineWidth: CGFloat = 5
    let diameter: CGFloat = 80

    @State private var rotationAngle: Double = 0

    /// Scan gradient colors extracted for use in AngularGradient
    private let gradientColors: [Color] = [
        Color(nsColor: NSColor(red: 0.282, green: 0.820, blue: 0.800, alpha: 1)),
        Color(nsColor: NSColor(red: 0.180, green: 0.620, blue: 0.900, alpha: 1)),
        Color(nsColor: NSColor(red: 0.282, green: 0.820, blue: 0.800, alpha: 1)),
    ]

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(
                    FUColors.border,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )

            // Filled arc
            Circle()
                .trim(from: 0, to: CGFloat(min(progress, 1.0)))
                .stroke(
                    AngularGradient(
                        colors: gradientColors,
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Glow layer behind the arc for a premium feel
            Circle()
                .trim(from: 0, to: CGFloat(min(progress, 1.0)))
                .stroke(
                    AngularGradient(
                        colors: gradientColors.map { $0.opacity(0.35) },
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth + 6, lineCap: .round)
                )
                .blur(radius: 6)
                .rotationEffect(.degrees(-90))

            // Spinning indicator dot at the head of progress
            Circle()
                .fill(FUColors.accent)
                .frame(width: lineWidth + 2, height: lineWidth + 2)
                .shadow(color: FUColors.accent.opacity(0.6), radius: 4, x: 0, y: 0)
                .offset(y: -diameter / 2)
                .rotationEffect(.degrees(progress * 360 - 90))
                .opacity(progress > 0.01 ? 1 : 0)

            // Rotating ambient ring (subtle)
            Circle()
                .trim(from: 0, to: 0.25)
                .stroke(
                    FUColors.accent.opacity(0.08),
                    style: StrokeStyle(lineWidth: lineWidth + 10, lineCap: .round)
                )
                .rotationEffect(.degrees(rotationAngle))
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
        }
    }
}

// MARK: - Pulsing Icon

/// A magnifying glass that pulses gently.
private struct PulsingIcon: View {
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            // Outer pulse ring
            Circle()
                .fill(FUColors.accent.opacity(0.08))
                .frame(width: 52, height: 52)
                .scaleEffect(isPulsing ? 1.25 : 0.9)
                .opacity(isPulsing ? 0 : 0.6)

            // Inner glow
            Circle()
                .fill(FUColors.accentDim)
                .frame(width: 38, height: 38)

            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(FUColors.accent)
                .scaleEffect(isPulsing ? 1.08 : 0.95)
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.2)
                .repeatForever(autoreverses: true)
            ) {
                isPulsing = true
            }
        }
    }
}

// MARK: - Stat Column

/// A single stat column (value + label).
private struct StatColumn: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(FUColors.textPrimary)
                .contentTransition(.numericText())

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(FUColors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.4)
        }
        .frame(minWidth: 100)
    }
}

// MARK: - Linear Progress Bar

/// A thin gradient-filled progress bar.
private struct GradientProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(FUColors.border)

                // Fill
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(FUColors.scanGradient)
                    .frame(width: max(geo.size.width * CGFloat(min(progress, 1.0)), 0))

                // Glow on the leading edge
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(FUColors.accent.opacity(0.3))
                    .frame(width: max(geo.size.width * CGFloat(min(progress, 1.0)), 0))
                    .blur(radius: 3)
            }
        }
        .frame(height: 4)
    }
}

// MARK: - ScanProgressView

/// View showing real-time scan progress as a large centered overlay card.
struct ScanProgressView: View {
    let state: ScanState
    let filesScanned: Int
    let sizeScanned: Int64
    let onCancel: () -> Void

    /// Current progress extracted from the state.
    private var progress: Double {
        switch state {
        case .scanning(let p, _): return p
        case .detectingDuplicates(let p): return p
        default: return 0
        }
    }

    /// Current directory being scanned, if available.
    private var currentDirectory: String? {
        if case .scanning(_, let dir) = state { return dir }
        return nil
    }

    /// Title text depending on scan phase.
    private var title: String {
        switch state {
        case .detectingDuplicates: return "Finding Duplicates..."
        default: return "Scanning..."
        }
    }

    /// Subtitle text depending on scan phase.
    private var subtitle: String {
        switch state {
        case .detectingDuplicates:
            return "Comparing files by content"
        default:
            return "Analyzing your storage"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // -- Circular Ring + Icon --
            ZStack {
                CircularProgressRing(progress: progress)
                PulsingIcon()
            }
            .padding(.top, 32)
            .padding(.bottom, 24)

            // -- Title & Subtitle --
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(FUColors.textPrimary)

                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(FUColors.textSecondary)

                if let dir = currentDirectory {
                    Text(dir)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(FUColors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 240)
                        .padding(.top, 2)
                }
            }
            .padding(.bottom, 24)

            // -- Stat Columns --
            HStack(spacing: 32) {
                StatColumn(
                    value: formatNumber(filesScanned),
                    label: "Files Found"
                )

                // Divider
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(FUColors.border)
                    .frame(width: 1, height: 36)

                StatColumn(
                    value: ByteFormatter.format(sizeScanned),
                    label: "Data Analyzed"
                )
            }
            .padding(.bottom, 20)

            // -- Linear Progress Bar --
            GradientProgressBar(progress: progress)
                .padding(.horizontal, 32)
                .padding(.bottom, 8)

            // Percentage label
            Text("\(Int(progress * 100))%")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(FUColors.textTertiary)
                .padding(.bottom, 20)

            // -- Cancel Button --
            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FUColors.textSecondary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(FUColors.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(.bottom, 28)
        }
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(FUColors.bgElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(FUColors.border, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 40, x: 0, y: 12)
        )
        .animation(.easeInOut(duration: 0.3), value: progress)
        .animation(.easeInOut(duration: 0.3), value: filesScanned)
    }

    // MARK: - Helpers

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}

// MARK: - InlineScanProgress

/// Inline progress indicator for toolbar — small HStack with tiny spinner + text.
struct InlineScanProgress: View {
    let state: ScanState
    let filesScanned: Int

    @State private var isSpinning = false

    var body: some View {
        HStack(spacing: 6) {
            switch state {
            case .scanning:
                spinner
                Text("Found \(filesScanned) files...")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FUColors.textSecondary)

            case .detectingDuplicates:
                spinner
                Text("Finding duplicates...")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FUColors.textSecondary)

            default:
                EmptyView()
            }
        }
    }

    /// A small custom spinning indicator using the theme accent.
    private var spinner: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(FUColors.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .frame(width: 12, height: 12)
            .rotationEffect(.degrees(isSpinning ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    isSpinning = true
                }
            }
    }
}

// MARK: - Previews

#Preview("Scanning") {
    ZStack {
        FUColors.bg.ignoresSafeArea()

        ScanProgressView(
            state: .scanning(progress: 0.45, currentDirectory: "~/Library/Caches/com.apple.Safari"),
            filesScanned: 12_345,
            sizeScanned: 5_368_709_120,
            onCancel: {}
        )
    }
    .frame(width: 500, height: 500)
}

#Preview("Detecting Duplicates") {
    ZStack {
        FUColors.bg.ignoresSafeArea()

        ScanProgressView(
            state: .detectingDuplicates(progress: 0.72),
            filesScanned: 48_291,
            sizeScanned: 12_884_901_888,
            onCancel: {}
        )
    }
    .frame(width: 500, height: 500)
}

#Preview("Inline") {
    HStack {
        InlineScanProgress(
            state: .scanning(progress: 0.3, currentDirectory: nil),
            filesScanned: 1_234
        )
    }
    .padding()
    .background(FUColors.bgElevated)
}
