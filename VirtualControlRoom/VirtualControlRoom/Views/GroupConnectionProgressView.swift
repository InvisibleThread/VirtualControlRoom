import SwiftUI

/// Progress view shown while group connections are being established
struct GroupConnectionProgressView: View {
    let groupName: String
    let connectionProfiles: [ConnectionProfile]
    @EnvironmentObject var groupOTPManager: GroupOTPManager
    @Environment(\.dismiss) private var dismiss
    
    private var connectingCount: Int {
        connectionProfiles.count { profile in
            if let id = profile.id?.uuidString,
               let state = groupOTPManager.connectionStates[id] {
                return state == .connecting || state == .preparing
            }
            return false
        }
    }
    
    private var connectedCount: Int {
        connectionProfiles.count { profile in
            if let id = profile.id?.uuidString,
               let state = groupOTPManager.connectionStates[id] {
                return state == .connected
            }
            return false
        }
    }
    
    private var failedCount: Int {
        connectionProfiles.count { profile in
            if let id = profile.id?.uuidString,
               case .failed = groupOTPManager.connectionStates[id] {
                return true
            }
            return false
        }
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                    .symbolEffect(.pulse, isActive: connectingCount > 0)
                
                Text("Connecting to \(groupName)")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("\(connectedCount) of \(connectionProfiles.count) connections established")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            // Connection list with status
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(connectionProfiles, id: \.id) { profile in
                        ConnectionProgressRow(
                            profile: profile,
                            state: profile.id.flatMap { groupOTPManager.connectionStates[$0.uuidString] }
                        )
                    }
                }
                .padding(.horizontal)
            }
            .frame(maxHeight: 300)
            
            // Progress summary
            HStack(spacing: 20) {
                ProgressSummaryItem(
                    icon: "checkmark.circle.fill",
                    count: connectedCount,
                    label: "Connected",
                    color: .green
                )
                
                ProgressSummaryItem(
                    icon: "arrow.triangle.2.circlepath",
                    count: connectingCount,
                    label: "Connecting",
                    color: .orange
                )
                
                ProgressSummaryItem(
                    icon: "exclamationmark.circle.fill",
                    count: failedCount,
                    label: "Failed",
                    color: .red
                )
            }
            .padding(.horizontal)
            
            // Cancel button
            Button(action: {
                Task {
                    await groupOTPManager.cancelGroupLaunch()
                    dismiss()
                }
            }) {
                Text("Cancel")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(groupOTPManager.groupLaunchState == .completed(.allSucceeded))
        }
        .padding(24)
        .frame(width: 500)
        .background(.regularMaterial)
    }
}

/// Individual connection progress row
struct ConnectionProgressRow: View {
    let profile: ConnectionProfile
    let state: GroupConnectionState?
    
    private var stateIcon: String {
        switch state {
        case .preparing:
            return "clock"
        case .connecting:
            return "arrow.triangle.2.circlepath"
        case .connected:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.circle.fill"
        case nil:
            return "circle"
        }
    }
    
    private var stateColor: Color {
        switch state {
        case .preparing:
            return .secondary
        case .connecting:
            return .orange
        case .connected:
            return .green
        case .failed:
            return .red
        case nil:
            return .secondary
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            Image(systemName: stateIcon)
                .font(.title3)
                .foregroundStyle(stateColor)
                .symbolEffect(.pulse, isActive: state == .connecting)
                .frame(width: 24)
            
            // Connection info
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                
                HStack(spacing: 4) {
                    if let sshHost = profile.sshHost, !sshHost.isEmpty {
                        Label("SSH", systemImage: "lock.shield")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text("\(profile.host ?? ""):\(profile.port)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospaced()
                }
            }
            
            Spacer()
            
            // State text
            if let state = state {
                Text(state.displayText)
                    .font(.caption)
                    .foregroundStyle(stateColor)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Progress summary item
struct ProgressSummaryItem: View {
    let icon: String
    let count: Int
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            
            Text("\(count)")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Value type for group progress window
struct GroupProgressValue: Hashable, Codable {
    let groupID: String
    let groupName: String
    let connectionIDs: [String]
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(groupID)
        hasher.combine(connectionIDs)
    }
    
    static func == (lhs: GroupProgressValue, rhs: GroupProgressValue) -> Bool {
        return lhs.groupID == rhs.groupID && lhs.connectionIDs == rhs.connectionIDs
    }
    
    /// Fetch connection profiles from Core Data
    func getConnectionProfiles() -> [ConnectionProfile] {
        let context = ConnectionProfileManager.shared.viewContext
        let request = ConnectionProfile.fetchRequest()
        let connectionUUIDs = connectionIDs.compactMap { UUID(uuidString: $0) }
        request.predicate = NSPredicate(format: "id IN %@", connectionUUIDs)
        
        do {
            let profiles = try context.fetch(request)
            // Sort profiles to match the order in connectionIDs
            return connectionIDs.compactMap { connectionID in
                profiles.first { $0.id?.uuidString == connectionID }
            }
        } catch {
            print("❌ Failed to fetch connection profiles: \(error)")
            return []
        }
    }
}

#Preview("Group Connection Progress") {
    // Create sample profiles
    let sampleProfiles = (1...5).map { i in
        let profile = ConnectionProfile(context: ConnectionProfileManager.shared.viewContext)
        profile.id = UUID()
        profile.name = "Server \(i)"
        profile.host = "192.168.1.\(i)"
        profile.port = 5900
        profile.sshHost = i <= 3 ? "ssh.example.com" : nil
        return profile
    }
    
    return GroupConnectionProgressView(
        groupName: "Production Servers",
        connectionProfiles: sampleProfiles
    )
    .environmentObject(GroupOTPManager.shared)
    .frame(width: 500, height: 600)
}