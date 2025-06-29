import Foundation
import Security

class KeychainManager {
    static let shared = KeychainManager()
    
    private init() {}
    
    private let service = "com.virtualcontrolroom.passwords"
    
    // Store password for a connection profile
    func storePassword(_ password: String, for profileID: UUID) -> Bool {
        let account = profileID.uuidString
        
        // Delete any existing password first
        deletePassword(for: profileID)
        
        guard let passwordData = password.data(using: .utf8) else {
            print("❌ Keychain: Failed to convert password to data")
            return false
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: passwordData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            print("✅ Keychain: Password stored successfully for profile \(account)")
            return true
        } else {
            print("❌ Keychain: Failed to store password. Status: \(status)")
            return false
        }
    }
    
    // Retrieve password for a connection profile
    func retrievePassword(for profileID: UUID) -> String? {
        let account = profileID.uuidString
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess {
            if let passwordData = result as? Data,
               let password = String(data: passwordData, encoding: .utf8) {
                print("✅ Keychain: Password retrieved successfully for profile \(account)")
                return password
            } else {
                print("❌ Keychain: Failed to convert retrieved data to string")
                return nil
            }
        } else if status == errSecItemNotFound {
            print("📝 Keychain: No password found for profile \(account)")
            return nil
        } else {
            print("❌ Keychain: Failed to retrieve password. Status: \(status)")
            return nil
        }
    }
    
    // Delete password for a connection profile
    func deletePassword(for profileID: UUID) -> Bool {
        let account = profileID.uuidString
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status == errSecSuccess || status == errSecItemNotFound {
            print("✅ Keychain: Password deleted successfully for profile \(account)")
            return true
        } else {
            print("❌ Keychain: Failed to delete password. Status: \(status)")
            return false
        }
    }
}