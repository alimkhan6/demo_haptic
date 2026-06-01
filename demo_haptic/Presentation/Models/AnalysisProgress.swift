//
//  AnalysisProgress.swift
//  haptico
//
//  Progress tracking for audio analysis pipeline
//

import Foundation

// MARK: - Analysis Progress

/// Represents the current progress of audio analysis
struct AnalysisProgress {
    let step: AnalysisStep          // Current analysis step
    let progress: Float             // Progress within current step (0.0-1.0)
    let overallProgress: Float      // Overall progress across all steps (0.0-1.0)
    let estimatedTimeRemaining: TimeInterval?  // Estimated seconds remaining
}

// MARK: - Analysis Steps

/// Individual steps in the audio analysis pipeline
enum AnalysisStep: String, CaseIterable {
    case reading = "Reading audio file"
    case fft = "Computing FFT spectrum"
    case onsets = "Detecting onsets"
    case beats = "Tracking beats"
    case pitch = "Detecting pitch"
    case segments = "Analyzing structure"
    case done = "Analysis complete"
    
    /// Overall progress weight for each step (must sum to 1.0)
    var progressWeight: Float {
        switch self {
        case .reading: return 0.10    // 10%
        case .fft: return 0.50         // 50% - самый тяжелый шаг
        case .onsets: return 0.10      // 10%
        case .beats: return 0.10       // 10%
        case .pitch: return 0.10       // 10%
        case .segments: return 0.10    // 10%
        case .done: return 0.0
        }
    }
    
    /// Starting overall progress for this step
    var startProgress: Float {
        let steps = AnalysisStep.allCases
        guard let index = steps.firstIndex(of: self) else { return 0 }
        return steps.prefix(index).reduce(0.0) { $0 + $1.progressWeight }
    }
    
    /// Calculate overall progress given progress within this step
    func calculateOverallProgress(stepProgress: Float) -> Float {
        return startProgress + (progressWeight * stepProgress)
    }
}

// MARK: - Progress Calculator

/// Helper class to calculate and track analysis progress
final class AnalysisProgressCalculator {
    private var currentStep: AnalysisStep = .reading
    private var stepStartTime: Date?
    private var stepProgressHistory: [(step: AnalysisStep, duration: TimeInterval)] = []
    
    /// Start tracking a new analysis step
    func startStep(_ step: AnalysisStep) {
        // Record previous step duration if exists
        if let startTime = stepStartTime {
            stepProgressHistory.append((
                step: currentStep,
                duration: Date().timeIntervalSince(startTime)
            ))
        }
        
        currentStep = step
        stepStartTime = Date()
    }
    
    /// Create progress update for current step
    func createProgress(stepProgress: Float) -> AnalysisProgress {
        let overallProgress = currentStep.calculateOverallProgress(stepProgress: stepProgress)
        let estimatedTime = estimateTimeRemaining(
            currentStep: currentStep,
            stepProgress: stepProgress
        )
        
        return AnalysisProgress(
            step: currentStep,
            progress: stepProgress,
            overallProgress: overallProgress,
            estimatedTimeRemaining: estimatedTime
        )
    }
    
    /// Estimate remaining time based on current progress
    private func estimateTimeRemaining(
        currentStep: AnalysisStep,
        stepProgress: Float
    ) -> TimeInterval? {
        guard let startTime = stepStartTime, stepProgress > 0.1 else {
            return nil
        }
        
        // Calculate time for current step
        let elapsedInStep = Date().timeIntervalSince(startTime)
        let estimatedStepDuration = elapsedInStep / Double(stepProgress)
        let remainingInStep = estimatedStepDuration * Double(1.0 - stepProgress)
        
        // Estimate time for remaining steps based on history
        let remainingSteps = AnalysisStep.allCases.drop(while: { $0 != currentStep }).dropFirst()
        let estimatedRemainingSteps: TimeInterval
        
        if stepProgressHistory.isEmpty {
            // No history: use proportional estimation based on weights
            let currentStepWeight = currentStep.progressWeight
            let remainingWeight = remainingSteps.reduce(0.0) { $0 + $1.progressWeight }
            
            if currentStepWeight > 0 {
                estimatedRemainingSteps = (elapsedInStep / Double(currentStepWeight)) * Double(remainingWeight)
            } else {
                estimatedRemainingSteps = 0
            }
        } else {
            // Use average from history
            let averageDuration = stepProgressHistory.reduce(0.0) { $0 + $1.duration } / Double(stepProgressHistory.count)
            estimatedRemainingSteps = averageDuration * Double(remainingSteps.count)
        }
        
        return remainingInStep + estimatedRemainingSteps
    }
    
    /// Reset calculator state
    func reset() {
        currentStep = .reading
        stepStartTime = nil
        stepProgressHistory.removeAll()
    }
}

// MARK: - Helper Extensions

extension TimeInterval {
    /// Format time interval as readable string (e.g., "2m 30s")
    var formattedEstimate: String {
        let minutes = Int(self) / 60
        let seconds = Int(self) % 60
        
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}
