import Foundation

/// Protocol for dependency injection container
protocol DIContainerProtocol {
    // MARK: - Repositories
    var audioRepository: AudioRepositoryProtocol { get }
    var analysisRepository: AnalysisRepositoryProtocol { get }
    
    // MARK: - Use Cases
    func makeAnalyzeAudioUseCase() -> AnalyzeAudioUseCaseProtocol
    func makeImportAudioFileUseCase() -> ImportAudioFileUseCaseProtocol
    func makeDownloadAudioUseCase() -> DownloadAudioUseCaseProtocol
    
    // MARK: - Services
    func makeHapticIntensityService() -> HapticIntensityService
    
    // MARK: - ViewModels
    func makeInputViewModel() -> InputViewModel
    func makePlayerViewModel(player: SynchronizedPlayer, analysis: AudioAnalysis) -> PlayerViewModel
    
    // MARK: - Players
    func makeSynchronizedPlayer() -> SynchronizedPlayer
    
    // MARK: - Coordinators
    func makeAppCoordinator() -> AppCoordinator
}

/// Concrete implementation of DI Container
final class DIContainer: DIContainerProtocol {
    // MARK: - Singleton Repositories (shared instances)
    
    private(set) lazy var audioRepository: AudioRepositoryProtocol = {
        AudioRepositoryImpl()
    }()
    
    private(set) lazy var analysisRepository: AnalysisRepositoryProtocol = {
        AnalysisRepositoryImpl(audioAnalyzer: AudioAnalyzer())
    }()
    
    // MARK: - Use Cases Factory
    
    func makeAnalyzeAudioUseCase() -> AnalyzeAudioUseCaseProtocol {
        return AnalyzeAudioUseCase(analysisRepository: analysisRepository)
    }
    
    func makeImportAudioFileUseCase() -> ImportAudioFileUseCaseProtocol {
        return ImportAudioFileUseCase(audioRepository: audioRepository)
    }
    
    func makeDownloadAudioUseCase() -> DownloadAudioUseCaseProtocol {
        return DownloadAudioUseCase(audioRepository: audioRepository)
    }
    
    // MARK: - Services Factory
    
    func makeHapticIntensityService() -> HapticIntensityService {
        let config = HapticIntensityConfig(
            downbeatScale: 1.0,
            beatScale: 0.75,
            percussiveOnsetScale: 0.65,
            tonalOnsetScale: 0.4,
            backgroundScale: 0.6,
            subBassScale: 0.3,
            midBassScale: 0.15,
            bassMaxScale: 0.9,
            timeThreshold: 0.05,
            segmentFadeDuration: 0.1
        )
        return HapticIntensityService(config: config)
    }
    
    // MARK: - ViewModels Factory
    
    func makeInputViewModel() -> InputViewModel {
        return InputViewModel(
            analyzeAudioUseCase: makeAnalyzeAudioUseCase(),
            importAudioFileUseCase: makeImportAudioFileUseCase()
        )
    }
    
    func makePlayerViewModel(player: SynchronizedPlayer, analysis: AudioAnalysis) -> PlayerViewModel {
        return PlayerViewModel(
            player: player,
            analysis: analysis,
            intensityService: makeHapticIntensityService()
        )
    }
    
    // MARK: - Players Factory
    
    func makeSynchronizedPlayer() -> SynchronizedPlayer {
        return SynchronizedPlayer()
    }
    
    // MARK: - Coordinators Factory
    
    func makeAppCoordinator() -> AppCoordinator {
        return AppCoordinator(container: self)
    }
}
