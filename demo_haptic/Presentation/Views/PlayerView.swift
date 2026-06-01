import SwiftUI

struct PlayerView: View {
    @StateObject var viewModel: PlayerViewModel
    @EnvironmentObject var coordinator: AppCoordinator
    
    let player: SynchronizedPlayer
    let analysis: AudioAnalysis
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // BPM Display
            BPMDisplayView(
                bpm: viewModel.getAnalysis().bpm,
                confidence: viewModel.getAnalysis().bpmConfidence
            )
            
            // Multi-Layer Haptic Visualization
            HapticLayersVisualization(viewModel: viewModel)
                .frame(height: 200)
                .padding(.horizontal)
            
            // Current Segment
            SegmentLabel(segment: viewModel.getCurrentSegment())
            
            // Time slider
            TimeSliderView(viewModel: viewModel)
                .padding(.horizontal)
            
            // Play/Pause button
            PlayerControlsView(
                viewModel: viewModel,
                onBack: {
                    viewModel.cleanup()
                    coordinator.reset()
                }
            )
            
            Spacer()
        }
        .padding()
        .navigationBarBackButtonHidden(true)
    }
}
