import Foundation

/// Concrete implementation of audio repository
final class AudioRepositoryImpl: AudioRepositoryProtocol {
    // MARK: - Dependencies
    
    private let audioDownloader: AudioDownloader
    
    // MARK: - Initialization
    
    init(audioDownloader: AudioDownloader = AudioDownloader()) {
        self.audioDownloader = audioDownloader
    }
    
    // MARK: - AudioRepositoryProtocol
    
    func downloadAudio(from url: URL, progressHandler: @escaping (Double) -> Void) async throws -> URL {
        return try await audioDownloader.download(from: url, progressHandler: progressHandler)
    }
    
    func importAudio(from sourceURL: URL) throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        
        // Remove existing temp file if any
        try? FileManager.default.removeItem(at: tempURL)
        
        // Copy file
        try FileManager.default.copyItem(at: sourceURL, to: tempURL)
        
        return tempURL
    }
    
    func getDemoAudio(fileName: String) throws -> URL {
        guard let bundleURL = Bundle.main.url(forResource: fileName, withExtension: "mp3") else {
            throw HapticoError.fileNotFound("\(fileName).mp3")
        }
        return bundleURL
    }
}
