//
//  TestingHelpers.swift
//  VM
//
//  Created by Sean Kelly on 20/11/2025.
//  
//  ⚠️ FOR DEVELOPMENT/TESTING ONLY - REMOVE BEFORE PRODUCTION ⚠️
//

import SwiftUI
import StoreKit
// MARK: - Testing View
// Add this view to your app during development to test subscription features

struct SubscriptionTestingView: View {
    @StateObject private var storeManager = StoreKitManager.shared
    @StateObject private var uploadManager = UploadLimitManager.shared
    
    var body: some View {
        NavigationView {
            Form {
                // Subscription Status Section
                Section(header: Text("Subscription Status")) {
                    HStack {
                        Text("Status:")
                        Spacer()
                        StatusBadge(status: storeManager.subscriptionStatus)
                    }
                    
                    if case .subscribed(let expirationDate) = storeManager.subscriptionStatus,
                       let expDate = expirationDate {
                        HStack {
                            Text("Expires:")
                            Spacer()
                            Text(expDate.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Button("Refresh Status") {
                        Task {
                            await storeManager.updateSubscriptionStatus()
                        }
                    }
                }
                
                // Upload Limit Section
                Section(header: Text("Upload Limits")) {
                    HStack {
                        Text("Upload Count:")
                        Spacer()
                        Text("\(uploadManager.uploadCount)")
                            .fontWeight(.bold)
                    }
                    
                    HStack {
                        Text("Remaining Uploads:")
                        Spacer()
                        Text("\(uploadManager.remainingUploads)")
                            .foregroundStyle(uploadManager.remainingUploads <= 2 ? .red : .primary)
                            .fontWeight(.bold)
                    }
                    
                    HStack {
                        Text("Can Upload:")
                        Spacer()
                        Text(uploadManager.canUpload ? "✅" : "❌")
                    }
                    
                    Button("Simulate Upload", role: .destructive) {
                        uploadManager.incrementUploadCount()
                    }
                    .disabled(!uploadManager.canUpload && !storeManager.subscriptionStatus.isActive)
                    
                    Button("Reset Count", role: .destructive) {
                        uploadManager.resetUploadCount()
                    }
                }
                
                // Products Section
                Section(header: Text("Available Products")) {
                    if storeManager.products.isEmpty {
                        if storeManager.isLoading {
                            HStack {
                                ProgressView()
                                Text("Loading products...")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("No products available")
                                .foregroundStyle(.secondary)
                            
                            Button("Reload Products") {
                                Task {
                                    await storeManager.loadProducts()
                                }
                            }
                        }
                    } else {
                        ForEach(storeManager.products, id: \.id) { product in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(product.displayName)
                                    .font(.headline)
                                
                                Text(product.displayPrice)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                // Actions Section
                Section(header: Text("Test Actions")) {
                    Button("Restore Purchases") {
                        Task {
                            await storeManager.restorePurchases()
                        }
                    }
                    .disabled(storeManager.isLoading)
                    
                    Button("Show Manage Subscriptions") {
                        Task {
                            await storeManager.showManageSubscriptions()
                        }
                    }
                    
                    if let error = storeManager.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                
                // Debug Info Section
                Section(header: Text("Debug Information")) {
                    VStack(alignment: .leading, spacing: 8) {
                        InfoRow(label: "Product ID", value: "vl_monthly")
                        InfoRow(label: "Free Limit", value: "5 uploads")
                        InfoRow(label: "Storage", value: "Keychain")
                        InfoRow(label: "StoreKit", value: "Version 2")
                    }
                }
            }
            .navigationTitle("Subscription Testing")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Helper Views

struct StatusBadge: View {
    let status: StoreKitManager.SubscriptionStatus
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(statusText)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(statusColor.opacity(0.2))
        .clipShape(Capsule())
    }
    
    private var statusText: String {
        switch status {
        case .unknown:
            return "Unknown"
        case .notSubscribed:
            return "Not Subscribed"
        case .subscribed:
            return "Subscribed"
        case .expired:
            return "Expired"
        case .inGracePeriod:
            return "Grace Period"
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .unknown:
            return .gray
        case .notSubscribed:
            return .red
        case .subscribed:
            return .green
        case .expired:
            return .orange
        case .inGracePeriod:
            return .yellow
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label + ":")
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.caption)
    }
}

// MARK: - Preview

#Preview {
    SubscriptionTestingView()
}

// MARK: - Usage Instructions
/*
 
 TO USE THIS TESTING VIEW:
 
 1. Add a button to your ContentView (temporarily):
 
    Button("Testing") {
        // Present the testing view
    }
    .sheet(isPresented: $showTestingView) {
        SubscriptionTestingView()
    }
 
 2. Or present it from anywhere:
 
    .sheet(isPresented: $showDebug) {
        SubscriptionTestingView()
    }
 
 3. IMPORTANT: Remove all testing code before production release!
 
 TESTING SCENARIOS:
 
 ✅ Test Free User Flow:
    1. Reset upload count
    2. Simulate 5 uploads
    3. Try to upload again → should show paywall
 
 ✅ Test Subscription Purchase:
    1. Use StoreKit testing in Xcode
    2. Complete a test purchase
    3. Verify status shows "Subscribed"
    4. Try to upload → should work unlimited
 
 ✅ Test Restore Purchases:
    1. Complete a test purchase
    2. "Delete" transaction in StoreKit manager
    3. Tap "Restore Purchases"
    4. Verify subscription restored
 
 ✅ Test Subscription Expiration:
    1. In Xcode: Debug → StoreKit → Manage Transactions
    2. Find your subscription transaction
    3. Expire the subscription
    4. Refresh status in app
    5. Verify shows expired and upload limit active
 
 ✅ Test Keychain Persistence:
    1. Upload 3 videos
    2. Delete the app
    3. Reinstall
    4. Check upload count → should still be 3
 
 */
