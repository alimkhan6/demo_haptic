//
//  SpectralAnalyzer.swift
//  haptico
//
//  Computes spectral centroid (brightness) and spectral flux (change)
//

import Foundation
import Accelerate

// MARK: - Spectral Analysis Result

/// Result of spectral analysis
struct SpectralAnalysisResult {
    let centroidPoints: [CentroidPoint]  // Spectral centroid over time
    let fluxValues: [Float]              // Spectral flux values (for onset detection)
    let fftResults: [FFTResult]          // Original FFT results (needed by other analyzers)
}

// MARK: - Spectral Analyzer

/// Analyzes spectral features: centroid and flux
final class SpectralAnalyzer: SpectralAnalyzerProtocol {
    
    // MARK: - Configuration
    
    private let centroidMaxFrequency: Float = 4000.0  // Map 0-4000 Hz to 0.0-1.0
    
    // MARK: - Public Methods
    
    /// Analyze spectral features from FFT results
    /// - Parameter fftResults: Array of FFT results from FFTAnalyzer
    /// - Returns: SpectralAnalysisResult containing centroid and flux
    func analyze(fftResults: [FFTResult]) -> SpectralAnalysisResult {
        guard !fftResults.isEmpty else {
            return SpectralAnalysisResult(
                centroidPoints: [],
                fluxValues: [],
                fftResults: []
            )
        }
        
        // Step 1: Calculate spectral centroid for each frame
        let centroids = calculateCentroids(fftResults: fftResults)
        
        // Step 2: Calculate spectral flux for each frame
        let flux = calculateFlux(fftResults: fftResults)
        
        return SpectralAnalysisResult(
            centroidPoints: centroids,
            fluxValues: flux,
            fftResults: fftResults
        )
    }
    
    /// Analyze spectral features with progress reporting
    /// - Parameters:
    ///   - fftResults: Array of FFT results from FFTAnalyzer
    ///   - chunkSize: Number of frames to process per chunk (default 100)
    ///   - progressHandler: Progress callback (0.0 to 1.0)
    /// - Returns: SpectralAnalysisResult containing centroid and flux
    func analyzeWithProgress(
        fftResults: [FFTResult],
        chunkSize: Int = 100,
        progressHandler: @escaping (Double) -> Void
    ) async -> SpectralAnalysisResult {
        guard !fftResults.isEmpty else {
            return SpectralAnalysisResult(
                centroidPoints: [],
                fluxValues: [],
                fftResults: []
            )
        }
        
        progressHandler(0.0)
        
        // Step 1: Calculate spectral centroid for each frame with progress
        let centroids = await calculateCentroidsWithProgress(
            fftResults: fftResults,
            chunkSize: chunkSize,
            onProgress: { centroidProgress in
                progressHandler(centroidProgress * 0.5)  // 0-50% for centroids
            }
        )
        
        // Step 2: Calculate spectral flux for each frame with progress
        let flux = await calculateFluxWithProgress(
            fftResults: fftResults,
            chunkSize: chunkSize,
            onProgress: { fluxProgress in
                progressHandler(0.5 + fluxProgress * 0.5)  // 50-100% for flux
            }
        )
        
        progressHandler(1.0)
        
        return SpectralAnalysisResult(
            centroidPoints: centroids,
            fluxValues: flux,
            fftResults: fftResults
        )
    }
    
    // MARK: - Spectral Centroid
    
    /// Calculate spectral centroid for each frame
    /// Formula: centroid = Σ(frequency[i] * magnitude[i]) / Σ(magnitude[i])
    /// Normalized to 0.0-1.0 based on 0-4000 Hz range
    private func calculateCentroids(fftResults: [FFTResult]) -> [CentroidPoint] {
        return fftResults.map { result in
            let centroidHz = calculateCentroid(magnitudes: result.magnitudes, sampleRate: result.sampleRate)
            let normalizedCentroid = normalizeCentroid(frequency: centroidHz)
            
            return CentroidPoint(
                time: result.frameTime,
                value: normalizedCentroid
            )
        }
    }
    
    /// Calculate centroids with progress reporting in chunks
    private func calculateCentroidsWithProgress(
        fftResults: [FFTResult],
        chunkSize: Int,
        onProgress: @escaping (Double) -> Void
    ) async -> [CentroidPoint] {
        var centroids: [CentroidPoint] = []
        centroids.reserveCapacity(fftResults.count)
        
        let totalCount = fftResults.count
        var processedCount = 0
        
        // Process in chunks to reduce yield overhead
        for chunkStart in stride(from: 0, to: totalCount, by: chunkSize) {
            let chunkEnd = min(chunkStart + chunkSize, totalCount)
            
            // Process chunk without yielding
            for index in chunkStart..<chunkEnd {
                let result = fftResults[index]
                let centroidHz = calculateCentroid(magnitudes: result.magnitudes, sampleRate: result.sampleRate)
                let normalizedCentroid = normalizeCentroid(frequency: centroidHz)
                
                centroids.append(CentroidPoint(
                    time: result.frameTime,
                    value: normalizedCentroid
                ))
            }
            
            processedCount = chunkEnd
            
            // Report progress and yield after chunk
            let progress = Double(processedCount) / Double(totalCount)
            onProgress(progress)
            await Task.yield()
        }
        
        return centroids
    }
    
    /// Calculate centroid for single frame
    private func calculateCentroid(magnitudes: [Float], sampleRate: Double) -> Float {
        let binCount = magnitudes.count
        
        // Create frequency array for each bin
        var frequencies = [Float](repeating: 0, count: binCount)
        let freqStep = Float(sampleRate) / Float(binCount * 2)
        
        vDSP_vramp(
            [0.0],                      // Start
            [freqStep],                 // Increment
            &frequencies, 1,
            vDSP_Length(binCount)
        )
        
        // Calculate numerator: Σ(frequency[i] * magnitude[i])
        var numerator = [Float](repeating: 0, count: binCount)
        vDSP_vmul(
            frequencies, 1,
            magnitudes, 1,
            &numerator, 1,
            vDSP_Length(binCount)
        )
        
        var sumNumerator: Float = 0.0
        vDSP_sve(
            numerator, 1,
            &sumNumerator,
            vDSP_Length(binCount)
        )
        
        // Calculate denominator: Σ(magnitude[i])
        var sumDenominator: Float = 0.0
        vDSP_sve(
            magnitudes, 1,
            &sumDenominator,
            vDSP_Length(binCount)
        )
        
        // Avoid division by zero
        guard sumDenominator > 0 else { return 0.0 }
        
        return sumNumerator / sumDenominator
    }
    
    /// Normalize centroid frequency to 0.0-1.0 range (0-4000 Hz)
    private func normalizeCentroid(frequency: Float) -> Float {
        let normalized = frequency / centroidMaxFrequency
        return min(max(normalized, 0.0), 1.0)  // Clamp to [0, 1]
    }
    
    // MARK: - Spectral Flux
    
    /// Calculate spectral flux for each frame
    /// Formula: flux = sqrt(Σ((mag[i] - prevMag[i])^2))  where mag[i] > prevMag[i]
    /// Only positive changes counted (half-wave rectification)
    private func calculateFlux(fftResults: [FFTResult]) -> [Float] {
        guard fftResults.count > 1 else { return [] }
        
        var fluxValues: [Float] = []
        fluxValues.reserveCapacity(fftResults.count)
        
        // First frame has no flux (no previous frame)
        fluxValues.append(0.0)
        
        for i in 1..<fftResults.count {
            let prevMagnitudes = fftResults[i - 1].magnitudes
            let currMagnitudes = fftResults[i].magnitudes
            
            let flux = calculateFluxBetweenFrames(
                previous: prevMagnitudes,
                current: currMagnitudes
            )
            
            fluxValues.append(flux)
        }
        
        return fluxValues
    }
    
    /// Calculate flux with progress reporting in chunks
    private func calculateFluxWithProgress(
        fftResults: [FFTResult],
        chunkSize: Int,
        onProgress: @escaping (Double) -> Void
    ) async -> [Float] {
        guard fftResults.count > 1 else { return [] }
        
        var fluxValues: [Float] = []
        fluxValues.reserveCapacity(fftResults.count)
        
        // First frame has no flux (no previous frame)
        fluxValues.append(0.0)
        
        let totalCount = fftResults.count
        var processedCount = 1
        
        // Process in chunks to reduce yield overhead
        for chunkStart in stride(from: 1, to: totalCount, by: chunkSize) {
            let chunkEnd = min(chunkStart + chunkSize, totalCount)
            
            // Process chunk without yielding
            for i in chunkStart..<chunkEnd {
                let prevMagnitudes = fftResults[i - 1].magnitudes
                let currMagnitudes = fftResults[i].magnitudes
                
                let flux = calculateFluxBetweenFrames(
                    previous: prevMagnitudes,
                    current: currMagnitudes
                )
                
                fluxValues.append(flux)
            }
            
            processedCount = chunkEnd
            
            // Report progress and yield after chunk
            let progress = Double(processedCount) / Double(totalCount)
            onProgress(progress)
            await Task.yield()
        }
        
        return fluxValues
    }
    
    /// Calculate flux between two frames using vDSP
    private func calculateFluxBetweenFrames(previous: [Float], current: [Float]) -> Float {
        let count = min(previous.count, current.count)
        
        // Step 1: Compute difference (current - previous)
        var difference = [Float](repeating: 0, count: count)
        vDSP_vsub(
            previous, 1,
            current, 1,
            &difference, 1,
            vDSP_Length(count)
        )
        
        // Step 2: Half-wave rectification (only positive values)
        // Clip to [0, inf]
        var lowerBound: Float = 0.0
        var upperBound: Float = Float.greatestFiniteMagnitude
        vDSP_vclip(
            difference, 1,
            &lowerBound,
            &upperBound,
            &difference, 1,
            vDSP_Length(count)
        )
        
        // Step 3: Square each difference
        var squared = [Float](repeating: 0, count: count)
        vDSP_vsq(
            difference, 1,
            &squared, 1,
            vDSP_Length(count)
        )
        
        // Step 4: Sum all squared differences
        var sum: Float = 0.0
        vDSP_sve(
            squared, 1,
            &sum,
            vDSP_Length(count)
        )
        
        // Step 5: Square root
        return sqrt(sum)
    }
}
