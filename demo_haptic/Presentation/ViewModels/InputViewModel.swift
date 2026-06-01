import Foundation
import Combine

@MainActor
final class InputViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var analysisProgress: AnalysisProgress?
    @Published var errorMessage: String?
    @Published var isProcessing: Bool = false
    @Published var analysisResult: (audioURL: URL, analysis: AudioAnalysis)?
    
    // MARK: - Dependencies
    
    private let analyzeAudioUseCase: AnalyzeAudioUseCaseProtocol
    private let importAudioFileUseCase: ImportAudioFileUseCaseProtocol
    
    // MARK: - Initialization
    
    init(
        analyzeAudioUseCase: AnalyzeAudioUseCaseProtocol,
        importAudioFileUseCase: ImportAudioFileUseCaseProtocol
    ) {
        self.analyzeAudioUseCase = analyzeAudioUseCase
        self.importAudioFileUseCase = importAudioFileUseCase
    }
    
    // MARK: - Public Methods
    
    /// Start analysis with demo track from bundle
    func analyzeDemoTrack() {
        Task {
            do {
                let bundleURL = try importAudioFileUseCase.getDemoTrack(fileName: "Rush")
                try await analyzeAudioFile(at: bundleURL)
            } catch {
                handleError(error)
            }
        }
    }
    
    /// Import and analyze file from device
    func importAndAnalyze(from sourceURL: URL) {
        Task {
            do {
                // Start accessing security-scoped resource
                guard sourceURL.startAccessingSecurityScopedResource() else {
                    throw HapticoError.invalidURL("Unable to access file")
                }
                
                defer { sourceURL.stopAccessingSecurityScopedResource() }
                
                // Import file to temp directory
                let tempURL = try importAudioFileUseCase.execute(from: sourceURL)
                
                // Analyze the imported file
                try await analyzeAudioFile(at: tempURL)
                
            } catch {
                handleError(error)
            }
        }
    }
    
    /// Clear error message
    func clearError() {
        errorMessage = nil
    }
    
    /// Set error message
    func setError(_ message: String) {
        errorMessage = message
    }
    
    // MARK: - Private Methods
    
    private func analyzeAudioFile(at url: URL) async throws {
        isProcessing = true
        errorMessage = nil
        
        let stream = analyzeAudioUseCase.execute(audioURL: url)
        
        for try await progress in stream {
            analysisProgress = progress
            
            if progress.step == .done {
                // Analysis complete
                if let analysis = analyzeAudioUseCase.getResult() {
                    isProcessing = false
                    analysisProgress = nil
                    analysisResult = (audioURL: url, analysis: analysis)
                }
            }
        }
    }
    
    private func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
        isProcessing = false
        analysisProgress = nil
    }
}
