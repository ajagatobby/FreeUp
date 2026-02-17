//
//  PermissionsView.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import SwiftUI

/// View for guiding users through Full Disk Access setup — dark themed
struct PermissionsView: View {
    let fdaStatus: PermissionStatus
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void
    
    @State private var currentStep = 0
    
    private var statusColor: Color {
        switch fdaStatus {
        case .granted: return Color.green
        case .denied: return Color.orange
        case .notDetermined: return Color.orange.opacity(0.7)
        case .restricted: return Color.red
        }
    }
    
    private var statusIcon: String {
        switch fdaStatus {
        case .granted: return "checkmark.shield.fill"
        case .denied: return "shield.slash"
        case .notDetermined: return "questionmark.shield"
        case .restricted: return "xmark.shield"
        }
    }
    
    private var statusText: String {
        switch fdaStatus {
        case .granted: return "Full Disk Access Granted"
        case .denied: return "Full Disk Access Required"
        case .notDetermined: return "Full Disk Access Not Configured"
        case .restricted: return "Full Disk Access Restricted"
        }
    }
    
    var body: some View {
        ZStack {
            Color(.windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(statusColor.opacity(0.12))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: statusIcon)
                            .font(.system(size: 36, weight: .medium))
                            .foregroundStyle(statusColor)
                    }
                    
                    Text(statusText)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Text(descriptionText)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.vertical, 30)
                
                Rectangle()
                    .fill(Color(.separatorColor))
                    .frame(height: 1)
                
                // Steps (only show if not granted)
                if fdaStatus != .granted {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            Text("How to enable Full Disk Access:")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)
                                .padding(.top)
                            
                            StepView(
                                number: 1,
                                title: "Open System Settings",
                                description: "Click the button below or go to Apple menu > System Settings",
                                isActive: currentStep == 0
                            )
                            
                            StepView(
                                number: 2,
                                title: "Navigate to Privacy & Security",
                                description: "In the sidebar, click Privacy & Security",
                                isActive: currentStep == 1
                            )
                            
                            StepView(
                                number: 3,
                                title: "Find Full Disk Access",
                                description: "Scroll down and click Full Disk Access",
                                isActive: currentStep == 2
                            )
                            
                            StepView(
                                number: 4,
                                title: "Enable FreeUp",
                                description: "Find FreeUp in the list and toggle it on. You may need to enter your password.",
                                isActive: currentStep == 3
                            )
                            
                            // Note about app appearing
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(Color.blue)
                                
                                Text("FreeUp should appear in the list automatically. If it doesn't, click the + button to add it manually from your Applications folder.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.blue.opacity(0.08))
                            )
                        }
                        .padding()
                    }
                    .scrollContentBackground(.hidden)
                } else {
                    // Success state
                    VStack(spacing: 20) {
                        Spacer()
                        
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.12))
                                .frame(width: 72, height: 72)

                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 38))
                                .foregroundStyle(Color.green)
                        }
                        
                        Text("You're all set!")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                        
                        Text("FreeUp can now access protected folders to find all reclaimable storage.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        
                        Spacer()
                    }
                }
                
                Rectangle()
                    .fill(Color(.separatorColor))
                    .frame(height: 1)
                
                // Action buttons
                HStack {
                    if fdaStatus != .granted {
                        Button {
                            onOpenSettings()
                            advanceStep()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "gear")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Open System Settings")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.accentColor)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Spacer()
                    
                    if fdaStatus == .granted {
                        Button {
                            onDismiss()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Get Started")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.accentColor)
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            onDismiss()
                        } label: {
                            Text("Continue Without Full Access")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
                .background(Color(.controlBackgroundColor))
            }
        }
        .frame(width: 500, height: 600)
    }
    
    private var descriptionText: String {
        switch fdaStatus {
        case .granted:
            return "FreeUp can access cache, logs, and system folders to find junk files."
        case .denied:
            return "FreeUp needs Full Disk Access to scan protected folders like Library and Application Support."
        case .notDetermined:
            return "Grant Full Disk Access to let FreeUp scan common junk locations on your Mac."
        case .restricted:
            return "Full Disk Access is restricted on this Mac. Contact your administrator."
        }
    }
    
    private func advanceStep() {
        if currentStep < 3 {
            withAnimation {
                currentStep += 1
            }
        }
    }
}

/// Single step in the setup process — dark themed
struct StepView: View {
    let number: Int
    let title: String
    let description: String
    let isActive: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.accentColor : Color(.quaternaryLabelColor))
                    .frame(width: 32, height: 32)
                
                Text("\(number)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isActive ? Color.white : Color(.tertiaryLabelColor))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isActive ? .primary : .secondary)
                
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Compact permission status indicator — dark themed
struct PermissionStatusBadge: View {
    let status: PermissionStatus
    
    private var color: Color {
        switch status {
        case .granted: return Color.green
        case .denied: return Color.orange
        case .notDetermined: return Color.orange.opacity(0.7)
        case .restricted: return Color.red
        }
    }
    
    private var text: String {
        switch status {
        case .granted: return "Full Access"
        case .denied: return "Limited Access"
        case .notDetermined: return "Not Configured"
        case .restricted: return "Restricted"
        }
    }
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(color.opacity(0.1))
        )
    }
}

#Preview("Not Determined") {
    PermissionsView(
        fdaStatus: .notDetermined,
        onOpenSettings: {},
        onDismiss: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Granted") {
    PermissionsView(
        fdaStatus: .granted,
        onOpenSettings: {},
        onDismiss: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Denied") {
    PermissionsView(
        fdaStatus: .denied,
        onOpenSettings: {},
        onDismiss: {}
    )
    .preferredColorScheme(.dark)
}
