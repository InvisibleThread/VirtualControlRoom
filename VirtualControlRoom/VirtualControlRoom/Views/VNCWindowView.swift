import SwiftUI

struct VNCWindowView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @State private var selectedConnectionID: UUID?
    
    // Find the active VNC client to display
    private var activeVNCClient: (UUID, LibVNCClient)? {
        // If user has selected a specific connection, try to use that
        if let selected = selectedConnectionID,
           connectionManager.activeConnections.contains(selected) {
            let client = connectionManager.getVNCClient(for: selected)
            let lifecycleState = connectionManager.getLifecycleState(for: selected)
            if case .connected = client.connectionState, 
               lifecycleState == .connected || lifecycleState == .windowOpen {
                return (selected, client)
            }
        }
        
        // Otherwise, find the most recently connected client that's ready for display
        let sortedConnections = connectionManager.activeConnections.sorted { id1, id2 in
            let client1 = connectionManager.getVNCClient(for: id1)
            let client2 = connectionManager.getVNCClient(for: id2)
            let state1 = connectionManager.getLifecycleState(for: id1)
            let state2 = connectionManager.getLifecycleState(for: id2)
            
            // Prioritize windowOpen over connected, connected over connecting
            let priority1 = state1 == .windowOpen ? 3 : (state1 == .connected ? 2 : 1)
            let priority2 = state2 == .windowOpen ? 3 : (state2 == .connected ? 2 : 1)
            
            if priority1 != priority2 {
                return priority1 > priority2
            }
            
            return id1.uuidString < id2.uuidString // Fallback to string comparison
        }
        
        for connectionID in sortedConnections {
            let client = connectionManager.getVNCClient(for: connectionID)
            let lifecycleState = connectionManager.getLifecycleState(for: connectionID)
            
            // Show any connection that's connected and ready for display
            if case .connected = client.connectionState,
               lifecycleState == .connected || lifecycleState == .windowOpen {
                return (connectionID, client)
            }
        }
        
        return nil
    }
    
    var body: some View {
        Group {
            if let (connectionID, vncClient) = activeVNCClient {
                VStack {
                    // Connection selector if multiple connections exist
                    if connectionManager.activeConnections.count > 1 {
                        HStack {
                            Text("Active Connection:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Menu {
                                ForEach(Array(connectionManager.activeConnections).sorted(by: { $0.uuidString < $1.uuidString }), id: \.self) { id in
                                    Button("Connection \(id.uuidString.prefix(8))") {
                                        selectedConnectionID = id
                                    }
                                }
                            } label: {
                                Text("Connection \(connectionID.uuidString.prefix(8))")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(6)
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, 32) // Increased to avoid corner radius cropping
                        .padding(.top, 12)        // Slightly increased top padding
                    }
                    
                    VNCSimpleWindowView(vncClient: vncClient)
                        .id(connectionID) // This ensures the view updates when connection changes
                }
            } else {
                // No active connections - show placeholder
                VStack {
                    Image(systemName: "network.slash")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                    
                    Text("No Active VNC Connection")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("This window will show your VNC connection once established")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32) // Increased to avoid corner radius cropping
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onAppear {
            print("🪟 VNCWindowView appeared - active connections: \(connectionManager.activeConnections.count)")
            // Notify connection manager that window opened for the active connection
            if let (connectionID, _) = activeVNCClient {
                print("🪟 VNCWindowView: Notifying window opened for connection \(connectionID)")
                connectionManager.windowDidOpen(for: connectionID)
            } else {
                print("🪟 VNCWindowView: No active VNC client found")
                // Give a moment for the connection state to update, then check again
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let (connectionID, _) = self.activeVNCClient {
                        print("🪟 VNCWindowView: Found delayed connection \(connectionID)")
                        connectionManager.windowDidOpen(for: connectionID)
                    }
                }
            }
        }
        .onDisappear {
            // When window is closed, notify connection manager
            if let (connectionID, _) = activeVNCClient {
                print("🪟 VNCWindowView closing - notifying connection manager")
                connectionManager.windowDidClose(for: connectionID)
            }
        }
    }
}