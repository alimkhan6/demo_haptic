import Foundation

/// Protocol defining the contract for audio downloading use case
protocol DownloadAudioUseCaseProtocol {
    func execute(from url: URL, progressHandler: @escaping (Double) -> Void) async throws -> URL
}

/// Concrete implementation of audio download use case
/// This use case orchestrates the audio download process
final class DownloadAudioUseCase: DownloadAudioUseCaseProtocol {
    // MARK: - Dependencies
    
    private let audioRepository: AudioRepositoryProtocol
    
    // MARK: - Initialization
    
    init(audioRepository: AudioRepositoryProtocol) {
        self.audioRepository = audioRepository
    }
    
    // MARK: - DownloadAudioUseCaseProtocol
    
    func execute(from url: URL, progressHandler: @escaping (Double) -> Void) async throws -> URL {
        return try await audioRepository.downloadAudio(from: url, progressHandler: progressHandler)
    }
}
