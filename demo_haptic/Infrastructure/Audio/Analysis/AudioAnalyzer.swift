import Foundation

// MARK: - Audio Analyzer

/// Coordinates all DSP analyzers to produce complete AudioAnalysis
final class AudioAnalyzer {
    
    // MARK: - Components
    
    private let fileReader: AudioFileReaderProtocol
    private let rmsAnalyzer: RMSAnalyzerProtocol
    private let bassAnalyzer: BassAnalyzerProtocol
    private let onsetDetector: OnsetDetectorProtocol
    private let beatTracker: BeatTrackerProtocol
    private let pitchDetector: PitchDetectorProtocol
    private let segmentAnalyzer: SegmentAnalyzerProtocol
    
    private var fftAnalyzer: FFTAnalyzerProtocol?
    private let spectralAnalyzer: SpectralAnalyzerProtocol
    
    // MARK: - State
    
    private var currentAnalysis: AudioAnalysis?
    private var progressCalculator = AnalysisProgressCalculator()
    
    // MARK: - Initialization
    
    init(
        fileReader: AudioFileReaderProtocol = AudioFileReader(),
        rmsAnalyzer: RMSAnalyzerProtocol = RMSAnalyzer(),
        bassAnalyzer: BassAnalyzerProtocol = BassAnalyzer(),
        onsetDetector: OnsetDetectorProtocol = OnsetDetector(),
        beatTracker: BeatTrackerProtocol = BeatTracker(),
        pitchDetector: PitchDetectorProtocol = PitchDetector(),
        segmentAnalyzer: SegmentAnalyzerProtocol = SegmentAnalyzer(),
        spectralAnalyzer: SpectralAnalyzerProtocol = SpectralAnalyzer()
    ) {
        self.fileReader = fileReader
        self.rmsAnalyzer = rmsAnalyzer
        self.bassAnalyzer = bassAnalyzer
        self.onsetDetector = onsetDetector
        self.beatTracker = beatTracker
        self.pitchDetector = pitchDetector
        self.segmentAnalyzer = segmentAnalyzer
        self.spectralAnalyzer = spectralAnalyzer
    }
    
    // MARK: - Public Methods
    
    /// Analyze audio file with progress reporting
    /// - Parameter audioURL: URL to audio file (local or remote)
    /// - Returns: AsyncThrowingStream of progress updates
    func analyze(audioURL: URL) -> AsyncThrowingStream<AnalysisProgress, Error> {
        AsyncThrowingStream { continuation in
            Task.detached(priority: .high) { [weak self] in
                guard let self = self else { return }
                
                do {
                    // Reset state
                    await self.progressCalculator.reset()
                    
                    // Step 1: Read audio file
                    await self.progressCalculator.startStep(.reading)
                    var audioData: AudioFileReader.AudioData? = try await self.readAudio(
                        url: audioURL,
                        continuation: continuation
                    )
                    
                    // Step 2: Compute FFT spectrum
                    await self.progressCalculator.startStep(.fft)
                    let spectralResult = try await self.computeSpectrum(
                        samples: audioData!.samples,
                        sampleRate: audioData!.sampleRate,
                        continuation: continuation
                    )
                    
                    // ✅ Get FFTResults from spectralResult (single source of truth)
                    let fftResults = spectralResult.fftResults
                    
                    // Step 3: Detect onsets
                    await self.progressCalculator.startStep(.onsets)
                    let onsets = try await self.detectOnsets(
                        spectralResult: spectralResult,
                        continuation: continuation
                    )
                    
                    // Step 4: Track beats
                    await self.progressCalculator.startStep(.beats)
                    let beatResult = try await self.trackBeats(
                        onsets: onsets,
                        continuation: continuation
                    )
                    
                    // Compute RMS and Bass in parallel BEFORE other analysis
                    // These need samples/FFT results, so do them early
                    print("🔊 [AudioAnalyzer] Computing RMS and Bass in parallel...")
                    async let rmsPoints = self.rmsAnalyzer.analyze(
                        samples: audioData!.samples,
                        sampleRate: audioData!.sampleRate
                    )
                    async let bassPoints = self.bassAnalyzer.analyze(fftResults: fftResults)
                    
                    // Step 5: Detect pitch (needs samples)
                    print("🎯 [AudioAnalyzer] Starting pitch detection...")
                    await self.progressCalculator.startStep(.pitch)
                    let pitchPoints = try await self.detectPitch(
                        samples: audioData!.samples,
                        sampleRate: audioData!.sampleRate,
                        continuation: continuation
                    )
                    print("✅ [AudioAnalyzer] Pitch detection complete: \(pitchPoints.count) points")
                    
                    // Await RMS and Bass results
                    let (rms, bass) = await (rmsPoints, bassPoints)
                    print("✅ [AudioAnalyzer] RMS and Bass complete")
                    
                    // Step 6: Analyze segments
                    print("📊 [AudioAnalyzer] Starting segment analysis...")
                    await self.progressCalculator.startStep(.segments)
                    let duration = audioData!.duration
                    
                    // ✅ Free samples ASAP - no longer needed after pitch detection
                    audioData = nil
                    print("🧹 [AudioAnalyzer] Released audio samples from memory")
                    
                    let segments = try await self.analyzeStructure(
                        fftResults: fftResults,
                        rmsPoints: rms,
                        onsets: onsets,
                        duration: duration,
                        continuation: continuation
                    )
                    print("✅ [AudioAnalyzer] Segment analysis complete: \(segments.count) segments")
                    
                    // Create final analysis
                    let analysis = AudioAnalysis(
                        duration: duration,  // ✅ Use saved duration
                        bpm: beatResult.bpm,
                        bpmConfidence: beatResult.confidence,
                        beats: beatResult.beats,
                        onsets: onsets,
                        pitch: pitchPoints,
                        bass: bass,
                        rms: rms,
                        centroid: spectralResult.centroidPoints,
                        segments: segments
                    )
                    
                    await self.setCurrentAnalysis(analysis)
                    
                    // Report completion
                    await self.progressCalculator.startStep(.done)
                    continuation.yield(await self.progressCalculator.createProgress(stepProgress: 1.0))
                    continuation.finish()
                    
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Get the result of the most recent analysis
    func getResult() -> AudioAnalysis? {
        return currentAnalysis
    }
    
    /// Set current analysis (thread-safe)
    private func setCurrentAnalysis(_ analysis: AudioAnalysis) async {
        self.currentAnalysis = analysis
    }
    
    // MARK: - Pipeline Steps
    
    /// Step 1: Read audio file
    private func readAudio(
        url: URL,
        continuation: AsyncThrowingStream<AnalysisProgress, Error>.Continuation
    ) async throws -> AudioFileReader.AudioData {
        return try await fileReader.readAudio(from: url) { progress in
            let analysisProgress = self.progressCalculator.createProgress(stepProgress: progress)
            continuation.yield(analysisProgress)
        }
    }
    
    /// Step 2: Compute FFT spectrum, RMS, bass, centroid, flux
    private func computeSpectrum(
        samples: [Float],
        sampleRate: Double,
        continuation: AsyncThrowingStream<AnalysisProgress, Error>.Continuation
    ) async throws -> SpectralAnalysisResult {
        // Initialize FFT analyzer
        guard let fftAnalyzer = FFTAnalyzer() else {
            throw NSError(domain: "AudioAnalyzer", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to initialize FFT analyzer"
            ])
        }
        self.fftAnalyzer = fftAnalyzer
        
        // Progress: 0-80% for FFT (более тяжелый шаг)
        let fftResults = await fftAnalyzer.analyzeWithProgress(
            samples: samples,
            sampleRate: sampleRate,
            chunkSize: 500  // Увеличен с 100 до 500 для меньшего overhead
        ) { fftProgress in
            let overallProgress = Float(fftProgress * 0.8)  // 0-80%
            continuation.yield(self.progressCalculator.createProgress(stepProgress: overallProgress))
        }
        
        // Progress: 80-100% for spectral features (быстрее, меньше процента)
        let spectralResult = await spectralAnalyzer.analyzeWithProgress(
            fftResults: fftResults,
            chunkSize: 500  // Увеличен с 100 до 500
        ) { spectralProgress in
            let overallProgress = Float(0.8 + spectralProgress * 0.2)  // 80-100%
            continuation.yield(self.progressCalculator.createProgress(stepProgress: overallProgress))
        }
        
        // ✅ Return only spectralResult - it already contains fftResults
        return spectralResult
    }
    
    /// Step 3: Detect onsets
    private func detectOnsets(
        spectralResult: SpectralAnalysisResult,
        continuation: AsyncThrowingStream<AnalysisProgress, Error>.Continuation
    ) async throws -> [Onset] {
        continuation.yield(progressCalculator.createProgress(stepProgress: 0.0))
        
        let onsets = onsetDetector.detectOnsets(
            fluxValues: spectralResult.fluxValues,
            fftResults: spectralResult.fftResults
        )
        
        continuation.yield(progressCalculator.createProgress(stepProgress: 1.0))
        
        return onsets
    }
    
    /// Step 4: Track beats
    private func trackBeats(
        onsets: [Onset],
        continuation: AsyncThrowingStream<AnalysisProgress, Error>.Continuation
    ) async throws -> BeatTrackingResult {
        continuation.yield(progressCalculator.createProgress(stepProgress: 0.0))
        
        let beatResult = beatTracker.trackBeats(onsets: onsets)
        
        continuation.yield(progressCalculator.createProgress(stepProgress: 1.0))
        
        return beatResult
    }
    
    /// Step 5: Detect pitch
    private func detectPitch(
        samples: [Float],
        sampleRate: Double,
        continuation: AsyncThrowingStream<AnalysisProgress, Error>.Continuation
    ) async throws -> [PitchPoint] {
        let pitchPoints = await pitchDetector.detectPitchWithProgress(
            samples: samples,
            sampleRate: sampleRate,
            chunkSize: 20  // Smaller chunks for more frequent updates
        ) { pitchProgress in
            continuation.yield(self.progressCalculator.createProgress(stepProgress: Float(pitchProgress)))
        }
        
        return pitchPoints
    }
    
    /// Step 6: Analyze structure
    private func analyzeStructure(
        fftResults: [FFTResult],
        rmsPoints: [RMSPoint],
        onsets: [Onset],
        duration: Double,
        continuation: AsyncThrowingStream<AnalysisProgress, Error>.Continuation
    ) async throws -> [Segment] {
        continuation.yield(progressCalculator.createProgress(stepProgress: 0.0))
        
        let segments = segmentAnalyzer.analyzeSegments(
            fftResults: fftResults,
            rmsPoints: rmsPoints,
            onsets: onsets,
            duration: duration
        )
        
        continuation.yield(progressCalculator.createProgress(stepProgress: 1.0))
        
        return segments
    }
}
