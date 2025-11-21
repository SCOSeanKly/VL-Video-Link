//
//  ContentView.swift
//  VM
//
//  Created by Sean Kelly on 19/11/2025.
//

import SwiftUI
import PhotosUI
import AVKit
import AVFoundation
import Photos
import StoreKit
import ZIPFoundation

struct ContentView: View {
    // Media selection
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var mediaType: MediaType = .none
    
    // Video-specific
    @State private var videoURL: URL?
    @State private var videoAsset: AVAsset?
    @State private var player: AVPlayer?
    
    // Photo-specific
    @State private var selectedPhotoURLs: [URL] = []
    @State private var photoPreviewImages: [UIImage] = []
    
    // Upload states
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0.0
    @State private var uploadStatus: String = ""
    @State private var downloadLink: String?
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var uploadTask: Task<Void, Never>?
    @State private var selectedQuality: VideoCompressionService.CompressionQuality = .medium
    @State private var originalSize: String = ""
    @State private var estimatedCompressedSize: String = ""
    @State private var referenceNumber: String = ""
    @State private var showReferencePopover = false
    @State private var showInstructions = false
    @State private var showHistory = false
    @StateObject private var historyService = CloudflareVideoHistoryService.shared
    @State private var isLoadingVideo = false
    @State private var showCamera = false
    @State private var showCameraPermissionAlert = false
    @StateObject private var uploadLimitManager = UploadLimitManager.shared
    @StateObject private var storeManager = StoreKitManager.shared
    @State private var showSubscriptionPaywall = false
    
    enum MediaType {
        case none
        case video
        case singlePhoto
        case multiplePhotos
        
        var displayName: String {
            switch self {
            case .none: return ""
            case .video: return "Video"
            case .singlePhoto: return "Photo"
            case .multiplePhotos: return "Photos"
            }
        }
        
        var icon: String {
            switch self {
            case .none: return ""
            case .video: return "video.fill"
            case .singlePhoto: return "photo.fill"
            case .multiplePhotos: return "photo.stack.fill"
            }
        }
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 20) {
                // Header
                ZStack {
                    VStack(spacing: 8) {
                        if mediaType == .video, let player = player {
                            // Mini video player when video is selected
                            VideoPlayer(player: player)
                                .frame(height: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                                .padding(EdgeInsets(top: 60, leading: 20, bottom: 12, trailing: 20))
                                .onAppear {
                                    // Ensure audio is enabled
                                    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                                    try? AVAudioSession.sharedInstance().setActive(true)
                                }
                            
                            Text("Video Preview")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white.opacity(0.8))
                        } else if mediaType == .singlePhoto, let photo = photoPreviewImages.first {
                            // Single photo preview
                            Image(uiImage: photo)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                                .padding(EdgeInsets(top: 60, leading: 20, bottom: 12, trailing: 20))
                            
                            Text("Photo Preview")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white.opacity(0.8))
                        } else if mediaType == .multiplePhotos {
                            // Multiple photos preview (grid)
                            VStack(spacing: 8) {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(Array(photoPreviewImages.prefix(5).enumerated()), id: \.offset) { index, image in
                                            Image(uiImage: image)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 100, height: 100)
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                        }
                                        
                                        if photoPreviewImages.count > 5 {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(Color.gray.opacity(0.3))
                                                    .frame(width: 100, height: 100)
                                                
                                                Text("+\(photoPreviewImages.count - 5)")
                                                    .font(.title2)
                                                    .fontWeight(.bold)
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                }
                                .frame(height: 100)
                                .padding(.top, 60)
                                .padding(.bottom, 12)
                                
                                Text("\(photoPreviewImages.count) Photos Selected")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        } else {
                            // Show logo when no media selected
                            Image("vmlogo")
                                .resizable()
                                .frame(width: 100, height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 24))
                                .shadow(color: .blue.opacity(0.2), radius: 5, x: 0, y: 4)
                                .padding(.bottom, 20)
                            
                            Text("Media Link")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text("""
Tap the 'Select Media' button to choose videos or photos from your Photos library. You can select any media you have saved on your device. 

We recommend using brief, concise videos to ensure optimal processing speed and quality.
""")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                                .padding(.top, 20)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Buttons in top corners
                    VStack {
                        HStack {
                            // History button and upload counter (top left)
                            HStack(spacing: 6) {
                                Button(action: {
                                    // Check if limit reached and not subscribed
                                    if uploadLimitManager.hasReachedLimit && !storeManager.subscriptionStatus.isActive {
                                        showSubscriptionPaywall = true
                                    } else {
                                        showHistory = true
                                    }
                                }) {
                                    ZStack(alignment: .topTrailing) {
                                        Image(systemName: "clock.arrow.circlepath")
                                            .font(.title2)
                                            .foregroundStyle(.blue)
                                            .padding()
                                        
                                        // Badge showing count
                                        if !historyService.videos.isEmpty {
                                            Text("\(historyService.videos.count)")
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                                .foregroundStyle(.white)
                                                .padding(4)
                                                .background(Color.red)
                                                .clipShape(Circle())
                                                .offset(x: -4, y: 4)
                                        }
                                    }
                                }
                                
                                // Upload counter capsule (only show if not subscribed)
                                if !storeManager.subscriptionStatus.isActive {
                                    UploadCounterCapsule(
                                        uploadCount: uploadLimitManager.uploadCount,
                                        remainingUploads: uploadLimitManager.remainingUploads,
                                        canUpload: uploadLimitManager.canUpload
                                    )
                                    .offset(x: -12)
                                }
                            }
                            
                            Spacer()
                            
                                Button(action: {
                                    showInstructions = true
                                }) {
                                    Image(systemName: "info.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.blue)
                                        .padding()
                                }
                        }
                        Spacer()
                    }
                }
                .padding(.top, 40)
                .padding(.bottom, 40)
                .background(mediaType != .none ? Color.black : Color.white)
                .ignoresSafeArea(edges: .all)
              
                // Limit reached banner - show prominently when credits exhausted
                if uploadLimitManager.hasReachedLimit && !storeManager.subscriptionStatus.isActive {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title2)
                                .foregroundStyle(.red)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Free Uploads Exhausted")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                
                                Text("Subscribe to continue uploading videos")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                        }
                        
                        Button(action: {
                            showSubscriptionPaywall = true
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "crown.fill")
                                Text("Subscribe to Pro")
                                Image(systemName: "arrow.right")
                            }
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.red.opacity(0.3), lineWidth: 1)
                    )
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
              
                // Reset button - only show when media is selected
                if mediaType != .none {
                    ZStack {
                        VStack(spacing: 4) {
                            Text("Select or record media")
                                .font(.body)
                                .fontWeight(.bold)
                            
                            // Upload limit indicator
                            if !storeManager.subscriptionStatus.isActive {
                                Text("\(uploadLimitManager.remainingUploads) free uploads remaining")
                                    .font(.caption)
                                    .foregroundStyle(uploadLimitManager.remainingUploads <= 2 ? .red : .secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        
                        HStack {
                            Spacer()
                            Button(action: resetApp) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.red)
                            }
                            .padding(.trailing, 20)
                           
                        }
                    }
                    .padding(.vertical, 8)
                }
                
             
                
                // Photo/Video selection buttons
                HStack(spacing: 12) {
                    // Photo library picker
                    PhotosPicker(
                        selection: $selectedItems,
                        maxSelectionCount: 20,
                        matching: .any(of: [.images, .videos])
                    ) {
                        Label(mediaType != .none ? "Choose New" : "Photo Library", systemImage: "photo.on.rectangle")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(mediaType != .none ? Color.orange : Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(uploadLimitManager.hasReachedLimit && !storeManager.subscriptionStatus.isActive)
                    .opacity((uploadLimitManager.hasReachedLimit && !storeManager.subscriptionStatus.isActive) ? 0.5 : 1.0)
                    .onChange(of: selectedItems) { oldValue, newValue in
                        Task {
                            await loadMedia()
                        }
                    }
                    
                    // Camera recording button
                    Button(action: {
                        // Check if limit reached before opening camera
                        if uploadLimitManager.hasReachedLimit && !storeManager.subscriptionStatus.isActive {
                            showSubscriptionPaywall = true
                        } else {
                            Task {
                                await openCamera()
                            }
                        }
                    }) {
                        Label("Record Video", systemImage: "video.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(!CameraPermissionHelper.isCameraAvailable || (uploadLimitManager.hasReachedLimit && !storeManager.subscriptionStatus.isActive))
                    .opacity((CameraPermissionHelper.isCameraAvailable && !(uploadLimitManager.hasReachedLimit && !storeManager.subscriptionStatus.isActive)) ? 1.0 : 0.5)
                }
                .padding(.horizontal)
                
                // Status Section
                if !isLoadingVideo && isUploading {
                VStack(spacing: 16) {
                    // Progress Bar
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(uploadStatus)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                            
                            Text("\(Int(uploadProgress * 100))%")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.blue)
                        }
                        
                        ProgressView(value: uploadProgress, total: 1.0)
                            .tint(.blue)
                            .scaleEffect(y: 1.5, anchor: .center)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    // Status Icon with dynamic message
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        
                        Text(uploadStatus.isEmpty ? "Processing..." : uploadStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
            } else if let downloadLink {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Download Link:")
                        .font(.headline)
                    
                    // Link display with copy button
                  
                        Text(downloadLink)
                            .font(.caption)
                            .lineLimit(2)
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    // Action buttons
                    HStack(spacing: 12) {
                        // Copy button
                        Button(action: {
                            UIPasteboard.general.string = downloadLink
                            
                            // Haptic feedback
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                        }) {
                            Label("Copy Link", systemImage: "doc.on.doc")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        
                        // Share button
                        Button(action: shareLink) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding()
              
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            } else if mediaType != .none {
                VStack(spacing: 16) {
                    // Media type indicator
                    if mediaType != .none {
                        HStack(spacing: 8) {
                            Image(systemName: mediaType.icon)
                                .font(.title3)
                                .foregroundStyle(.blue)
                            
                            Text("\(mediaType.displayName) Selected")
                                .font(.headline)
                            
                            if mediaType == .multiplePhotos {
                                Text("(\(photoPreviewImages.count) photos)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    
                    // File size info
                    if !originalSize.isEmpty {
                        VStack(spacing: 4) {
                            HStack {
                                Text("Original size:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(originalSize)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            
                            if !estimatedCompressedSize.isEmpty {
                                HStack {
                                    Text("After compression:")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(estimatedCompressedSize)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    
                    // Quality picker (only for videos)
                    if mediaType == .video {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Compression Quality")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Picker("Quality", selection: $selectedQuality) {
                                Text("Low").tag(VideoCompressionService.CompressionQuality.low)
                                Text("Medium").tag(VideoCompressionService.CompressionQuality.medium)
                                Text("High").tag(VideoCompressionService.CompressionQuality.high)
                                Text("Original").tag(VideoCompressionService.CompressionQuality.original)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: selectedQuality) { oldValue, newValue in
                                updateEstimatedSize()
                            }
                        }
                    }
                    
                    // Upload button
                    if !isUploading {
                        Button(action: {
                            // Check upload limit before showing reference popover
                            if uploadLimitManager.canUpload {
                                showReferencePopover = true
                            } else {
                                showSubscriptionPaywall = true
                            }
                        }) {
                            Label("Upload & Generate Link", systemImage: "arrow.up.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(uploadLimitManager.canUpload ? Color.green : Color.gray)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.top)
                    } else {
                        Button(action: cancelUpload) {
                            Label("Cancel Upload", systemImage: "xmark.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.top)
                    }
                }
                .padding()
            }
            Spacer()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showReferencePopover) {
            ReferenceNumberView(
                referenceNumber: $referenceNumber,
                isPresented: $showReferencePopover,
                onSubmit: {
                    uploadMedia()
                }
            )
        }
        .sheet(isPresented: $showInstructions) {
            InstructionsView()
        }
        .sheet(isPresented: $showHistory) {
            UploadHistoryView()
        }
        .sheet(isPresented: $showSubscriptionPaywall) {
            SubscriptionPaywallView()
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView { recordedURL in
                Task {
                    await loadRecordedVideo(from: recordedURL)
                }
            }
            .ignoresSafeArea()
        }
        .alert("Camera Permission Required", isPresented: $showCameraPermissionAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Open Settings") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
        } message: {
            Text("Please grant camera access in Settings to record videos.")
        }
        
        // Full screen loading overlay
        if isLoadingVideo {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .overlay {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        
                        Text("Loading video...")
                            .font(.headline)
                            .foregroundStyle(.white)
                        
                        Text("Please wait while we prepare your video")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(32)
                    .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(.black.opacity(0.8))
                    )
                }
                .transition(.opacity)
        }
    }
        .animation(.snappy(duration: 0.1), value: videoURL)
        .task {
            // Fetch history on app launch to update the badge
            await historyService.fetchVideos()
        }
        .onAppear {
            // Show paywall on launch if limit is reached
            if uploadLimitManager.hasReachedLimit && !storeManager.subscriptionStatus.isActive {
                // Delay slightly so the UI loads first
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showSubscriptionPaywall = true
                }
            }
        }
    }
    
    // MARK: - Media Loading
    
    // Load media from PhotosPicker - intelligently handles videos and photos
    private func loadMedia() async {
        guard !selectedItems.isEmpty else { return }
        
        await MainActor.run {
            isLoadingVideo = true
            videoURL = nil
            videoAsset = nil
            downloadLink = nil
            referenceNumber = ""
            player = nil
            originalSize = ""
            estimatedCompressedSize = ""
            selectedPhotoURLs = []
            photoPreviewImages = []
        }
        
        do {
            // Try to determine if first item is a video or photo
            let firstItem = selectedItems[0]
            
            // Try loading as video first
            if let videoFile = try? await firstItem.loadTransferable(type: VideoFile.self) {
                // It's a video - load as single video
                await loadSingleVideo(item: firstItem, videoFile: videoFile)
            } else {
                // It's a photo/photos
                if selectedItems.count == 1 {
                    await loadSinglePhoto(item: firstItem)
                } else {
                    await loadMultiplePhotos(items: selectedItems)
                }
            }
        } catch {
            await MainActor.run {
                isLoadingVideo = false
                errorMessage = "Failed to load media: \(error.localizedDescription)"
                showError = true
            }
        }
    }
    
    // Load single video
    private func loadSingleVideo(item: PhotosPickerItem, videoFile: VideoFile) async {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: videoFile.url.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            
            await MainActor.run {
                let newPlayer = AVPlayer(url: videoFile.url)
                newPlayer.volume = 1.0
                self.player = newPlayer
                
                self.videoURL = videoFile.url
                self.mediaType = .video
                self.originalSize = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
                self.isLoadingVideo = false
                updateEstimatedSize()
            }
        } catch {
            await MainActor.run {
                isLoadingVideo = false
                errorMessage = "Failed to load video: \(error.localizedDescription)"
                showError = true
            }
        }
    }
    
    // Load single photo
    private func loadSinglePhoto(item: PhotosPickerItem) async {
        guard let imageData = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: imageData) else {
            await MainActor.run {
                errorMessage = "Failed to load photo"
                showError = true
                isLoadingVideo = false
            }
            return
        }
        
        // Save to temp file
        let tempDir = FileManager.default.temporaryDirectory
        let photoURL = tempDir.appendingPathComponent("\(UUID().uuidString).jpg")
        
        if let jpegData = image.jpegData(compressionQuality: 0.9) {
            try? jpegData.write(to: photoURL)
            
            await MainActor.run {
                selectedPhotoURLs = [photoURL]
                photoPreviewImages = [image]
                mediaType = .singlePhoto
                originalSize = ByteCountFormatter.string(fromByteCount: Int64(jpegData.count), countStyle: .file)
                estimatedCompressedSize = "" // No compression for single photo
                isLoadingVideo = false
            }
        }
    }
    
    // Load multiple photos
    private func loadMultiplePhotos(items: [PhotosPickerItem]) async {
        var photoURLs: [URL] = []
        var photos: [UIImage] = []
        var totalSize: Int64 = 0
        
        for (index, item) in items.enumerated() {
            guard let imageData = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: imageData) else {
                continue
            }
            
            let tempDir = FileManager.default.temporaryDirectory
            let photoURL = tempDir.appendingPathComponent("photo_\(index + 1).jpg")
            
            if let jpegData = image.jpegData(compressionQuality: 0.9) {
                try? jpegData.write(to: photoURL)
                photoURLs.append(photoURL)
                photos.append(image)
                totalSize += Int64(jpegData.count)
            }
        }
        
        await MainActor.run {
            selectedPhotoURLs = photoURLs
            photoPreviewImages = photos
            mediaType = .multiplePhotos
            originalSize = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
            // Estimate zip size at ~70% of original
            estimatedCompressedSize = ByteCountFormatter.string(fromByteCount: Int64(Double(totalSize) * 0.7), countStyle: .file) + " (zipped)"
            isLoadingVideo = false
        }
    }
    
    // Fetch PHAsset from identifier
    private func fetchPHAsset(for identifier: String) async -> PHAsset? {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        return fetchResult.firstObject
    }
    
    // Estimate AVAsset file size
    private func estimateAssetSize(asset: AVAsset) async -> Double {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else {
            return 0
        }
        
        do {
            let duration = try await asset.load(.duration)
            let estimatedDataRate = try await track.load(.estimatedDataRate)
            let durationSeconds = CMTimeGetSeconds(duration)
            
            return Double(estimatedDataRate) * durationSeconds / 8.0 // Convert bits to bytes
        } catch {
            return 0
        }
    }
    
    // Update estimated compressed size
    private func updateEstimatedSize() {
        // Handle both URL-based and AVAsset-based videos
        guard videoURL != nil || videoAsset != nil else { return }
        
        Task {
            do {
                let fileSize: Int64
                
                if let videoURL = videoURL {
                    // Get size from file
                    let attributes = try FileManager.default.attributesOfItem(atPath: videoURL.path)
                    fileSize = attributes[.size] as? Int64 ?? 0
                } else if let videoAsset = videoAsset {
                    // Estimate size from AVAsset
                    let estimatedSize = await estimateAssetSize(asset: videoAsset)
                    fileSize = Int64(estimatedSize)
                } else {
                    return
                }
                
                // Rough estimation based on quality
                let compressionRatio: Double
                switch selectedQuality {
                case .low:
                    compressionRatio = 0.3 // 30% of original
                case .medium:
                    compressionRatio = 0.5 // 50% of original
                case .high:
                    compressionRatio = 0.7 // 70% of original
                case .original:
                    compressionRatio = 1.0 // 100% - no compression
                }
                
                let estimatedSize = Int64(Double(fileSize) * compressionRatio)
                
                await MainActor.run {
                    self.estimatedCompressedSize = ByteCountFormatter.string(fromByteCount: estimatedSize, countStyle: .file)
                }
            } catch {
                // Ignore errors
            }
        }
    }
    
    // MARK: - Upload Functions
    
    // Upload media (video, single photo, or multiple photos) and generate download link
    private func uploadMedia() {
        guard mediaType != .none else { return }
        
        isUploading = true
        uploadProgress = 0.0
        uploadStatus = "Starting..."
        
        uploadTask = Task {
            do {
                let cloudflareService = CloudflareWorkerService()
                var link: String
                
                switch mediaType {
                case .video:
                    // Handle video upload with compression
                    var sourceURL: URL
                    
                    // If we have AVAsset but no URL, export it first
                    if let videoAsset = videoAsset, videoURL == nil {
                        uploadStatus = "Preparing video..."
                        sourceURL = try await exportAVAssetToFile(asset: videoAsset)
                    } else if let videoURL = videoURL {
                        sourceURL = videoURL
                    } else {
                        throw VideoError.loadFailed
                    }
                    
                    // Step 1: Compress the video
                    let compressionService = VideoCompressionService()
                    let compressedURL = try await compressionService.compress(
                        videoURL: sourceURL,
                        quality: selectedQuality
                    ) { progress, status in
                        Task { @MainActor in
                            // Compression is 0-50% of total progress
                            self.uploadProgress = progress * 0.5
                            self.uploadStatus = "🗜️ \(status)"
                        }
                    }
                    
                    // Check for cancellation after compression
                    try Task.checkCancellation()
                    
                    // Step 2: Upload the compressed video
                    link = try await cloudflareService.upload(
                        videoURL: compressedURL,
                        fileName: nil,
                        referenceNumber: referenceNumber
                    ) { progress, status in
                        Task { @MainActor in
                            // Upload is 50-100% of total progress
                            self.uploadProgress = 0.5 + (progress * 0.5)
                            self.uploadStatus = "☁️ \(status)"
                        }
                    }
                    
                    // Clean up compressed file and temporary export
                    try? FileManager.default.removeItem(at: compressedURL)
                    if videoURL == nil {
                        try? FileManager.default.removeItem(at: sourceURL)
                    }
                    
                case .singlePhoto:
                    // Handle single photo upload
                    guard let photoURL = selectedPhotoURLs.first else {
                        throw MediaUploadError.noPhotosSelected
                    }
                    
                    link = try await cloudflareService.upload(
                        videoURL: photoURL,
                        fileName: nil,
                        referenceNumber: referenceNumber
                    ) { progress, status in
                        Task { @MainActor in
                            self.uploadProgress = progress
                            self.uploadStatus = "📷 \(status)"
                        }
                    }
                    
                    // Clean up temp file
                    try? FileManager.default.removeItem(at: photoURL)
                    
                case .multiplePhotos:
                    // Handle multiple photos - create zip first
                    uploadStatus = "Creating photo archive..."
                    
                    let zipURL = try await createPhotoZip(photoURLs: selectedPhotoURLs)
                    
                    // Check for cancellation after zip creation
                    try Task.checkCancellation()
                    
                    link = try await cloudflareService.upload(
                        videoURL: zipURL,
                        fileName: nil,
                        referenceNumber: referenceNumber
                    ) { progress, status in
                        Task { @MainActor in
                            self.uploadProgress = 0.3 + (progress * 0.7) // Zip is 0-30%, upload is 30-100%
                            self.uploadStatus = "📦 \(status)"
                        }
                    }
                    
                    // Clean up temp files
                    try? FileManager.default.removeItem(at: zipURL)
                    for photoURL in selectedPhotoURLs {
                        try? FileManager.default.removeItem(at: photoURL)
                    }
                    
                case .none:
                    throw VideoError.loadFailed
                }
                
                await MainActor.run {
                    self.downloadLink = link
                    self.isUploading = false
                    self.uploadProgress = 0.0
                    self.uploadStatus = ""
                    self.uploadTask = nil
                    
                    // Increment upload count
                    uploadLimitManager.incrementUploadCount()
                    
                    // Success feedback
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }
                
                // Refresh the history from Cloudflare to update badge
                await historyService.refresh()
            } catch is CancellationError {
                await MainActor.run {
                    self.isUploading = false
                    self.uploadProgress = 0.0
                    self.uploadStatus = ""
                    self.uploadTask = nil
                    
                    // Cancelled feedback
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.warning)
                }
            } catch {
                await MainActor.run {
                    self.isUploading = false
                    self.uploadProgress = 0.0
                    self.uploadStatus = ""
                    self.uploadTask = nil
                    self.errorMessage = "Upload failed: \(error.localizedDescription)"
                    self.showError = true
                    
                    // Error feedback
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                }
            }
        }
    }
    
    // Create a ZIP file from multiple photo URLs
    private func createPhotoZip(photoURLs: [URL]) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let zipURL = tempDir.appendingPathComponent("photos_\(UUID().uuidString).zip")
        
        // Remove existing zip if present
        try? FileManager.default.removeItem(at: zipURL)
        
        // Create archive using ZIPFoundation
        guard let archive = Archive(url: zipURL, accessMode: .create) else {
            throw MediaUploadError.zipCreationFailed
        }
        
        // Add each photo to the zip
        for (index, photoURL) in photoURLs.enumerated() {
            let photoName = "photo_\(index + 1).\(photoURL.pathExtension)"
            
            // Add the file directly from its URL
            try archive.addEntry(with: photoName, relativeTo: photoURL.deletingLastPathComponent())
            
            await MainActor.run {
                self.uploadProgress = Double(index + 1) / Double(photoURLs.count) * 0.3
                self.uploadStatus = "Adding photo \(index + 1) of \(photoURLs.count)..."
            }
        }
        
        return zipURL
    }
    
    // Export AVAsset to a file URL
    private func exportAVAssetToFile(asset: AVAsset) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw VideoError.loadFailed
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        
        await exportSession.export()
        
        guard exportSession.status == .completed else {
            throw exportSession.error ?? VideoError.loadFailed
        }
        
        return outputURL
    }
    
    // Cancel the ongoing upload
    private func cancelUpload() {
        uploadTask?.cancel()
        uploadTask = nil
        isUploading = false
        uploadProgress = 0.0
        uploadStatus = ""
        
        // Warning feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
    
    // Share link using system share sheet
    private func shareLink() {
        guard let downloadLink else { return }
        
        let activityVC = UIActivityViewController(
            activityItems: [downloadLink],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            activityVC.popoverPresentationController?.sourceView = window
            rootVC.present(activityVC, animated: true)
        }
    }
    
    // MARK: - Reset Function
    
    // Reset the app to initial state
    private func resetApp() {
        // Cancel any ongoing upload
        uploadTask?.cancel()
        uploadTask = nil
        
        // Stop and clear the player
        player?.pause()
        player = nil
        
        // Clean up temp files
        for photoURL in selectedPhotoURLs {
            try? FileManager.default.removeItem(at: photoURL)
        }
        
        // Clear all state
        videoURL = nil
        videoAsset = nil
        selectedItems = []
        selectedPhotoURLs = []
        photoPreviewImages = []
        mediaType = .none
        downloadLink = nil
        referenceNumber = ""
        originalSize = ""
        estimatedCompressedSize = ""
        isUploading = false
        uploadProgress = 0.0
        uploadStatus = ""
        isLoadingVideo = false
        
        // Reset quality to default
        selectedQuality = .medium
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    // MARK: - Camera Functions
    
    // Open camera for recording
    private func openCamera() async {
        // Check if camera is available
        guard CameraPermissionHelper.isCameraAvailable else {
            return
        }
        
        // Check camera permission
        let hasPermission = await CameraPermissionHelper.checkCameraPermission()
        
        await MainActor.run {
            if hasPermission {
                showCamera = true
            } else {
                showCameraPermissionAlert = true
            }
        }
    }
    
    // Load recorded video
    private func loadRecordedVideo(from url: URL) async {
        await MainActor.run {
            isLoadingVideo = true
            videoURL = nil
            videoAsset = nil
            downloadLink = nil
            referenceNumber = ""
            player = nil
            originalSize = ""
            estimatedCompressedSize = ""
            selectedPhotoURLs = []
            photoPreviewImages = []
        }
        
        do {
            // Get file size
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            
            await MainActor.run {
                let newPlayer = AVPlayer(url: url)
                newPlayer.volume = 1.0
                self.player = newPlayer
                
                self.videoURL = url
                self.mediaType = .video
                self.originalSize = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
                self.isLoadingVideo = false
                updateEstimatedSize()
                
                // Success feedback
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
        } catch {
            await MainActor.run {
                self.isLoadingVideo = false
                errorMessage = "Failed to load recorded video: \(error.localizedDescription)"
                showError = true
            }
        }
    }
}

// Transferable conformance for video loading
struct VideoFile: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            // We need to copy because the received file is in a temporary location
            // that will be cleaned up. However, we'll do this efficiently.
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension)
            
            // Use copyItem which is optimized by the system
            try FileManager.default.copyItem(at: received.file, to: tempURL)
            return VideoFile(url: tempURL)
        }
    }
}

// Custom error types
enum VideoError: LocalizedError {
    case loadFailed
    case uploadFailed
    
    var errorDescription: String? {
        switch self {
        case .loadFailed: return "Could not load the selected video"
        case .uploadFailed: return "Could not upload the video"
        }
    }
}

enum MediaUploadError: LocalizedError {
    case zipCreationFailed
    case noPhotosSelected
    
    var errorDescription: String? {
        switch self {
        case .zipCreationFailed: return "Failed to create photo archive"
        case .noPhotosSelected: return "No photos selected for upload"
        }
    }
}

// MARK: - Reference Number Input View
struct ReferenceNumberView: View {
    @Binding var referenceNumber: String
    @Binding var isPresented: Bool
    @FocusState private var isFocused: Bool
    let onSubmit: () -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Icon
                Image(systemName: "number.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)
                    .padding(.top, 40)
                
                // Instructions
                VStack(spacing: 8) {
                    Text("Enter Reference")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Please enter a reference number for this media (e.g., Registration, Case ID)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Text Field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reference Number")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    TextField("e.g., REG-12345", text: $referenceNumber)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                        .focused($isFocused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .submitLabel(.done)
                        .onSubmit {
                            if !referenceNumber.trimmingCharacters(in: .whitespaces).isEmpty {
                                submit()
                            }
                        }
                }
                .padding(.horizontal, 24)
                
                // Character count
                if !referenceNumber.isEmpty {
                    Text("\(referenceNumber.count) characters")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Submit Button
                Button(action: submit) {
                    Text("Continue Upload")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(referenceNumber.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray : Color.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(referenceNumber.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .navigationTitle("Reference Required")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
        .onAppear {
            // Auto-focus text field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isFocused = true
            }
        }
    }
    
    private func submit() {
        // Trim whitespace
        referenceNumber = referenceNumber.trimmingCharacters(in: .whitespaces)
        
        guard !referenceNumber.isEmpty else { return }
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        // Close sheet and proceed with upload
        isPresented = false
        onSubmit()
    }
}

// MARK: - Instructions View
struct InstructionsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var storeManager = StoreKitManager.shared
    @StateObject private var uploadLimitManager = UploadLimitManager.shared
    @StateObject private var historyService = CloudflareVideoHistoryService.shared
    @State private var showSubscriptionPaywall = false
    @State private var secretTapCount = 0
    @State private var showAllHistoryUnlockedAlert = false
    @State private var isTogglingHistory = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Welcome section
                    VStack(spacing: 12) {
                        ZStack {
                            Image("vmlogo")
                                .resizable()
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                                .onTapGesture {
                                    handleSecretTap()
                                }
                            
                            // Progress indicator - always present but with dynamic trim value
                            RoundedRectangle(cornerRadius: 20)
                                .trim(from: 0, to: max(0, Double(secretTapCount - 2)) / 8.0)
                                .stroke(
                                    LinearGradient(
                                        colors: [.blue, .purple, .pink],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                                )
                                .frame(width: 86, height: 86)
                                .rotationEffect(.degrees(-90))
                                .animation(.spring(response: 0.3), value: secretTapCount)
                        }
                        .frame(width: 86, height: 86)
                         
                        Text("Welcome to Media link")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Share videos easily with automatic compression and cloud storage")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    
                    Divider()
                    
                    // Subscription section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "crown.fill")
                                .font(.title2)
                                .foregroundStyle(storeManager.subscriptionStatus.isActive ? 
                                    LinearGradient(colors: [.orange, .pink], startPoint: .leading, endPoint: .trailing) : 
                                    LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                            
                            Text("Subscription")
                                .font(.title3)
                                .fontWeight(.bold)
                        }
                        
                        if storeManager.subscriptionStatus.isActive {
                            // Already subscribed
                            VStack(spacing: 12) {
                                HStack(spacing: 12) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.title)
                                        .foregroundStyle(.green)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Pro Subscriber")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                        
                                        if case .subscribed(let expirationDate) = storeManager.subscriptionStatus,
                                           let date = expirationDate {
                                            Text("Renews: \(date.formatted(date: .abbreviated, time: .omitted))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } else {
                                            Text("Unlimited uploads")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    
                                    Spacer()
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.green.opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .strokeBorder(Color.green.opacity(0.3), lineWidth: 1)
                                        )
                                )
                                
                                // Manage subscription button
                                Button(action: {
                                    Task {
                                        await storeManager.showManageSubscriptions()
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "gear")
                                        Text("Manage Subscription")
                                    }
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundColor(.blue)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        } else {
                            // Not subscribed - show benefits and subscribe button
                            VStack(spacing: 12) {
                                // Current status
                                HStack(spacing: 12) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.orange)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Free Plan")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                        
                                        Text("\(uploadLimitManager.remainingUploads) of 5 uploads remaining")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.orange.opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
                                        )
                                )
                                
                                // Pro benefits
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Pro Benefits:")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                    
                                    ProBenefitRow(icon: "infinity", text: "Unlimited uploads and link retreivals")
                                  
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.blue.opacity(0.05))
                                )
                                
                                // Subscribe button
                                Button(action: {
                                    showSubscriptionPaywall = true
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "crown.fill")
                                        Text("Subscribe to Pro")
                                        Image(systemName: "arrow.right")
                                    }
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        LinearGradient(
                                            colors: [.blue, .purple],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                   
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Step-by-step instructions
                    VStack(alignment: .leading, spacing: 20) {
                        Text("How to Use")
                            .font(.title3)
                            .fontWeight(.bold)
                        
                        InstructionStep(
                            number: 1,
                            icon: "photo.on.rectangle",
                            title: "Select or Record a Video",
                            description: "Choose a video from your Photos library or tap 'Record Video' to record a new one using your device's camera. You can record videos up to 10 minutes long."
                        )
                        
                        InstructionStep(
                            number: 2,
                            icon: "slider.horizontal.3",
                            title: "Choose Compression Quality",
                            description: "Select your preferred quality:\n• Low: Smallest file size, good for sharing over slow connections\n• Medium: Balanced size and quality (recommended)\n• High: Best quality, larger file size\n• Original: No compression, preserves original quality"
                        )
                        
                        InstructionStep(
                            number: 3,
                            icon: "number.circle",
                            title: "Enter Reference Number",
                            description: "Provide a reference number to help identify your video later. This could be a registration number, case ID, or any identifier you choose."
                        )
                        
                        InstructionStep(
                            number: 4,
                            icon: "arrow.up.circle",
                            title: "Upload Video",
                            description: "Tap 'Upload & Generate Link'. The app will compress your video and upload it to secure cloud storage. This may take a few moments depending on the video size."
                        )
                        
                        InstructionStep(
                            number: 5,
                            icon: "link.circle",
                            title: "Share the Link",
                            description: "Once uploaded, you'll receive a download link. You can copy it to your clipboard or share it directly with others using the share button."
                        )
                    }
                    
                    Divider()
                    
                    // Tips section
                    VStack(alignment: .leading, spacing: 16) {
                        Label {
                            Text("Tips & Best Practices")
                                .font(.title3)
                                .fontWeight(.bold)
                        } icon: {
                            Image(systemName: "lightbulb.fill")
                                .foregroundStyle(.yellow)
                        }
                        
                        TipItem(
                            icon: "wifi",
                            text: "Use Wi-Fi for uploading large videos to save cellular data"
                        )
                        
                        TipItem(
                            icon: "battery.100",
                            text: "Keep your device charged during upload to prevent interruption"
                        )
                        
                        TipItem(
                            icon: "checkmark.circle",
                            text: "Medium quality is recommended for most use cases - it provides good balance between quality and file size"
                        )
                        
                        TipItem(
                            icon: "doc.text",
                            text: "Use clear reference numbers to easily identify your videos later"
                        )
                        
                        TipItem(
                            icon: "clock",
                            text: "Upload times vary based on video size and internet connection speed"
                        )
                    }
                    
                    Divider()
                    
                    // Features section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Features")
                            .font(.title3)
                            .fontWeight(.bold)
                        
                        FeatureItem(
                            icon: "lock.shield.fill",
                            iconColor: .green,
                            title: "Secure Storage",
                            description: "Videos are stored securely in the cloud"
                        )
                        
                        FeatureItem(
                            icon: "arrow.down.circle.fill",
                            iconColor: .blue,
                            title: "Automatic Compression",
                            description: "Videos are compressed to reduce file size while maintaining quality"
                        )
                        
                        FeatureItem(
                            icon: "link.circle.fill",
                            iconColor: .purple,
                            title: "Easy Sharing",
                            description: "Generate shareable links instantly"
                        )
                        
                        FeatureItem(
                            icon: "gauge.with.dots.needle.67percent",
                            iconColor: .orange,
                            title: "Progress Tracking",
                            description: "See real-time progress of compression and upload"
                        )
                    }
                    
                    // Footer
                    Text("If you encounter any issues, please contact support.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, 20)
                }
                .padding(24)
            }
            .navigationTitle("Instructions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showSubscriptionPaywall) {
                SubscriptionPaywallView()
            }
            .alert("History View Updated!", isPresented: $showAllHistoryUnlockedAlert) {
                Button("OK", role: .cancel) {
                    // Haptic feedback
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }
            } message: {
                Text(historyService.showAllDevices ? 
                    "You can now see videos from all devices in your history view." : 
                    "History view now shows only videos uploaded from this device.")
            }
        }
    }
    
    // MARK: - Secret Tap Handler
    
    private func handleSecretTap() {
        secretTapCount += 1
        
        // Only provide haptic feedback after 3 taps
        if secretTapCount >= 3 {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
        
        // Show progress feedback at milestones (only after 3 taps)
        if secretTapCount == 5 || secretTapCount == 7 {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }
        
        // Toggle at 10 taps
        if secretTapCount >= 10 {
            // Prevent multiple simultaneous toggles
            guard !isTogglingHistory else {
                print("⚠️ DEBUG: Toggle already in progress, ignoring tap")
                return
            }
            
            isTogglingHistory = true
            
            Task {
                print("🔓 DEBUG: Toggling history view mode...")
                print("🔓 DEBUG: Before toggle - showAllDevices: \(historyService.showAllDevices)")
                
                await historyService.toggleShowAllDevices()
                
                print("🔓 DEBUG: After toggle - showAllDevices: \(historyService.showAllDevices)")
                print("🔓 DEBUG: Current video count: \(historyService.videos.count)")
                
                await MainActor.run {
                    showAllHistoryUnlockedAlert = true
                    
                    // Animate back to 0
                    withAnimation(.easeOut(duration: 0.3)) {
                        secretTapCount = 0
                    }
                    
                    // Reset the toggle lock
                    isTogglingHistory = false
                }
                
                // Strong haptic feedback for toggle
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
        }
        
        // Reset counter after 3 seconds of no taps (animate it back to 0)
        Task {
            try? await Task.sleep(for: .seconds(3))
            if secretTapCount < 10 && secretTapCount > 0 {
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.5)) {
                        secretTapCount = 0
                    }
                }
            }
        }
    }
}

// MARK: - Instruction Step Component
struct InstructionStep: View {
    let number: Int
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Step number with icon
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 40, height: 40)
                
                Text("\(number)")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(title)
                        .font(.headline)
                } icon: {
                    Image(systemName: icon)
                        .foregroundStyle(.blue)
                }
                
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Tip Item Component
struct TipItem: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.blue)
                .frame(width: 24)
            
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Feature Item Component
struct FeatureItem: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Pro Benefit Row Component
struct ProBenefitRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 20)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

// MARK: - Upload Counter Capsule Component
struct UploadCounterCapsule: View {
    let uploadCount: Int
    let remainingUploads: Int
    let canUpload: Bool
    
    private var totalLimit: Int {
        uploadCount + remainingUploads
    }
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.subheadline)
                .foregroundColor(canUpload ? .blue : .red)
            
            Text("\(uploadCount)/\(totalLimit)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .foregroundColor(canUpload ? .blue : .red)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(canUpload ? Color.blue.opacity(0.1) : Color.red.opacity(0.1))
                .overlay(
                    Capsule()
                        .strokeBorder(
                            canUpload ? Color.blue.opacity(0.3) : Color.red.opacity(0.3),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: (canUpload ? Color.blue : Color.red).opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

#Preview {
    ContentView()
}
