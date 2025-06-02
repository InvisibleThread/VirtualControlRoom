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
    @State private var showVNCTest = false

    var body: some View {
        VStack {
            Model3D(named: "Scene", bundle: realityKitContentBundle)
                .padding(.bottom, 50)

            Text("Hello, world! Anikah")

            ToggleImmersiveSpaceButton()
            
            Button("VNC Test") {
                showVNCTest = true
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
        }
        .padding()
        .sheet(isPresented: $showVNCTest) {
            VNCTestView()
                .frame(minWidth: 800, minHeight: 600)
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
