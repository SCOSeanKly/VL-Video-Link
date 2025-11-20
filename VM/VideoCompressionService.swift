//
//  VideoCompressionService.swift
//  VM
//
//  Created by Sean Kelly on 19/11/2025.
//

import Foundation
import AVFoundation
import UIKit

/// Service for compressing videos before upload
actor VideoCompressionService {
    
    // MARK: - Compression Quality Presets
    
    enum CompressionQuality {
        case low        // Smallest file, lower quality (good for sharing)
        case medium     // Balanced (recommended)
        case high       // Better quality, larger file
        case original   // No compression, original quality
        
        var videoBitRate: Int {
            switch self {
            case .low: return 1_000_000      // 1 Mbps
            case .medium: return 2_500_000   // 2.5 Mbps
            case .high: return 5_000_000     // 5 Mbps
            case .original: return 15_000_000 // 15 Mbps (high bitrate to preserve quality)
            }
        }
        
        var audioBitRate: Int {
            switch self {
            case .low: return 64_000         // 64 kbps
            case .medium: return 128_000     // 128 kbps
            case .high: return 192_000       // 192 kbps
            case .original: return 256_000   // 256 kbps
            }
        }
        
        var maxDimension: CGFloat {
            switch self {
            case .low: return 720           // 720p
            case .medium: return 1080       // 1080p
            case .high: return 1920         // Full HD
            case .original: return .infinity // No dimension limit
            }
        }
    }
    
    // MARK: - Progress Callback
    
    typealias ProgressCallback = (Double, String) -> Void
    
    // MARK: - Public Methods
    
    /// Compresses a video and returns the URL of the compressed file
    /// - Parameters:
    ///   - sourceURL: Original video URL
    ///   - quality: Compression quality preset
    ///   - progress: Progress callback (0.0 to 1.0, status message)
    func compress(
        videoURL sourceURL: URL,
        quality: CompressionQuality = .medium,
        progress: @escaping ProgressCallback
    ) async throws -> URL {
        
        progress(0.0, "Analyzing video...")
        
        let asset = AVAsset(url: sourceURL)
        
        // Get video track
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw CompressionError.noVideoTrack
        }
        
        // For "original" quality, just copy the file without re-encoding
        if quality == .original {
            progress(0.1, "Preparing original quality...")
            
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
            
            try? FileManager.default.removeItem(at: outputURL)
            
            // Use passthrough preset for original quality
            guard let exportSession = AVAssetExportSession(
                asset: asset,
                presetName: AVAssetExportPresetPassthrough
            ) else {
                throw CompressionError.exportSessionFailed
            }
            
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mp4
            exportSession.shouldOptimizeForNetworkUse = true
            
            progress(0.2, "Exporting original...")
            
            // Monitor progress
            await withCheckedContinuation { continuation in
                let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                    let exportProgress = Double(exportSession.progress)
                    let overallProgress = 0.2 + (exportProgress * 0.7)
                    
                    Task { @MainActor in
                        progress(overallProgress, "Exporting: \(Int(exportProgress * 100))%")
                    }
                    
                    if exportSession.progress >= 1.0 || exportSession.status != .exporting {
                        timer.invalidate()
                    }
                }
                
                exportSession.exportAsynchronously {
                    timer.invalidate()
                    continuation.resume()
                }
            }
            
            progress(0.95, "Finalizing...")
            
            guard exportSession.status == .completed else {
                throw exportSession.error ?? CompressionError.exportFailed
            }
            
            progress(1.0, "Complete!")
            return outputURL
        }
        
        // Get original dimensions and calculate output size
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let outputSize = calculateOutputSize(
            from: naturalSize,
            transform: preferredTransform,
            maxDimension: quality.maxDimension
        )
        
        progress(0.1, "Preparing compression...")
        
        // Create output URL
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        
        // Remove if exists
        try? FileManager.default.removeItem(at: outputURL)
        
        // Use AVAssetWriter for proper custom compression
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        
        // Configure video settings with custom bitrate
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: outputSize.width,
            AVVideoHeightKey: outputSize.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: quality.videoBitRate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 30
            ]
        ]
        
        let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoWriterInput.expectsMediaDataInRealTime = false
        
        // Handle video orientation
        let transform = try await videoTrack.load(.preferredTransform)
        videoWriterInput.transform = transform
        
        writer.add(videoWriterInput)
        
        // Configure audio settings
        var audioWriterInput: AVAssetWriterInput?
        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: quality.audioBitRate
            ]
            
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput.expectsMediaDataInRealTime = false
            writer.add(audioInput)
            audioWriterInput = audioInput
        }
        
        // Start writing
        guard writer.startWriting() else {
            throw CompressionError.exportSessionFailed
        }
        
        writer.startSession(atSourceTime: .zero)
        
        progress(0.2, "Compressing video...")
        
        // Process video
        let videoReader = try AVAssetReader(asset: asset)
        let videoReaderOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            ]
        )
        videoReader.add(videoReaderOutput)
        
        // Process audio
        var audioReader: AVAssetReader?
        var audioReaderOutput: AVAssetReaderTrackOutput?
        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            reader.add(output)
            audioReader = reader
            audioReaderOutput = output
        }
        
        videoReader.startReading()
        audioReader?.startReading()
        
        // Process video samples
        var lastProgress = 0.0
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        
        // Use async continuation to wait for processing to complete
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var videoFinished = false
            var audioFinished = audioWriterInput == nil // If no audio, mark as finished
            
            func checkCompletion() {
                if videoFinished && audioFinished {
                    continuation.resume()
                }
            }
            
            // Process video samples
            videoWriterInput.requestMediaDataWhenReady(on: DispatchQueue(label: "videoQueue")) {
                while videoWriterInput.isReadyForMoreMediaData {
                    // Check reader status
                    if videoReader.status == .failed || videoReader.status == .cancelled {
                        videoWriterInput.markAsFinished()
                        videoFinished = true
                        checkCompletion()
                        return
                    }
                    
                    guard let sampleBuffer = videoReaderOutput.copyNextSampleBuffer() else {
                        videoWriterInput.markAsFinished()
                        videoFinished = true
                        checkCompletion()
                        return
                    }
                    
                    // Update progress
                    let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    let currentSeconds = CMTimeGetSeconds(timestamp)
                    let progressValue = currentSeconds / durationSeconds
                    
                    if progressValue - lastProgress > 0.05 { // Update every 5%
                        lastProgress = progressValue
                        let overallProgress = 0.2 + (progressValue * 0.6) // 20% to 80%
                        Task { @MainActor in
                            progress(overallProgress, "Compressing: \(Int(progressValue * 100))%")
                        }
                    }
                    
                    if !videoWriterInput.append(sampleBuffer) {
                        print("⚠️ Warning: Failed to append video sample")
                    }
                }
            }
            
            // Process audio samples
            if let audioWriterInput = audioWriterInput, let audioReaderOutput = audioReaderOutput, let audioReader = audioReader {
                audioWriterInput.requestMediaDataWhenReady(on: DispatchQueue(label: "audioQueue")) {
                    while audioWriterInput.isReadyForMoreMediaData {
                        // Check reader status
                        if audioReader.status == .failed || audioReader.status == .cancelled {
                            audioWriterInput.markAsFinished()
                            audioFinished = true
                            checkCompletion()
                            return
                        }
                        
                        guard let sampleBuffer = audioReaderOutput.copyNextSampleBuffer() else {
                            audioWriterInput.markAsFinished()
                            audioFinished = true
                            checkCompletion()
                            return
                        }
                        
                     
                    }
                }
            }
        }
        
        progress(0.9, "Finalizing...")
        
        await writer.finishWriting()
        
        guard writer.status == .completed else {
            throw writer.error ?? CompressionError.exportFailed
        }
        
        // Get file sizes for logging
        let originalSize = try? FileManager.default.attributesOfItem(atPath: sourceURL.path)[.size] as? Int64 ?? 0
        let compressedSize = try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64 ?? 0
        
        if let original = originalSize, let compressed = compressedSize {
            let reduction = Int((1.0 - Double(compressed) / Double(original)) * 100)
            print("✅ Compression complete: \(formatFileSize(original)) → \(formatFileSize(compressed)) (\(reduction)% smaller)")
        }
        
        progress(1.0, "Compression complete!")
        return outputURL
    }
    
    // MARK: - Private Methods
    
    private func calculateOutputSize(
        from naturalSize: CGSize,
        transform: CGAffineTransform,
        maxDimension: CGFloat
    ) -> CGSize {
        // Apply transform to get actual display size
        var size = naturalSize.applying(transform)
        size.width = abs(size.width)
        size.height = abs(size.height)
        
        // Calculate scaling
        let maxSize = max(size.width, size.height)
        if maxSize > maxDimension {
            let scale = maxDimension / maxSize
            size.width *= scale
            size.height *= scale
        }
        
        // Round to even numbers (required for H.264)
        size.width = floor(size.width / 2) * 2
        size.height = floor(size.height / 2) * 2
        
        return size
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Errors

enum CompressionError: LocalizedError {
    case noVideoTrack
    case exportSessionFailed
    case exportFailed
    case cancelled
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "Video file has no video track"
        case .exportSessionFailed:
            return "Failed to create video export session"
        case .exportFailed:
            return "Video compression failed"
        case .cancelled:
            return "Compression was cancelled"
        case .unknown:
            return "Unknown compression error"
        }
    }
}
