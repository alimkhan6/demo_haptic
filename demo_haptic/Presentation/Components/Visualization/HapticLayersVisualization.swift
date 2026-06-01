//
//  HapticLayersVisualization.swift
//  haptico
//
//  Multi-layer haptic visualization component
//

import SwiftUI

struct HapticLayersVisualization: View {
    @ObservedObject var viewModel: PlayerViewModel
    
    var body: some View {
        VStack(spacing: 8) {
            // Row 1: Downbeats, Beats, Onsets
            HStack(spacing: 8) {
                LayerBar(
                    title: "Downbeats",
                    value: viewModel.getDownbeatIntensity(),
                    color: .red
                )
                LayerBar(
                    title: "Beats",
                    value: viewModel.getBeatIntensity(),
                    color: .orange
                )
                LayerBar(
                    title: "Onsets",
                    value: viewModel.getOnsetIntensity(),
                    color: .yellow
                )
            }
            
            // Row 2: Background, Bass, Segment
            HStack(spacing: 8) {
                LayerBar(
                    title: "Background",
                    value: viewModel.getBackgroundIntensity(),
                    color: .green
                )
                LayerBar(
                    title: "Bass",
                    value: viewModel.getBassIntensity(),
                    color: .blue
                )
                LayerBar(
                    title: "Chorus",
                    value: viewModel.getSegmentIntensity(),
                    color: .purple
                )
            }
        }
    }
}
