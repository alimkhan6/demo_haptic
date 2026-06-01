import Foundation

// MARK: - Main Analysis Result

/// Complete audio analysis result containing all extracted features
struct AudioAnalysis: Codable {
    let duration: Double
    let bpm: Float
    let bpmConfidence: Float
    let beats: [Beat]
    let onsets: [Onset]
    let pitch: [PitchPoint]
    let bass: [BassPoint]
    let rms: [RMSPoint]
    let centroid: [CentroidPoint]
    let segments: [Segment]
}

// MARK: - Beat Information

/// Represents a detected beat in the audio
struct Beat: Codable {
    let time: Double        // Time in seconds
    let intensity: Float    // Beat strength (0.0-1.0)
    let isDownbeat: Bool    // True if this is a downbeat (first beat of measure)
}

// MARK: - Onset Information

/// Represents a detected onset (attack/transient) in the audio
struct Onset: Codable {
    let time: Double        // Time in seconds
    let intensity: Float    // Onset strength (0.0-1.0)
    let type: OnsetType     // Classification of onset type
}

/// Type of onset based on spectral characteristics
enum OnsetType: String, Codable {
    case percussive  // High flux across wide frequency range (drums, impacts)
    case tonal       // Flux concentrated in narrow frequency range (melodic instruments)
}

// MARK: - Pitch Information

/// Represents detected pitch at a point in time
struct PitchPoint: Codable {
    let time: Double        // Time in seconds
    let frequency: Float    // Detected pitch in Hz (80-1200 Hz), or 0 if no pitch
}

// MARK: - Bass Energy Information

/// Represents bass energy in two frequency bands
struct BassPoint: Codable {
    let time: Double        // Time in seconds
    let subBass: Float      // Energy in 20-80 Hz range (normalized 0.0-1.0)
    let midBass: Float      // Energy in 80-250 Hz range (normalized 0.0-1.0)
}

// MARK: - RMS Energy Information

/// Represents RMS (root mean square) energy level
struct RMSPoint: Codable {
    let time: Double        // Time in seconds
    let value: Float        // RMS energy (normalized 0.0-1.0)
}

// MARK: - Spectral Centroid Information

/// Represents spectral centroid (brightness) of the audio
struct CentroidPoint: Codable {
    let time: Double        // Time in seconds
    let value: Float        // Centroid normalized to 0.0-1.0 (0-4000 Hz range)
}

// MARK: - Segment Information

/// Represents a structural segment of the track (verse, chorus, etc.)
struct Segment: Codable {
    let time: Double            // Start time in seconds
    let duration: Double        // Segment duration in seconds
    let type: SegmentType       // Type of segment
}

/// Type of structural segment
enum SegmentType: String, Codable {
    case intro
    case verse
    case chorus
    case bridge
    case outro
}

// MARK: - Helper Extensions

extension AudioAnalysis {
    /// Get bass point at specific time using linear interpolation
    func getBass(at time: Double) -> (subBass: Float, midBass: Float) {
        guard !bass.isEmpty else { return (0, 0) }
        
        // Find surrounding points
        guard let afterIndex = bass.firstIndex(where: { $0.time >= time }) else {
            return (bass.last!.subBass, bass.last!.midBass)
        }
        
        if afterIndex == 0 {
            return (bass[0].subBass, bass[0].midBass)
        }
        
        let before = bass[afterIndex - 1]
        let after = bass[afterIndex]
        
        // Linear interpolation
        let t = Float((time - before.time) / (after.time - before.time))
        let subBass = before.subBass + (after.subBass - before.subBass) * t
        let midBass = before.midBass + (after.midBass - before.midBass) * t
        
        return (subBass, midBass)
    }
    
    /// Get RMS value at specific time using linear interpolation
    func getRMS(at time: Double) -> Float {
        guard !rms.isEmpty else { return 0 }
        
        guard let afterIndex = rms.firstIndex(where: { $0.time >= time }) else {
            return rms.last!.value
        }
        
        if afterIndex == 0 {
            return rms[0].value
        }
        
        let before = rms[afterIndex - 1]
        let after = rms[afterIndex]
        
        let t = Float((time - before.time) / (after.time - before.time))
        return before.value + (after.value - before.value) * t
    }
    
    /// Get spectral centroid at specific time using linear interpolation
    func getCentroid(at time: Double) -> Float {
        guard !centroid.isEmpty else { return 0 }
        
        guard let afterIndex = centroid.firstIndex(where: { $0.time >= time }) else {
            return centroid.last!.value
        }
        
        if afterIndex == 0 {
            return centroid[0].value
        }
        
        let before = centroid[afterIndex - 1]
        let after = centroid[afterIndex]
        
        let t = Float((time - before.time) / (after.time - before.time))
        return before.value + (after.value - before.value) * t
    }
    
    /// Get current segment at specific time
    func getSegment(at time: Double) -> Segment? {
        return segments.first { segment in
            time >= segment.time && time < segment.time + segment.duration
        }
    }
    
    /// Find next downbeat after given time
    func nextDownbeat(after time: Double) -> Beat? {
        return beats.first { $0.time > time && $0.isDownbeat }
    }
}
