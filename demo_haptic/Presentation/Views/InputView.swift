import SwiftUI
import Combine

struct InputView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @StateObject var viewModel: InputViewModel
    @State private var showFilePicker = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Progress bar at the top
            if let progress = viewModel.analysisProgress {
                ProgressBarView(progress: progress)
            }
            
            // Main content
            VStack(spacing: 40) {
                Spacer()
                
                // Demo Button
                ActionButtonView(
                    iconName: "waveform.circle.fill",
                    title: "Analyze Demo Track",
                    subtitle: "Rush by Maneskin",
                    gradientColors: [.purple, .blue],
                    isDisabled: viewModel.isProcessing,
                    action: viewModel.analyzeDemoTrack
                )
                .padding(.horizontal)
                
                // Import Button
                ActionButtonView(
                    iconName: "folder.circle.fill",
                    title: "Import from Device",
                    subtitle: "Audio or video files (MP3, MP4, etc.)",
                    gradientColors: [.orange, .pink],
                    isDisabled: viewModel.isProcessing,
                    action: { showFilePicker = true }
                )
                .padding(.horizontal)
                
                Spacer()
                
                // Error message
                if let error = viewModel.errorMessage {
                    ErrorMessageView(message: error)
                }
            }
            .padding()
        }
        .sheet(isPresented: $showFilePicker) {
            DocumentPickerView(
                onFilePicked: { url in
                    viewModel.importAndAnalyze(from: url)
                },
                onError: { error in
                    viewModel.setError(error)
                }
            )
        }
        .onReceive(viewModel.$analysisResult) { result in
            if let result = result {
                coordinator.showPlayer(audioURL: result.audioURL, analysis: result.analysis)
            }
        }
    }
}
