import Foundation

/// Configuration for haptic intensity calculations
struct HapticIntensityConfig: Sendable {
    let downbeatScale: Float
    let beatScale: Float
    let percussiveOnsetScale: Float
    let tonalOnsetScale: Float
    let backgroundScale: Float
    let subBassScale: Float
    let midBassScale: Float
    let bassMaxScale: Float
    let timeThreshold: Double
    let segmentFadeDuration: Double
}

/// Service for calculating haptic layer intensities
/// This service is nonisolated and can be called from any context
final class HapticIntensityService: Sendable {
    // MARK: - Properties
    
    private let config: HapticIntensityConfig
    
    // MARK: - Initialization
    
    nonisolated init(config: HapticIntensityConfig) {
        self.config = config
    }
    
    // MARK: - Public Methods
    
    /// Calculate downbeat intensity at specific time
    func getDownbeatIntensity(analysis: AudioAnalysis, currentTime: Double) -> Float {
        if let beat = analysis.beats.first(where: {
            $0.isDownbeat && abs($0.time - currentTime) < config.timeThreshold
        }) {
            return beat.intensity * config.downbeatScale
        }
        return 0.0
    }
    
    /// Calculate beat intensity at specific time
    func getBeatIntensity(analysis: AudioAnalysis, currentTime: Double) -> Float {
        if let beat = analysis.beats.first(where: {
            !$0.isDownbeat && abs($0.time - currentTime) < config.timeThreshold
        }) {
            return beat.intensity * config.beatScale
        }
        return 0.0
    }
    
    /// Calculate onset intensity at specific time
    func getOnsetIntensity(analysis: AudioAnalysis, currentTime: Double) -> Float {
        let beatTimes = Set(analysis.beats.map { $0.time })
        
        if let onset = analysis.onsets.first(where: { onset in
            abs(onset.time - currentTime) < config.timeThreshold &&
            !beatTimes.contains(where: { abs($0 - onset.time) < config.timeThreshold })
        }) {
            let scale: Float = onset.type == .percussive ? config.percussiveOnsetScale : config.tonalOnsetScale
            return onset.intensity * scale
        }
        return 0.0
    }
    
    /// Calculate background intensity at specific time
    func getBackgroundIntensity(analysis: AudioAnalysis, currentTime: Double) -> Float {
        let rmsValue = analysis.getRMS(at: currentTime)
        return rmsValue * config.backgroundScale
    }
    
    /// Calculate bass intensity at specific time
    func getBassIntensity(analysis: AudioAnalysis, currentTime: Double) -> Float {
        let (subBass, midBass) = analysis.getBass(at: currentTime)
        let bassValue = subBass * config.subBassScale + midBass * config.midBassScale
        return min(bassValue * config.bassMaxScale, 1.0)
    }
    
    /// Calculate segment transition intensity at specific time
    func getSegmentIntensity(analysis: AudioAnalysis, currentTime: Double) -> Float {
        if let segment = analysis.segments.first(where: {
            $0.type == .chorus && abs($0.time - currentTime) < config.segmentFadeDuration
        }) {
            let timeSinceBoundary = currentTime - segment.time
            if timeSinceBoundary >= 0 && timeSinceBoundary < config.segmentFadeDuration {
                let fadeProgress = Float(timeSinceBoundary / config.segmentFadeDuration)
                return 1.0 * (1.0 - fadeProgress)
            }
        }
        return 0.0
    }
    
    /// Get all layer intensities at once
    func getAllIntensities(analysis: AudioAnalysis, currentTime: Double) -> LayerIntensities {
        return LayerIntensities(
            downbeat: getDownbeatIntensity(analysis: analysis, currentTime: currentTime),
            beat: getBeatIntensity(analysis: analysis, currentTime: currentTime),
            onset: getOnsetIntensity(analysis: analysis, currentTime: currentTime),
            background: getBackgroundIntensity(analysis: analysis, currentTime: currentTime),
            bass: getBassIntensity(analysis: analysis, currentTime: currentTime),
            segment: getSegmentIntensity(analysis: analysis, currentTime: currentTime)
        )
    }
}

/// Container for all layer intensities
struct LayerIntensities {
    let downbeat: Float
    let beat: Float
    let onset: Float
    let background: Float
    let bass: Float
    let segment: Float
}
