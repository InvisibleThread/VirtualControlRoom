import SwiftUI

struct VNCConnectionWindowView: View {
    let connectionID: UUID
    @EnvironmentObject var connectionManager: ConnectionManager
    
    // Get the specific VNC client for this connection
    private var vncClient: LibVNCClient? {
        // Only return client if it exists and has a valid connection
        if connectionManager.activeConnections.contains(connectionID) ||
           connectionManager.getLifecycleState(for: connectionID) != .idle {
            return connectionManager.getVNCClient(for: connectionID)
        }
        return nil
    }
    
    var body: some View {
        Group {
            if let client = vncClient {
                VStack {
                    // Connection header with ID for identification
                    HStack {
                        Text("Connection: \(connectionID.uuidString.prefix(8))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        // Show connection state
                        switch client.connectionState {
                        case .connecting:
                            Label("Connecting", systemImage: "arrow.triangle.2.circlepath")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        case .connected:
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        case .disconnected:
                            Label("Disconnected", systemImage: "xmark.circle")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        case .failed(let error):
                            Label("Failed", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    // The actual VNC display
                    VNCSimpleWindowView(vncClient: client)
                        .onAppear {
                            print("🪟 VNCConnectionWindowView appeared for connection \(connectionID)")
                            // Notify both the client and connection manager
                            client.windowDidOpen()
                            connectionManager.windowDidOpen(for: connectionID)
                        }
                        .onDisappear {
                            print("🪟 VNCConnectionWindowView disappeared for connection \(connectionID)")
                            // Notify both the client and connection manager if they still exist
                            if connectionManager.hasClient(for: connectionID) {
                                let currentClient = connectionManager.getVNCClient(for: connectionID)
                                currentClient.windowDidClose()
                            }
                            connectionManager.windowDidClose(for: connectionID)
                        }
                }
            } else {
                // No client found for this connection ID
                VStack {
                    Image(systemName: "network.slash")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                    
                    Text("Connection Not Found")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Connection \(connectionID.uuidString.prefix(8)) is no longer available")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .navigationTitle("VNC Connection")
    }
}

#Preview {
    VNCConnectionWindowView(connectionID: UUID())
        .environmentObject(ConnectionManager.shared)
}