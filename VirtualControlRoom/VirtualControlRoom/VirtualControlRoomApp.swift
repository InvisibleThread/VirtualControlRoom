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
