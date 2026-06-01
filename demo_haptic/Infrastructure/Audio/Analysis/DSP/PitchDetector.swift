//
//  PitchDetector.swift
//  haptico
//
//  Detects pitch using YIN algorithm with median filtering
//

import Foundation
import Accelerate

// MARK: - Pitch Detector

/// Detects predominant pitch using YIN algorithm
/// Range: 80-1200 Hz, with median filtering to remove octave errors
final class PitchDetector: PitchDetectorProtocol {
    
    // MARK: - Configuration
    
    private let frameSize: Int = 2048  // Larger frame for pitch accuracy
    private let hopSize: Int = 2048    // Process every 4th FFT frame (512 * 4)
    private let yinThreshold: Float = 0.1
    private let frequencyRange: ClosedRange<Float> = 80.0...1200.0
    private let medianFilterWindow: Int = 5  // Remove octave errors
    
    // MARK: - Public Methods
    
    /// Detect pitch from audio samples
    /// - Parameters:
    ///   - samples: Input audio samples
    ///   - sampleRate: Sample rate of audio
    /// - Returns: Array of PitchPoint with time and frequency
    func detectPitch(samples: [Float], sampleRate: Double) -> [PitchPoint] {
        guard !samples.isEmpty else { return [] }
        
        var pitchPoints: [PitchPoint] = []
        let frameCount = (samples.count - frameSize) / hopSize + 1
        pitchPoints.reserveCapacity(frameCount)
        
        // Process frames
        for frameIndex in 0..<frameCount {
            let startIndex = frameIndex * hopSize
            let endIndex = min(startIndex + frameSize, samples.count)
            
            guard endIndex - startIndex == frameSize else {
                break
            }
            
            let frame = Array(samples[startIndex..<endIndex])
            let frequency = detectPitchInFrame(frame: frame, sampleRate: sampleRate)
            
            let time = Double(startIndex + frameSize / 2) / sampleRate
            pitchPoints.append(PitchPoint(time: time, frequency: frequency))
        }
        
        // Apply median filter to remove octave errors
        let filteredPoints = applyMedianFilter(pitchPoints: pitchPoints)
        
        return filteredPoints
    }
    
    /// Detect pitch from audio samples with progress reporting
    /// - Parameters:
    ///   - samples: Input audio samples
    ///   - sampleRate: Sample rate of audio
    ///   - chunkSize: Number of frames to process per chunk (default 20)
    ///   - progressHandler: Progress callback (0.0 to 1.0)
    /// - Returns: Array of PitchPoint with time and frequency
    func detectPitchWithProgress(
        samples: [Float],
        sampleRate: Double,
        chunkSize: Int = 20,
        progressHandler: @escaping (Double) -> Void
    ) async -> [PitchPoint] {
        guard !samples.isEmpty else { return [] }
        
        var pitchPoints: [PitchPoint] = []
        let frameCount = (samples.count - frameSize) / hopSize + 1
        pitchPoints.reserveCapacity(frameCount)
        
        progressHandler(0.0)
        
        print("🎵 [PitchDetector] Starting pitch detection for \(frameCount) frames")
        
        // Process frames in chunks
        for chunkStart in stride(from: 0, to: frameCount, by: chunkSize) {
            let chunkEnd = min(chunkStart + chunkSize, frameCount)
            
            // Process chunk
            for frameIndex in chunkStart..<chunkEnd {
                let startIndex = frameIndex * hopSize
                let endIndex = min(startIndex + frameSize, samples.count)
                
                guard endIndex - startIndex == frameSize else {
                    break
                }
                
                let frame = Array(samples[startIndex..<endIndex])
                let frequency = detectPitchInFrame(frame: frame, sampleRate: sampleRate)
                
                let time = Double(startIndex + frameSize / 2) / sampleRate
                pitchPoints.append(PitchPoint(time: time, frequency: frequency))
            }
            
            // Report progress more frequently
            let progress = Double(chunkEnd) / Double(frameCount)
            progressHandler(progress * 0.9)  // 0-90% for detection
            
            if chunkStart % 40 == 0 {  // Log every 2 chunks
                print("🎵 [PitchDetector] Progress: \(Int(progress * 100))% (\(chunkEnd)/\(frameCount) frames)")
            }
            
            await Task.yield()
        }
        
        print("🎵 [PitchDetector] Applying median filter...")
        
        // Apply median filter to remove octave errors (last 10%)
        progressHandler(0.9)
        let filteredPoints = applyMedianFilter(pitchPoints: pitchPoints)
        progressHandler(1.0)
        
        print("🎵 [PitchDetector] Pitch detection complete!")
        
        return filteredPoints
    }
    
    // MARK: - YIN Algorithm
    
    /// Detect pitch in single frame using YIN
    private func detectPitchInFrame(frame: [Float], sampleRate: Double) -> Float {
        // Calculate lag range from frequency range
        let minLag = Int(sampleRate / Double(frequencyRange.upperBound))
        let maxLag = Int(sampleRate / Double(frequencyRange.lowerBound))
        
        // Step 1: Calculate difference function
        let difference = calculateDifferenceFunction(frame: frame, maxLag: maxLag)
        
        // Step 2: Calculate cumulative mean normalized difference
        let cmndf = calculateCMNDF(difference: difference)
        
        // Step 3: Absolute threshold to find minimum
        guard let lagEstimate = findAbsoluteMinimum(
            cmndf: cmndf,
            threshold: yinThreshold,
            minLag: minLag,
            maxLag: maxLag
        ) else {
            return 0.0  // No pitch detected
        }
        
        // Step 4: Parabolic interpolation for sub-sample accuracy
        let refinedLag = parabolicInterpolation(
            cmndf: cmndf,
            lag: lagEstimate
        )
        
        // Convert lag to frequency
        let frequency = Float(sampleRate) / refinedLag
        
        // Validate frequency is in range
        if frequencyRange.contains(frequency) {
            return frequency
        } else {
            return 0.0
        }
    }
    
    /// Calculate difference function efficiently using vDSP
    /// d(tau) = 2*energy - 2*autocorrelation(tau)
    private func calculateDifferenceFunction(frame: [Float], maxLag: Int) -> [Float] {
        let count = frame.count
        var difference = [Float](repeating: 0, count: maxLag)
        
        // Calculate energy (sum of squares)
        var energy: Float = 0.0
        vDSP_svesq(frame, 1, &energy, vDSP_Length(count))
        
        // Calculate autocorrelation directly without intermediate arrays
        frame.withUnsafeBufferPointer { framePtr in
            for tau in 0..<min(maxLag, count) {
                var autocorr: Float = 0.0
                
                // Use pointer arithmetic to avoid array copies
                let length = count - tau
                vDSP_dotpr(
                    framePtr.baseAddress!, 1,
                    framePtr.baseAddress! + tau, 1,
                    &autocorr,
                    vDSP_Length(length)
                )
                
                // d(tau) = 2*energy - 2*autocorr(tau)
                difference[tau] = 2.0 * energy - 2.0 * autocorr
            }
        }
        
        // First value should be 0
        difference[0] = 0.0
        
        return difference
    }
    
    /// Calculate Cumulative Mean Normalized Difference Function
    /// cmndf(tau) = d(tau) / [(1/tau) * sum(d(j)) for j=1 to tau]
    private func calculateCMNDF(difference: [Float]) -> [Float] {
        var cmndf = [Float](repeating: 0, count: difference.count)
        var cumulativeSum: Float = 0.0
        
        cmndf[0] = 1.0  // Special case
        
        for tau in 1..<difference.count {
            cumulativeSum += difference[tau]
            
            if cumulativeSum > 0 {
                cmndf[tau] = difference[tau] * Float(tau) / cumulativeSum
            } else {
                cmndf[tau] = 1.0
            }
        }
        
        return cmndf
    }
    
    /// Find absolute minimum below threshold
    private func findAbsoluteMinimum(
        cmndf: [Float],
        threshold: Float,
        minLag: Int,
        maxLag: Int
    ) -> Int? {
        // Search for first value below threshold
        for tau in minLag..<min(maxLag, cmndf.count) {
            if cmndf[tau] < threshold {
                // Find local minimum after this point
                var minValue = cmndf[tau]
                var minIndex = tau
                
                for t in (tau + 1)..<min(maxLag, cmndf.count) {
                    if cmndf[t] < minValue {
                        minValue = cmndf[t]
                        minIndex = t
                    } else if cmndf[t] > minValue {
                        // Found local minimum
                        break
                    }
                }
                
                return minIndex
            }
        }
        
        return nil
    }
    
    /// Parabolic interpolation for sub-sample accuracy
    /// Fits parabola through 3 points to find true minimum
    private func parabolicInterpolation(cmndf: [Float], lag: Int) -> Float {
        guard lag > 0 && lag < cmndf.count - 1 else {
            return Float(lag)
        }
        
        let alpha = cmndf[lag - 1]
        let beta = cmndf[lag]
        let gamma = cmndf[lag + 1]
        
        // Parabolic peak interpolation formula
        let peak = 0.5 * (alpha - gamma) / (alpha - 2.0 * beta + gamma)
        
        return Float(lag) + peak
    }
    
    // MARK: - Median Filter
    
    /// Apply median filter to remove octave errors
    private func applyMedianFilter(pitchPoints: [PitchPoint]) -> [PitchPoint] {
        guard pitchPoints.count > medianFilterWindow else {
            return pitchPoints
        }
        
        var filtered: [PitchPoint] = []
        let halfWindow = medianFilterWindow / 2
        
        for i in 0..<pitchPoints.count {
            let windowStart = max(0, i - halfWindow)
            let windowEnd = min(pitchPoints.count, i + halfWindow + 1)
            
            let window = Array(pitchPoints[windowStart..<windowEnd].map { $0.frequency })
            let medianFreq = calculateMedian(values: window)
            
            filtered.append(PitchPoint(
                time: pitchPoints[i].time,
                frequency: medianFreq
            ))
        }
        
        return filtered
    }
    
    /// Calculate median of array
    private func calculateMedian(values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        
        let sorted = values.sorted()
        let mid = sorted.count / 2
        
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2.0
        } else {
            return sorted[mid]
        }
    }
}
