//
//  PlaybackSynchronizer.swift
//  haptico
//
//  Service for synchronizing multiple playback streams (audio, haptics, sub-bass)
//

import Foundation
import QuartzCore

// MARK: - Playback Synchronizer Protocol

/// Protocol for synchronizing multiple playback streams
protocol PlaybackSynchronizerProtocol {
    /// Start synchronization timer
    @MainActor
    func startSynchronization(
        startHostTime: CFTimeInterval,
        seekOffset: TimeInterval,
        duration: TimeInterval,
        onUpdate: @escaping (TimeInterval) -> Void,
        onComplete: @escaping () -> Void
    )
    
    /// Stop synchronization timer
    @MainActor
    func stopSynchronization()
}

// MARK: - Playback Synchronizer

/// Coordinates timing synchronization between audio, haptics, and sub-bass
final class PlaybackSynchronizer: PlaybackSynchronizerProtocol {
    
    // MARK: - Properties
    
    private var syncTimer: Timer?
    private let syncInterval: TimeInterval = 0.02 // 50 Hz update rate
    
    // MARK: - Public Methods
    
    /// Start synchronization with timing callbacks
    @MainActor
    func startSynchronization(
        startHostTime: CFTimeInterval,
        seekOffset: TimeInterval,
        duration: TimeInterval,
        onUpdate: @escaping (TimeInterval) -> Void,
        onComplete: @escaping () -> Void
    ) {
        stopSynchronization()
        
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let elapsed = CACurrentMediaTime() - startHostTime
            let syncTime = seekOffset + elapsed
            
            // Update callback with current sync time
            onUpdate(syncTime)
            
            // Check if playback ended
            if syncTime >= duration {
                Task { @MainActor in
                    self.stopSynchronization()
                    onComplete()
                }
            }
        }
    }
    
    /// Stop synchronization timer
    @MainActor
    func stopSynchronization() {
        syncTimer?.invalidate()
        syncTimer = nil
    }
    
    // MARK: - Deinitialization
    
    deinit {
        syncTimer?.invalidate()
        syncTimer = nil
    }
}
