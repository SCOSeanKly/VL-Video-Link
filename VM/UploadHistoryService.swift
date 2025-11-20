//
//  UploadHistoryService.swift
//  VM
//
//  Created by Sean Kelly on 20/11/2025.
//

import Foundation
import Combine

/// Model for storing upload history
struct UploadRecord: Codable, Identifiable {
    let id: UUID
    let downloadURL: String
    let referenceNumber: String
    let fileName: String
    let uploadDate: Date
    let fileSize: String
    let quality: String
    
    init(id: UUID = UUID(),
         downloadURL: String,
         referenceNumber: String,
         fileName: String = "Video",
         uploadDate: Date = Date(),
         fileSize: String,
         quality: String) {
        self.id = id
        self.downloadURL = downloadURL
        self.referenceNumber = referenceNumber
        self.fileName = fileName
        self.uploadDate = uploadDate
        self.fileSize = fileSize
        self.quality = quality
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: uploadDate)
    }
}

/// Service for managing upload history using UserDefaults
class UploadHistoryService: ObservableObject {
    static let shared = UploadHistoryService()
    
    @Published private(set) var uploads: [UploadRecord] = []
    
    private let storageKey = "uploadHistory"
    private let maxRecords = 100 // Keep last 100 uploads
    
    private init() {
        loadUploads()
    }
    
    /// Add a new upload record
    func addUpload(_ record: UploadRecord) {
        uploads.insert(record, at: 0) // Add to beginning
        
        // Limit to maxRecords
        if uploads.count > maxRecords {
            uploads = Array(uploads.prefix(maxRecords))
        }
        
        saveUploads()
    }
    
    /// Delete an upload record
    func deleteUpload(at offsets: IndexSet) {
        // Manually remove items at specified offsets
        var newUploads = uploads
        for offset in offsets.sorted().reversed() {
            newUploads.remove(at: offset)
        }
        uploads = newUploads
        saveUploads()
    }
    
    /// Delete a specific upload by ID
    func deleteUpload(_ record: UploadRecord) {
        uploads.removeAll { $0.id == record.id }
        saveUploads()
    }
    
    /// Clear all history
    func clearAll() {
        uploads.removeAll()
        saveUploads()
    }
    
    /// Search uploads by reference number
    func search(query: String) -> [UploadRecord] {
        guard !query.isEmpty else { return uploads }
        
        let lowercasedQuery = query.lowercased()
        return uploads.filter {
            $0.referenceNumber.lowercased().contains(lowercasedQuery) ||
            $0.fileName.lowercased().contains(lowercasedQuery)
        }
    }
    
    // MARK: - Private Methods
    
    private func loadUploads() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            uploads = []
            return
        }
        
        do {
            uploads = try JSONDecoder().decode([UploadRecord].self, from: data)
        } catch {
            print("Failed to decode uploads: \(error)")
            uploads = []
        }
    }
    
    private func saveUploads() {
        do {
            let data = try JSONEncoder().encode(uploads)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("Failed to save uploads: \(error)")
        }
    }
}
