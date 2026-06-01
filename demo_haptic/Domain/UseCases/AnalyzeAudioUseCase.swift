import Foundation

/// Protocol defining the contract for audio analysis use case
protocol AnalyzeAudioUseCaseProtocol {
    func execute(audioURL: URL) -> AsyncThrowingStream<AnalysisProgress, Error>
    func getResult() -> AudioAnalysis?
}

/// Concrete implementation of audio analysis use case
/// This use case orchestrates the audio analysis process
final class AnalyzeAudioUseCase: AnalyzeAudioUseCaseProtocol {
    // MARK: - Dependencies
    
    private let analysisRepository: AnalysisRepositoryProtocol
    
    // MARK: - Initialization
    
    init(analysisRepository: AnalysisRepositoryProtocol) {
        self.analysisRepository = analysisRepository
    }
    
    // MARK: - AnalyzeAudioUseCaseProtocol
    
    func execute(audioURL: URL) -> AsyncThrowingStream<AnalysisProgress, Error> {
        return analysisRepository.analyzeAudio(audioURL: audioURL)
    }
    
    func getResult() -> AudioAnalysis? {
        return analysisRepository.getAnalysisResult()
    }
}
