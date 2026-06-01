//
//  FFTAnalyzer.swift
//  haptico
//
//  Computes FFT spectrum with Hann windowing for spectral analysis
//

import Foundation
import Accelerate

// MARK: - FFT Result

/// Result of FFT analysis for a single frame
struct FFTResult {
    let frameTime: Double       // Time of frame center in seconds
    let magnitudes: [Float]     // Magnitude spectrum (512 bins from 0 to Nyquist)
    let sampleRate: Double      // Sample rate for frequency calculation
    
    /// Convert bin index to frequency in Hz
    func frequency(forBin bin: Int) -> Float {
        return Float(bin) * Float(sampleRate) / Float(magnitudes.count * 2)
    }
    
    /// Convert frequency to bin index
    func bin(forFrequency frequency: Float) -> Int {
        let binFloat = frequency * Float(magnitudes.count * 2) / Float(sampleRate)
        return Int(binFloat.rounded())
    }
}

// MARK: - FFT Analyzer

/// Performs FFT analysis with Hann windowing on audio frames
final class FFTAnalyzer: FFTAnalyzerProtocol {
    
    // MARK: - Configuration
    
    private let frameSize: Int = 1024
    private let hopSize: Int = 512
    private let fftSize: Int = 1024
    
    // MARK: - FFT Setup
    
    private let fftSetup: vDSP_DFT_Setup
    private let hannWindow: [Float]
    
    // MARK: - Initialization
    
    init?() {
        // Create FFT setup (vDSP uses DFT for real-to-complex transforms)
        guard let setup = vDSP_DFT_zop_CreateSetup(
            nil,
            vDSP_Length(fftSize),
            vDSP_DFT_Direction.FORWARD
        ) else {
            return nil
        }
        
        self.fftSetup = setup
        
        // Create Hann window
        self.hannWindow = Self.createHannWindow(size: frameSize)
    }
    
    deinit {
        vDSP_DFT_DestroySetup(fftSetup)
    }
    
    // MARK: - Public Methods
    
    /// Analyze FFT spectrum of audio samples
    /// - Parameters:
    ///   - samples: Input audio samples
    ///   - sampleRate: Sample rate of audio
    /// - Returns: Array of FFTResult for each frame
    func analyze(samples: [Float], sampleRate: Double) -> [FFTResult] {
        guard !samples.isEmpty else { return [] }
        
        var results: [FFTResult] = []
        let frameCount = (samples.count - frameSize) / hopSize + 1
        results.reserveCapacity(frameCount)
        
        for frameIndex in 0..<frameCount {
            let startIndex = frameIndex * hopSize
            let endIndex = min(startIndex + frameSize, samples.count)
            
            guard endIndex - startIndex == frameSize else {
                // Skip incomplete last frame
                break
            }
            
            // Extract frame
            let frame = Array(samples[startIndex..<endIndex])
            
            // Apply Hann window
            let windowedFrame = applyWindow(frame: frame)
            
            // Compute FFT
            let magnitudes = computeFFTMagnitude(windowedFrame: windowedFrame)
            
            // Calculate frame time (center of frame)
            let frameTime = Double(startIndex + frameSize / 2) / sampleRate
            
            results.append(FFTResult(
                frameTime: frameTime,
                magnitudes: magnitudes,
                sampleRate: sampleRate
            ))
        }
        
        return results
    }
    
    /// Analyze FFT spectrum with progress reporting in chunks
    /// - Parameters:
    ///   - samples: Input audio samples
    ///   - sampleRate: Sample rate of audio
    ///   - chunkSize: Number of frames to process per chunk (default 500)
    ///   - progressHandler: Progress callback (0.0 to 1.0)
    /// - Returns: Array of FFTResult for each frame
    func analyzeWithProgress(
        samples: [Float],
        sampleRate: Double,
        chunkSize: Int = 500,
        progressHandler: @escaping (Double) -> Void
    ) async -> [FFTResult] {
        guard !samples.isEmpty else { return [] }
        
        var results: [FFTResult] = []
        let frameCount = (samples.count - frameSize) / hopSize + 1
        results.reserveCapacity(frameCount)
        
        progressHandler(0.0)
        
        // Pre-allocate reusable buffers to reduce memory allocations
        var frameBuffer = [Float](repeating: 0, count: frameSize)
        
        for frameIndex in 0..<frameCount {
            // ✅ Use autoreleasepool to release temporary objects immediately
            autoreleasepool {
                let startIndex = frameIndex * hopSize
                let endIndex = min(startIndex + frameSize, samples.count)
                
                guard endIndex - startIndex == frameSize else {
                    // Skip incomplete last frame
                    return
                }
                
                // Copy frame data directly into buffer (avoid Array allocation)
                samples.withUnsafeBufferPointer { samplesPtr in
                    frameBuffer.withUnsafeMutableBufferPointer { framePtr in
                        let sourcePtr = samplesPtr.baseAddress! + startIndex
                        framePtr.baseAddress!.initialize(from: sourcePtr, count: frameSize)
                    }
                }
                
                // Apply Hann window in-place
                let windowedFrame = applyWindow(frame: frameBuffer)
                
                // Compute FFT
                let magnitudes = computeFFTMagnitude(windowedFrame: windowedFrame)
                
                // Calculate frame time (center of frame)
                let frameTime = Double(startIndex + frameSize / 2) / sampleRate
                
                results.append(FFTResult(
                    frameTime: frameTime,
                    magnitudes: magnitudes,
                    sampleRate: sampleRate
                ))
            }  // ✅ autoreleasepool end - temporary objects released here
            
            // Report progress and yield periodically
            if frameIndex % chunkSize == 0 || frameIndex == frameCount - 1 {
                let progress = Double(frameIndex + 1) / Double(frameCount)
                progressHandler(progress)
                await Task.yield()  // Allow UI updates
            }
        }
        
        progressHandler(1.0)
        return results
    }
    
    // MARK: - Private Methods
    
    /// Apply Hann window to frame using vDSP
    private func applyWindow(frame: [Float]) -> [Float] {
        var windowed = [Float](repeating: 0, count: frameSize)
        
        vDSP_vmul(
            frame, 1,               // Input frame
            hannWindow, 1,          // Hann window
            &windowed, 1,           // Output
            vDSP_Length(frameSize)
        )
        
        return windowed
    }
    
    /// Compute FFT magnitude spectrum
    /// Returns 512 magnitude bins (0 to Nyquist frequency)
    private func computeFFTMagnitude(windowedFrame: [Float]) -> [Float] {
        let halfSize = fftSize / 2
        
        // Prepare complex buffers for DFT
        // DFT requires separate real and imaginary arrays
        var realIn = [Float](repeating: 0, count: fftSize)
        let imagIn = [Float](repeating: 0, count: fftSize)
        var realOut = [Float](repeating: 0, count: fftSize)
        var imagOut = [Float](repeating: 0, count: fftSize)
        
        // Copy windowed frame to real input (zero-padded if needed)
        for i in 0..<min(windowedFrame.count, fftSize) {
            realIn[i] = windowedFrame[i]
        }
        
        // Perform DFT
        vDSP_DFT_Execute(
            fftSetup,
            realIn, imagIn,
            &realOut, &imagOut
        )
        
        // Compute magnitude: sqrt(real^2 + imag^2)
        var magnitudes = [Float](repeating: 0, count: halfSize)
        
        realOut.withUnsafeBufferPointer { realPtr in
            imagOut.withUnsafeBufferPointer { imagPtr in
                // Create DSPSplitComplex
                var splitComplex = DSPSplitComplex(
                    realp: UnsafeMutablePointer(mutating: realPtr.baseAddress!),
                    imagp: UnsafeMutablePointer(mutating: imagPtr.baseAddress!)
                )
                
                // Compute magnitude (only first half, as second half is mirror)
                vDSP_zvabs(
                    &splitComplex, 1,
                    &magnitudes, 1,
                    vDSP_Length(halfSize)
                )
            }
        }
        
        // Normalize by FFT size
        let scale = 2.0 / Float(fftSize)
        vDSP_vsmul(
            magnitudes, 1,
            [scale],
            &magnitudes, 1,
            vDSP_Length(halfSize)
        )
        
        return magnitudes
    }
    
    /// Create Hann window using vDSP
    /// Formula: w[n] = 0.5 * (1 - cos(2π * n / (N-1)))
    private static func createHannWindow(size: Int) -> [Float] {
        var window = [Float](repeating: 0, count: size)
        
        vDSP_hann_window(
            &window,
            vDSP_Length(size),
            Int32(vDSP_HANN_NORM)  // Normalized window
        )
        
        return window
    }
}

// MARK: - FFT Result Extensions

extension Array where Element == FFTResult {
    /// Get magnitude at specific frequency for all frames
    func magnitudes(atFrequency frequency: Float) -> [(time: Double, magnitude: Float)] {
        return self.map { result in
            let bin = result.bin(forFrequency: frequency)
            let clampedBin = Swift.min(Swift.max(bin, 0), result.magnitudes.count - 1)
            return (result.frameTime, result.magnitudes[clampedBin])
        }
    }
    
    /// Sum magnitudes in frequency range for each frame
    func sumMagnitudes(inRange range: ClosedRange<Float>) -> [(time: Double, sum: Float)] {
        return self.map { fftResult in
            let startBin = Swift.max(0, fftResult.bin(forFrequency: range.lowerBound))
            let endBin = Swift.min(fftResult.magnitudes.count - 1, fftResult.bin(forFrequency: range.upperBound))
            
            var sum: Float = 0.0
            if startBin <= endBin {
                let magnitudeSlice = fftResult.magnitudes[startBin...endBin]
                let sliceArray = [Float](magnitudeSlice)
                vDSP_sve(
                    sliceArray, 1,
                    &sum,
                    vDSP_Length(sliceArray.count)
                )
            }
            
            return (fftResult.frameTime, sum)
        }
    }
}
