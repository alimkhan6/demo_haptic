//
//  SynchronizedPlayer.swift
//  haptico
//
//  Synchronizes three playback streams: AVPlayer + CHHaptics + SubBass
//

import Foundation
import AVFoundation
import CoreHaptics
import Combine

// MARK: - Synchronized Player

/// Coordinates synchronized playback of audio, haptics, and sub-bass
@MainActor
final class SynchronizedPlayer: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0.0
    @Published var duration: TimeInterval = 0.0
    
    // MARK: - Components
    
    private var avPlayer: AVPlayer?
    private let hapticPlayer: HapticPlayer
    private let subBassGenerator: SubBassGenerator
    private let ahapGenerator: AHAPGenerator
    private let synchronizer: PlaybackSynchronizerProtocol
    
    // MARK: - State
    
    private var analysis: AudioAnalysis?
    private var audioURL: URL?
    
    private var startHostTime: CFTimeInterval?
    private var seekOffset: TimeInterval = 0.0
    
    private var timeObserver: Any?
    
    // MARK: - Initialization
    
    init(
        hapticPlayer: HapticPlayer,
        subBassGenerator: SubBassGenerator,
        ahapGenerator: AHAPGenerator,
        synchronizer: PlaybackSynchronizerProtocol
    ) {
        self.hapticPlayer = hapticPlayer
        self.subBassGenerator = subBassGenerator
        self.ahapGenerator = ahapGenerator
        self.synchronizer = synchronizer
    }
    
    /// Convenience initializer for creating with default dependencies
    convenience init() {
        self.init(
            hapticPlayer: HapticPlayer(),
            subBassGenerator: SubBassGenerator(),
            ahapGenerator: AHAPGenerator(),
            synchronizer: PlaybackSynchronizer()
        )
    }
    
    deinit {
        // Note: Cannot call @MainActor methods from deinit
        // Timer will be invalidated when synchronizer is deallocated
        
        // Remove time observer
        if let observer = timeObserver {
            avPlayer?.removeTimeObserver(observer)
            timeObserver = nil
        }
    }
    
    // MARK: - Public Methods
    
    /// Prepare player with audio file and analysis
    /// - Parameters:
    ///   - audioURL: URL to audio file
    ///   - analysis: Complete audio analysis
    func prepare(audioURL: URL, analysis: AudioAnalysis) throws {
        self.audioURL = audioURL
        self.analysis = analysis
        self.duration = analysis.duration
        
        // Setup AVPlayer
        let playerItem = AVPlayerItem(url: audioURL)
        avPlayer = AVPlayer(playerItem: playerItem)
        
        // Setup time observer
        setupTimeObserver()
        
        // Prepare haptics (if available)
        if HapticPlayer.isAvailable {
            do {
                let pattern = try ahapGenerator.generatePattern(from: analysis)
                try hapticPlayer.prepare(pattern: pattern)
            } catch {
                print("Failed to prepare haptics: \(error)")
                // Continue without haptics
            }
        }
        
        // Prepare sub-bass generator
        subBassGenerator.prepare(with: analysis)
    }
    
    /// Start playback from current position
    func play() {
        guard let avPlayer = avPlayer else { return }
        
        // Record exact start time for sync
        startHostTime = CACurrentMediaTime()
        
        // Start audio first for reference
        avPlayer.play()
        
        // Start haptics at current seekOffset position
        if HapticPlayer.isAvailable {
            do {
                try hapticPlayer.start(at: seekOffset)
            } catch {
                print("Failed to start haptics: \(error)")
                // Continue without haptics
            }
        }
        
        // Start sub-bass generator
        subBassGenerator.start()
        
        // Start synchronization
        startSynchronization()
        
        isPlaying = true
    }
    
    /// Pause playback
    func pause() {
        guard let avPlayer = avPlayer else { return }
        
        // Stop all streams
        avPlayer.pause()
        hapticPlayer.pause()
        subBassGenerator.stop()
        
        synchronizer.stopSynchronization()
        
        // Update seek offset for resume - calculate exact position
        if let startTime = startHostTime {
            let elapsed = CACurrentMediaTime() - startTime
            seekOffset += elapsed
            
            // Also update currentTime to match
            currentTime = seekOffset
        }
        
        isPlaying = false
    }
    
    /// Seek to specific time
    /// - Parameter time: Time in seconds
    func seek(to time: TimeInterval) {
        guard let avPlayer = avPlayer else { return }
        
        let wasPlaying = isPlaying
        
        // Pause if playing
        if wasPlaying {
            pause()
        }
        
        // CRITICAL: Update seekOffset and currentTime immediately for UI
        seekOffset = time
        currentTime = time
        
        // Seek audio (fast, on main thread)
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        avPlayer.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        
        // Seek sub-bass (fast)
        subBassGenerator.seek(to: time)
        
        // Seek haptics asynchronously (heavy operation - recreates player)
        Task {
            try? hapticPlayer.seek(to: time)
            
            // Resume if was playing (on main thread)
            if wasPlaying {
                await MainActor.run {
                    startHostTime = nil
                    play()
                }
            }
        }
    }
    
    /// Get current analysis (for UI)
    func getAnalysis() -> AudioAnalysis? {
        return analysis
    }
    
    // MARK: - Private Methods
    
    private func setupTimeObserver() {
        guard let avPlayer = avPlayer else { return }
        
        // Observe time every 0.1 seconds
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        
        timeObserver = avPlayer.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.currentTime = time.seconds
            }
        }
    }
    
    private func startSynchronization() {
        guard let startTime = startHostTime,
              let duration = analysis?.duration else { return }
        
        synchronizer.startSynchronization(
            startHostTime: startTime,
            seekOffset: seekOffset,
            duration: duration,
            onUpdate: { [weak self] syncTime in
                // Update sub-bass generator time
                self?.subBassGenerator.updateTime(syncTime)
            },
            onComplete: { [weak self] in
                self?.pause()
                self?.seek(to: 0)
            }
        )
    }
    
    private func cleanup() {
        // Stop playback first
        pause()
        
        // Shutdown haptics
        hapticPlayer.shutdown()
        
        // Stop sub-bass
        subBassGenerator.stop()
        
        // Remove time observer
        if let observer = timeObserver {
            avPlayer?.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        // Stop synchronizer
        synchronizer.stopSynchronization()
        startHostTime = nil
        
        // Clear AVPlayer
        avPlayer = nil
    }
}
