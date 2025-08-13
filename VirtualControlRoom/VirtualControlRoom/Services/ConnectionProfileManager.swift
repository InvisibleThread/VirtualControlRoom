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
        // Clean up Keychain entry if it exists
        if let profileID = profile.id {
            let _ = KeychainManager.shared.deletePassword(for: profileID)
        }
        
        viewContext.delete(profile)
        saveContext()
    }
    
    func markProfileAsUsed(_ profile: ConnectionProfile) {
        profile.lastUsedAt = Date()
        saveContext()
    }
    
    func duplicateProfile(_ profile: ConnectionProfile) -> ConnectionProfile {
        let originalName = profile.name ?? "Unnamed Connection"
        let duplicatedName = "\(originalName) Copy"
        
        let duplicateProfile = ConnectionProfile(context: viewContext)
        duplicateProfile.id = UUID()
        duplicateProfile.name = duplicatedName
        duplicateProfile.host = profile.host
        duplicateProfile.port = profile.port
        duplicateProfile.username = profile.username
        duplicateProfile.sshHost = profile.sshHost
        duplicateProfile.sshPort = profile.sshPort
        duplicateProfile.sshUsername = profile.sshUsername
        duplicateProfile.savePassword = profile.savePassword
        duplicateProfile.createdAt = Date()
        duplicateProfile.updatedAt = Date()
        
        // Copy optimization settings
        duplicateProfile.useCustomOptimization = profile.useCustomOptimization
        duplicateProfile.compressionLevel = profile.compressionLevel
        duplicateProfile.jpegQuality = profile.jpegQuality
        duplicateProfile.maxFrameRate = profile.maxFrameRate
        duplicateProfile.pixelFormat = profile.pixelFormat
        duplicateProfile.preferredEncodings = profile.preferredEncodings
        
        // Copy passwords from Keychain if they exist
        if let originalID = profile.id, let newID = duplicateProfile.id {
            // Copy VNC password
            if let vncPassword = KeychainManager.shared.retrievePassword(for: originalID) {
                let _ = KeychainManager.shared.storePassword(vncPassword, for: newID)
            }
            
            // Copy SSH password
            if let sshPassword = KeychainManager.shared.retrieveSSHPassword(for: originalID) {
                let _ = KeychainManager.shared.saveSSHPassword(sshPassword, for: newID)
            }
        }
        
        saveContext()
        return duplicateProfile
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