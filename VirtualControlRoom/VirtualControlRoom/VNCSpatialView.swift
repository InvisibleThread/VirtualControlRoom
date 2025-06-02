import SwiftUI
import RealityKit
import RealityKitContent

struct VNCSpatialView: View {
    @ObservedObject var vncClient: RoyalVNCClient
    @State private var desktopEntity: ModelEntity?
    @State private var isEntityCreated = false
    
    var body: some View {
        RealityView { content in
            print("DEBUG: RealityView initialized")
            print("DEBUG: RealityView content entities count: \(content.entities.count)")
            
            // Create the initial plane
            if let framebuffer = vncClient.framebuffer {
                print("DEBUG: RealityView has framebuffer on init: \(framebuffer.width)x\(framebuffer.height)")
                createDesktopPlane(content: content, framebuffer: framebuffer)
            } else {
                print("DEBUG: RealityView has no framebuffer on init")
            }
            
        } update: { content in
            print("DEBUG: RealityView update block called")
            print("DEBUG: vncClient.framebuffer is \(vncClient.framebuffer != nil ? "NOT NIL" : "NIL")")
            print("DEBUG: desktopEntity is \(desktopEntity != nil ? "NOT NIL" : "NIL")")
            print("DEBUG: isEntityCreated is \(isEntityCreated)")
            
            // Only update texture if entity exists
            if let framebuffer = vncClient.framebuffer, let entity = desktopEntity {
                print("DEBUG: Updating existing entity texture")
                updateTexture(entity: entity, framebuffer: framebuffer)
            } else if let framebuffer = vncClient.framebuffer, !isEntityCreated {
                print("DEBUG: Creating new entity")
                // Create entity if it doesn't exist yet
                createDesktopPlane(content: content, framebuffer: framebuffer)
            } else {
                print("DEBUG: No action taken in update block")
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
    
    private func createDesktopPlane(content: RealityViewContent, framebuffer: CGImage) {
        guard !isEntityCreated else { return }
        
        let aspectRatio = Float(framebuffer.width) / Float(framebuffer.height)
        let height: Float = 1.5
        let width = height * aspectRatio
        
        print("DEBUG: Creating plane with size: \(width) x \(height) (aspect ratio: \(aspectRatio))")
        
        let mesh = MeshResource.generatePlane(width: width, height: height)
        let entity = ModelEntity(mesh: mesh, materials: [SimpleMaterial()])
        entity.position = [0, 1.5, -3] // Position 3 meters in front, 1.5m high
        
        content.add(entity)
        desktopEntity = entity
        isEntityCreated = true
        
        // Apply initial texture
        updateTexture(entity: entity, framebuffer: framebuffer)
    }
    
    private func updateTexture(entity: ModelEntity, framebuffer: CGImage) {
        do {
            let texture = try TextureResource.generate(from: framebuffer, options: .init(semantic: .color))
            var material = SimpleMaterial()
            material.color = .init(texture: .init(texture))
            material.metallic = 0.0
            material.roughness = 1.0
            entity.model?.materials = [material]
            print("DEBUG: AR texture updated successfully")
        } catch {
            print("DEBUG: Failed to generate AR texture: \(error)")
        }
    }
}