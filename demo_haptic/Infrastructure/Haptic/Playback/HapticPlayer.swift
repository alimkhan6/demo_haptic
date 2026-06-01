//
//  HapticPlayer.swift
//  haptico
//
//  Manages CHHapticEngine for haptic playback
//

import Foundation
import CoreHaptics

// MARK: - Haptic Player

/// Manages haptic playback using CHHapticEngine
final class HapticPlayer {
    
    // MARK: - Properties
    
    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?
    private var pattern: CHHapticPattern?
    
    private var isEngineRunning = false
    
    /// Master intensity multiplier (0.0-2.0, higher values for stronger haptics)
    var intensity: Float = 1.5 {
        didSet {
            updateEngineIntensity()
        }
    }
    
    // MARK: - Initialization
    
    init() {
        setupEngine()
    }
    
    // MARK: - Public Methods
    
    /// Check if haptic engine is available on this device
    static var isAvailable: Bool {
        return CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }
    
    /// Prepare pattern for playback
    /// - Parameter pattern: CHHapticPattern to play
    func prepare(pattern: CHHapticPattern) throws {
        guard let engine = engine else {
            throw HapticPlayerError.engineNotAvailable
        }
        
        self.pattern = pattern
        
        // Start engine if not running
        if !isEngineRunning {
            try engine.start()
            isEngineRunning = true
        }
        
        // Create advanced pattern player
        player = try engine.makeAdvancedPlayer(with: pattern)
    }
    
    /// Start playback at given offset
    /// - Parameter offset: Time offset in seconds to start from
    /// - Note: If seek(to:) was called before, the player is already at the correct position
    func start(at offset: TimeInterval = 0.0) throws {
        guard let engine = engine else {
            throw HapticPlayerError.engineNotAvailable
        }
        
        guard let player = player else {
            throw HapticPlayerError.notPrepared
        }
        
        // Ensure engine is running
        if !isEngineRunning {
            try engine.start()
            isEngineRunning = true
        }
        
        // Seek to the correct position
        try player.seek(toOffset: offset)
        
        // Start playback immediately
        try player.start(atTime: CHHapticTimeImmediate)
    }
    
    /// Stop playback (stops player but keeps engine running)
    func stop() {
        do {
            try player?.stop(atTime: CHHapticTimeImmediate)
        } catch {
            print("Failed to stop haptic player: \(error)")
        }
    }
    
    /// Pause playback (keeps engine running for quick resume)
    func pause() {
        stop()
        // NOTE: We keep the engine running for faster resume/seek
        // The engine will auto-stop after timeout if not used
    }
    
    /// Completely stop and shutdown the engine
    /// Use this when done with playback entirely
    func shutdown() {
        stop()
        
        if isEngineRunning {
            engine?.stop { error in
                if let error = error {
                    print("Failed to stop haptic engine: \(error)")
                }
            }
            isEngineRunning = false
        }
    }
    
    /// Seek to specific time offset
    /// - Parameter time: Time in seconds
    /// - Note: Recreates the player at the new position. Call start() to begin playback.
    func seek(to time: TimeInterval) throws {
        guard let pattern = pattern else {
            throw HapticPlayerError.notPrepared
        }
        
        guard let engine = engine else {
            throw HapticPlayerError.engineNotAvailable
        }
        
        // Stop current player if playing
        stop()
        
        // Ensure engine is running before creating new player
        if !isEngineRunning {
            try engine.start()
            isEngineRunning = true
        }
        
        // Recreate player with pattern
        player = try engine.makeAdvancedPlayer(with: pattern)
        
        // Seek to the desired position
        try player?.seek(toOffset: time)
    }
    
    // MARK: - Private Methods
    
    private func setupEngine() {
        guard Self.isAvailable else {
            print("Haptic engine not available on this device")
            return
        }
        
        do {
            engine = try CHHapticEngine()
            
            // Handle engine reset
            engine?.resetHandler = { [weak self] in
                print("Haptic engine reset")
                self?.isEngineRunning = false
                
                do {
                    try self?.engine?.start()
                    self?.isEngineRunning = true
                    self?.updateEngineIntensity()
                } catch {
                    print("Failed to restart haptic engine: \(error)")
                }
            }
            
            // Handle engine stopped
            engine?.stoppedHandler = { [weak self] reason in
                print("Haptic engine stopped: \(reason)")
                self?.isEngineRunning = false
            }
            
        } catch {
            print("Failed to create haptic engine: \(error)")
        }
    }
    
    private func updateEngineIntensity() {
        guard let engine = engine, isEngineRunning else { return }
        
        do {
            let parameter = CHHapticDynamicParameter(
                parameterID: .hapticIntensityControl,
                value: intensity,
                relativeTime: 0
            )
            engine.notifyWhenPlayersFinished { _ in .stopEngine }
            
            // Apply intensity to current player if exists
            if let player = player {
                try player.sendParameters([parameter], atTime: 0)
            }
        } catch {
            print("Failed to update engine intensity: \(error)")
        }
    }
}

// MARK: - Errors

enum HapticPlayerError: LocalizedError {
    case engineNotAvailable
    case notPrepared
    
    var errorDescription: String? {
        switch self {
        case .engineNotAvailable:
            return "Haptic engine is not available on this device"
        case .notPrepared:
            return "Haptic player not prepared with pattern"
        }
    }
}
