//
//  BassAnalyzer.swift
//  haptico
//
//  Extracts bass energy in two frequency bands (sub-bass and mid-bass)
//

import Foundation
import Accelerate

// MARK: - Bass Analyzer

/// Analyzes bass energy in two frequency bands:
/// - Sub-bass: 20-80 Hz (deep rumble, felt more than heard)
/// - Mid-bass: 80-250 Hz (punch, warmth)
final class BassAnalyzer: BassAnalyzerProtocol {
    
    // MARK: - Configuration
    
    private struct FrequencyBands {
        static let subBassRange: ClosedRange<Float> = 20.0...80.0
        static let midBassRange: ClosedRange<Float> = 80.0...250.0
    }
    
    private let normalizationPercentile: Float = 0.95
    
    // MARK: - Public Methods
    
    /// Analyze bass energy from FFT results
    /// - Parameter fftResults: Array of FFT results from FFTAnalyzer
    /// - Returns: Array of BassPoint with time and normalized bass energies
    func analyze(fftResults: [FFTResult]) async -> [BassPoint] {
        guard !fftResults.isEmpty else { return [] }
        
        // Step 1: Extract sub-bass and mid-bass energy for each frame
        let (subBassEnergies, midBassEnergies) = extractBassEnergies(fftResults: fftResults)
        
        // Step 2: Normalize each band independently using 95th percentile
        let normalizedSubBass = normalizeByPercentile(values: subBassEnergies)
        let normalizedMidBass = normalizeByPercentile(values: midBassEnergies)
        
        // Step 3: Create time-stamped points
        return fftResults.enumerated().map { index, fftResult in
            BassPoint(
                time: fftResult.frameTime,
                subBass: normalizedSubBass[index],
                midBass: normalizedMidBass[index]
            )
        }
    }
    
    // MARK: - Private Methods
    
    /// Extract bass energies from FFT results
    /// Returns tuple of (subBassEnergies, midBassEnergies)
    private func extractBassEnergies(
        fftResults: [FFTResult]
    ) -> (subBass: [Float], midBass: [Float]) {
        var subBassEnergies: [Float] = []
        var midBassEnergies: [Float] = []
        
        subBassEnergies.reserveCapacity(fftResults.count)
        midBassEnergies.reserveCapacity(fftResults.count)
        
        for result in fftResults {
            // Calculate sub-bass energy (20-80 Hz)
            let subBassEnergy = sumEnergy(
                in: FrequencyBands.subBassRange,
                fftResult: result
            )
            subBassEnergies.append(subBassEnergy)
            
            // Calculate mid-bass energy (80-250 Hz)
            let midBassEnergy = sumEnergy(
                in: FrequencyBands.midBassRange,
                fftResult: result
            )
            midBassEnergies.append(midBassEnergy)
        }
        
        return (subBassEnergies, midBassEnergies)
    }
    
    /// Sum energy (magnitude) in frequency range using vDSP
    private func sumEnergy(
        in range: ClosedRange<Float>,
        fftResult: FFTResult
    ) -> Float {
        // Convert frequency range to bin indices
        let startBin = max(0, fftResult.bin(forFrequency: range.lowerBound))
        let endBin = min(fftResult.magnitudes.count - 1, fftResult.bin(forFrequency: range.upperBound))
        
        guard startBin <= endBin else { return 0.0 }
        
        // Sum magnitudes in range using vDSP_sve (sum vector elements)
        var sum: Float = 0.0
        let binsInRange = Array(fftResult.magnitudes[startBin...endBin])
        
        vDSP_sve(
            binsInRange, 1,
            &sum,
            vDSP_Length(binsInRange.count)
        )
        
        return sum
    }
    
    /// Normalize values using 95th percentile as maximum
    /// Each bass band is normalized independently
    private func normalizeByPercentile(values: [Float]) -> [Float] {
        guard !values.isEmpty else { return [] }
        
        // Find 95th percentile value
        let percentileValue = calculatePercentile(values: values, percentile: normalizationPercentile)
        
        guard percentileValue > 0 else {
            // All zeros or very small values
            return values
        }
        
        // Normalize: divide by percentile and clamp to [0, 1]
        var normalized = [Float](repeating: 0, count: values.count)
        let scale = 1.0 / percentileValue
        
        vDSP_vsmul(
            values, 1,
            [scale],
            &normalized, 1,
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
    private func calculatePercentile(values: [Float], percentile: Float) -> Float {
        guard !values.isEmpty else { return 0 }
        
        var sortedValues = values
        sortedValues.sort()
        
        let index = Int(Float(sortedValues.count - 1) * percentile)
        return sortedValues[index]
    }
}
