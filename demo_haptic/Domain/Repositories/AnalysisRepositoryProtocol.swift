import Foundation

/// Repository protocol for audio analysis operations
protocol AnalysisRepositoryProtocol {
    /// Analyze audio file with progress reporting
    /// - Parameter audioURL: Local URL of the audio file
    /// - Returns: AsyncThrowingStream of progress updates
    func analyzeAudio(audioURL: URL) -> AsyncThrowingStream<AnalysisProgress, Error>
    
    /// Get the result of the most recent analysis
    /// - Returns: AudioAnalysis if available
    func getAnalysisResult() -> AudioAnalysis?
}
