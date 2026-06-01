//
//  SegmentAnalyzer.swift
//  haptico
//
//  Analyzes track structure using self-similarity and energy features
//

import Foundation
import Accelerate

// MARK: - Segment Analyzer

/// Analyzes track structure (intro, verse, chorus, bridge, outro)
/// Uses simplified approach based on energy and onset density
final class SegmentAnalyzer: SegmentAnalyzerProtocol {
    
    // MARK: - Configuration
    
    private let segmentMinDuration: Double = 8.0   // Minimum 8 seconds per segment
    private let noveltyThreshold: Float = 0.5       // Threshold for segment boundaries
    
    // MARK: - Public Methods
    
    /// Analyze track structure
    /// - Parameters:
    ///   - fftResults: FFT results for spectral features
    ///   - rmsPoints: RMS energy points
    ///   - onsets: Detected onsets
    ///   - duration: Total track duration
    /// - Returns: Array of segments with type and timing
    func analyzeSegments(
        fftResults: [FFTResult],
        rmsPoints: [RMSPoint],
        onsets: [Onset],
        duration: Double
    ) -> [Segment] {
        guard !fftResults.isEmpty && !rmsPoints.isEmpty else { return [] }
        
        // Step 1: Extract MFCC-like features (simplified log mel filterbank)
        let features = extractSpectralFeatures(fftResults: fftResults)
        
        // Step 2: Calculate self-similarity matrix
        let similarityMatrix = calculateSelfSimilarity(features: features)
        
        // Step 3: Find segment boundaries using novelty curve
        let boundaries = findSegmentBoundaries(
            similarityMatrix: similarityMatrix,
            fftResults: fftResults
        )
        
        // Step 4: Classify each segment
        let segments = classifySegments(
            boundaries: boundaries,
            rmsPoints: rmsPoints,
            onsets: onsets,
            duration: duration
        )
        
        return segments
    }
    
    // MARK: - Feature Extraction
    
    /// Extract simplified spectral features (log mel filterbank approximation)
    /// Returns 13 coefficients per frame
    private func extractSpectralFeatures(fftResults: [FFTResult]) -> [[Float]] {
        let melBands = 13
        
        return fftResults.map { result in
            extractMelBands(magnitudes: result.magnitudes, bandCount: melBands)
        }
    }
    
    /// Extract mel-spaced frequency bands (approximation)
    private func extractMelBands(magnitudes: [Float], bandCount: Int) -> [Float] {
        var bands = [Float](repeating: 0, count: bandCount)
        
        // Simple logarithmic spacing of bands
        for band in 0..<bandCount {
            let startBin = Int(pow(Float(band) / Float(bandCount), 2.0) * Float(magnitudes.count))
            let endBin = Int(pow(Float(band + 1) / Float(bandCount), 2.0) * Float(magnitudes.count))
            
            let clampedStart = max(0, min(startBin, magnitudes.count - 1))
            let clampedEnd = max(0, min(endBin, magnitudes.count))
            
            if clampedStart < clampedEnd {
                // Sum energy in band
                var sum: Float = 0.0
                let bandSlice = Array(magnitudes[clampedStart..<clampedEnd])
                vDSP_sve(bandSlice, 1, &sum, vDSP_Length(bandSlice.count))
                
                // Log compression
                bands[band] = log10(max(sum, 1e-10))
            }
        }
        
        return bands
    }
    
    // MARK: - Self-Similarity Matrix
    
    /// Calculate self-similarity matrix using cosine similarity
    private func calculateSelfSimilarity(features: [[Float]]) -> [[Float]] {
        let count = features.count
        var matrix = Array(repeating: Array(repeating: Float(0), count: count), count: count)
        
        // Calculate pairwise cosine similarities
        for i in 0..<count {
            for j in i..<count {
                let similarity = cosineSimilarity(a: features[i], b: features[j])
                matrix[i][j] = similarity
                matrix[j][i] = similarity  // Symmetric
            }
        }
        
        return matrix
    }
    
    /// Calculate cosine similarity between two feature vectors
    /// similarity = dot(a, b) / (||a|| * ||b||)
    private func cosineSimilarity(a: [Float], b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        
        // Dot product
        var dotProduct: Float = 0.0
        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        
        // Norms
        var normA: Float = 0.0
        var normB: Float = 0.0
        vDSP_svesq(a, 1, &normA, vDSP_Length(a.count))
        vDSP_svesq(b, 1, &normB, vDSP_Length(b.count))
        
        normA = sqrt(normA)
        normB = sqrt(normB)
        
        guard normA > 0 && normB > 0 else { return 0 }
        
        return dotProduct / (normA * normB)
    }
    
    // MARK: - Boundary Detection
    
    /// Find segment boundaries using novelty curve from diagonal of similarity matrix
    private func findSegmentBoundaries(
        similarityMatrix: [[Float]],
        fftResults: [FFTResult]
    ) -> [Double] {
        let count = similarityMatrix.count
        
        // Calculate novelty curve (checkerboard kernel on diagonal)
        var novelty = [Float](repeating: 0, count: count)
        let kernelSize = 16  // 16 frames (~0.7 seconds at hop 512)
        
        for i in kernelSize..<(count - kernelSize) {
            // Contrast: within-segment similarity vs across-boundary dissimilarity
            var withinSum: Float = 0.0
            var acrossSum: Float = 0.0
            
            for k in 0..<kernelSize {
                // Within segment (before and after separately)
                withinSum += similarityMatrix[i - k][i - k]
                withinSum += similarityMatrix[i + k][i + k]
                
                // Across boundary
                acrossSum += similarityMatrix[i - k][i + k]
            }
            
            novelty[i] = acrossSum / (withinSum + 1e-10)
        }
        
        // Find peaks in novelty curve
        var boundaries: [Double] = [0.0]  // Start with beginning
        
        for i in kernelSize..<(count - kernelSize) {
            let isLocalMax = novelty[i] > novelty[i - 1] && novelty[i] > novelty[i + 1]
            let isAboveThreshold = novelty[i] > noveltyThreshold
            
            if isLocalMax && isAboveThreshold {
                let time = fftResults[i].frameTime
                
                // Check minimum duration from last boundary
                if let lastBoundary = boundaries.last {
                    if time - lastBoundary >= segmentMinDuration {
                        boundaries.append(time)
                    }
                } else {
                    boundaries.append(time)
                }
            }
        }
        
        return boundaries
    }
    
    // MARK: - Segment Classification
    
    /// Classify segments based on energy and onset density
    private func classifySegments(
        boundaries: [Double],
        rmsPoints: [RMSPoint],
        onsets: [Onset],
        duration: Double
    ) -> [Segment] {
        var segments: [Segment] = []
        
        for i in 0..<boundaries.count {
            let startTime = boundaries[i]
            let endTime = i < boundaries.count - 1 ? boundaries[i + 1] : duration
            let segmentDuration = endTime - startTime
            
            // Calculate average energy in segment
            let avgEnergy = calculateAverageEnergy(
                rmsPoints: rmsPoints,
                startTime: startTime,
                endTime: endTime
            )
            
            // Calculate onset density (onsets per second)
            let onsetCount = onsets.filter { $0.time >= startTime && $0.time < endTime }.count
            let onsetDensity = Float(onsetCount) / Float(segmentDuration)
            
            // Classify based on position, energy, and onset density
            let type = classifySegment(
                position: i,
                totalSegments: boundaries.count,
                energy: avgEnergy,
                onsetDensity: onsetDensity,
                startTime: startTime,
                duration: duration
            )
            
            segments.append(Segment(
                time: startTime,
                duration: segmentDuration,
                type: type
            ))
        }
        
        return segments
    }
    
    /// Calculate average energy in time range
    private func calculateAverageEnergy(
        rmsPoints: [RMSPoint],
        startTime: Double,
        endTime: Double
    ) -> Float {
        let relevantPoints = rmsPoints.filter { $0.time >= startTime && $0.time < endTime }
        
        guard !relevantPoints.isEmpty else { return 0 }
        
        let values = relevantPoints.map { $0.value }
        var mean: Float = 0.0
        vDSP_meanv(values, 1, &mean, vDSP_Length(values.count))
        
        return mean
    }
    
    /// Classify individual segment
    private func classifySegment(
        position: Int,
        totalSegments: Int,
        energy: Float,
        onsetDensity: Float,
        startTime: Double,
        duration: Double
    ) -> SegmentType {
        // Position-based heuristics
        let relativePosition = Float(position) / Float(max(totalSegments - 1, 1))
        
        // Intro: low position, lower energy
        if relativePosition < 0.15 && energy < 0.5 {
            return .intro
        }
        
        // Outro: high position, decreasing energy
        if relativePosition > 0.85 && energy < 0.6 {
            return .outro
        }
        
        // Chorus: high energy, high onset density
        if energy > 0.7 && onsetDensity > 3.0 {
            return .chorus
        }
        
        // Bridge: middle position, moderate energy, unusual onset pattern
        if relativePosition > 0.5 && relativePosition < 0.8 && energy < 0.7 && onsetDensity < 2.5 {
            return .bridge
        }
        
        // Default: verse
        return .verse
    }
}
