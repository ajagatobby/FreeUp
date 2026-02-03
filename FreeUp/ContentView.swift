//
//  ContentView.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import SwiftUI
import SwiftData

/// Main content view - delegates to DashboardView
/// This file is kept for compatibility but the main UI is in DashboardView
struct ContentView: View {
    @State private var viewModel = ScanViewModel()
    
    var body: some View {
        DashboardView(viewModel: viewModel)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [ScannedItem.self, ScanSession.self], inMemory: true)
}
