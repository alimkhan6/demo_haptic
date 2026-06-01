import Foundation

// MARK: - Haptico Errors

enum HapticoError: LocalizedError {
    case downloadFailed(URL, underlying: Error)
    case unsupportedFormat(String)
    case analysisFailedAtStep(AnalysisStep, underlying: Error)
    case hapticEngineUnavailable
    case fileReadError(underlying: Error)
    case cacheError(underlying: Error)
    case networkError(underlying: Error)
    case invalidURL(String)
    case fileNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .downloadFailed(let url, let error):
            return "Failed to download audio from \(url.absoluteString): \(error.localizedDescription)"
            
        case .unsupportedFormat(let format):
            return "Unsupported audio format: \(format). Please use MP3, AAC, or WAV."
            
        case .analysisFailedAtStep(let step, let error):
            return "Analysis failed at step '\(step.rawValue)': \(error.localizedDescription)"
            
        case .hapticEngineUnavailable:
            return "Haptic engine is not available on this device. Playback will continue without haptic feedback."
            
        case .fileReadError(let error):
            return "Failed to read audio file: \(error.localizedDescription)"
            
        case .cacheError(let error):
            return "Cache operation failed: \(error.localizedDescription)"
            
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
            
        case .invalidURL(let urlString):
            return "Invalid URL: \(urlString)"
            
        case .fileNotFound(let fileName):
            return "File not found: \(fileName)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .downloadFailed:
            return "Please check your internet connection and verify the URL is correct."
            
        case .unsupportedFormat:
            return "Try converting the audio file to MP3, AAC, or WAV format."
            
        case .analysisFailedAtStep:
            return "Try downloading the file again or using a different audio file."
            
        case .hapticEngineUnavailable:
            return "Haptic feedback requires iPhone 8 or newer. You can still enjoy the audio and visual effects."
            
        case .fileReadError:
            return "Make sure the file exists and is accessible."
            
        case .cacheError:
            return "Try clearing the app cache in Settings."
            
        case .networkError:
            return "Check your internet connection and try again."
            
        case .invalidURL:
            return "Please enter a valid URL starting with http:// or https://"
            
        case .fileNotFound:
            return "Make sure the file is added to the app bundle."
        }
    }
}
