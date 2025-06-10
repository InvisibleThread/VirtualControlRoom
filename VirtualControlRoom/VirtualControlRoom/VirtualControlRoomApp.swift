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
    @StateObject private var vncClient = LibVNCClient()
    @StateObject private var profileManager = ConnectionProfileManager.shared
    

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
                .environmentObject(vncClient)
                .environment(\.managedObjectContext, profileManager.viewContext)
        }
        
        WindowGroup(id: "vnc-simple-window") {
            VNCSimpleWindowView(vncClient: vncClient)
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
