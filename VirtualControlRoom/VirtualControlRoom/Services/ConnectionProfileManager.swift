import CoreData
import SwiftUI

class ConnectionProfileManager: ObservableObject {
    static let shared = ConnectionProfileManager()
    
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "VirtualControlRoom")
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Failed to load Core Data stack: \(error)")
            }
        }
        return container
    }()
    
    var viewContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }
    
    private init() {}
    
    func saveContext() {
        if viewContext.hasChanges {
            do {
                try viewContext.save()
            } catch {
                print("Failed to save context: \(error)")
            }
        }
    }
    
    func createProfile(name: String, host: String, port: Int32, username: String?,
                      sshHost: String?, sshPort: Int32?, sshUsername: String?) -> ConnectionProfile {
        let profile = ConnectionProfile(context: viewContext)
        profile.id = UUID()
        profile.name = name
        profile.host = host
        profile.port = port
        profile.username = username
        profile.sshHost = sshHost
        profile.sshPort = sshPort ?? 22
        profile.sshUsername = sshUsername
        profile.createdAt = Date()
        profile.updatedAt = Date()
        
        saveContext()
        return profile
    }
    
    func updateProfile(_ profile: ConnectionProfile) {
        profile.updatedAt = Date()
        saveContext()
    }
    
    func deleteProfile(_ profile: ConnectionProfile) {
        viewContext.delete(profile)
        saveContext()
    }
    
    func markProfileAsUsed(_ profile: ConnectionProfile) {
        profile.lastUsedAt = Date()
        saveContext()
    }
}

extension ConnectionProfile {
    var displayName: String {
        name ?? "Unnamed Connection"
    }
    
    var displayHost: String {
        if let sshHost = sshHost, !sshHost.isEmpty {
            return "\(sshHost) → \(host ?? "unknown")"
        }
        return host ?? "unknown"
    }
    
    var formattedLastUsed: String {
        guard let lastUsed = lastUsedAt else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastUsed, relativeTo: Date())
    }
}