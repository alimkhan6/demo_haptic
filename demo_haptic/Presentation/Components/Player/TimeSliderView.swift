//
//  TimeSliderView.swift
//  haptico
//
//  Time slider component for audio playback
//

import SwiftUI

struct TimeSliderView: View {
    @ObservedObject var viewModel: PlayerViewModel
    
    var body: some View {
        VStack(spacing: 8) {
            // Time display
            HStack {
                Text(formatTime(viewModel.isSeeking ? viewModel.seekPosition : viewModel.currentTime))
                Spacer()
                Text(formatTime(viewModel.duration))
            }
            .font(.caption)
            .foregroundColor(.secondary)
            
            // Progress slider
            Slider(
                value: Binding(
                    get: {
                        viewModel.isSeeking ? viewModel.seekPosition : viewModel.currentTime
                    },
                    set: { newValue in
                        viewModel.updateSeekPosition(newValue)
                    }
                ),
                in: 0...viewModel.duration,
                onEditingChanged: { editing in
                    if !editing {
                        viewModel.seek(to: viewModel.seekPosition)
                    }
                }
            )
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
