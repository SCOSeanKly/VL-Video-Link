//
//  UploadHistoryView.swift
//  VM
//
//  Created by Sean Kelly on 20/11/2025.
//

import SwiftUI
import AVKit

struct UploadHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var historyService = CloudflareVideoHistoryService.shared
    @State private var searchText = ""
    @State private var showDeleteConfirmation = false
    @State private var videoToDelete: CloudflareVideo?
    @State private var isDeleting = false
    @State private var showDeleteError = false
    @State private var deleteErrorMessage = ""
    
    // Multi-selection states
    @State private var isEditMode = false
    @State private var selectedVideos: Set<String> = []
    @State private var showBulkDeleteConfirmation = false
    
    // Video player overlay
    @State private var showVideoPlayer = false
    @State private var videoToPlay: String?
    
    private var filteredVideos: [CloudflareVideo] {
        historyService.search(query: searchText)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 0) {
                    // Device filter indicator banner
                    Group {
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
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    
                    // Main content
                    Group {
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                // Delete progress overlay
                if isDeleting {
                    deleteProgressOverlay
                }
                
                // Video player overlay
                if showVideoPlayer, let videoURL = videoToPlay {
                    VideoPlayerOverlay(videoURL: videoURL, isPresented: $showVideoPlayer)
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
                    Group {
                        if isEditMode {
                            Button("Cancel") {
                                isEditMode = false
                                selectedVideos.removeAll()
                            }
                        } else if historyService.videos.isEmpty {
                            Button(action: {
                                Task {
                                    await historyService.refresh()
                                }
                            }) {
                                if historyService.isLoading {
                                    ProgressView()
                                        .frame(width: 20, height: 20)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .frame(width: 20, height: 20)
                                }
                            }
                            .disabled(historyService.isLoading)
                        } else {
                            Menu {
                                Button(action: {
                                    isEditMode = true
                                }) {
                                    Label("Select Videos", systemImage: "checkmark.circle")
                                }
                                
                                Button(action: {
                                    Task {
                                        await historyService.refresh()
                                    }
                                }) {
                                    Label("Refresh", systemImage: "arrow.clockwise")
                                }
                                .disabled(historyService.isLoading)
                            } label: {
                                if historyService.isLoading {
                                    ProgressView()
                                        .frame(width: 20, height: 20)
                                } else {
                                    Image(systemName: "ellipsis.circle")
                                        .frame(width: 20, height: 20)
                                }
                            }
                            .disabled(historyService.isLoading)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isEditMode && !selectedVideos.isEmpty {
                    bulkActionBar
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
            .alert("Delete Videos", isPresented: $showBulkDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete \(selectedVideos.count)", role: .destructive) {
                    Task {
                        await deleteBulkVideos()
                    }
                }
            } message: {
                Text("Are you sure you want to delete \(selectedVideos.count) video(s)? This action cannot be undone.")
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
                
                Text(selectedVideos.count > 1 ? "Deleting \(selectedVideos.count) videos..." : "Deleting video...")
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
    
    // MARK: - Bulk Action Bar
    
    private var bulkActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(selectedVideos.count) Selected")
                        .font(.headline)
                    
                    if !filteredVideos.isEmpty {
                        Button(action: {
                            if selectedVideos.count == filteredVideos.count {
                                selectedVideos.removeAll()
                            } else {
                                selectedVideos = Set(filteredVideos.map { $0.id })
                            }
                        }) {
                            Text(selectedVideos.count == filteredVideos.count ? "Deselect All" : "Select All")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                }
                
                Spacer()
                
                Button(action: {
                    showBulkDeleteConfirmation = true
                }) {
                    Label("Delete", systemImage: "trash")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding()
            .background(.ultraThinMaterial)
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
    
    // MARK: - Bulk Delete Function
    
    private func deleteBulkVideos() async {
        isDeleting = true
        
        let videosToDelete = filteredVideos.filter { selectedVideos.contains($0.id) }
        var failedDeletions: [String] = []
        
        for video in videosToDelete {
            do {
                try await historyService.deleteVideo(video)
            } catch {
                failedDeletions.append(video.reference)
            }
        }
        
        // Reset selection and edit mode
        selectedVideos.removeAll()
        isEditMode = false
        
        // Show feedback
        if failedDeletions.isEmpty {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        } else {
            deleteErrorMessage = "Failed to delete: \(failedDeletions.joined(separator: ", "))"
            showDeleteError = true
            
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
        ZStack(alignment: .bottom) {
            List {
                ForEach(filteredVideos) { video in
                    if isEditMode {
                        CloudflareVideoRow(
                            video: video,
                            isEditMode: true,
                            isSelected: selectedVideos.contains(video.id),
                            onToggleSelection: {
                                if selectedVideos.contains(video.id) {
                                    selectedVideos.remove(video.id)
                                } else {
                                    selectedVideos.insert(video.id)
                                }
                            },
                            onDelete: {
                                videoToDelete = video
                                showDeleteConfirmation = true
                            },
                            onPlay: {
                                videoToPlay = video.downloadURL
                                showVideoPlayer = true
                            }
                        )
                    } else {
                        CloudflareVideoRow(
                            video: video,
                            isEditMode: false,
                            isSelected: false,
                            onToggleSelection: {},
                            onDelete: {
                                videoToDelete = video
                                showDeleteConfirmation = true
                            },
                            onPlay: {
                                videoToPlay = video.downloadURL
                                showVideoPlayer = true
                            }
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
            
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
    let isEditMode: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onDelete: () -> Void
    let onPlay: () -> Void
    
    @State private var showShareSheet = false
    @State private var showImagePreview = false // For photo preview
    
    // Determine file type from URL
    private var fileType: FileType {
        let urlLower = video.downloadURL.lowercased()
        if urlLower.hasSuffix(".zip") {
            return .zip
        } else if urlLower.hasSuffix(".jpg") || urlLower.hasSuffix(".jpeg") || urlLower.hasSuffix(".png") {
            return .photo
        } else {
            return .video
        }
    }
    
    private enum FileType {
        case video
        case photo
        case zip
        
        var icon: String {
            switch self {
            case .video: return "play.circle.fill"
            case .photo: return "eye.circle.fill"
            case .zip: return "arrow.down.circle.fill"
            }
        }
        
        var actionLabel: String {
            switch self {
            case .video: return "Play"
            case .photo: return "View"
            case .zip: return "Download"
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Selection indicator in edit mode
            if isEditMode {
                Button(action: onToggleSelection) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isSelected ? .blue : .gray)
                }
                .buttonStyle(.plain)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                // Header with reference and date
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 12) {
                            Text(video.reference)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            
                            Spacer()
                            
                            // Action button (play/view/download based on file type)
                            Button(action: {
                                handlePrimaryAction()
                            }) {
                                Image(systemName: fileType.icon)
                                    .font(.title2)
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text(video.formattedDate)
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                
                // File info with type indicator
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: fileTypeIndicatorIcon)
                            .font(.caption2)
                        Text(fileTypeLabel)
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(fileTypeColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(fileTypeColor.opacity(0.15))
                    .clipShape(Capsule())
                    
                    HStack(spacing: 4) {
                        Image(systemName: "doc.fill")
                            .font(.caption2)
                        Text(video.formattedSize)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                
                // Download link preview
                Text(video.downloadURL)
                    .font(.caption2)
                    .lineLimit(1)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                
                // Action buttons (hidden in edit mode)
                if !isEditMode {
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
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditMode {
                onToggleSelection()
            }
        }
        .sheet(isPresented: $showImagePreview) {
            ImagePreviewSheet(imageURL: video.downloadURL, isPresented: $showImagePreview)
        }
    }
    
    // File type helpers
    private var fileTypeIndicatorIcon: String {
        switch fileType {
        case .video: return "video.fill"
        case .photo: return "photo.fill"
        case .zip: return "doc.zipper"
        }
    }
    
    private var fileTypeLabel: String {
        switch fileType {
        case .video: return "Video"
        case .photo: return "Photo"
        case .zip: return "ZIP Archive"
        }
    }
    
    private var fileTypeColor: Color {
        switch fileType {
        case .video: return .blue
        case .photo: return .orange
        case .zip: return .purple
        }
    }
    
    // Handle primary action based on file type
    private func handlePrimaryAction() {
        switch fileType {
        case .video:
            // Play video
            onPlay()
            
        case .photo:
            // Show photo preview
            showImagePreview = true
            
        case .zip:
            // Download ZIP file
            downloadFile()
        }
    }
    
    private func downloadFile() {
        guard let url = URL(string: video.downloadURL) else { return }
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        // Open in Safari to trigger download
        UIApplication.shared.open(url)
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

// MARK: - Video Player Overlay

struct VideoPlayerOverlay: View {
    let videoURL: String
    @Binding var isPresented: Bool
    @State private var player: AVPlayer?
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    // Close when tapping outside
                    player?.pause()
                    isPresented = false
                }
            
            // Video player container
            ZStack(alignment: .topTrailing) {
                // Video player
                if let player = player {
                    VideoPlayer(player: player)
                        .frame(maxHeight: UIScreen.main.bounds.height * 0.6)
                        .aspectRatio(contentMode: .fill)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                
                // Close button overlay
                Button(action: {
                    player?.pause()
                    isPresented = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.white, .black.opacity(0.6))
                }
                .padding()
            }
            .shadow(radius: 20)
            .padding(.horizontal, 20)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.6)))
        .animation(.spring(response: 0.3), value: isPresented)
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
    
    private func setupPlayer() {
        guard let url = URL(string: videoURL) else {
            print("❌ Invalid video URL: \(videoURL)")
            return
        }
        
        player = AVPlayer(url: url)
        player?.play()
        
        // Optional: Loop video
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { _ in
            player?.seek(to: .zero)
            player?.play()
        }
    }
}

// MARK: - Image Preview Sheet

struct ImagePreviewSheet: View {
    let imageURL: String
    @Binding var isPresented: Bool
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var loadError = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        
                        Text("Loading photo...")
                            .foregroundStyle(.white)
                            .font(.subheadline)
                    }
                } else if loadError {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.orange)
                        
                        Text("Failed to load photo")
                            .foregroundStyle(.white)
                            .font(.headline)
                        
                        Button("Dismiss") {
                            isPresented = false
                        }
                        .buttonStyle(.bordered)
                    }
                } else if let image = image {
                    ScrollView([.horizontal, .vertical], showsIndicators: false) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                // Zoom gesture support
                            }
                    )
                }
            }
            .navigationTitle("Photo Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                    .foregroundStyle(.white)
                }
                
                if !isLoading && !loadError {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: imageURL) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .task {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        guard let url = URL(string: imageURL) else {
            loadError = true
            isLoading = false
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            
            await MainActor.run {
                if let downloadedImage = UIImage(data: data) {
                    self.image = downloadedImage
                    self.loadError = false
                } else {
                    self.loadError = true
                }
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.loadError = true
                self.isLoading = false
            }
            print("❌ Failed to load image: \(error)")
        }
    }
}

#Preview {
    UploadHistoryView()
}
