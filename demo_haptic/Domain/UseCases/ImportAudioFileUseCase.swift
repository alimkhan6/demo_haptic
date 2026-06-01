import Foundation

/// Protocol defining the contract for audio file importing use case
protocol ImportAudioFileUseCaseProtocol {
    func execute(from sourceURL: URL) throws -> URL
    func getDemoTrack(fileName: String) throws -> URL
}

/// Concrete implementation of audio file import use case
/// This use case orchestrates the audio import process
final class ImportAudioFileUseCase: ImportAudioFileUseCaseProtocol {
    // MARK: - Dependencies
    
    private let audioRepository: AudioRepositoryProtocol
    
    // MARK: - Initialization
    
    init(audioRepository: AudioRepositoryProtocol) {
        self.audioRepository = audioRepository
    }
    
    // MARK: - ImportAudioFileUseCaseProtocol
    
    func execute(from sourceURL: URL) throws -> URL {
        return try audioRepository.importAudio(from: sourceURL)
    }
    
    func getDemoTrack(fileName: String) throws -> URL {
        return try audioRepository.getDemoAudio(fileName: fileName)
    }
}
