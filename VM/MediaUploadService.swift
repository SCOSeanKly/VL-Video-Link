//
//  MediaUploadService.swift
//  VM
//
//  Created by Sean Kelly on 21/11/2025.
//

import Foundation
import UIKit
import UniformTypeIdentifiers
import ZIPFoundation

/// Service for uploading videos, single photos, or multiple photos (as zip)
actor MediaUploadService {
    
    // MARK: - Configuration
    
    private let workerURL = "https://video-uploader.ske-d03.workers.dev/upload"
    private let apiKey = "sk_a8d9f7b2c4e1x6z3"
    
    // MARK: - Types
    
    enum MediaType {
        case video
        case singlePhoto
        case multiplePhotos(count: Int)
        
        var description: String {
            switch self {
            case .video:
                return "video"
            case .singlePhoto:
                return "photo"
            case .multiplePhotos(let count):
                return "\(count) photos"
            }
        }
    }
    
    typealias ProgressCallback = (Double, String) -> Void
    
    // MARK: - Public Methods
    
    /// Upload a single video file
    func uploadVideo(
        url: URL,
        fileName: String? = nil,
        referenceNumber: String? = nil,
        progress: @escaping ProgressCallback
    ) async throws -> String {
        progress(0.0, "Reading video file...")
        
        let videoData = try Data(contentsOf: url)
        let finalFileName = generateFileName(
            originalName: fileName,
            originalURL: url,
            mediaType: .video
        )
        
        return try await uploadData(
            data: videoData,
            fileName: finalFileName,
            contentType: "video/quicktime",
            referenceNumber: referenceNumber,
            progress: progress
        )
    }
    
    /// Upload a single photo
    func uploadPhoto(
        url: URL,
        fileName: String? = nil,
        referenceNumber: String? = nil,
        progress: @escaping ProgressCallback
    ) async throws -> String {
        progress(0.0, "Reading photo...")
        
        let photoData = try Data(contentsOf: url)
        let finalFileName = generateFileName(
            originalName: fileName,
            originalURL: url,
            mediaType: .singlePhoto
        )
        
        return try await uploadData(
            data: photoData,
            fileName: finalFileName,
            contentType: "image/jpeg",
            referenceNumber: referenceNumber,
            progress: progress
        )
    }
    
    /// Upload multiple photos as a ZIP file
    func uploadPhotos(
        urls: [URL],
        fileName: String? = nil,
        referenceNumber: String? = nil,
        progress: @escaping ProgressCallback
    ) async throws -> String {
        progress(0.0, "Creating photo archive...")
        
        // Create a temporary directory for the zip
        let tempDir = FileManager.default.temporaryDirectory
        let zipFileName = fileName ?? "photos_\(Date().timeIntervalSince1970)"
        let zipURL = tempDir.appendingPathComponent("\(zipFileName).zip")
        
        // Remove existing zip if present
        try? FileManager.default.removeItem(at: zipURL)
        
        // Create the zip archive
        guard let archive = Archive(url: zipURL, accessMode: .create) else {
            throw MediaServiceError.zipCreationFailed
        }
        
        // Add each photo to the zip
        for (index, photoURL) in urls.enumerated() {
            progress(Double(index) / Double(urls.count) * 0.3, "Adding photo \(index + 1) of \(urls.count)...")
            
            // Use the actual file name from URL
            let fileName = photoURL.lastPathComponent
            
            // Add file directly from its location
            try archive.addEntry(with: fileName, relativeTo: photoURL.deletingLastPathComponent())
        }
        
        progress(0.4, "Finalizing archive...")
        
        // Read the zip data
        let zipData = try Data(contentsOf: zipURL)
        
        // Clean up
        try? FileManager.default.removeItem(at: zipURL)
        
        let finalFileName = generateFileName(
            originalName: fileName,
            originalURL: urls.first,
            mediaType: .multiplePhotos(count: urls.count)
        )
        
        return try await uploadData(
            data: zipData,
            fileName: finalFileName.replacingOccurrences(of: ".jpg", with: ".zip").replacingOccurrences(of: ".jpeg", with: ".zip"),
            contentType: "application/zip",
            referenceNumber: referenceNumber,
            progress: progress
        )
    }
    
    // MARK: - Private Methods
    
    private func uploadData(
        data: Data,
        fileName: String,
        contentType: String,
        referenceNumber: String?,
        progress: @escaping ProgressCallback
    ) async throws -> String {
        let deviceID = DeviceIdentifierService.shared.shortDeviceIdentifier
        
        progress(0.5, "Uploading to server...")
        
        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: workerURL)!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        
        let httpBody = createMultipartBody(
            data: data,
            boundary: boundary,
            fileName: fileName,
            contentType: contentType,
            referenceNumber: referenceNumber,
            deviceID: deviceID
        )
        
        let (responseData, response) = try await URLSession.shared.upload(for: request, from: httpBody)
        
        progress(0.9, "Processing response...")
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw MediaServiceError.uploadFailed
        }
        
        let result = try JSONDecoder().decode(UploadResponse.self, from: responseData)
        
        progress(1.0, "Upload complete!")
        return result.downloadURL
    }
    
    private func generateFileName(
        originalName: String?,
        originalURL: URL?,
        mediaType: MediaType
    ) -> String {
        let deviceID = DeviceIdentifierService.shared.shortDeviceIdentifier
        let timestamp = Int(Date().timeIntervalSince1970)
        
        if let name = originalName, !name.isEmpty {
            let ext = originalURL?.pathExtension ?? defaultExtension(for: mediaType)
            let baseName = name.replacingOccurrences(of: ".\(ext)", with: "")
            return "\(baseName)_\(deviceID)_\(timestamp).\(ext)"
        } else {
            let ext = originalURL?.pathExtension ?? defaultExtension(for: mediaType)
            let prefix = prefix(for: mediaType)
            return "\(prefix)_\(deviceID)_\(timestamp).\(ext)"
        }
    }
    
    private func defaultExtension(for mediaType: MediaType) -> String {
        switch mediaType {
        case .video:
            return "mp4"
        case .singlePhoto:
            return "jpg"
        case .multiplePhotos:
            return "zip"
        }
    }
    
    private func prefix(for mediaType: MediaType) -> String {
        switch mediaType {
        case .video:
            return "video"
        case .singlePhoto:
            return "photo"
        case .multiplePhotos:
            return "photos"
        }
    }
    
    private func createMultipartBody(
        data: Data,
        boundary: String,
        fileName: String,
        contentType: String,
        referenceNumber: String?,
        deviceID: String
    ) -> Data {
        var body = Data()
        
        // Add file data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add reference number if provided
        if let referenceNumber = referenceNumber, !referenceNumber.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"reference\"\r\n\r\n".data(using: .utf8)!)
            body.append(referenceNumber.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        // Add device ID
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"deviceId\"\r\n\r\n".data(using: .utf8)!)
        body.append(deviceID.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        return body
    }
}

// MARK: - Response Models

struct UploadResponse: Codable {
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

// MARK: - Errors
// Note: This file is not currently used in the project.
// The actual upload logic is in CloudflareWorkerService.swift
// and ContentView.swift uses MediaUploadError defined there.

enum MediaServiceError: LocalizedError {
    case uploadFailed
    case invalidResponse
    case zipCreationFailed
    case noPhotosSelected
    
    var errorDescription: String? {
        switch self {
        case .uploadFailed:
            return "Failed to upload media to server"
        case .invalidResponse:
            return "Invalid response from server"
        case .zipCreationFailed:
            return "Failed to create photo archive"
        case .noPhotosSelected:
            return "No photos selected for upload"
        }
    }
}
