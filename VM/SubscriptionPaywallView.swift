//
//  SubscriptionPaywallView.swift
//  VM
//
//  Created by Sean Kelly on 20/11/2025.
//

import SwiftUI
import StoreKit

struct SubscriptionPaywallView: View {
    @StateObject private var storeManager = StoreKitManager.shared
    @StateObject private var uploadManager = UploadLimitManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    
    @State private var isPurchasing = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    // Determine if user can dismiss (only if they have uploads remaining)
    private var canDismiss: Bool {
        !uploadManager.hasReachedLimit || storeManager.subscriptionStatus.isActive
    }
    
    // Debug status text
    private var debugStatusText: String {
        switch storeManager.subscriptionStatus {
        case .unknown:
            return "Unknown"
        case .notSubscribed:
            return "Not Subscribed"
        case .subscribed(let date):
            if let date = date {
                return "Subscribed (expires: \(date.formatted(date: .abbreviated, time: .omitted)))"
            } else {
                return "Subscribed"
            }
        case .expired:
            return "Expired"
        case .inGracePeriod:
            return "Grace Period"
        }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 32) {
                    // Already subscribed banner (if active)
                    if storeManager.subscriptionStatus.isActive {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(.green)
                            
                            Text("You're Already Subscribed!")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text("You have unlimited access to all features.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            
                            Button(action: {
                                Task {
                                    await storeManager.showManageSubscriptions()
                                }
                            }) {
                                HStack {
                                    Image(systemName: "gear")
                                    Text("Manage Subscription")
                                }
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .padding(.top, 8)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.green.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .strokeBorder(Color.green.opacity(0.3), lineWidth: 2)
                                )
                        )
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                    }
                    
                    // Header
                    VStack(spacing: 16) {
                        Image("vmlogo")
                            .resizable()
                            .frame(width: 100, height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                            .shadow(color: .blue.opacity(0.2), radius: 5, x: 0, y: 4)
                        
                        // Dynamic title based on limit status
                        if uploadManager.hasReachedLimit {
                            VStack(spacing: 8) {
                                Text("Free Uploads Used")
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .multilineTextAlignment(.center)
                                
                                Text("You've used all \(uploadManager.uploadCount) free uploads. Subscribe to continue sharing videos.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                        } else {
                            VStack(spacing: 8) {
                                Text("Upgrade to Pro")
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .multilineTextAlignment(.center)
                                
                                Text("Get unlimited uploads and premium features")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.top, 20)
                    
                    // Upload status badge (if limit reached)
                    if uploadManager.hasReachedLimit {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title2)
                                .foregroundStyle(.red)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Upload Limit Reached")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                
                                Text("\(uploadManager.uploadCount) of \(uploadManager.uploadCount) free uploads used")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.red.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(Color.red.opacity(0.3), lineWidth: 1)
                                )
                        )
                        .padding(.horizontal, 24)
                    }
                    
                    // Features
                    VStack(spacing: 12) {
                        PaywallFeatureRow(
                            icon: "infinity",
                            iconColor: .blue,
                            title: "Unlimited Uploads",
                            description: "Upload as many videos as you need"
                        )
                        
                        PaywallFeatureRow(
                            icon: "clock.arrow.circlepath",
                            iconColor: .purple,
                            title: "Unlimited History Access",
                            description: "View all your uploaded videos anytime"
                        )
                        
                        PaywallFeatureRow(
                            icon: "bolt.fill",
                            iconColor: .orange,
                            title: "Priority Support",
                            description: "Get help when you need it most"
                        )
                        
                        PaywallFeatureRow(
                            icon: "arrow.triangle.2.circlepath",
                            iconColor: .green,
                            title: "Cancel Anytime",
                            description: "No long-term commitment required"
                        )
                    }
                    .padding(.horizontal, 24)
                    
                    // Products
                    VStack(spacing: 16) {
                        if storeManager.isLoading {
                            ProgressView()
                                .scaleEffect(1.2)
                                .padding()
                        } else if storeManager.products.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.largeTitle)
                                    .foregroundStyle(.yellow)
                                
                                Text("Unable to Load Subscription")
                                    .font(.headline)
                                
                                Text("Please check your internet connection and try again")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                
                                Button(action: {
                                    Task {
                                        await storeManager.loadProducts()
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "arrow.clockwise")
                                        Text("Retry")
                                    }
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                                    .background(Color.blue)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .padding(.top, 8)
                            }
                            .padding()
                        } else {
                            ForEach(storeManager.products, id: \.id) { product in
                                PaywallSubscriptionProductView(product: product, isPurchasing: $isPurchasing) {
                                    await purchaseProduct(product)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    // Restore purchases
                    Button(action: {
                        Task {
                            await storeManager.restorePurchases()
                            
                            // Check if subscription is now active and dismiss if possible
                            if storeManager.subscriptionStatus.isActive {
                                dismiss()
                            }
                        }
                    }) {
                        Text("Restore Purchases")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                            .underline()
                    }
                    .disabled(storeManager.isLoading || isPurchasing)
                    .padding(.top, 8)
                    
                    // Debug info (helpful for troubleshooting)
                    #if DEBUG
                    VStack(spacing: 8) {
                        Text("Debug Info")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        
                        Text("Status: \(debugStatusText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 12) {
                            Button("Refresh Status") {
                                Task {
                                    print("🔄 Manual status refresh requested")
                                    await storeManager.updateSubscriptionStatus()
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.orange)
                            
                            Button("Print All Transactions") {
                                Task {
                                    await storeManager.debugPrintAllTransactions()
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.purple)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal)
                    #endif
                    
                    // Terms and Privacy
                    HStack(spacing: 16) {
                        Button("Terms of Service") {
                            if let url = URL(string: "https://showcreative.co.uk/terms-of-use.html") {
                                openURL(url)
                            }
                        }
                        
                        Text("•")
                        
                        Button("Privacy Policy") {
                            if let url = URL(string: "https://showcreative.co.uk/privacy-policy.html") {
                                openURL(url)
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 40)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Only show close button if user can dismiss
                if canDismiss {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.gray)
                        }
                        .disabled(isPurchasing)
                    }
                }
            }
            .interactiveDismissDisabled(!canDismiss)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Purchase Product
    
    private func purchaseProduct(_ product: Product) async {
        isPurchasing = true
        
        do {
            try await storeManager.purchase(product)
            
            // Check if subscription is now active
            if storeManager.subscriptionStatus.isActive {
                // Success feedback
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                
                // Dismiss the paywall
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            
            // Error feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
        
        isPurchasing = false
    }
}

// MARK: - Paywall Feature Row

struct PaywallFeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(iconColor)
            }
            
            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Paywall Subscription Product View

struct PaywallSubscriptionProductView: View {
    let product: Product
    @Binding var isPurchasing: Bool
    let onPurchase: () async -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Crown badge
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.orange, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                    .shadow(color: .orange.opacity(0.3), radius: 8, x: 0, y: 4)
                
                Image(systemName: "crown.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white)
            }
            
            // Product info
            VStack(spacing: 8) {
                Text(product.displayName)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(product.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Price
            VStack(spacing: 4) {
                Text(product.displayPrice)
                    .font(.system(size: 44, weight: .bold))
                
                Text("per month")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            // Subscribe button
            Button(action: {
                Task {
                    await onPurchase()
                }
            }) {
                Group {
                    if isPurchasing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "crown.fill")
                            Text("Subscribe to Pro")
                            Image(systemName: "arrow.right")
                        }
                        .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .disabled(isPurchasing)
            
            // Additional info
            Text("Billed monthly. Cancel anytime in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(
                    LinearGradient(
                        colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
        )
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
}

#Preview {
    SubscriptionPaywallView()
}
