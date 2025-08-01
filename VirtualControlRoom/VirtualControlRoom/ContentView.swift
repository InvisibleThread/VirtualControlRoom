//
//  ContentView.swift
//  VirtualControlRoom
//
//  Created by Alex Hessler on 6/1/25.
//

import SwiftUI
import RealityKit
import RealityKitContent

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ConnectionListView()
                .tabItem {
                    Label("Connections", systemImage: "network")
                }
                .tag(0)
            
            GroupListView()
                .tabItem {
                    Label("Groups", systemImage: "rectangle.3.group")
                }
                .tag(1)
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(2)
        }
    }
}

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("Build")
                        Spacer()
                        Text("Sprint 1")
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("VNC Settings") {
                    HStack {
                        Text("Default Port")
                        Spacer()
                        Text("5900")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("Connection Timeout")
                        Spacer()
                        Text("30 seconds")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
        .environment(\.managedObjectContext, ConnectionProfileManager.shared.viewContext)
}
