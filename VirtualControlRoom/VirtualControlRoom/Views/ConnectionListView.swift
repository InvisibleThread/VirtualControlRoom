import SwiftUI
import CoreData

struct ConnectionListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \ConnectionProfile.lastUsedAt, ascending: false),
            NSSortDescriptor(keyPath: \ConnectionProfile.name, ascending: true)
        ],
        animation: .default
    )
    private var connections: FetchedResults<ConnectionProfile>
    
    @State private var showingAddConnection = false
    @State private var selectedConnection: ConnectionProfile?
    @State private var showingEditConnection = false
    
    var body: some View {
        NavigationStack {
            Group {
                if connections.isEmpty {
                    emptyStateView
                } else {
                    connectionsList
                }
            }
            .navigationTitle("Connections")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddConnection = true
                    } label: {
                        Label("Add Connection", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddConnection) {
                NavigationStack {
                    ConnectionEditView(connection: nil)
                }
            }
            .sheet(item: $selectedConnection) { connection in
                NavigationStack {
                    ConnectionEditView(connection: connection)
                }
            }
            .alert("Connection Info", isPresented: $showingConnectionAlert) {
                Button("OK") { }
            } message: {
                Text(connectionAlertMessage)
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "network")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("No Connections")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Add a VNC connection to get started")
                .foregroundStyle(.secondary)
            
            Button {
                showingAddConnection = true
            } label: {
                Label("Add Connection", systemImage: "plus")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    private var connectionsList: some View {
        List {
            ForEach(connections) { connection in
                ConnectionRowView(connection: connection) {
                    // Connect action
                    connectToProfile(connection)
                } onEdit: {
                    // Edit action
                    selectedConnection = connection
                } onDelete: {
                    // Delete action
                    deleteConnection(connection)
                }
            }
        }
        .listStyle(.plain)
    }
    
    @State private var showingConnectionAlert = false
    @State private var connectionAlertMessage = ""
    
    private func connectToProfile(_ profile: ConnectionProfile) {
        ConnectionProfileManager.shared.markProfileAsUsed(profile)
        
        // TODO: Implement connection logic in Sprint 2
        // For now, show what will happen
        var message = "Connection Details:\n"
        message += "Host: \(profile.host ?? "unknown"):\(profile.port)\n"
        
        if let username = profile.username {
            message += "Username: \(username)\n"
        }
        
        if profile.savePassword, let hint = profile.passwordHint {
            message += "Password Hint: \(hint)\n"
        } else {
            message += "Password: Will be requested when connecting\n"
        }
        
        if profile.sshHost != nil {
            message += "\nSSH Tunnel:\n"
            message += "SSH Host: \(profile.sshHost ?? ""):\(profile.sshPort)\n"
            message += "SSH User: \(profile.sshUsername ?? "")\n"
        }
        
        message += "\n(Connection functionality coming in Sprint 2)"
        
        connectionAlertMessage = message
        showingConnectionAlert = true
    }
    
    private func deleteConnection(_ connection: ConnectionProfile) {
        withAnimation {
            ConnectionProfileManager.shared.deleteProfile(connection)
        }
    }
}

struct ConnectionRowView: View {
    let connection: ConnectionProfile
    let onConnect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(connection.displayName)
                        .font(.headline)
                    
                    if connection.sshHost != nil {
                        Image(systemName: "lock.shield")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Text(connection.displayHost)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Text("Last used: \(connection.formattedLastUsed)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button {
                    onConnect()
                } label: {
                    Label("Connect", systemImage: "play.fill")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderedProminent)
                
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                
                Button {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(.vertical, 4)
        .confirmationDialog("Delete Connection?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete \(connection.displayName)?")
        }
    }
}

#Preview {
    ConnectionListView()
        .environment(\.managedObjectContext, ConnectionProfileManager.shared.viewContext)
}