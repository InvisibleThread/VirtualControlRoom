import SwiftUI

/// Single 2D window containing a grid of VNC connections for a group
struct GroupGridWindow: View {
    let groupGridValue: GroupGridValue
    @EnvironmentObject var connectionManager: ConnectionManager
    @StateObject private var gridLayoutManager = GridLayoutManager.shared
    
    private var connectionProfiles: [ConnectionProfile] {
        let context = ConnectionProfileManager.shared.viewContext
        let request = ConnectionProfile.fetchRequest()
        let connectionUUIDs = groupGridValue.connectionIDs.compactMap { UUID(uuidString: $0) }
        request.predicate = NSPredicate(format: "id IN %@", connectionUUIDs)
        
        do {
            let profiles = try context.fetch(request)
            // Sort profiles to match the order in connectionIDs
            return groupGridValue.connectionIDs.compactMap { connectionID in
                profiles.first { $0.id?.uuidString == connectionID }
            }
        } catch {
            print("❌ Failed to fetch connection profiles: \(error)")
            return []
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Grid header
            GroupGridHeader(
                groupName: groupGridValue.groupName,
                connectionCount: connectionProfiles.count,
                layoutType: groupGridValue.layoutType
            )
            
            // VNC grid content
            if connectionProfiles.isEmpty {
                emptyStateView
            } else {
                gridContentView
            }
        }
        .background(Color(.systemBackground))
        .onAppear {
            print("🏗️ GroupGridWindow appeared for group \(groupGridValue.groupID)")
        }
        .onDisappear {
            print("🏗️ GroupGridWindow disappeared for group \(groupGridValue.groupID)")
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("No Connections")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Group connections are not available")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
    
    private var gridContentView: some View {
        let (rows, columns) = gridLayoutManager.getGridDimensions(from: groupGridValue.layoutType)
        let positions = gridLayoutManager.calculateGridPositions(
            layoutType: groupGridValue.layoutType, 
            connectionCount: connectionProfiles.count
        )
        
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            ForEach(Array(connectionProfiles.enumerated()), id: \.element.id) { index, profile in
                let position = positions[safe: index]
                
                GroupGridCell(
                    connectionProfile: profile,
                    gridPosition: position,
                    connectionManager: connectionManager
                )
                .aspectRatio(4/3, contentMode: .fit) // Standard VNC aspect ratio
            }
        }
        .padding(12)
    }
}

/// Header view for the group grid window
struct GroupGridHeader: View {
    let groupName: String
    let connectionCount: Int
    let layoutType: String
    
    var body: some View {
        HStack {
            // Group info
            HStack(spacing: 8) {
                Image(systemName: "rectangle.3.group")
                    .foregroundStyle(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(groupName)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("\(connectionCount) connections • \(layoutType) layout")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Layout indicator
            Text(layoutType)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.regularMaterial)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(.separator),
            alignment: .bottom
        )
    }
}

/// Individual cell in the group grid containing a VNC connection
struct GroupGridCell: View {
    let connectionProfile: ConnectionProfile
    let gridPosition: GridPosition?
    let connectionManager: ConnectionManager
    
    private var vncClient: LibVNCClient? {
        guard let profileID = connectionProfile.id else { return nil }
        return connectionManager.getVNCClient(for: profileID)
    }
    
    private var connectionState: VNCConnectionState {
        guard let profileID = connectionProfile.id else { return .disconnected }
        return connectionManager.getConnectionState(for: profileID)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Cell header with connection info
            HStack {
                // Connection status indicator
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                
                Text(connectionProfile.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Spacer()
                
                // Grid position indicator
                if let position = gridPosition {
                    Text("[\(position.row + 1),\(position.column + 1)]")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospaced()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            
            // VNC content
            Group {
                if let client = vncClient {
                    VNCSimpleWindowView(vncClient: client)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    connectionPlaceholder
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(.separator, lineWidth: 1)
            )
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            if let profileID = connectionProfile.id {
                connectionManager.windowDidOpen(for: profileID)
            }
        }
        .onDisappear {
            if let profileID = connectionProfile.id {
                connectionManager.windowDidClose(for: profileID)
            }
        }
    }
    
    private var statusColor: Color {
        switch connectionState {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .failed:
            return .red
        case .disconnected:
            return .secondary
        }
    }
    
    private var connectionPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: connectionState == .connecting ? "arrow.triangle.2.circlepath" : "network.slash")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse, isActive: connectionState == .connecting)
            
            Text(connectionState.displayText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGray6))
    }
}

/// Value type for group grid windows
struct GroupGridValue: Hashable, Codable {
    let groupID: String
    let groupName: String
    let connectionIDs: [String]
    let layoutType: String
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(groupID)
        hasher.combine(groupName)
        hasher.combine(connectionIDs)
        hasher.combine(layoutType)
    }
    
    static func == (lhs: GroupGridValue, rhs: GroupGridValue) -> Bool {
        return lhs.groupID == rhs.groupID &&
               lhs.groupName == rhs.groupName &&
               lhs.connectionIDs == rhs.connectionIDs &&
               lhs.layoutType == rhs.layoutType
    }
}

// Helper extension for safe array access
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

#Preview("Group Grid Window") {
    let sampleValue = GroupGridValue(
        groupID: "sample-group",
        groupName: "Development Servers",
        connectionIDs: ["conn-1", "conn-2", "conn-3", "conn-4"],
        layoutType: "2x2"
    )
    
    return GroupGridWindow(groupGridValue: sampleValue)
        .environmentObject(ConnectionManager.shared)
        .frame(width: 1200, height: 800)
}

#Preview("Group Grid Header") {
    GroupGridHeader(
        groupName: "Production Servers",
        connectionCount: 6,
        layoutType: "3x2"
    )
}