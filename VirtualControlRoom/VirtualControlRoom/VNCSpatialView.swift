import SwiftUI
import RealityKit
import RealityKitContent

struct VNCSpatialView: View {
    @ObservedObject var vncClient: VNCClient
    @State private var desktopEntity: ModelEntity?
    
    var body: some View {
        RealityView { content in
            // Create a plane to display the VNC content
            let mesh = MeshResource.generatePlane(width: 2.0, height: 1.125) // 16:9 aspect ratio
            
            // Create material with initial color
            var material = SimpleMaterial()
            material.color = .init(tint: .gray)
            
            // Create the desktop entity
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.position = [0, 1.5, -2] // Position 2 meters in front, 1.5m high
            
            content.add(entity)
            desktopEntity = entity
            
        } update: { content in
            // Update the texture when framebuffer changes
            if let framebuffer = vncClient.framebuffer,
               let entity = desktopEntity {
                
                // Convert CGImage to texture
                if let texture = try? TextureResource.generate(from: framebuffer, options: .init(semantic: .color)) {
                    var material = SimpleMaterial()
                    material.color = .init(texture: .init(texture))
                    entity.model?.materials = [material]
                }
            }
        }
        .onDisappear {
            vncClient.disconnect()
        }
        .toolbar {
            ToolbarItem(placement: .bottomOrnament) {
                HStack {
                    switch vncClient.connectionState {
                    case .connected:
                        Label("Connected", systemImage: "circle.fill")
                            .foregroundColor(.green)
                    case .connecting:
                        Label("Connecting...", systemImage: "circle.fill")
                            .foregroundColor(.orange)
                    case .disconnected:
                        Label("Disconnected", systemImage: "circle.fill")
                            .foregroundColor(.gray)
                    case .failed(let errorMessage):
                        Label("Error: \(errorMessage)", systemImage: "exclamationmark.triangle")
                            .foregroundColor(.red)
                    }
                    
                    Spacer()
                    
                    Button("Disconnect") {
                        vncClient.disconnect()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .frame(width: 400)
            }
        }
    }
}