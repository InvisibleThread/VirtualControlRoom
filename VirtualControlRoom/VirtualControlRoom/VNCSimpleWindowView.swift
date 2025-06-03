import SwiftUI

struct VNCSimpleWindowView: View {
    @ObservedObject var vncClient: RoyalVNCClient
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // VNC Display
            if let framebuffer = vncClient.framebuffer {
                Image(uiImage: UIImage(cgImage: framebuffer))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            } else {
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding()
                    Text("Waiting for VNC content...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.9))
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .frame(idealWidth: 1200, idealHeight: 800)
        .navigationTitle("VNC Display")
        .onDisappear {
            vncClient.disconnect()
        }
    }
}