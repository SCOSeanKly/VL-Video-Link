//
//  CloudflareWorkerService.swift
//  VM
//
//  Created by Sean Kelly on 19/11/2025.
//

import Foundation

/// Simplified service that uses Cloudflare Workers for uploads
/// This is easier and more secure than direct R2 access from the app
actor CloudflareWorkerService {
    
    // MARK: - Configuration
    
    // Your Cloudflare Worker URL
    private let workerURL = "https://video-uploader.ske-d03.workers.dev/upload"
    private let listURL = "https://video-uploader.ske-d03.workers.dev/list"
    
    // Optional: Add authentication
    private let apiKey = "sk_a8d9f7b2c4e1x6z3" // Set this in your Worker (generate a random string)
    
    // MARK: - Public Methods
    
    /// Progress callback type
    typealias ProgressCallback = (Double, String) -> Void
    
    /// Uploads a file (video, photo, or zip) via Cloudflare Worker and returns download URL
    func upload(
        videoURL: URL,
        fileName: String? = nil,
        referenceNumber: String? = nil,
        progress: @escaping ProgressCallback
    ) async throws -> String {
        progress(0.0, "Reading file...")
        
        let videoData = try Data(contentsOf: videoURL)
        
        // Get device identifier
        let deviceID = DeviceIdentifierService.shared.shortDeviceIdentifier
        print("🔍 DEBUG: Device ID for upload: \(deviceID)")
        
        let finalFileName: String
        
        if let fileName = fileName, !fileName.isEmpty {
            // Use provided filename and ensure it has extension
            let fileExtension = videoURL.pathExtension.isEmpty ? "mp4" : videoURL.pathExtension
            if fileName.contains(".") {
                // Insert device ID before extension
                let components = fileName.split(separator: ".")
                if components.count > 1 {
                    let nameWithoutExt = components.dropLast().joined(separator: ".")
                    let ext = components.last!
                    finalFileName = "\(nameWithoutExt)_\(deviceID).\(ext)"
                } else {
                    finalFileName = "\(fileName)_\(deviceID).\(fileExtension)"
                }
            } else {
                finalFileName = "\(fileName)_\(deviceID).\(fileExtension)"
            }
        } else {
            // Generate UUID-based name with device ID - use actual file extension
            let fileExtension = videoURL.pathExtension.isEmpty ? "mp4" : videoURL.pathExtension
            finalFileName = "\(UUID().uuidString)_\(deviceID).\(fileExtension)"
        }
        
        print("🔍 DEBUG: Generated filename for upload: \(finalFileName)")
        print("🔍 DEBUG: Reference number: \(referenceNumber ?? "nil")")
        
        progress(0.1, "Preparing upload...")
        
        // Create multipart request
        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: workerURL)!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", 
                        forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        
        let httpBody = createMultipartBody(
            videoData: videoData,
            boundary: boundary,
            fileName: finalFileName,
            referenceNumber: referenceNumber
        )
        
        progress(0.2, "Uploading to server...")
        
        let (responseData, response) = try await URLSession.shared.upload(
            for: request,
            from: httpBody
        )
        
        progress(0.9, "Processing response...")
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw WorkerError.uploadFailed
        }
        
        let result = try JSONDecoder().decode(WorkerResponse.self, from: responseData)
        
        // Log email status for debugging
        if let emailSent = result.emailSent {
            if emailSent {
                print("✅ Email notification sent successfully")
            } else {
                print("❌ Email notification failed")
                if let emailError = result.emailError {
                    print("   Error: \(emailError)")
                }
            }
        } else {
            print("⚠️ No email status in response (old worker version?)")
        }
        
        progress(1.0, "Upload complete!")
        return result.downloadURL
    }
    
    /// Fetches the list of all uploaded videos from Cloudflare R2
    func fetchVideoList() async throws -> [CloudflareVideo] {
        var request = URLRequest(url: URL(string: listURL)!)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        
        let (responseData, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw WorkerError.fetchFailed
        }
        
        let result = try JSONDecoder().decode(VideoListResponse.self, from: responseData)
        return result.videos
    }
    
    /// Deletes a video from Cloudflare R2
    func deleteVideo(fileId: String) async throws {
        let deleteURL = "https://video-uploader.ske-d03.workers.dev/delete/\(fileId)"
        
        var request = URLRequest(url: URL(string: deleteURL)!)
        request.httpMethod = "DELETE"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        
        let (responseData, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            // Try to decode error message
            if let errorResponse = try? JSONDecoder().decode(DeleteErrorResponse.self, from: responseData) {
                throw WorkerError.deleteFailed(message: errorResponse.message)
            }
            throw WorkerError.deleteFailed(message: "Failed to delete video")
        }
        
        let result = try JSONDecoder().decode(DeleteResponse.self, from: responseData)
        print("✅ Successfully deleted video: \(result.fileId)")
    }
    
    // MARK: - Private Methods
    
    private func createMultipartBody(videoData: Data, boundary: String, fileName: String, referenceNumber: String?) -> Data {
        var body = Data()
        
        // Add video file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"video\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: video/quicktime\r\n\r\n".data(using: .utf8)!)
        body.append(videoData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add reference number if provided
        if let referenceNumber = referenceNumber, !referenceNumber.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"reference\"\r\n\r\n".data(using: .utf8)!)
            body.append(referenceNumber.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        // Add device ID
        let deviceID = DeviceIdentifierService.shared.shortDeviceIdentifier
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"deviceId\"\r\n\r\n".data(using: .utf8)!)
        body.append(deviceID.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        return body
    }
}

// MARK: - Response Models

struct WorkerResponse: Codable {
    let downloadURL: String
    let fileId: String
    let expiresAt: String?
    let emailSent: Bool?
    let emailError: String?
    
    enum CodingKeys: String, CodingKey {
        case downloadURL = "download_url"
        case fileId = "file_id"
        case expiresAt = "expires_at"
        case emailSent = "email_sent"
        case emailError = "email_error"
    }
}

struct VideoListResponse: Codable {
    let success: Bool
    let count: Int
    let videos: [CloudflareVideo]
}

struct DeleteResponse: Codable {
    let success: Bool
    let message: String
    let fileId: String
    let deletedAt: String
    
    enum CodingKeys: String, CodingKey {
        case success
        case message
        case fileId = "file_id"
        case deletedAt = "deleted_at"
    }
}

struct DeleteErrorResponse: Codable {
    let error: String
    let message: String
}

struct CloudflareVideo: Codable, Identifiable {
    let fileId: String
    let reference: String
    let downloadURL: String
    let fileSize: Int
    let uploadedAt: String
    let fileName: String
    
    var id: String { fileId }
    
    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case reference
        case downloadURL = "download_url"
        case fileSize = "file_size"
        case uploadedAt = "uploaded_at"
        case fileName = "file_name"
    }
    
    var formattedDate: String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: uploadedAt) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        return uploadedAt
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }
}

// MARK: - Errors

enum WorkerError: LocalizedError {
    case uploadFailed
    case invalidResponse
    case fetchFailed
    case deleteFailed(message: String)
    
    var errorDescription: String? {
        switch self {
        case .uploadFailed:
            return "Failed to upload video to server"
        case .invalidResponse:
            return "Invalid response from server"
        case .fetchFailed:
            return "Failed to fetch video list from server"
        case .deleteFailed(let message):
            return message
        }
    }
}
