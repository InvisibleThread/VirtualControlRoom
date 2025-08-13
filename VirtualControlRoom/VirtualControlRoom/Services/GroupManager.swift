import Foundation
import CoreData
import SwiftUI
import Combine

// MARK: - ConnectionGroup Extension for Connection Management
extension ConnectionGroup {
    /// Get connections for this group by looking up profiles by stored IDs
    var connections: [ConnectionProfile] {
        guard let connectionIDsString = self.connectionIDs,
              !connectionIDsString.isEmpty else {
            return []
        }
        
        let uuidStrings = connectionIDsString.components(separatedBy: ",")
        let context = ConnectionProfileManager.shared.viewContext
        
        let request: NSFetchRequest<ConnectionProfile> = ConnectionProfile.fetchRequest()
        let uuids = uuidStrings.compactMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        request.predicate = NSPredicate(format: "id IN %@", uuids)
        
        do {
            let profiles = try context.fetch(request)
            // Return in the same order as stored IDs
            return uuidStrings.compactMap { uuidString in
                profiles.first { $0.id?.uuidString == uuidString.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        } catch {
            print("❌ Failed to fetch connections for group: \(error)")
            return []
        }
    }
    
    /// Set connections for this group by storing their IDs
    func setConnections(_ connections: [ConnectionProfile]) {
        let uuidStrings = connections.compactMap { $0.id?.uuidString }
        self.connectionIDs = uuidStrings.joined(separator: ",")
    }
    
    /// Add a connection to this group
    func addConnection(_ connection: ConnectionProfile) {
        guard connection.id?.uuidString != nil else { return }
        
        var currentConnections = self.connections
        if !currentConnections.contains(connection) {
            currentConnections.append(connection)
            setConnections(currentConnections)
        }
    }
    
    /// Remove a connection from this group
    func removeConnection(_ connection: ConnectionProfile) {
        let currentConnections = self.connections.filter { $0 != connection }
        setConnections(currentConnections)
    }
}

/// Manages connection groups and their relationships with connection profiles
@MainActor
class GroupManager: ObservableObject {
    static let shared = GroupManager()
    
    @Published var groups: [ConnectionGroup] = []
    var context: NSManagedObjectContext
    
    private init() {
        self.context = ConnectionProfileManager.shared.viewContext
        loadGroups()
    }
    
    // MARK: - CRUD Operations
    
    /// Create a new connection group
    func createGroup(name: String, connections: [ConnectionProfile] = []) -> ConnectionGroup {
        let group = ConnectionGroup(context: context)
        group.id = UUID()
        group.name = name
        group.createdAt = Date()
        group.updatedAt = Date()
        group.layoutType = "auto"
        
        // Add connections to the group
        group.setConnections(connections)
        
        saveContext()
        loadGroups()
        
        print("✅ Created group '\(name)' with \(connections.count) connections")
        return group
    }
    
    /// Update an existing group
    func updateGroup(_ group: ConnectionGroup, name: String? = nil, layoutType: String? = nil) {
        if let name = name {
            group.name = name
        }
        if let layoutType = layoutType {
            group.layoutType = layoutType
        }
        group.updatedAt = Date()
        
        saveContext()
        loadGroups()
        
        print("✅ Updated group '\(group.name ?? "Unknown")'")
    }
    
    /// Delete a connection group
    func deleteGroup(_ group: ConnectionGroup) {
        let groupName = group.name ?? "Unknown"
        context.delete(group)
        saveContext()
        loadGroups()
        
        print("✅ Deleted group '\(groupName)'")
    }
    
    /// Duplicate a connection group
    func duplicateGroup(_ group: ConnectionGroup) -> ConnectionGroup {
        let originalName = group.name ?? "Untitled"
        let newName = "\(originalName) Copy"
        
        // Get connections from the original group
        let connections = group.connections
        return createGroup(name: newName, connections: connections)
    }
    
    // MARK: - Connection Management
    
    /// Add a connection to a group
    func addConnection(_ connection: ConnectionProfile, to group: ConnectionGroup) {
        group.addConnection(connection)
        group.updatedAt = Date()
        
        saveContext()
        loadGroups()
        
        print("✅ Added connection '\(connection.name ?? "Unknown")' to group '\(group.name ?? "Unknown")'")
    }
    
    /// Remove a connection from a group
    func removeConnection(_ connection: ConnectionProfile, from group: ConnectionGroup) {
        group.removeConnection(connection)
        group.updatedAt = Date()
        
        saveContext()
        loadGroups()
        
        print("✅ Removed connection '\(connection.name ?? "Unknown")' from group '\(group.name ?? "Unknown")'")
    }
    
    /// Reorder connections within a group
    func reorderConnections(in group: ConnectionGroup, from source: IndexSet, to destination: Int) {
        var connections = group.connections
        connections.move(fromOffsets: source, toOffset: destination)
        
        group.setConnections(connections)
        group.updatedAt = Date()
        
        saveContext()
        loadGroups()
        
        print("✅ Reordered connections in group '\(group.name ?? "Unknown")'")
    }
    
    // MARK: - OTP Detection
    
    /// Check if a group requires shared OTP
    func requiresSharedOTP(_ group: ConnectionGroup) -> Bool {
        let connections = group.connections
        
        // Check if any connections use SSH (indicating potential OTP requirement)
        let sshHosts = Set(connections.compactMap { $0.sshHost?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        
        // If there are SSH connections, they may require OTP authentication
        // Note: Single connections can also require OTP for multi-factor authentication
        return sshHosts.count > 0
    }
    
    /// Get the SSH configuration for shared OTP
    func getSharedSSHConfig(_ group: ConnectionGroup) -> SSHConnectionConfig? {
        let connections = group.connections
        
        // Find the first connection with SSH configuration
        guard let sshConnection = connections.first(where: { 
            ($0.sshHost?.isEmpty == false) && ($0.sshUsername?.isEmpty == false) 
        }) else {
            return nil
        }
        
        return SSHConnectionConfig(
            host: sshConnection.sshHost!,
            port: Int(sshConnection.sshPort),
            username: sshConnection.sshUsername!,
            authMethod: .password(""), // Password will be filled in later
            connectTimeout: 15.0
        )
    }
    
    // MARK: - Group Analysis
    
    /// Get the recommended layout type for a group based on connection count
    func getRecommendedLayout(for group: ConnectionGroup) -> String {
        let connections = group.connections
        let count = connections.count
        
        switch count {
        case 0:
            return "empty"
        case 1:
            return "1x1"
        case 2:
            return "2x1"
        case 3:
            return "3x1"
        case 4:
            return "2x2"
        case 5, 6:
            return "3x2"
        case 7, 8, 9:
            return "3x3"
        default:
            return "grid"
        }
    }
    
    /// Get groups that contain a specific connection
    func getGroups(containing connection: ConnectionProfile) -> [ConnectionGroup] {
        return groups.filter { group in
            let connections = group.connections
            return connections.contains(connection)
        }
    }
    
    /// Get all available connections not in a specific group
    func getAvailableConnections(excluding group: ConnectionGroup? = nil) -> [ConnectionProfile] {
        let request: NSFetchRequest<ConnectionProfile> = ConnectionProfile.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ConnectionProfile.name, ascending: true)]
        
        do {
            let allProfiles = try context.fetch(request)
            
            // If no group to exclude, return all profiles
            guard let excludeGroup = group else {
                return allProfiles
            }
            
            // Filter out connections that are already in the excluded group
            let groupConnections = excludeGroup.connections
            return allProfiles.filter { profile in
                !groupConnections.contains(profile)
            }
        } catch {
            print("❌ Failed to fetch connection profiles: \(error)")
            return []
        }
    }
    
    // MARK: - Group Validation
    
    /// Validate that a group is ready for launch
    func validateGroupForLaunch(_ group: ConnectionGroup) -> (isValid: Bool, issues: [String]) {
        var issues: [String] = []
        
        if group.name?.isEmpty ?? true {
            issues.append("Group name is required")
        }
        
        let connections = group.connections
        
        if connections.isEmpty {
            issues.append("Group must contain at least one connection")
        }
        
        // Validate each connection
        for connection in connections {
            if connection.host?.isEmpty ?? true {
                issues.append("Connection '\(connection.name ?? "Unknown")' is missing host")
            }
        }
        
        return (isValid: issues.isEmpty, issues: issues)
    }
    
    // MARK: - Private Methods
    
    private func loadGroups() {
        let request: NSFetchRequest<ConnectionGroup> = ConnectionGroup.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \ConnectionGroup.lastUsedAt, ascending: false),
            NSSortDescriptor(keyPath: \ConnectionGroup.createdAt, ascending: false)
        ]
        
        do {
            let allGroups = try context.fetch(request)
            
            // Clean up invalid groups (empty names or duplicates)
            var groupsToDelete: [ConnectionGroup] = []
            for group in allGroups {
                if group.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                    groupsToDelete.append(group)
                }
            }
            
            // Delete invalid groups
            for group in groupsToDelete {
                context.delete(group)
                print("🧹 Cleaned up invalid group: '\(group.name ?? "nil")'")
            }
            
            if !groupsToDelete.isEmpty {
                try context.save()
            }
            
            // Reload after cleanup
            groups = try context.fetch(request).filter { 
                !(($0.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ?? true)
            }
            
            print("📋 Loaded \(groups.count) connection groups")
        } catch {
            print("❌ Failed to load groups: \(error)")
            groups = []
        }
    }
    
    private func saveContext() {
        do {
            try context.save()
        } catch {
            print("❌ Failed to save groups context: \(error)")
        }
    }
}

// MARK: - Extensions for Array manipulation

extension Array {
    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let elementsToMove = source.compactMap { self.indices.contains($0) ? self[$0] : nil }
        
        // Remove elements from their original positions (in reverse order to maintain indices)
        for index in source.sorted(by: >) {
            if self.indices.contains(index) {
                self.remove(at: index)
            }
        }
        
        // Insert elements at the destination
        let adjustedDestination = destination - source.filter { $0 < destination }.count
        for (offset, element) in elementsToMove.enumerated() {
            self.insert(element, at: adjustedDestination + offset)
        }
    }
}