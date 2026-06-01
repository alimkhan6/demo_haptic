import Foundation

/// Concrete implementation of analysis repository
final class AnalysisRepositoryImpl: AnalysisRepositoryProtocol {
    // MARK: - Dependencies
    
    private let audioAnalyzer: AudioAnalyzer
    
    // MARK: - Initialization
    
    init(audioAnalyzer: AudioAnalyzer) {
        self.audioAnalyzer = audioAnalyzer
    }
    
    // MARK: - AnalysisRepositoryProtocol
    
    func analyzeAudio(audioURL: URL) -> AsyncThrowingStream<AnalysisProgress, Error> {
        return audioAnalyzer.analyze(audioURL: audioURL)
    }
    
    func getAnalysisResult() -> AudioAnalysis? {
        return audioAnalyzer.getResult()
    }
}
