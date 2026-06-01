//
//  BeatTracker.swift
//  haptico
//
//  Two-phase beat tracking: tempo detection + beat grid alignment
//

import Foundation
import Accelerate

// MARK: - Beat Tracking Result

struct BeatTrackingResult {
    let bpm: Float
    let confidence: Float  // 0.0-1.0
    let beats: [Beat]
}

// MARK: - Beat Tracker

/// Tracks beats in two phases:
/// Phase 1: Detect tempo (BPM) via autocorrelation
/// Phase 2: Align beat grid to onsets using dynamic programming
final class BeatTracker: BeatTrackerProtocol {
    
    // MARK: - Configuration
    
    private let bpmRange: ClosedRange<Float> = 60.0...200.0
    private let preferredBPMs: [Float] = [120, 90, 140, 100, 80, 160]  // Common tempos
    private let beatsPerMeasure: Int = 4  // Assume 4/4 time signature
    
    // MARK: - Public Methods
    
    /// Track beats from onset detections
    /// - Parameter onsets: Array of detected onsets
    /// - Returns: BeatTrackingResult with BPM and beat locations
    func trackBeats(onsets: [Onset]) -> BeatTrackingResult {
        guard onsets.count > 10 else {
            // Too few onsets to track beats
            return BeatTrackingResult(bpm: 120.0, confidence: 0.0, beats: [])
        }
        
        // Phase 1: Tempo detection
        let (bpm, confidence) = detectTempo(onsets: onsets)
        
        // Phase 2: Beat grid alignment
        let beats = alignBeatGrid(onsets: onsets, bpm: bpm)
        
        return BeatTrackingResult(
            bpm: bpm,
            confidence: confidence,
            beats: beats
        )
    }
    
    // MARK: - Phase 1: Tempo Detection
    
    /// Detect tempo using autocorrelation of onset envelope
    private func detectTempo(onsets: [Onset]) -> (bpm: Float, confidence: Float) {
        // Create onset envelope (onset strength over time)
        let envelope = createOnsetEnvelope(onsets: onsets)
        
        // Calculate autocorrelation
        let autocorr = calculateAutocorrelation(signal: envelope)
        
        // Find peaks in valid BPM range
        let peaks = findTempoPeaks(autocorr: autocorr, envelope: envelope)
        
        // Weight peaks by musical preference
        let weightedPeaks = weightPeaksByMusicalPreference(peaks: peaks)
        
        // Select best peak
        guard let bestPeak = weightedPeaks.max(by: { $0.score < $1.score }) else {
            return (120.0, 0.0)  // Default fallback
        }
        
        return (bestPeak.bpm, bestPeak.confidence)
    }
    
    /// Create onset envelope: discrete signal of onset strength
    /// Sampled at 100 Hz (10ms resolution)
    private func createOnsetEnvelope(onsets: [Onset]) -> [Float] {
        guard let lastOnset = onsets.last else { return [] }
        
        let sampleRate: Float = 100.0  // 100 Hz
        let duration = lastOnset.time
        let sampleCount = Int(Float(duration) * sampleRate)
        
        var envelope = [Float](repeating: 0, count: sampleCount)
        
        // Place onsets in envelope
        for onset in onsets {
            let index = Int(Float(onset.time) * sampleRate)
            if index < envelope.count {
                envelope[index] += onset.intensity
            }
        }
        
        return envelope
    }
    
    /// Calculate autocorrelation using vDSP_conv
    private func calculateAutocorrelation(signal: [Float]) -> [Float] {
        let count = signal.count
        var autocorr = [Float](repeating: 0, count: count)
        
        // Autocorrelation: convolve signal with itself
        vDSP_conv(
            signal, 1,
            signal.reversed(), 1,
            &autocorr, 1,
            vDSP_Length(count),
            vDSP_Length(count)
        )
        
        return autocorr
    }
    
    /// Find peaks in autocorrelation corresponding to valid BPM range
    private func findTempoPeaks(autocorr: [Float], envelope: [Float]) -> [(lag: Int, bpm: Float, strength: Float)] {
        let sampleRate: Float = 100.0
        var peaks: [(lag: Int, bpm: Float, strength: Float)] = []
        
        // Convert BPM range to lag range
        let minLag = Int((60.0 / bpmRange.upperBound) * sampleRate)
        let maxLag = Int((60.0 / bpmRange.lowerBound) * sampleRate)
        
        // Find local maxima in autocorrelation
        for lag in minLag..<min(maxLag, autocorr.count - 1) {
            if lag > 0 && lag < autocorr.count - 1 {
                let isLocalMax = autocorr[lag] > autocorr[lag - 1] && autocorr[lag] > autocorr[lag + 1]
                
                if isLocalMax {
                    let bpm = 60.0 * sampleRate / Float(lag)
                    peaks.append((lag, bpm, autocorr[lag]))
                }
            }
        }
        
        return peaks
    }
    
    /// Weight peaks by proximity to musically preferred BPMs
    private func weightPeaksByMusicalPreference(
        peaks: [(lag: Int, bpm: Float, strength: Float)]
    ) -> [(bpm: Float, score: Float, confidence: Float)] {
        return peaks.map { peak in
            // Base score from autocorrelation strength
            var score = peak.strength
            
            // Bonus for preferred BPMs
            let closestPreferred = preferredBPMs.min(by: { abs($0 - peak.bpm) < abs($1 - peak.bpm) }) ?? 120
            let distance = abs(closestPreferred - peak.bpm)
            let preferenceBonus = exp(-distance / 10.0)  // Gaussian bonus
            
            score *= (1.0 + preferenceBonus)
            
            // Confidence based on peak prominence
            let confidence = min(peak.strength / (peaks.map(\.strength).max() ?? 1.0), 1.0)
            
            return (peak.bpm, score, confidence)
        }
    }
    
    // MARK: - Phase 2: Beat Grid Alignment
    
    /// Align beat grid to onsets using dynamic programming
    private func alignBeatGrid(onsets: [Onset], bpm: Float) -> [Beat] {
        guard !onsets.isEmpty else { return [] }
        
        let beatInterval = 60.0 / Double(bpm)
        let duration = onsets.last!.time
        
        // Initialize beat grid
        var beats: [Beat] = []
        
        // Find first beat (strongest onset in first measure)
        let firstMeasureDuration = beatInterval * Double(beatsPerMeasure)
        let firstMeasureOnsets = onsets.filter { $0.time < firstMeasureDuration }
        
        guard let firstBeat = firstMeasureOnsets.max(by: { $0.intensity < $1.intensity }) else {
            return []
        }
        
        let startTime = firstBeat.time
        
        // Generate beat grid
        var beatTime = startTime
        var beatIndex = 0
        
        while beatTime < duration {
            // Find closest onset to this beat position
            let closestOnset = onsets.min(by: { abs($0.time - beatTime) < abs($1.time - beatTime) })
            
            let intensity = closestOnset.map { onset in
                // Intensity decreases with distance from beat
                let distance = abs(onset.time - beatTime)
                let maxDistance = beatInterval * 0.2  // Within 20% of beat interval
                
                if distance < maxDistance {
                    // Scale to at least 0.6, max 1.0 for strong haptics
                    let scaledIntensity = 0.6 + onset.intensity * 0.4
                    let distanceFactor = Float(1.0 - Double(distance) / maxDistance)
                    return scaledIntensity * distanceFactor
                } else {
                    return Float(0.7)  // Higher default for inferred beats (was 0.3)
                }
            } ?? Float(0.7)
            
            // Downbeat every N beats (4 beats per measure in 4/4 time)
            let isDownbeat = beatIndex % beatsPerMeasure == 0
            
            beats.append(Beat(
                time: beatTime,
                intensity: intensity,
                isDownbeat: isDownbeat
            ))
            
            beatTime += beatInterval
            beatIndex += 1
        }
        
        // Refine beat positions using dynamic programming
        beats = refineBeatPositions(beats: beats, onsets: onsets, beatInterval: beatInterval)
        
        return beats
    }
    
    /// Refine beat positions using dynamic programming
    /// Optimize alignment between beat grid and onsets
    private func refineBeatPositions(
        beats: [Beat],
        onsets: [Onset],
        beatInterval: Double
    ) -> [Beat] {
        // For each beat, find best alignment within +/- 10% of beat interval
        let searchWindow = beatInterval * 0.1
        
        return beats.map { beat in
            // Search for strongest onset near this beat
            let nearbyOnsets = onsets.filter { onset in
                abs(onset.time - beat.time) <= searchWindow
            }
            
            guard let bestOnset = nearbyOnsets.max(by: { $0.intensity < $1.intensity }) else {
                return beat
            }
            
            // Snap to strongest nearby onset
            return Beat(
                time: bestOnset.time,
                intensity: bestOnset.intensity,
                isDownbeat: beat.isDownbeat
            )
        }
    }
}
