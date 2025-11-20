//
//  DeviceIdentifierService.swift
//  VM
//
//  Created by Sean Kelly on 20/11/2025.
//

import Foundation
import Security

/// Service for managing a persistent device identifier stored in Keychain
/// This identifier persists across app deletions and reinstalls
class DeviceIdentifierService {
    static let shared = DeviceIdentifierService()
    
    private let service = "com.yourcompany.vm.deviceid"
    private let account = "device-identifier"
    
    private init() {}
    
    /// Gets or creates a unique device identifier
    /// This identifier persists in the Keychain even after app deletion
    var deviceIdentifier: String {
        // Try to retrieve existing identifier
        if let existingID = retrieveFromKeychain() {
            return existingID
        }
        
        // Generate new identifier and save it
        let newID = UUID().uuidString
        saveToKeychain(newID)
        return newID
    }
    
    /// Gets a short version of the device identifier (first 8 characters)
    var shortDeviceIdentifier: String {
        String(deviceIdentifier.prefix(8))
    }
    
    // MARK: - Keychain Operations
    
    private func saveToKeychain(_ identifier: String) {
        guard let data = identifier.data(using: .utf8) else { return }
        
        // Delete any existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecSuccess {
            print("✅ Device identifier saved to Keychain")
        } else {
            print("❌ Failed to save device identifier: \(status)")
        }
    }
    
    private func retrieveFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let identifier = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return identifier
    }
    
    /// For debugging: delete the stored device identifier
    func resetDeviceIdentifier() {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        print("⚠️ Device identifier reset")
    }
}
