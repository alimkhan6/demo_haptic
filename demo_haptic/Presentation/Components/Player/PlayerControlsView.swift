//
//  PlayerControlsView.swift
//  haptico
//
//  Player controls component with play/pause and back button
//

import SwiftUI

struct PlayerControlsView: View {
    @ObservedObject var viewModel: PlayerViewModel
    let onBack: () -> Void
    
    var body: some View {
        HStack(spacing: 40) {
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.title2)
            }
            
            Button(action: viewModel.togglePlayPause) {
                Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 80))
            }
        }
    }
}
