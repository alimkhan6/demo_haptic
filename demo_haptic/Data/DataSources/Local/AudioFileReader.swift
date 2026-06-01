import Foundation
import AVFoundation
import Accelerate

// MARK: - Audio File Reader

/// Reads audio files and converts them to Float32 PCM mono samples at 44100 Hz
final class AudioFileReader: AudioFileReaderProtocol {
    
    // MARK: - Public Types
    
    struct AudioData {
        let samples: [Float]        // Mono PCM samples
        let sampleRate: Double      // Always 44100
        let duration: Double        // Duration in seconds
    }
    
    enum ReaderError: LocalizedError {
        case assetLoadFailed
        case noAudioTrack
        case readerSetupFailed
        case readingFailed(underlying: Error?)
        
        var errorDescription: String? {
            switch self {
            case .assetLoadFailed:
                return "Failed to load audio asset"
            case .noAudioTrack:
                return "No audio track found in file"
            case .readerSetupFailed:
                return "Failed to setup audio reader"
            case .readingFailed(let error):
                return "Failed to read audio data: \(error?.localizedDescription ?? "unknown error")"
            }
        }
    }
    
    // MARK: - Properties
    
    private let targetSampleRate: Double = 44100.0
    
    // MARK: - Public Methods
    
    /// Read audio file and extract PCM samples
    /// - Parameters:
    ///   - url: URL to audio file (local or remote)
    ///   - progressHandler: Called periodically with progress (0.0-1.0)
    /// - Returns: AudioData containing samples, sample rate, and duration
    func readAudio(
        from url: URL,
        progressHandler: @escaping (Float) -> Void
    ) async throws -> AudioData {
        print("🎵 [AudioFileReader] Starting to read audio from: \(url.path)")
        print("🎵 [AudioFileReader] File exists: \(FileManager.default.fileExists(atPath: url.path))")
        
        // Load asset
        let asset = AVURLAsset(url: url)
        print("🎵 [AudioFileReader] AVURLAsset created")
        
        // Load tracks
        do {
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            print("🎵 [AudioFileReader] Found \(tracks.count) audio track(s)")
            
            guard let audioTrack = tracks.first else {
                print("❌ [AudioFileReader] No audio track found")
                throw ReaderError.noAudioTrack
            }
            
            // Get duration
            let duration = try await asset.load(.duration).seconds
            print("🎵 [AudioFileReader] Audio duration: \(duration) seconds")
            
            // Setup reader
            let reader: AVAssetReader
            do {
                reader = try AVAssetReader(asset: asset)
                print("🎵 [AudioFileReader] AVAssetReader created successfully")
            } catch {
                print("❌ [AudioFileReader] Failed to create AVAssetReader: \(error.localizedDescription)")
                throw ReaderError.readerSetupFailed
            }
            
            return try await continueReading(reader: reader, audioTrack: audioTrack, duration: duration, progressHandler: progressHandler)
        } catch {
            print("❌ [AudioFileReader] Failed to load asset: \(error.localizedDescription)")
            throw ReaderError.assetLoadFailed
        }
    }
    
    private func continueReading(
        reader: AVAssetReader,
        audioTrack: AVAssetTrack,
        duration: Double,
        progressHandler: @escaping (Float) -> Void
    ) async throws -> AudioData {
        
        // Configure output settings: Float32 PCM
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: targetSampleRate
        ]
        
        let readerOutput = AVAssetReaderTrackOutput(
            track: audioTrack,
            outputSettings: outputSettings
        )
        
        reader.add(readerOutput)
        print("🎵 [AudioFileReader] Reader output configured")
        
        // Start reading
        guard reader.startReading() else {
            print("❌ [AudioFileReader] Failed to start reading. Error: \(reader.error?.localizedDescription ?? "unknown")")
            throw ReaderError.readingFailed(underlying: reader.error)
        }
        
        print("🎵 [AudioFileReader] Started reading audio data...")
        
        // Read all samples
        var allSamples: [Float] = []
        let estimatedSampleCount = Int(duration * targetSampleRate)
        allSamples.reserveCapacity(estimatedSampleCount)
        
        var lastProgressReport: Float = 0.0
        
        while reader.status == .reading {
            guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else {
                break
            }
            
            // Extract samples from buffer
            let samples = extractSamples(from: sampleBuffer)
            allSamples.append(contentsOf: samples)
            
            // Report progress every 5%
            let currentProgress = Float(allSamples.count) / Float(estimatedSampleCount)
            if currentProgress - lastProgressReport >= 0.05 || currentProgress >= 1.0 {
                progressHandler(min(currentProgress, 1.0))
                lastProgressReport = currentProgress
            }
        }
        
        // Check final status
        if reader.status == .failed {
            print("❌ [AudioFileReader] Reader failed: \(reader.error?.localizedDescription ?? "unknown")")
            throw ReaderError.readingFailed(underlying: reader.error)
        }
        
        print("✅ [AudioFileReader] Successfully read \(allSamples.count) samples")
        
        // Final progress
        progressHandler(1.0)
        
        return AudioData(
            samples: allSamples,
            sampleRate: targetSampleRate,
            duration: duration
        )
    }
    
    // MARK: - Private Methods
    
    /// Extract Float32 PCM samples from CMSampleBuffer
    /// Converts stereo to mono by averaging channels
    private func extractSamples(from sampleBuffer: CMSampleBuffer) -> [Float] {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return []
        }
        
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        )
        
        guard status == kCMBlockBufferNoErr,
              let data = dataPointer else {
            return []
        }
        
        // Get format description
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return []
        }
        
        let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        guard let asbd = audioStreamBasicDescription?.pointee else {
            return []
        }
        
        let channelCount = Int(asbd.mChannelsPerFrame)
        let floatPointer = data.withMemoryRebound(to: Float.self, capacity: length / MemoryLayout<Float>.stride) { $0 }
        let sampleCount = length / MemoryLayout<Float>.stride
        
        // Convert to mono if needed
        if channelCount == 1 {
            // Already mono
            return Array(UnsafeBufferPointer(start: floatPointer, count: sampleCount))
        } else if channelCount == 2 {
            // Stereo to mono: average L and R channels
            return convertStereoToMono(
                stereoSamples: floatPointer,
                frameCount: sampleCount / 2
            )
        } else {
            // Multi-channel: average all channels
            return convertMultiChannelToMono(
                samples: floatPointer,
                frameCount: sampleCount / channelCount,
                channelCount: channelCount
            )
        }
    }
    
    /// Convert stereo samples to mono using vDSP (SIMD accelerated)
    /// Formula: mono[i] = (left[i] + right[i]) / 2
    private func convertStereoToMono(
        stereoSamples: UnsafePointer<Float>,
        frameCount: Int
    ) -> [Float] {
        var monoSamples = [Float](repeating: 0, count: frameCount)
        
        // Deinterleave stereo samples manually (simpler and correct)
        for i in 0..<frameCount {
            let left = stereoSamples[i * 2]
            let right = stereoSamples[i * 2 + 1]
            monoSamples[i] = (left + right) / 2.0
        }
        
        return monoSamples
    }
    
    /// Convert multi-channel audio to mono by averaging all channels
    private func convertMultiChannelToMono(
        samples: UnsafePointer<Float>,
        frameCount: Int,
        channelCount: Int
    ) -> [Float] {
        var monoSamples = [Float](repeating: 0, count: frameCount)
        let scale = 1.0 / Float(channelCount)
        
        // Sum all channels manually
        for frame in 0..<frameCount {
            var sum: Float = 0.0
            for channel in 0..<channelCount {
                sum += samples[frame * channelCount + channel]
            }
            monoSamples[frame] = sum
        }
        
        // Scale by 1/channelCount
        vDSP_vsmul(
            monoSamples, 1,
            [scale],
            &monoSamples, 1,
            vDSP_Length(frameCount)
        )
        
        return monoSamples
    }
}
