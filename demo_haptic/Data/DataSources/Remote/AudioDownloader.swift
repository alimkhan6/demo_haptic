import Foundation

// MARK: - Audio Downloader

/// Downloads audio files from URLs with progress tracking
final class AudioDownloader: NSObject {
    
    // MARK: - Progress Callback
    
    typealias ProgressHandler = (Double) -> Void
    
    // MARK: - Properties
    
    private var downloadTask: URLSessionDownloadTask?
    private var progressHandler: ProgressHandler?
    private var continuation: CheckedContinuation<URL, Error>?
    
    // MARK: - Public Methods
    
    /// Download audio file from URL
    /// - Parameters:
    ///   - url: Remote URL to audio file
    ///   - progressHandler: Called with progress (0.0-1.0)
    /// - Returns: Local file URL of downloaded file
    func download(
        from url: URL,
        progressHandler: @escaping ProgressHandler
    ) async throws -> URL {
        print("📥 [AudioDownloader] Starting download from: \(url.absoluteString)")
        self.progressHandler = progressHandler
        
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            
            let config = URLSessionConfiguration.default
            let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            
            downloadTask = session.downloadTask(with: url)
            print("📥 [AudioDownloader] Download task created and starting...")
            downloadTask?.resume()
        }
    }
    
    /// Cancel ongoing download
    func cancel() {
        downloadTask?.cancel()
        continuation?.resume(throwing: CancellationError())
    }
}

// MARK: - URLSessionDownloadDelegate

extension AudioDownloader: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        print("✅ [AudioDownloader] Download finished to temporary location: \(location.path)")
        
        // Check HTTP response
        if let httpResponse = downloadTask.response as? HTTPURLResponse {
            print("📡 [AudioDownloader] HTTP Status Code: \(httpResponse.statusCode)")
            print("📡 [AudioDownloader] Content-Type: \(httpResponse.allHeaderFields["Content-Type"] ?? "unknown")")
            print("📡 [AudioDownloader] Content-Length: \(httpResponse.allHeaderFields["Content-Length"] ?? "unknown")")
            
            // Check if content type is HTML (YouTube page)
            if let contentType = httpResponse.allHeaderFields["Content-Type"] as? String,
               contentType.contains("text/html") {
                print("❌ [AudioDownloader] Downloaded file is HTML, not audio!")
                print("💡 [AudioDownloader] YouTube links need to be converted to direct audio URLs")
                continuation?.resume(throwing: HapticoError.unsupportedFormat("YouTube links are not supported. Please use direct audio file links (MP3, AAC, WAV)."))
                return
            }
        }
        
        // Check file size
        if let fileSize = try? FileManager.default.attributesOfItem(atPath: location.path)[.size] as? Int64 {
            print("📊 [AudioDownloader] Downloaded file size: \(fileSize) bytes")
            
            // Read first few bytes to check file signature
            if let data = try? Data(contentsOf: location, options: .mappedIfSafe).prefix(100) {
                let preview = String(data: data, encoding: .utf8) ?? "binary data"
                print("📄 [AudioDownloader] File preview: \(preview.prefix(200))")
            }
        }
        
        // Move to permanent location
        let tempDirectory = FileManager.default.temporaryDirectory
        let destinationURL = tempDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("audio")
        
        print("📁 [AudioDownloader] Moving file to: \(destinationURL.path)")
        
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                print("⚠️ [AudioDownloader] Destination file exists, removing...")
                try FileManager.default.removeItem(at: destinationURL)
            }
            
            try FileManager.default.moveItem(at: location, to: destinationURL)
            print("✅ [AudioDownloader] File moved successfully")
            continuation?.resume(returning: destinationURL)
        } catch {
            print("❌ [AudioDownloader] Failed to move file: \(error.localizedDescription)")
            continuation?.resume(throwing: HapticoError.downloadFailed(
                downloadTask.originalRequest?.url ?? location,
                underlying: error
            ))
        }
    }
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else {
            print("⚠️ [AudioDownloader] Unknown file size, progress unavailable")
            return
        }
        
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        print("📊 [AudioDownloader] Progress: \(Int(progress * 100))% (\(totalBytesWritten)/\(totalBytesExpectedToWrite) bytes)")
        progressHandler?(progress)
    }
    
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error = error {
            print("❌ [AudioDownloader] Download failed with error: \(error.localizedDescription)")
            if let httpResponse = (task as? URLSessionDownloadTask)?.response as? HTTPURLResponse {
                print("📡 [AudioDownloader] HTTP Status Code: \(httpResponse.statusCode)")
                print("📡 [AudioDownloader] Response Headers: \(httpResponse.allHeaderFields)")
            }
            continuation?.resume(throwing: HapticoError.networkError(underlying: error))
        }
    }
}
