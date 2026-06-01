import Foundation

// MARK: - Audio File Reader Protocol

/// Protocol for reading audio files and extracting PCM samples
protocol AudioFileReaderProtocol {
    /// Audio data structure
    typealias AudioData = AudioFileReader.AudioData
    
    /// Read audio file and extract PCM samples
    /// - Parameters:
    ///   - url: URL to audio file
    ///   - progressHandler: Progress callback (0.0-1.0)
    /// - Returns: AudioData with samples, sample rate, and duration
    func readAudio(
        from url: URL,
        progressHandler: @escaping (Float) -> Void
    ) async throws -> AudioData
}

// MARK: - RMS Analyzer Protocol

/// Protocol for RMS energy analysis
protocol RMSAnalyzerProtocol {
    /// Analyze RMS energy of audio samples
    /// - Parameters:
    ///   - samples: Input audio samples
    ///   - sampleRate: Sample rate of audio
    /// - Returns: Array of RMSPoint with time and normalized values
    func analyze(samples: [Float], sampleRate: Double) async -> [RMSPoint]
}

// MARK: - Bass Analyzer Protocol

/// Protocol for bass frequency analysis
protocol BassAnalyzerProtocol {
    /// Analyze bass energy from FFT results
    /// - Parameter fftResults: Array of FFT results
    /// - Returns: Array of BassPoint with sub-bass and mid-bass energies
    func analyze(fftResults: [FFTResult]) async -> [BassPoint]
}

// MARK: - Onset Detector Protocol

/// Protocol for onset detection
protocol OnsetDetectorProtocol {
    /// Detect onsets from spectral flux and FFT data
    /// - Parameters:
    ///   - fluxValues: Spectral flux values
    ///   - fftResults: FFT results
    /// - Returns: Array of detected onsets
    func detectOnsets(fluxValues: [Float], fftResults: [FFTResult]) -> [Onset]
}

// MARK: - Beat Tracker Protocol

/// Protocol for beat tracking
protocol BeatTrackerProtocol {
    /// Track beats from detected onsets
    /// - Parameter onsets: Array of onsets
    /// - Returns: Beat tracking result with BPM and beat times
    func trackBeats(onsets: [Onset]) -> BeatTrackingResult
}

// MARK: - Pitch Detector Protocol

/// Protocol for pitch detection
protocol PitchDetectorProtocol {
    /// Detect pitch from audio samples
    /// - Parameters:
    ///   - samples: Input audio samples
    ///   - sampleRate: Sample rate of audio
    ///   - chunkSize: Chunk size for progress reporting
    ///   - progressHandler: Progress callback
    /// - Returns: Array of pitch points
    func detectPitchWithProgress(
        samples: [Float],
        sampleRate: Double,
        chunkSize: Int,
        progressHandler: @escaping (Double) -> Void
    ) async -> [PitchPoint]
}

// MARK: - Segment Analyzer Protocol

/// Protocol for segment/structure analysis
protocol SegmentAnalyzerProtocol {
    /// Analyze audio structure and segments
    /// - Parameters:
    ///   - fftResults: FFT results
    ///   - rmsPoints: RMS energy points
    ///   - onsets: Detected onsets
    ///   - duration: Total audio duration
    /// - Returns: Array of segments
    func analyzeSegments(
        fftResults: [FFTResult],
        rmsPoints: [RMSPoint],
        onsets: [Onset],
        duration: Double
    ) -> [Segment]
}

// MARK: - FFT Analyzer Protocol

/// Protocol for FFT analysis
protocol FFTAnalyzerProtocol {
    /// Analyze audio with FFT and report progress
    /// - Parameters:
    ///   - samples: Input audio samples
    ///   - sampleRate: Sample rate
    ///   - chunkSize: Chunk size for progress reporting
    ///   - progressHandler: Progress callback
    /// - Returns: Array of FFT results
    func analyzeWithProgress(
        samples: [Float],
        sampleRate: Double,
        chunkSize: Int,
        progressHandler: @escaping (Double) -> Void
    ) async -> [FFTResult]
}

// MARK: - Spectral Analyzer Protocol

/// Protocol for spectral feature analysis
protocol SpectralAnalyzerProtocol {
    /// Analyze spectral features from FFT results
    /// - Parameters:
    ///   - fftResults: Array of FFT results
    ///   - chunkSize: Chunk size for progress reporting
    ///   - progressHandler: Progress callback
    /// - Returns: Spectral analysis result
    func analyzeWithProgress(
        fftResults: [FFTResult],
        chunkSize: Int,
        progressHandler: @escaping (Double) -> Void
    ) async -> SpectralAnalysisResult
}
