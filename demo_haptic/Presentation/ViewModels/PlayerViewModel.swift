import Foundation
import Combine

@MainActor
final class PlayerViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isSeeking: Bool = false
    @Published var seekPosition: TimeInterval = 0
    
    // MARK: - Dependencies
    
    private let player: SynchronizedPlayer
    private let analysis: AudioAnalysis
    private let intensityService: HapticIntensityService
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(
        player: SynchronizedPlayer,
        analysis: AudioAnalysis,
        intensityService: HapticIntensityService
    ) {
        self.player = player
        self.analysis = analysis
        self.intensityService = intensityService
        
        setupBindings()
    }
    
    // MARK: - Public Methods
    
    func togglePlayPause() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
    }
    
    func seek(to time: TimeInterval) {
        player.seek(to: time)
        isSeeking = false
    }
    
    func updateSeekPosition(_ position: TimeInterval) {
        seekPosition = position
        isSeeking = true
    }
    
    func getAnalysis() -> AudioAnalysis {
        return analysis
    }
    
    func getCurrentSegment() -> Segment? {
        return analysis.getSegment(at: currentTime)
    }
    
    func cleanup() {
        player.pause()
        cancellables.removeAll()
    }
    
    // MARK: - Layer Intensity Calculations
    
    func getDownbeatIntensity() -> Float {
        return intensityService.getDownbeatIntensity(analysis: analysis, currentTime: currentTime)
    }
    
    func getBeatIntensity() -> Float {
        return intensityService.getBeatIntensity(analysis: analysis, currentTime: currentTime)
    }
    
    func getOnsetIntensity() -> Float {
        return intensityService.getOnsetIntensity(analysis: analysis, currentTime: currentTime)
    }
    
    func getBackgroundIntensity() -> Float {
        return intensityService.getBackgroundIntensity(analysis: analysis, currentTime: currentTime)
    }
    
    func getBassIntensity() -> Float {
        return intensityService.getBassIntensity(analysis: analysis, currentTime: currentTime)
    }
    
    func getSegmentIntensity() -> Float {
        return intensityService.getSegmentIntensity(analysis: analysis, currentTime: currentTime)
    }
    
    func getAllIntensities() -> LayerIntensities {
        return intensityService.getAllIntensities(analysis: analysis, currentTime: currentTime)
    }
    
    // MARK: - Private Methods
    
    private func setupBindings() {
        // Observe player state changes
        player.objectWillChange
            .sink { [weak self] _ in
                self?.updateFromPlayer()
            }
            .store(in: &cancellables)
        
        // Initial update
        updateFromPlayer()
    }
    
    private func updateFromPlayer() {
        isPlaying = player.isPlaying
        currentTime = player.currentTime
        duration = player.duration
    }
}
