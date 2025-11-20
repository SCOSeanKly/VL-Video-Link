//
//  VMApp.swift
//  VM
//
//  Created by Sean Kelly on 19/11/2025.
//

import SwiftUI

@main
struct VMApp: App {
    // Connect the AppDelegate to initialize StoreKit
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            SplashScreenView()
                .preferredColorScheme(.light)
        }
    }
}
