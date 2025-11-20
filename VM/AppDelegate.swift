//
//  AppDelegate.swift
//  VM
//
//  Created by Sean Kelly on 20/11/2025.
//

import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        
        // Initialize StoreKit manager to start listening for transactions
        let _ = StoreKitManager.shared
        
        // Initialize upload limit manager to load count from Keychain
        let _ = UploadLimitManager.shared
        
        print("✅ App initialized with subscription support")
        
        return true
    }
}
