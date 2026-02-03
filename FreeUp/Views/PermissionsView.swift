//
//  PermissionsView.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import SwiftUI

/// View for guiding users through Full Disk Access setup
struct PermissionsView: View {
    let fdaStatus: PermissionStatus
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void
    
    @State private var currentStep = 0
    
    private var statusColor: Color {
        switch fdaStatus {
        case .granted: return .green
        case .denied: return .orange
        case .notDetermined: return .yellow
        case .restricted: return .red
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
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.15))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: statusIcon)
                        .font(.system(size: 36))
                        .foregroundStyle(statusColor)
                }
                
                Text(statusText)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(descriptionText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.vertical, 30)
            
            Divider()
            
            // Steps (only show if not granted)
            if fdaStatus != .granted {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("How to enable Full Disk Access:")
                            .font(.headline)
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
                                .foregroundStyle(.blue)
                            
                            Text("FreeUp should appear in the list automatically. If it doesn't, click the + button to add it manually from your Applications folder.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue.opacity(0.1))
                        )
                    }
                    .padding()
                }
            } else {
                // Success state
                VStack(spacing: 20) {
                    Spacer()
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.green)
                    
                    Text("You're all set!")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Text("FreeUp can now access protected folders to find all reclaimable storage.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Spacer()
                }
            }
            
            Divider()
            
            // Action buttons
            HStack {
                if fdaStatus != .granted {
                    Button("Open System Settings") {
                        onOpenSettings()
                        advanceStep()
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                Spacer()
                
                if fdaStatus == .granted {
                    Button("Get Started") {
                        onDismiss()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Continue Without Full Access") {
                        onDismiss()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
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

/// Single step in the setup process
struct StepView: View {
    let number: Int
    let title: String
    let description: String
    let isActive: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.2))
                    .frame(width: 32, height: 32)
                
                Text("\(number)")
                    .font(.headline)
                    .foregroundStyle(isActive ? .white : .secondary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(isActive ? .primary : .secondary)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Compact permission status indicator
struct PermissionStatusBadge: View {
    let status: PermissionStatus
    
    private var color: Color {
        switch status {
        case .granted: return .green
        case .denied: return .orange
        case .notDetermined: return .yellow
        case .restricted: return .red
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
                .font(.caption)
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
}

#Preview("Granted") {
    PermissionsView(
        fdaStatus: .granted,
        onOpenSettings: {},
        onDismiss: {}
    )
}

#Preview("Denied") {
    PermissionsView(
        fdaStatus: .denied,
        onOpenSettings: {},
        onDismiss: {}
    )
}
