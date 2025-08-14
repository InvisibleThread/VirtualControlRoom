//
//  VirtualControlRoomApp.swift
//  VirtualControlRoom
//
//  Created by Alex Hessler on 6/1/25.
//

import SwiftUI
import CoreData

@main
struct VirtualControlRoomApp: App {

    @State private var appModel = AppModel()
    @StateObject private var profileManager = ConnectionProfileManager.shared
    @StateObject private var connectionManager = ConnectionManager.shared
    

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
                .environment(\.managedObjectContext, profileManager.viewContext)
                .environmentObject(connectionManager)
        }
        .defaultSize(width: 600, height: 700)
        .windowStyle(.automatic)
        
        WindowGroup(id: "vnc-window", for: UUID.self) { $connectionID in
            if let connectionID = connectionID {
                VNCConnectionWindowView(connectionID: connectionID)
                    .environmentObject(connectionManager)
            } else {
                VNCWindowView()
                    .environmentObject(connectionManager)
            }
        }
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentSize)
        .windowStyle(.automatic)
        
        // Group VNC windows with grid positioning (legacy - individual windows)
        WindowGroup(id: "vnc-group-window", for: GroupWindowValue.self) { $groupWindowValue in
            if let groupWindowValue = groupWindowValue {
                GroupVNCWindowView(groupWindowValue: groupWindowValue)
                    .environmentObject(connectionManager)
            } else {
                Text("Group window not available")
                    .foregroundStyle(.secondary)
            }
        }
        .defaultSize(width: 800, height: 600) // Base size - will be scaled by grid layout
        .windowResizability(.contentSize)
        .windowStyle(.automatic)
        
        // Unified group grid window - single window containing all connections in a grid
        WindowGroup(id: "vnc-group-grid", for: GroupGridValue.self) { $groupGridValue in
            if let groupGridValue = groupGridValue {
                GroupGridWindow(groupGridValue: groupGridValue)
                    .environmentObject(connectionManager)
                    .environmentObject(GroupOTPManager.shared)
            } else {
                Text("Group grid not available")
                    .foregroundStyle(.secondary)
            }
        }
        .defaultSize(width: 1600, height: 1200) // Larger default size to prevent initial overlap
        .windowResizability(.contentMinSize)
        .windowStyle(.automatic)
        
        // Group connection progress window
        WindowGroup(id: "group-progress", for: GroupProgressValue.self) { $progressValue in
            if let progressValue = progressValue {
                GroupConnectionProgressView(
                    groupName: progressValue.groupName,
                    connectionProfiles: progressValue.getConnectionProfiles()
                )
                .environmentObject(GroupOTPManager.shared)
            } else {
                Text("Progress not available")
                    .foregroundStyle(.secondary)
            }
        }
        .defaultSize(width: 500, height: 600)
        .windowResizability(.contentSize)
        .windowStyle(.automatic)

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
                .onAppear {
                    appModel.immersiveSpaceState = .open
                }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                }
        }
        .immersionStyle(selection: .constant(.full), in: .full)
    }
}
