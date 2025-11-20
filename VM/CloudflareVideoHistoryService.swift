//
//  CloudflareVideoHistoryService.swift
//  VM
//
//  Created by Sean Kelly on 20/11/2025.
//

import Foundation
import Combine

/// Service for fetching video history from Cloudflare R2 (server-side)
@MainActor
class CloudflareVideoHistoryService: ObservableObject {
    static let shared = CloudflareVideoHistoryService()
    
    @Published private(set) var videos: [CloudflareVideo] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var showAllDevices = false // Toggle to show all videos or just this device
    
    private let cloudflareService = CloudflareWorkerService()
    private let deviceID = DeviceIdentifierService.shared.shortDeviceIdentifier
    
    private init() {}
    
    /// Fetch videos from Cloudflare
    func fetchVideos() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let fetchedVideos = try await cloudflareService.fetchVideoList()
            
            print("🔍 DEBUG: Current device ID: \(deviceID)")
            print("🔍 DEBUG: Fetched \(fetchedVideos.count) total videos from server")
            
            // Debug: Print all fetched filenames
            if !fetchedVideos.isEmpty {
                print("🔍 DEBUG: All filenames from server:")
                for video in fetchedVideos {
                    print("   - \(video.fileName)")
                }
            }
            
            // Filter by device ID unless showAllDevices is enabled
            if showAllDevices {
                self.videos = fetchedVideos
                print("✅ Fetched \(fetchedVideos.count) videos from Cloudflare (all devices)")
            } else {
                let filtered = fetchedVideos.filter { video in
                    let matches = video.fileName.contains("_\(deviceID)")
                    print("🔍 DEBUG: Checking '\(video.fileName)' for '_\(deviceID)': \(matches)")
                    return matches
                }
                self.videos = filtered
                print("✅ Filtered to \(self.videos.count) videos for this device (ID: \(deviceID))")
                
                if filtered.isEmpty && !fetchedVideos.isEmpty {
                    print("⚠️ WARNING: No videos matched device ID. This might mean:")
                    print("   1. Videos were uploaded before device ID feature was added")
                    print("   2. Device ID format in filename doesn't match expected pattern")
                    print("   3. You need to unlock 'Show All Devices' mode")
                }
            }
        } catch {
            self.errorMessage = "Failed to load videos: \(error.localizedDescription)"
            print("❌ Failed to fetch videos: \(error)")
        }
        
        isLoading = false
    }
    
    /// Refresh videos (alias for fetchVideos for clarity)
    func refresh() async {
        await fetchVideos()
    }
    
    /// Delete a video from Cloudflare R2
    func deleteVideo(_ video: CloudflareVideo) async throws {
        isLoading = true
        errorMessage = nil
        
        do {
            try await cloudflareService.deleteVideo(fileId: video.fileId)
            
            // Remove from local array
            videos.removeAll { $0.id == video.id }
            
            print("✅ Deleted video: \(video.fileName)")
        } catch {
            errorMessage = "Failed to delete video: \(error.localizedDescription)"
            print("❌ Failed to delete video: \(error)")
            throw error
        }
        
        isLoading = false
    }
    
    /// Search videos by reference or filename
    func search(query: String) -> [CloudflareVideo] {
        guard !query.isEmpty else { return videos }
        
        let lowercasedQuery = query.lowercased()
        return videos.filter {
            $0.reference.lowercased().contains(lowercasedQuery) ||
            $0.fileName.lowercased().contains(lowercasedQuery)
        }
    }
    
    /// Toggle between showing all devices or just this device
    func toggleShowAllDevices() async {
        showAllDevices.toggle()
        await fetchVideos()
    }
    
    /// Get the current device identifier for display
    var currentDeviceID: String {
        deviceID
    }
}
