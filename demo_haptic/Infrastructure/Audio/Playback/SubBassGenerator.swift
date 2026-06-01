//
//  SubBassGenerator.swift
//  haptico
//
//  Generates 40Hz sine wave bass synchronized with audio analysis
//

import Foundation
import AVFoundation

// MARK: - Sub Bass Generator

/// Generates low-frequency (40Hz) sine wave modulated by bass energy from analysis
final class SubBassGenerator {
    
    // MARK: - Configuration
    
    private let frequency: Float = 40.0  // 40Hz sine wave
    private let sampleRate: Double = 44100.0
    
    // MARK: - Properties
    
    private let audioEngine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    
    private var analysis: AudioAnalysis?
    private var isPlaying = false
    
    private var currentTime: TimeInterval = 0.0
    private var phase: Float = 0.0
    private var currentAmplitude: Float = 0.0
    private var targetAmplitude: Float = 0.0
    private let smoothingFactor: Float = 0.01  // Smooth amplitude changes
    
    // MARK: - Initialization
    
    init() {
        setupAudioSession()
        setupAudioEngine()
    }
    
    // MARK: - Public Methods
    
    /// Prepare generator with audio analysis
    /// - Parameter analysis: AudioAnalysis containing bass energy data
    func prepare(with analysis: AudioAnalysis) {
        self.analysis = analysis
    }
    
    /// Start generating bass
    func start() {
        guard !isPlaying else { return }
        
        do {
            try audioEngine.start()
            isPlaying = true
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }
    
    /// Stop generating bass
    func stop() {
        guard isPlaying else { return }
        
        audioEngine.stop()
        isPlaying = false
        phase = 0.0
        currentAmplitude = 0.0
        targetAmplitude = 0.0
    }
    
    /// Seek to specific time
    /// - Parameter time: Time in seconds
    func seek(to time: TimeInterval) {
        currentTime = time
        // Reset phase to avoid discontinuity
        let twoPi = 2.0 * Float.pi
        let phaseValue = Float(frequency) * Float(time) * twoPi
        phase = Float(fmod(Double(phaseValue), Double(twoPi)))
        // Update amplitude for new position
        let newAmplitude = getAmplitude(at: time)
        currentAmplitude = newAmplitude
        targetAmplitude = newAmplitude
    }
    
    /// Update current playback time (called by sync timer)
    /// - Parameter time: Current playback time in seconds
    func updateTime(_ time: TimeInterval) {
        currentTime = time
        // Pre-calculate target amplitude for smooth interpolation
        targetAmplitude = getAmplitude(at: time)
    }
    
    // MARK: - Private Methods
    
    private func setupAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            
            // Force output to speaker for better bass response (iOS only)
            try session.overrideOutputAudioPort(.speaker)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
        #endif
    }
    
    private func setupAudioEngine() {
        let mainMixer = audioEngine.mainMixerNode
        
        // Create source node
        let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        
        sourceNode = AVAudioSourceNode(format: inputFormat) { [weak self] _, _, frameCount, audioBufferList in
            guard let self = self else { return noErr }
            
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let phaseIncrement = 2.0 * Float.pi * self.frequency / Float(self.sampleRate)
            
            for frame in 0..<Int(frameCount) {
                // Smooth amplitude interpolation to avoid clicks
                self.currentAmplitude += (self.targetAmplitude - self.currentAmplitude) * self.smoothingFactor
                
                // Generate 40Hz sine wave with smoothed amplitude
                let sample = sin(self.phase) * self.currentAmplitude
                
                // Write to all channels
                for buffer in ablPointer {
                    let buf = UnsafeMutableBufferPointer<Float>(buffer)
                    buf[frame] = sample
                }
                
                // Update phase
                self.phase += phaseIncrement
                
                // Wrap phase to avoid floating point drift
                if self.phase >= 2.0 * Float.pi {
                    self.phase -= 2.0 * Float.pi
                }
            }
            
            return noErr
        }
        
        // Connect nodes
        guard let sourceNode = sourceNode else { return }
        
        audioEngine.attach(sourceNode)
        audioEngine.connect(
            sourceNode,
            to: mainMixer,
            format: inputFormat
        )
        
        // Prepare engine
        audioEngine.prepare()
    }
    
    /// Get amplitude at current time from bass analysis
    /// Formula: amplitude = subBass * 0.3 + midBass * 0.15
    private func getAmplitude(at time: TimeInterval) -> Float {
        guard let analysis = analysis else { return 0.0 }
        
        let (subBass, midBass) = analysis.getBass(at: time)
        
        // Weight sub-bass more heavily (felt vibration)
        // Reduced from 0.4/0.2 to 0.3/0.15 to prevent clipping
        let amplitude = subBass * 0.3 + midBass * 0.15
        
        // Safety clamp to prevent distortion
        return min(amplitude, 0.8)
    }
}
