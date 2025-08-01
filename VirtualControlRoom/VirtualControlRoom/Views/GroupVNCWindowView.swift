import SwiftUI
import RealityKit

/// Individual VNC window view for group connections with grid positioning
struct GroupVNCWindowView: View {
    let groupWindowValue: GroupWindowValue
    @EnvironmentObject var connectionManager: ConnectionManager
    @StateObject private var gridLayoutManager = GridLayoutManager.shared
    
    private var connectionID: UUID? {
        UUID(uuidString: groupWindowValue.connectionID)
    }
    
    private var vncClient: LibVNCClient? {
        guard let id = connectionID else { return nil }
        return connectionManager.getVNCClient(for: id)
    }
    
    private var connectionProfile: ConnectionProfile? {
        guard let id = connectionID else { return nil }
        
        // Fetch the connection profile
        let context = ConnectionProfileManager.shared.viewContext
        let request = ConnectionProfile.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        
        do {
            let profiles = try context.fetch(request)
            return profiles.first
        } catch {
            print("❌ Failed to fetch connection profile: \(error)")
            return nil
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Group window header
            if let profile = connectionProfile {
                GroupWindowHeader(
                    connectionName: profile.displayName,
                    groupPosition: groupWindowValue.gridPosition,
                    isGroupWindow: groupWindowValue.isGroupWindow
                )
            }
            
            // VNC content
            Group {
                if let client = vncClient {
                    VNCSimpleWindowView(vncClient: client)
                        .id(groupWindowValue.connectionID) // Ensure view updates with connection changes
                } else {
                    VStack {
                        Image(systemName: "network.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        
                        Text("Connection Not Available")
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Text("Connection ID: \(groupWindowValue.connectionID.prefix(8))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
                }
            }
        }
        .onAppear {
            guard let id = connectionID else { return }
            
            print("🪟 GroupVNCWindowView appeared for connection \(id) in group \(groupWindowValue.groupID)")
            
            // Notify connection manager that this group window opened
            connectionManager.windowDidOpen(for: id)
            
            // Apply grid positioning if available
            if let gridPosition = groupWindowValue.gridPosition {
                applyGridPositioning(gridPosition)
            }
        }
        .onDisappear {
            guard let id = connectionID else { return }
            
            print("🪟 GroupVNCWindowView disappeared for connection \(id)")
            connectionManager.windowDidClose(for: id)
        }
    }
    
    /// Apply grid positioning to the window (if supported by visionOS)
    private func applyGridPositioning(_ position: GridPosition) {
        print("🏗️ Applying grid position: row \(position.row), col \(position.column), scale \(position.scaleFactor)")
        
        // Note: In visionOS, direct window positioning is limited
        // The positioning information is primarily for layout calculation
        // The actual 3D positioning would be handled by the visionOS window system
        // based on the defaultSize and other window properties
    }
}

/// Header view for group VNC windows showing connection info and position
struct GroupWindowHeader: View {
    let connectionName: String
    let groupPosition: GridPosition?
    let isGroupWindow: Bool
    
    var body: some View {
        HStack {
            // Connection indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(isGroupWindow ? .blue : .green)
                    .frame(width: 8, height: 8)
                
                Text(connectionName)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            
            Spacer()
            
            // Grid position indicator
            if let position = groupPosition {
                HStack(spacing: 2) {
                    Text("[\(position.row + 1),\(position.column + 1)]")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospaced()
                    
                    if position.scaleFactor < 1.0 {
                        Text("\(Int(position.scaleFactor * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.regularMaterial)
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(.separator),
            alignment: .bottom
        )
    }
}

#Preview("Group VNC Window") {
    let sampleValue = GroupWindowValue(
        groupID: "sample-group",
        connectionID: "sample-connection",
        isGroupWindow: true
    )
    
    return GroupVNCWindowView(groupWindowValue: sampleValue)
        .environmentObject(ConnectionManager.shared)
}

#Preview("Group Window Header") {
    let samplePosition = GridPosition(
        index: 0,
        row: 0,
        column: 1,
        position: SIMD3<Float>(0, 0, -2),
        size: CGSize(width: 800, height: 600),
        scaleFactor: 0.65
    )
    
    return GroupWindowHeader(
        connectionName: "Development Server",
        groupPosition: samplePosition,
        isGroupWindow: true
    )
}