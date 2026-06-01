//
//  OnsetDetector.swift
//  haptico
//
//  Detects onsets (attacks/transients) using adaptive threshold and classification
//

import Foundation
import Accelerate

// MARK: - Onset Detector

/// Detects onsets using spectral flux with adaptive threshold
/// Classifies onsets as percussive or tonal
final class OnsetDetector: OnsetDetectorProtocol {
    
    // MARK: - Configuration
    
    private let adaptiveWindowSize: Int = 20          // Frames for threshold calculation
    private let thresholdMultiplier: Float = 1.0      // ОСЛАБЛЕНО: было 1.5, теперь 1.0 - больше onsets проходит!
    private let minOnsetInterval: Double = 0.02       // ОСЛАБЛЕНО: было 0.05 (50ms), теперь 0.02 (20ms) - rapid fire!
    
    // MARK: - Public Methods
    
    /// Detect onsets from spectral flux and FFT results
    /// - Parameters:
    ///   - fluxValues: Spectral flux values from SpectralAnalyzer
    ///   - fftResults: FFT results for onset classification
    /// - Returns: Array of Onset with time, intensity, and type
    func detectOnsets(
        fluxValues: [Float],
        fftResults: [FFTResult]
    ) -> [Onset] {
        guard fluxValues.count > adaptiveWindowSize else { return [] }
        guard fluxValues.count == fftResults.count else { return [] }
        
        // Step 1: Calculate adaptive threshold
        let threshold = calculateAdaptiveThreshold(fluxValues: fluxValues)
        
        // Step 2: Peak picking (local maxima above threshold)
        let peakIndices = findPeaks(
            fluxValues: fluxValues,
            threshold: threshold
        )
        
        // Step 3: Suppress close onsets (minimum interval)
        let suppressedIndices = suppressCloseOnsets(
            peakIndices: peakIndices,
            fftResults: fftResults
        )
        
        // Step 4: Calculate intensity and classify each onset
        let onsets = suppressedIndices.map { index -> Onset in
            let intensity = calculateIntensity(
                fluxValue: fluxValues[index],
                threshold: threshold[index]
            )
            
            let type = classifyOnset(
                fftResult: fftResults[index],
                previousFFT: index > 0 ? fftResults[index - 1] : nil
            )
            
            return Onset(
                time: fftResults[index].frameTime,
                intensity: intensity,
                type: type
            )
        }
        
        return onsets
    }
    
    // MARK: - Adaptive Threshold
    
    /// Calculate adaptive threshold: threshold[i] = mean + 1.5 * std
    /// Uses sliding window of 20 frames
    private func calculateAdaptiveThreshold(fluxValues: [Float]) -> [Float] {
        var threshold = [Float](repeating: 0, count: fluxValues.count)
        let halfWindow = adaptiveWindowSize / 2
        
        for i in 0..<fluxValues.count {
            let windowStart = max(0, i - halfWindow)
            let windowEnd = min(fluxValues.count, i + halfWindow)
            let window = Array(fluxValues[windowStart..<windowEnd])
            
            // Calculate mean
            var mean: Float = 0.0
            vDSP_meanv(
                window, 1,
                &mean,
                vDSP_Length(window.count)
            )
            
            // Calculate standard deviation using vDSP_normalize
            var normalized = [Float](repeating: 0, count: window.count)
            var std: Float = 0.0
            vDSP_normalize(
                window, 1,
                &normalized, 1,
                &mean,
                &std,
                vDSP_Length(window.count)
            )
            
            // Threshold = mean + 1.5 * std
            threshold[i] = mean + thresholdMultiplier * std
        }
        
        return threshold
    }
    
    // MARK: - Peak Picking
    
    /// Find peaks: flux[i] > threshold[i] AND local maximum
    private func findPeaks(
        fluxValues: [Float],
        threshold: [Float]
    ) -> [Int] {
        var peaks: [Int] = []
        
        for i in 1..<(fluxValues.count - 1) {
            let isAboveThreshold = fluxValues[i] > threshold[i]
            let isLocalMax = fluxValues[i] > fluxValues[i - 1] && fluxValues[i] > fluxValues[i + 1]
            
            if isAboveThreshold && isLocalMax {
                peaks.append(i)
            }
        }
        
        return peaks
    }
    
    // MARK: - Onset Suppression
    
    /// Suppress onsets that are too close (minimum 50ms interval)
    /// Keep the onset with higher flux value
    private func suppressCloseOnsets(
        peakIndices: [Int],
        fftResults: [FFTResult]
    ) -> [Int] {
        guard !peakIndices.isEmpty else { return [] }
        
        var suppressed: [Int] = [peakIndices[0]]
        
        for i in 1..<peakIndices.count {
            let currentIndex = peakIndices[i]
            let previousIndex = suppressed.last!
            
            let timeDiff = fftResults[currentIndex].frameTime - fftResults[previousIndex].frameTime
            
            if timeDiff >= minOnsetInterval {
                suppressed.append(currentIndex)
            }
            // If too close, keep the one with higher flux (already selected, so skip)
        }
        
        return suppressed
    }
    
    // MARK: - Intensity Calculation
    
    /// Calculate onset intensity normalized to 0.0-1.0
    /// Formula: (flux - threshold) / threshold, then boosted for stronger haptics
    private func calculateIntensity(fluxValue: Float, threshold: Float) -> Float {
        guard threshold > 0 else { return 1.0 }
        
        // Calculate relative strength above threshold
        let rawIntensity = (fluxValue - threshold) / threshold
        
        // Apply power curve to boost mid-range values
        // This makes moderate onsets more intense while keeping weak ones weak
        let boosted = pow(min(max(rawIntensity, 0.0), 2.0), 0.7) / pow(2.0, 0.7)
        
        return min(boosted, 1.0)
    }
    
    // MARK: - Onset Classification
    
    /// Classify onset as percussive or tonal
    /// Percussive: high flux across wide frequency range (e.g., drums)
    /// Tonal: flux concentrated in narrow frequency range (e.g., melody)
    private func classifyOnset(
        fftResult: FFTResult,
        previousFFT: FFTResult?
    ) -> OnsetType {
        guard let previousFFT = previousFFT else {
            return .percussive  // First frame, default to percussive
        }
        
        // Calculate spectral difference
        let diff = calculateSpectralDifference(
            current: fftResult.magnitudes,
            previous: previousFFT.magnitudes
        )
        
        // Analyze spectral spread of difference
        let spread = calculateSpectralSpread(diff: diff)
        
        // High spread = percussive (wide frequency range)
        // Low spread = tonal (narrow frequency range)
        let spreadThreshold: Float = 0.5
        return spread > spreadThreshold ? .percussive : .tonal
    }
    
    /// Calculate spectral difference (positive changes only)
    private func calculateSpectralDifference(
        current: [Float],
        previous: [Float]
    ) -> [Float] {
        let count = min(current.count, previous.count)
        var diff = [Float](repeating: 0, count: count)
        
        // Subtract: current - previous
        vDSP_vsub(
            previous, 1,
            current, 1,
            &diff, 1,
            vDSP_Length(count)
        )
        
        // Half-wave rectification (only positive)
        var lowerBound: Float = 0.0
        var upperBound: Float = Float.greatestFiniteMagnitude
        vDSP_vclip(
            diff, 1,
            &lowerBound,
            &upperBound,
            &diff, 1,
            vDSP_Length(count)
        )
        
        return diff
    }
    
    /// Calculate spectral spread (concentration vs dispersion)
    /// Returns 0.0-1.0 where 1.0 = maximum spread (energy across all frequencies)
    private func calculateSpectralSpread(diff: [Float]) -> Float {
        // Calculate weighted variance of spectral energy
        // High variance = wide spread (percussive)
        // Low variance = narrow spread (tonal)
        
        // Find centroid (mean position)
        var sum: Float = 0.0
        vDSP_sve(diff, 1, &sum, vDSP_Length(diff.count))
        
        guard sum > 0 else { return 0.0 }
        
        // Calculate weighted center
        var indices = [Float](repeating: 0, count: diff.count)
        for i in 0..<diff.count {
            indices[i] = Float(i)
        }
        
        var weighted = [Float](repeating: 0, count: diff.count)
        vDSP_vmul(
            indices, 1,
            diff, 1,
            &weighted, 1,
            vDSP_Length(diff.count)
        )
        
        var weightedSum: Float = 0.0
        vDSP_sve(weighted, 1, &weightedSum, vDSP_Length(weighted.count))
        
        let centroid = weightedSum / sum
        
        // Calculate variance
        var squaredDiff = [Float](repeating: 0, count: diff.count)
        for i in 0..<diff.count {
            let deviation = Float(i) - centroid
            squaredDiff[i] = deviation * deviation * diff[i]
        }
        
        var variance: Float = 0.0
        vDSP_sve(squaredDiff, 1, &variance, vDSP_Length(squaredDiff.count))
        variance /= sum
        
        // Normalize variance to 0-1 range (heuristic based on typical values)
        let normalizedSpread = sqrt(variance) / (Float(diff.count) * 0.5)
        return min(normalizedSpread, 1.0)
    }
}
