//
//  UploadLimitManager.swift
//  VM
//
//  Created by Sean Kelly on 20/11/2025.
//

import Foundation
import Security
import Combine

/// Manager for tracking upload limits using Keychain for persistence
@MainActor
final class UploadLimitManager: ObservableObject {
    static let shared = UploadLimitManager()
    
    // MARK: - Published Properties
    
    @Published private(set) var uploadCount: Int = 0
    @Published var hasReachedLimit: Bool = false
    
    // MARK: - Constants
    
    private let freeUploadLimit = 5
    private let keychainService = "com.videolink.upload-count3"
    private let keychainAccount = "upload-counter3"
    
    // MARK: - Computed Properties
    
    var remainingUploads: Int {
        max(0, freeUploadLimit - uploadCount)
    }
    
    var canUpload: Bool {
        // Check if user is subscribed
        if StoreKitManager.shared.subscriptionStatus.isActive {
            return true
        }
        
        // Check if within free limit
        return uploadCount < freeUploadLimit
    }
    
    // MARK: - Initialization
    
    private init() {
        loadUploadCount()
        updateLimitStatus()
    }
    
    // MARK: - Upload Tracking
    
    /// Increment upload count (call this when user successfully uploads a video)
    func incrementUploadCount() {
        uploadCount += 1
        saveUploadCount()
        updateLimitStatus()
        
        print("📊 Upload count incremented to \(uploadCount)/\(freeUploadLimit)")
    }
    
    /// Reset upload count (for testing or admin purposes)
    func resetUploadCount() {
        uploadCount = 0
        saveUploadCount()
        updateLimitStatus()
        
        print("🔄 Upload count reset to 0")
    }
    
    /// Update the limit status
    private func updateLimitStatus() {
        // If user is subscribed, they never hit the limit
        if StoreKitManager.shared.subscriptionStatus.isActive {
            hasReachedLimit = false
        } else {
            hasReachedLimit = uploadCount >= freeUploadLimit
        }
    }
    
    // MARK: - Keychain Operations
    
    /// Save upload count to Keychain
    private func saveUploadCount() {
        let data = Data("\(uploadCount)".utf8)
        
        // Create query
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data
        ]
        
        // Delete any existing item
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            print("✅ Upload count saved to Keychain")
        } else {
            print("❌ Failed to save upload count to Keychain: \(status)")
        }
    }
    
    /// Load upload count from Keychain
    private func loadUploadCount() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess {
            if let data = result as? Data,
               let countString = String(data: data, encoding: .utf8),
               let count = Int(countString) {
                uploadCount = count
                print("✅ Upload count loaded from Keychain: \(count)")
            }
        } else if status == errSecItemNotFound {
            // First launch, initialize to 0
            uploadCount = 0
            saveUploadCount()
            print("ℹ️ No upload count found, initialized to 0")
        } else {
            print("❌ Failed to load upload count from Keychain: \(status)")
            uploadCount = 0
        }
    }
}
