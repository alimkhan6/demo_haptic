import Foundation

/// Repository protocol for audio file operations
protocol AudioRepositoryProtocol {
    /// Download audio from remote URL
    /// - Parameters:
    ///   - url: Remote URL of the audio file
    ///   - progressHandler: Callback for download progress (0.0-1.0)
    /// - Returns: Local URL of the downloaded file
    func downloadAudio(from url: URL, progressHandler: @escaping (Double) -> Void) async throws -> URL
    
    /// Import audio file from device
    /// - Parameter sourceURL: Source URL (security-scoped)
    /// - Returns: Local URL of the imported file
    func importAudio(from sourceURL: URL) throws -> URL
    
    /// Get demo audio file from bundle
    /// - Parameter fileName: Name of the file (without extension)
    /// - Returns: URL of the demo file
    func getDemoAudio(fileName: String) throws -> URL
}
