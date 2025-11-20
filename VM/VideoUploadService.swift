//
//  VideoUploadService.swift
//  VM
//
//  Created by Sean Kelly on 19/11/2025.
//

import Foundation

/// Service for uploading videos and generating download links
/// Choose one of the backend options below and implement accordingly
actor VideoUploadService {
    
    // MARK: - Configuration
    
    // TODO: Set your upload endpoint here
    private let uploadEndpoint = "YOUR_UPLOAD_ENDPOINT_HERE"
    
    // MARK: - Public Methods
    
    /// Uploads a video file and returns a shareable download URL
    func upload(videoURL: URL) async throws -> String {
        let data = try Data(contentsOf: videoURL)
        let boundary = UUID().uuidString
        
        var request = URLRequest(url: URL(string: uploadEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        let httpBody = createMultipartBody(
            videoData: data,
            boundary: boundary,
            fileName: videoURL.lastPathComponent
        )
        
        let (responseData, response) = try await URLSession.shared.upload(
            for: request,
            from: httpBody
        )
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw UploadError.serverError
        }
        
        let result = try JSONDecoder().decode(UploadResponse.self, from: responseData)
        return result.downloadURL
    }
    
    // MARK: - Private Methods
    
    private func createMultipartBody(videoData: Data, boundary: String, fileName: String) -> Data {
        var body = Data()
        
        // Add video file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"video\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: video/quicktime\r\n\r\n".data(using: .utf8)!)
        body.append(videoData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        return body
    }
}

// MARK: - Response Model

struct UploadResponse: Codable {
    let downloadURL: String
    let fileId: String?
    let expiresAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case downloadURL = "download_url"
        case fileId = "file_id"
        case expiresAt = "expires_at"
    }
}

// MARK: - Errors

enum UploadError: LocalizedError {
    case serverError
    case invalidResponse
    case fileTooBig
    
    var errorDescription: String? {
        switch self {
        case .serverError:
            return "Server error occurred during upload"
        case .invalidResponse:
            return "Invalid response from server"
        case .fileTooBig:
            return "Video file is too large to upload"
        }
    }
}

// MARK: - Backend Implementation Examples

/*
 
 OPTION 1: Firebase Storage
 ---------------------------
 1. Add Firebase SDK: https://firebase.google.com/docs/ios/setup
 2. Install: `FirebaseStorage` package
 3. Implementation:
 
 import FirebaseStorage
 
 func uploadToFirebase(videoURL: URL) async throws -> String {
     let storage = Storage.storage()
     let storageRef = storage.reference()
     let videoRef = storageRef.child("videos/\(UUID().uuidString).mov")
     
     let metadata = StorageMetadata()
     metadata.contentType = "video/quicktime"
     
     _ = try await videoRef.putFileAsync(from: videoURL, metadata: metadata)
     let downloadURL = try await videoRef.downloadURL()
     
     return downloadURL.absoluteString
 }
 
 
 OPTION 2: AWS S3 with Presigned URLs
 -------------------------------------
 1. Add AWS SDK: https://aws.amazon.com/sdk-for-swift/
 2. Install: `AWSS3` package
 3. Implementation:
 
 import AWSS3
 
 func uploadToS3(videoURL: URL) async throws -> String {
     let s3Client = try S3Client(region: "us-east-1")
     let bucketName = "your-bucket-name"
     let key = "videos/\(UUID().uuidString).mov"
     
     let fileData = try Data(contentsOf: videoURL)
     
     let putObjectRequest = PutObjectInput(
         body: .data(fileData),
         bucket: bucketName,
         key: key,
         contentType: "video/quicktime"
     )
     
     _ = try await s3Client.putObject(input: putObjectRequest)
     
     return "https://\(bucketName).s3.amazonaws.com/\(key)"
 }
 
 
 OPTION 3: Cloudinary
 --------------------
 1. Sign up at https://cloudinary.com
 2. Get your cloud name, API key, and secret
 3. Implementation:
 
 func uploadToCloudinary(videoURL: URL) async throws -> String {
     let cloudName = "your_cloud_name"
     let uploadPreset = "your_upload_preset"
     
     let url = URL(string: "https://api.cloudinary.com/v1_1/\(cloudName)/video/upload")!
     let boundary = UUID().uuidString
     
     var request = URLRequest(url: url)
     request.httpMethod = "POST"
     request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
     
     let videoData = try Data(contentsOf: videoURL)
     var body = Data()
     
     // Add upload preset
     body.append("--\(boundary)\r\n".data(using: .utf8)!)
     body.append("Content-Disposition: form-data; name=\"upload_preset\"\r\n\r\n".data(using: .utf8)!)
     body.append("\(uploadPreset)\r\n".data(using: .utf8)!)
     
     // Add video file
     body.append("--\(boundary)\r\n".data(using: .utf8)!)
     body.append("Content-Disposition: form-data; name=\"file\"; filename=\"video.mov\"\r\n".data(using: .utf8)!)
     body.append("Content-Type: video/quicktime\r\n\r\n".data(using: .utf8)!)
     body.append(videoData)
     body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
     
     let (data, response) = try await URLSession.shared.upload(for: request, from: body)
     
     guard let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode == 200 else {
         throw UploadError.serverError
     }
     
     let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
     return json["secure_url"] as! String
 }
 
 
 OPTION 4: Your Own Server
 --------------------------
 If you have your own backend, create an endpoint that:
 1. Accepts multipart/form-data POST requests
 2. Saves the video file to storage
 3. Returns a JSON response with the download URL
 
 Example response:
 {
   "download_url": "https://yourserver.com/videos/abc123.mov",
   "file_id": "abc123",
   "expires_at": "2025-12-19T00:00:00Z"
 }
 
 */
