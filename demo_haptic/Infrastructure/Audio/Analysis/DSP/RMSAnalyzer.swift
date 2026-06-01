//
//  RMSAnalyzer.swift
//  haptico
//
//  Computes RMS (Root Mean Square) energy with smoothing and percentile normalization
//

import Foundation
import Accelerate

// MARK: - RMS Analyzer

/// Analyzes RMS energy of audio signal with smoothing and normalization
final class RMSAnalyzer: RMSAnalyzerProtocol {
    
    // MARK: - Configuration
    
    private let frameSize: Int = 1024
    private let hopSize: Int = 512
    private let smoothingWindow: Int = 5     // Moving average window size
    private let normalizationPercentile: Float = 0.95  // Use 95th percentile as max
    
    // MARK: - Public Methods
    
    /// Analyze RMS energy of audio samples
    /// - Parameters:
    ///   - samples: Input audio samples
    ///   - sampleRate: Sample rate of audio
    /// - Returns: Array of RMSPoint with time and normalized RMS values
    func analyze(samples: [Float], sampleRate: Double) async -> [RMSPoint] {
        guard !samples.isEmpty else { return [] }
        
        // Step 1: Calculate RMS for each frame
        let rawRMS = calculateFrameRMS(samples: samples)
        
        // Step 2: Apply smoothing (moving average)
        let smoothedRMS = applySmoothingWindow(values: rawRMS)
        
        // Step 3: Normalize using 95th percentile
        let normalizedRMS = normalizeByPercentile(values: smoothedRMS)
        
        // Step 4: Create time-stamped points
        let timeStep = Double(hopSize) / sampleRate
        return normalizedRMS.enumerated().map { index, value in
            RMSPoint(time: Double(index) * timeStep, value: value)
        }
    }
    
    // MARK: - Private Methods
    
    /// Calculate RMS value for each frame using vDSP_rmsqv
    private func calculateFrameRMS(samples: [Float]) -> [Float] {
        var rmsValues: [Float] = []
        let frameCount = (samples.count - frameSize) / hopSize + 1
        rmsValues.reserveCapacity(frameCount)
        
        for frameIndex in 0..<frameCount {
            let startIndex = frameIndex * hopSize
            let endIndex = min(startIndex + frameSize, samples.count)
            
            guard endIndex - startIndex == frameSize else {
                // Skip incomplete last frame
                break
            }
            
            // Calculate RMS using vDSP
            var rms: Float = 0.0
            samples.withUnsafeBufferPointer { buffer in
                let framePointer = buffer.baseAddress! + startIndex
                vDSP_rmsqv(
                    framePointer, 1,
                    &rms,
                    vDSP_Length(frameSize)
                )
            }
            
            rmsValues.append(rms)
        }
        
        return rmsValues
    }
    
    /// Apply moving average smoothing using vDSP_vma
    /// Formula: smoothed[i] = mean(raw[i-2], raw[i-1], raw[i], raw[i+1], raw[i+2])
    private func applySmoothingWindow(values: [Float]) -> [Float] {
        guard values.count > smoothingWindow else {
            return values
        }
        
        var smoothed = [Float](repeating: 0, count: values.count)
        let halfWindow = smoothingWindow / 2
        
        // Handle edges: copy original values
        for i in 0..<halfWindow {
            smoothed[i] = values[i]
        }
        for i in (values.count - halfWindow)..<values.count {
            smoothed[i] = values[i]
        }
        
        // Apply moving average to middle section
        // vDSP_vma computes: C[i] = A[i] * B[i] + C[i]
        // We'll use manual averaging for clarity and correctness
        let scale = 1.0 / Float(smoothingWindow)
        
        for i in halfWindow..<(values.count - halfWindow) {
            var sum: Float = 0.0
            for j in (i - halfWindow)...(i + halfWindow) {
                sum += values[j]
            }
            smoothed[i] = sum * scale
        }
        
        return smoothed
    }
    
    /// Normalize values using 95th percentile as maximum
    /// This prevents single outlier peaks from dominating normalization
    private func normalizeByPercentile(values: [Float]) -> [Float] {
        guard !values.isEmpty else { return [] }
        
        // Find 95th percentile value
        let percentileValue = calculatePercentile(values: values, percentile: normalizationPercentile)
        
        guard percentileValue > 0 else {
            // All zeros or negative, return as-is
            return values
        }
        
        // Normalize: divide by percentile and clamp to [0, 1]
        var normalized = [Float](repeating: 0, count: values.count)
        let scale = 1.0 / percentileValue
        
        vDSP_vsmul(
            values, 1,              // Input
            [scale],                // Scalar multiplier
            &normalized, 1,         // Output
            vDSP_Length(values.count)
        )
        
        // Clamp to [0, 1]
        var lowerBound: Float = 0.0
        var upperBound: Float = 1.0
        vDSP_vclip(
            normalized, 1,
            &lowerBound,
            &upperBound,
            &normalized, 1,
            vDSP_Length(values.count)
        )
        
        return normalized
    }
    
    /// Calculate percentile value from array
    /// Uses sorting to find the value at given percentile (0.0-1.0)
    private func calculatePercentile(values: [Float], percentile: Float) -> Float {
        guard !values.isEmpty else { return 0 }
        
        // Sort values using vDSP_vsorti (indices) then access
        var sortedValues = values
        sortedValues.sort()
        
        // Find index at percentile
        let index = Int(Float(sortedValues.count - 1) * percentile)
        return sortedValues[index]
    }
}
