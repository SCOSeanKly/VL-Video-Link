//
//  StoreKitManager.swift
//  VM
//
//  Created by Sean Kelly on 20/11/2025.
//

import Foundation
import StoreKit
import Combine

/// Manager for handling StoreKit subscriptions
@MainActor
final class StoreKitManager: ObservableObject {
    static let shared = StoreKitManager()
    
    // MARK: - Published Properties
    
    @Published private(set) var subscriptionStatus: SubscriptionStatus = .unknown
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    
    // MARK: - Subscription Status
    
    enum SubscriptionStatus: Equatable {
        case unknown
        case notSubscribed
        case subscribed(expirationDate: Date?)
        case expired
        case inGracePeriod
        
        var isActive: Bool {
            switch self {
            case .subscribed, .inGracePeriod:
                return true
            default:
                return false
            }
        }
    }
    
    // MARK: - Product IDs
    
    private let monthlySubscriptionID = "videoLinkMonthly"
    
    // MARK: - Private Properties
    
    private var updateListenerTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    private init() {
        // Start listening for transaction updates
        updateListenerTask = Task {
            await listenForTransactions()
        }
        
        // Load products and check subscription status
        Task {
            await loadProducts()
            await updateSubscriptionStatus()
        }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    // MARK: - Product Loading
    
    /// Load available products from App Store
    func loadProducts() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Load products from the App Store
            let loadedProducts = try await Product.products(for: [monthlySubscriptionID])
            self.products = loadedProducts.sorted { $0.price < $1.price }
            print("✅ Loaded \(loadedProducts.count) products")
        } catch {
            self.errorMessage = "Failed to load products: \(error.localizedDescription)"
            print("❌ Failed to load products: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Subscription Status
    
    /// Update the current subscription status
    func updateSubscriptionStatus() async {
        print("🔍 Checking subscription status...")
        
        // Check for active subscriptions
        var activeSubscription: Product.SubscriptionInfo.Status?
        var foundTransaction = false
        
        for await result in Transaction.currentEntitlements {
            // Verify the transaction
            guard case .verified(let transaction) = result else {
                print("⚠️ Found unverified transaction")
                continue
            }
            
            foundTransaction = true
            print("🔍 Found transaction for product: \(transaction.productID)")
            
            // Check if the transaction is for our subscription
            if transaction.productID == monthlySubscriptionID {
                print("✅ Found matching subscription transaction!")
                
                // Check if it's active
                do {
                    if let subscription = try await transaction.subscriptionStatus {
                        activeSubscription = subscription
                        print("✅ Got subscription status: \(subscription.state)")
                        break
                    } else {
                        print("⚠️ No subscription status available")
                    }
                } catch {
                    print("❌ Error getting subscription status: \(error)")
                }
            }
        }
        
        if !foundTransaction {
            print("⚠️ No transactions found in currentEntitlements")
        }
        
        // Update the subscription status
        if let status = activeSubscription {
            // Extract renewal info
            let expirationDate: Date?
            switch status.renewalInfo {
            case .verified(let renewalInfo):
                expirationDate = renewalInfo.renewalDate
            case .unverified(let renewalInfo, _):
                expirationDate = renewalInfo.renewalDate
            }
            
            switch status.state {
            case .subscribed:
                self.subscriptionStatus = .subscribed(expirationDate: expirationDate)
                print("✅ User is subscribed (expires: \(expirationDate?.formatted() ?? "unknown"))")
                
            case .inGracePeriod:
                self.subscriptionStatus = .inGracePeriod
                print("⚠️ User is in grace period")
                
            case .expired:
                self.subscriptionStatus = .expired
                print("⏰ Subscription expired")
                
            case .inBillingRetryPeriod:
                // Treat as subscribed for now (user can still use the app)
                self.subscriptionStatus = .subscribed(expirationDate: expirationDate)
                print("⚠️ User is in billing retry period")
                
            case .revoked:
                self.subscriptionStatus = .notSubscribed
                print("❌ Subscription revoked")
                
            default:
                self.subscriptionStatus = .unknown
                print("❓ Unknown subscription state: \(status.state)")
            }
        } else {
            // If we just completed a purchase but status isn't found yet, wait and retry
            if foundTransaction {
                print("⚠️ Transaction found but no subscription status - this might be a timing issue")
                // Give StoreKit a moment to update
                try? await Task.sleep(for: .seconds(1))
                
                // Retry once
                print("🔄 Retrying subscription status check...")
                for await result in Transaction.currentEntitlements {
                    guard case .verified(let transaction) = result else { continue }
                    
                    if transaction.productID == monthlySubscriptionID {
                        if let subscription = try? await transaction.subscriptionStatus {
                            if subscription.state == .subscribed || subscription.state == .inGracePeriod {
                                self.subscriptionStatus = .subscribed(expirationDate: nil)
                                print("✅ User is subscribed (found on retry)")
                                return
                            }
                        }
                    }
                }
            }
            
            self.subscriptionStatus = .notSubscribed
            print("❌ User is not subscribed")
        }
    }
    
    // MARK: - Purchase
    
    /// Purchase a subscription product
    func purchase(_ product: Product) async throws {
        print("🛒 Starting purchase for product: \(product.id)")
        
        // First check if already subscribed
        if subscriptionStatus.isActive {
            print("⚠️ User already has an active subscription!")
            self.errorMessage = "You already have an active subscription. Use 'Manage Subscription' to make changes."
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // Attempt to purchase the product
            print("⏳ Calling product.purchase()...")
            let result = try await product.purchase()
            print("✅ Got purchase result")
            
            switch result {
            case .success(let verificationResult):
                print("✅ Purchase succeeded, verifying transaction...")
                // Verify the transaction
                switch verificationResult {
                case .verified(let transaction):
                    // Transaction verified, grant access
                    print("✅ Transaction verified: \(transaction.id)")
                    print("   Product ID: \(transaction.productID)")
                    print("   Purchase Date: \(transaction.purchaseDate)")
                    await transaction.finish()
                    
                    // Give StoreKit a moment to fully process before checking status
                    print("⏳ Waiting for StoreKit to update entitlements...")
                    try? await Task.sleep(for: .seconds(2))
                    
                    // Now check subscription status
                    await updateSubscriptionStatus()
                    print("✅ Purchase successful and verified")
                    
                case .unverified(_, let error):
                    // Transaction failed verification
                    print("❌ Transaction verification failed: \(error)")
                    throw StoreError.verificationFailed(error)
                }
                
            case .userCancelled:
                print("ℹ️ User cancelled purchase")
                // Don't throw an error for user cancellation
                
            case .pending:
                print("⏳ Purchase pending (waiting for approval)")
                self.errorMessage = "Purchase is pending approval. This may take a moment."
                
            @unknown default:
                print("❓ Unknown purchase result")
            }
        } catch {
            // Check for specific StoreKit errors
            let nsError = error as NSError
            
            if nsError.domain == "ASDErrorDomain" || nsError.domain == "SKErrorDomain" {
                // StoreKit specific errors
                switch nsError.code {
                case 2: // SKErrorPaymentCancelled
                    print("ℹ️ Payment was cancelled")
                    self.errorMessage = "Purchase was cancelled."
                case 3: // SKErrorClientInvalid
                    print("❌ Client is not allowed to make purchases")
                    self.errorMessage = "Your device is not allowed to make purchases. Check Settings > Screen Time > Content & Privacy Restrictions."
                case 4: // SKErrorPaymentInvalid
                    print("❌ Payment invalid")
                    self.errorMessage = "The purchase request was invalid."
                case 5: // SKErrorPaymentNotAllowed
                    print("❌ Device is not allowed to make payments")
                    self.errorMessage = "Purchases are not allowed on this device."
                default:
                    print("❌ StoreKit error: \(nsError.code) - \(nsError.localizedDescription)")
                    self.errorMessage = "Purchase failed: \(error.localizedDescription)"
                }
            } else {
                self.errorMessage = "Purchase failed: \(error.localizedDescription)"
                print("❌ Purchase failed with error: \(error)")
                print("   Error domain: \(nsError.domain)")
                print("   Error code: \(nsError.code)")
                print("   Error type: \(type(of: error))")
            }
            
            throw error
        }
        
        isLoading = false
        print("🛒 Purchase flow completed")
    }
    
    /// Restore previous purchases
    func restorePurchases() async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await AppStore.sync()
            await updateSubscriptionStatus()
            print("✅ Purchases restored")
        } catch {
            self.errorMessage = "Failed to restore purchases: \(error.localizedDescription)"
            print("❌ Failed to restore purchases: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Transaction Listener
    
    /// Listen for transaction updates
    private func listenForTransactions() async {
        // Iterate through any transactions that don't come from a direct call to `purchase()`
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else {
                continue
            }
            
            // Deliver products to the user
            await transaction.finish()
            
            // Update subscription status
            await updateSubscriptionStatus()
        }
    }
    
    // MARK: - Manage Subscription
    
    /// Show the subscription management interface
    func showManageSubscriptions() async {
        if let windowScene = await UIApplication.shared.connectedScenes.first as? UIWindowScene {
            do {
                try await AppStore.showManageSubscriptions(in: windowScene)
            } catch {
                print("❌ Failed to show manage subscriptions: \(error)")
            }
        }
    }
    
    // MARK: - Debug Helpers
    
    #if DEBUG
    /// Debug: Print all current transactions and entitlements
    func debugPrintAllTransactions() async {
        print("\n═══════════════════════════════════════")
        print("🔍 DEBUG: ALL TRANSACTIONS & ENTITLEMENTS")
        print("═══════════════════════════════════════")
        
        print("\n📦 Current Products:")
        for product in products {
            print("  • \(product.id)")
            print("    Display Name: \(product.displayName)")
            print("    Price: \(product.displayPrice)")
            print("    Type: \(product.type)")
        }
        
        print("\n🎫 Current Entitlements:")
        var entitlementCount = 0
        for await result in Transaction.currentEntitlements {
            entitlementCount += 1
            switch result {
            case .verified(let transaction):
                print("  ✅ Verified Transaction #\(entitlementCount)")
                print("     ID: \(transaction.id)")
                print("     Product: \(transaction.productID)")
                print("     Purchase Date: \(transaction.purchaseDate)")
                print("     Expiration Date: \(transaction.expirationDate?.formatted() ?? "N/A")")
                print("     Revocation Date: \(transaction.revocationDate?.formatted() ?? "N/A")")
                print("     Original ID: \(transaction.originalID)")
                
                // Try to get subscription status
                if let status = try? await transaction.subscriptionStatus {
                    print("     Subscription State: \(status.state)")
                    switch status.renewalInfo {
                    case .verified(let renewalInfo):
                        print("     Will Auto-Renew: \(renewalInfo.willAutoRenew)")
                        print("     Renewal Date: \(renewalInfo.renewalDate?.formatted() ?? "N/A")")
                    case .unverified(let renewalInfo, _):
                        print("     ⚠️ Unverified Renewal Info")
                        print("     Will Auto-Renew: \(renewalInfo.willAutoRenew)")
                    }
                }
                
            case .unverified(let transaction, let error):
                print("  ⚠️ Unverified Transaction #\(entitlementCount)")
                print("     ID: \(transaction.id)")
                print("     Product: \(transaction.productID)")
                print("     Error: \(error)")
            }
        }
        
        if entitlementCount == 0 {
            print("  (No entitlements found)")
        }
        
        print("\n📜 All Transactions:")
        var allTransactionCount = 0
        for await result in Transaction.all {
            allTransactionCount += 1
            switch result {
            case .verified(let transaction):
                print("  • Transaction #\(allTransactionCount)")
                print("    Product: \(transaction.productID)")
                print("    Date: \(transaction.purchaseDate.formatted())")
                print("    Revoked: \(transaction.revocationDate != nil ? "Yes" : "No")")
            case .unverified:
                print("  • Unverified Transaction #\(allTransactionCount)")
            }
            
            // Limit to first 10 to avoid spam
            if allTransactionCount >= 10 {
                print("  ... (showing first 10 only)")
                break
            }
        }
        
        if allTransactionCount == 0 {
            print("  (No transactions found)")
        }
        
        print("\n📊 Current Subscription Status:")
        print("  \(subscriptionStatus)")
        print("  Is Active: \(subscriptionStatus.isActive)")
        
        print("\n═══════════════════════════════════════\n")
    }
    #endif
}

// MARK: - Store Error

enum StoreError: LocalizedError {
    case verificationFailed(Error)
    case purchaseFailed
    
    var errorDescription: String? {
        switch self {
        case .verificationFailed(let error):
            return "Transaction verification failed: \(error.localizedDescription)"
        case .purchaseFailed:
            return "Purchase failed. Please try again."
        }
    }
}
