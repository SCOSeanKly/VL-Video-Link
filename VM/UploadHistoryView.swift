//
//  UploadHistoryView.swift
//  VM
//
//  Created by Sean Kelly on 20/11/2025.
//

import SwiftUI

struct UploadHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var historyService = CloudflareVideoHistoryService.shared
    @State private var searchText = ""
    @State private var showDeleteConfirmation = false
    @State private var videoToDelete: CloudflareVideo?
    @State private var isDeleting = false
    @State private var showDeleteError = false
    @State private var deleteErrorMessage = ""
    
    private var filteredVideos: [CloudflareVideo] {
        historyService.search(query: searchText)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 0) {
                    // Device filter indicator banner
                    if historyService.showAllDevices {
                        HStack(spacing: 12) {
                            Image(systemName: "globe")
                                .font(.title3)
                                .foregroundStyle(.orange)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Viewing All Devices")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                
                                Text("Showing uploads from all devices")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.green)
                        }
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.15), Color.purple.opacity(0.15)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .overlay(
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(.orange.opacity(0.3)),
                            alignment: .bottom
                        )
                    } else {
                        HStack(spacing: 12) {
                            Image(systemName: "iphone")
                                .font(.title3)
                                .foregroundStyle(.blue)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("This Device Only")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                
                                Text("Device ID: \(historyService.currentDeviceID)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .monospaced()
                            }
                            
                            Spacer()
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .overlay(
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(.blue.opacity(0.3)),
                            alignment: .bottom
                        )
                    }
                    
                    // Main content
                    if historyService.isLoading && historyService.videos.isEmpty {
                        loadingView
                    } else if let errorMessage = historyService.errorMessage, historyService.videos.isEmpty {
                        errorView(message: errorMessage)
                    } else if filteredVideos.isEmpty {
                        emptyStateView
                    } else {
                        videosList
                    }
                }
                
                // Delete progress overlay
                if isDeleting {
                    deleteProgressOverlay
                }
            }
            .navigationTitle("Upload History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        Task {
                            await historyService.refresh()
                        }
                    }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(historyService.isLoading)
                }
            }
            .searchable(text: $searchText, prompt: "Search by reference or filename")
            .task {
                // Always refresh when view appears to get latest data
                await historyService.refresh()
            }
            .refreshable {
                await historyService.refresh()
            }
            .alert("Delete Video", isPresented: $showDeleteConfirmation, presenting: videoToDelete) { video in
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    Task {
                        await deleteVideo(video)
                    }
                }
            } message: { video in
                Text("Are you sure you want to delete '\(video.reference)'? This action cannot be undone.")
            }
            .alert("Delete Failed", isPresented: $showDeleteError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(deleteErrorMessage)
            }
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Loading videos...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
    
    // MARK: - Delete Progress Overlay
    
    private var deleteProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.primary)
                
                Text("Deleting video...")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Text("Please wait")
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.8))
            }
            .padding(40)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 20)
        }
    }
    
    // MARK: - Delete Function
    
    private func deleteVideo(_ video: CloudflareVideo) async {
        isDeleting = true
        
        do {
            try await historyService.deleteVideo(video)
            
            // Haptic feedback on success
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
        } catch {
            deleteErrorMessage = error.localizedDescription
            showDeleteError = true
            
            // Haptic feedback on error
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
        
        isDeleting = false
    }
    
    // MARK: - Error View
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.orange)
            
            Text("Failed to Load")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Try Again") {
                Task {
                    await historyService.refresh()
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: searchText.isEmpty ? "clock.arrow.circlepath" : "magnifyingglass")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text(searchText.isEmpty ? "No Upload History" : "No Results")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(searchText.isEmpty ? 
                 "Your uploaded videos will appear here" :
                 "Try a different search term")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer()
        }
        .frame(maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - Videos List
    
    private var videosList: some View {
        List {
            ForEach(filteredVideos) { video in
                CloudflareVideoRow(
                    video: video,
                    onDelete: {
                        videoToDelete = video
                        showDeleteConfirmation = true
                    }
                )
            }
        }
        .listStyle(.insetGrouped)
        .overlay(alignment: .bottom) {
            if historyService.isLoading {
                ProgressView()
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding()
            }
        }
    }
}

// MARK: - Cloudflare Video Row

struct CloudflareVideoRow: View {
    let video: CloudflareVideo
    let onDelete: () -> Void
    
    @State private var showShareSheet = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with reference and date
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(video.reference)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text(video.formattedDate)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            // File info
            HStack(spacing: 4) {
                Image(systemName: "doc.fill")
                    .font(.caption2)
                Text(video.formattedSize)
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            
            // Download link preview
            Text(video.downloadURL)
                .font(.caption2)
                .lineLimit(1)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            
            // Action buttons
            HStack(spacing: 8) {
                Button(action: {
                    UIPasteboard.general.string = video.downloadURL
                    
                    // Haptic feedback
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }) {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    // Haptic feedback
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    
                    shareLink()
                }) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    onDelete()
                }) {
                    Label("Delete", systemImage: "trash")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.red)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
    }
    
    private func shareLink() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            print("❌ Could not find window for share sheet")
            return
        }
        
        let activityVC = UIActivityViewController(
            activityItems: [video.downloadURL],
            applicationActivities: nil
        )
        
        // For iPad support
        activityVC.popoverPresentationController?.sourceView = window
        activityVC.popoverPresentationController?.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
        activityVC.popoverPresentationController?.permittedArrowDirections = []
        
        // Find the topmost view controller
        var topController = window.rootViewController
        while let presentedViewController = topController?.presentedViewController {
            topController = presentedViewController
        }
        
        topController?.present(activityVC, animated: true)
    }
}

#Preview {
    UploadHistoryView()
}
