//
//  AHAPGenerator.swift
//  haptico
//
//  Generates CHHapticPattern from AudioAnalysis
//

import Foundation
import CoreHaptics

// MARK: - AHAP Generator

/// Generates haptic patterns from audio analysis results
final class AHAPGenerator {
    
    // MARK: - Configuration
    
    private struct HapticMapping {
        // ═══════════════════════════════════════════════════════════════════
        // TRANSIENT EVENTS (Short, Punchy)
        // ═══════════════════════════════════════════════════════════════════
        
        // Downbeats: EXPLOSIVE - максимальная сила и резкость
        // Pattern: ████ (single heavy impact)
        static let downbeatIntensityScale: Float = 1.0
        static let downbeatSharpness: Float = 1.0
        
        // Regular beats: CRISP - умеренная сила, высокая резкость
        // Pattern: ███ (crisp tap)
        static let beatIntensityScale: Float = 0.75
        static let beatSharpness: Float = 0.9
        
        // Percussive onsets: SNAPPY - УСИЛЕНО для больше ударов
        // Pattern: ███ (strong snap)
        static let percussiveIntensityScale: Float = 0.85  // было 0.65
        static let percussiveSharpness: Float = 1.0  // было 0.95 - максимум!
        
        // Tonal onsets: SOFT TAP - УСИЛЕНО
        // Pattern: ██ (medium tap)
        static let tonalIntensityScale: Float = 0.65  // было 0.4
        // Sharpness varies with spectral centroid (0.4-0.8 range - выше!)
        
        // ═══════════════════════════════════════════════════════════════════
        // CONTINUOUS EVENTS (Long, Sustained)
        // ═══════════════════════════════════════════════════════════════════
        
        // Background layer: AMBIENT PULSE - ритмичная пульсация
        // Pattern: ▁▂▁▂▁▂ (steady rhythmic pulse)
        static let backgroundIntensityScale: Float = 0.6
        static let backgroundSharpness: Float = 0.3
        static let backgroundInterval: Double = 0.08  // 12.5Hz - faster pulse
        static let backgroundDuration: Double = 0.10
        static let backgroundBoost: Float = 1.8  // ВАРИАНТ 2: пропорциональное усиление
        
        // Bass layer: DEEP RUMBLE - глубокая непрерывная вибрация
        // Pattern: ▂▃▄▃▂ (rolling bass wave)
        static let bassIntensityScale: Float = 0.9
        static let bassSharpness: Float = 0.0  // Максимально мягкое для баса
        static let bassInterval: Double = 0.04  // 25Hz - более плавное
        static let bassDuration: Double = 0.08  // Длиннее для слияния
        static let bassBoost: Float = 1.5  // ВАРИАНТ 2: пропорциональное усиление
        
        // ═══════════════════════════════════════════════════════════════════
        // SPECIAL EVENTS
        // ═══════════════════════════════════════════════════════════════════
        
        // Segment boundaries (chorus): THUNDER STRIKE - мощнейший акцент
        // Pattern: █████ (massive impact)
        static let segmentBoundaryIntensity: Float = 1.0
        static let segmentBoundarySharpness: Float = 1.0
    }
    
    // MARK: - Public Methods
    
    /// Generate CHHapticPattern from audio analysis
    /// - Parameter analysis: Complete audio analysis result
    /// - Returns: CHHapticPattern ready for playback
    /// - Throws: If pattern creation fails
    func generatePattern(from analysis: AudioAnalysis) throws -> CHHapticPattern {
        var events: [CHHapticEvent] = []
        
        // 1. Add downbeats (strongest)
        events.append(contentsOf: createDownbeatEvents(beats: analysis.beats))
        
        // 2. Add regular beats
        events.append(contentsOf: createBeatEvents(beats: analysis.beats))
        
        // 3. Add onsets
        events.append(contentsOf: createOnsetEvents(
            onsets: analysis.onsets,
            beats: analysis.beats,
            centroidPoints: analysis.centroid
        ))
        
        // 4. Add background continuous layer
        events.append(contentsOf: createBackgroundLayer(
            rmsPoints: analysis.rms,
            duration: analysis.duration,
            beats: analysis.beats,
            onsets: analysis.onsets
        ))
        
        // 5. Add bass continuous layer
        events.append(contentsOf: createBassLayer(
            bassPoints: analysis.bass,
            duration: analysis.duration,
            beats: analysis.beats,
            onsets: analysis.onsets
        ))
        
        // 6. Add segment boundaries (chorus emphasis)
        events.append(contentsOf: createSegmentBoundaryEvents(segments: analysis.segments))
        
        // Sort events by time
        events.sort { $0.relativeTime < $1.relativeTime }
        
        // Create pattern
        return try CHHapticPattern(events: events, parameters: [])
    }
    
    // MARK: - Event Creation
    
    /// Create transient events for downbeats
    private func createDownbeatEvents(beats: [Beat]) -> [CHHapticEvent] {
        return beats
            .filter { $0.isDownbeat }
            .map { beat in
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(
                            parameterID: .hapticIntensity,
                            value: beat.intensity * HapticMapping.downbeatIntensityScale
                        ),
                        CHHapticEventParameter(
                            parameterID: .hapticSharpness,
                            value: HapticMapping.downbeatSharpness
                        )
                    ],
                    relativeTime: beat.time
                )
            }
    }
    
    /// Create transient events for regular beats (non-downbeats)
    private func createBeatEvents(beats: [Beat]) -> [CHHapticEvent] {
        return beats
            .filter { !$0.isDownbeat }
            .map { beat in
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(
                            parameterID: .hapticIntensity,
                            value: beat.intensity * HapticMapping.beatIntensityScale
                        ),
                        CHHapticEventParameter(
                            parameterID: .hapticSharpness,
                            value: HapticMapping.beatSharpness
                        )
                    ],
                    relativeTime: beat.time
                )
            }
    }
    
    /// Create transient events for onsets (ALL onsets, no filtering for maximum impact!)
    private func createOnsetEvents(
        onsets: [Onset],
        beats: [Beat],
        centroidPoints: [CentroidPoint]
    ) -> [CHHapticEvent] {
        // ФИЛЬТР УБРАН - используем ВСЕ onsets для максимального количества ударов!
        // Это создаст наложение с beats, но даст больше ощущений
        
        return onsets
            .map { onset in
                let sharpness: Float
                let intensityScale: Float
                
                switch onset.type {
                case .percussive:
                    // Percussive: максимально резкое и быстрое
                    sharpness = HapticMapping.percussiveSharpness
                    intensityScale = HapticMapping.percussiveIntensityScale
                    
                case .tonal:
                    // Tonal: УСИЛЕНО - более резкие тональные удары
                    // Spectral centroid определяет "яркость" тона
                    let centroid = getCentroid(at: onset.time, from: centroidPoints)
                    
                    // Map centroid (0.0-1.0) to sharpness range (0.4-0.8) - ВЫШЕ!
                    // Низкие частоты (бас-гитара) = средне (0.4)
                    // Высокие частоты (струны, голос) = резко (0.8)
                    sharpness = 0.4 + centroid * 0.4
                    intensityScale = HapticMapping.tonalIntensityScale
                }
                
                return CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(
                            parameterID: .hapticIntensity,
                            value: onset.intensity * intensityScale
                        ),
                        CHHapticEventParameter(
                            parameterID: .hapticSharpness,
                            value: sharpness
                        )
                    ],
                    relativeTime: onset.time
                )
            }
    }
    
    /// Create continuous background layer based on RMS energy
    /// Pattern: Ambient pulse that breathes with the music
    /// ПРИОРИТИЗАЦИЯ: Отключается рядом с transient events
    private func createBackgroundLayer(
        rmsPoints: [RMSPoint],
        duration: Double,
        beats: [Beat],
        onsets: [Onset]
    ) -> [CHHapticEvent] {
        var events: [CHHapticEvent] = []
        var time: Double = 0.0
        var previousRMS: Float = 0.0
        
        // Собираем все transient времена для проверки
        let transientTimes = beats.map { $0.time } + onsets.map { $0.time }
        let suppressionWindow: Double = 0.05  // ±50ms вокруг transient
        
        while time < duration {
            // Get RMS value at this time
            let rmsValue = getRMS(at: time, from: rmsPoints)
            
            // Calculate change in RMS (velocity) for more dynamic feel
            let rmsVelocity = abs(rmsValue - previousRMS)
            
            // Base intensity from RMS, boosted by changes
            // Apply power curve to boost presence
            let baseIntensity = pow(rmsValue, 0.7) * 0.7 + rmsVelocity * 0.3
            
            // ВАРИАНТ 2: Пропорциональное усиление - умножаем на boost
            let boosted = baseIntensity * HapticMapping.backgroundBoost
            let intensity = boosted * HapticMapping.backgroundIntensityScale
            
            // ПРИОРИТИЗАЦИЯ: Пропускаем событие если рядом есть transient
            let hasNearbyTransient = transientTimes.contains { abs($0 - time) < suppressionWindow }
            
            // ФИЛЬТР УБРАН - создаём ВСЕ события, даже слабые!
            if intensity > 0.0 && !hasNearbyTransient {
                let event = CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(
                            parameterID: .hapticIntensity,
                            value: min(intensity, 1.0)
                        ),
                        CHHapticEventParameter(
                            parameterID: .hapticSharpness,
                            value: HapticMapping.backgroundSharpness
                        )
                    ],
                    relativeTime: time,
                    duration: HapticMapping.backgroundDuration
                )
                
                events.append(event)
            }
            
            previousRMS = rmsValue
            time += HapticMapping.backgroundInterval
        }
        
        return events
    }
    
    /// Create continuous bass layer based on bass energy (matches SubBassGenerator)
    /// Pattern: Deep, rolling rumble that follows sub-bass frequencies
    /// ПРИОРИТИЗАЦИЯ: Отключается рядом с transient events
    private func createBassLayer(
        bassPoints: [BassPoint],
        duration: Double,
        beats: [Beat],
        onsets: [Onset]
    ) -> [CHHapticEvent] {
        var events: [CHHapticEvent] = []
        var time: Double = 0.0
        var previousBass: Float = 0.0
        
        // Собираем все transient времена для проверки
        let transientTimes = beats.map { $0.time } + onsets.map { $0.time }
        let suppressionWindow: Double = 0.05  // ±50ms вокруг transient
        
        while time < duration {
            // Get bass values at this time (same formula as SubBassGenerator)
            let bassValue = getBass(at: time, from: bassPoints)
            
            // Smooth out rapid changes for more continuous feel
            let smoothedBass = previousBass * 0.3 + bassValue * 0.7
            
            // Apply power curve to boost bass presence
            let boostedBass = pow(smoothedBass, 0.6)
            
            // ВАРИАНТ 2: Пропорциональное усиление - умножаем на boost
            let amplified = boostedBass * HapticMapping.bassBoost
            let intensity = amplified * HapticMapping.bassIntensityScale
            
            // ПРИОРИТИЗАЦИЯ: Пропускаем событие если рядом есть transient
            let hasNearbyTransient = transientTimes.contains { abs($0 - time) < suppressionWindow }
            
            // ФИЛЬТР УБРАН - создаём ВСЕ басовые события!
            if intensity > 0.0 && !hasNearbyTransient {
                let event = CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(
                            parameterID: .hapticIntensity,
                            value: min(intensity, 1.0)
                        ),
                        CHHapticEventParameter(
                            parameterID: .hapticSharpness,
                            value: HapticMapping.bassSharpness
                        )
                    ],
                    relativeTime: time,
                    duration: HapticMapping.bassDuration
                )
                
                events.append(event)
            }
            
            previousBass = smoothedBass
            time += HapticMapping.bassInterval
        }
        
        return events
    }
    
    /// Create strong transient events at chorus segment boundaries
    private func createSegmentBoundaryEvents(segments: [Segment]) -> [CHHapticEvent] {
        return segments
            .filter { $0.type == .chorus }
            .map { segment in
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(
                            parameterID: .hapticIntensity,
                            value: HapticMapping.segmentBoundaryIntensity
                        ),
                        CHHapticEventParameter(
                            parameterID: .hapticSharpness,
                            value: HapticMapping.segmentBoundarySharpness
                        )
                    ],
                    relativeTime: segment.time
                )
            }
    }
    
    // MARK: - Helper Methods
    
    /// Get RMS value at specific time using linear interpolation
    private func getRMS(at time: Double, from rmsPoints: [RMSPoint]) -> Float {
        guard !rmsPoints.isEmpty else { return 0 }
        
        // Find surrounding points
        guard let afterIndex = rmsPoints.firstIndex(where: { $0.time >= time }) else {
            return rmsPoints.last!.value
        }
        
        if afterIndex == 0 {
            return rmsPoints[0].value
        }
        
        let before = rmsPoints[afterIndex - 1]
        let after = rmsPoints[afterIndex]
        
        // Linear interpolation
        let t = Float((time - before.time) / (after.time - before.time))
        return before.value + (after.value - before.value) * t
    }
    
    /// Get spectral centroid at specific time using linear interpolation
    private func getCentroid(at time: Double, from centroidPoints: [CentroidPoint]) -> Float {
        guard !centroidPoints.isEmpty else { return 0.5 }
        
        guard let afterIndex = centroidPoints.firstIndex(where: { $0.time >= time }) else {
            return centroidPoints.last!.value
        }
        
        if afterIndex == 0 {
            return centroidPoints[0].value
        }
        
        let before = centroidPoints[afterIndex - 1]
        let after = centroidPoints[afterIndex]
        
        let t = Float((time - before.time) / (after.time - before.time))
        return before.value + (after.value - before.value) * t
    }
    
    /// Get bass amplitude at specific time (matches SubBassGenerator formula)
    /// Formula: amplitude = subBass * 0.3 + midBass * 0.15
    private func getBass(at time: Double, from bassPoints: [BassPoint]) -> Float {
        guard !bassPoints.isEmpty else { return 0.0 }
        
        // Find surrounding points
        guard let afterIndex = bassPoints.firstIndex(where: { $0.time >= time }) else {
            let last = bassPoints.last!
            return last.subBass * 0.3 + last.midBass * 0.15
        }
        
        if afterIndex == 0 {
            let first = bassPoints[0]
            return first.subBass * 0.3 + first.midBass * 0.15
        }
        
        let before = bassPoints[afterIndex - 1]
        let after = bassPoints[afterIndex]
        
        // Linear interpolation
        let t = Float((time - before.time) / (after.time - before.time))
        let subBass = before.subBass + (after.subBass - before.subBass) * t
        let midBass = before.midBass + (after.midBass - before.midBass) * t
        
        // Same formula as SubBassGenerator (reduced to prevent clipping)
        let amplitude = subBass * 0.3 + midBass * 0.15
        
        return min(amplitude, 0.8)
    }
}
