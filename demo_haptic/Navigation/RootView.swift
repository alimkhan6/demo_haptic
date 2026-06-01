import SwiftUI

/// Root view that observes coordinator and displays appropriate screen
struct RootView: View {
    // MARK: - Properties
    
    @ObservedObject var coordinator: AppCoordinator
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            coordinatorContent
                .navigationBarHidden(true)
        }
    }
    
    // MARK: - Content Builder
    
    @ViewBuilder
    private var coordinatorContent: some View {
        switch coordinator.currentScreen {
        case .input:
            InputViewContainer(coordinator: coordinator)
            
        case .player(let player, let analysis):
            PlayerViewContainer(
                coordinator: coordinator,
                player: player,
                analysis: analysis
            )
        }
    }
}

// MARK: - View Containers

/// Container that creates InputViewModel only once
private struct InputViewContainer: View {
    @ObservedObject var coordinator: AppCoordinator
    @StateObject private var viewModel: InputViewModel
    
    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        _viewModel = StateObject(wrappedValue: coordinator.makeInputViewModel())
    }
    
    var body: some View {
        InputView(viewModel: viewModel)
            .environmentObject(coordinator)
    }
}

/// Container that creates PlayerViewModel only once
private struct PlayerViewContainer: View {
    @ObservedObject var coordinator: AppCoordinator
    let player: SynchronizedPlayer
    let analysis: AudioAnalysis
    @StateObject private var viewModel: PlayerViewModel
    
    init(coordinator: AppCoordinator, player: SynchronizedPlayer, analysis: AudioAnalysis) {
        self.coordinator = coordinator
        self.player = player
        self.analysis = analysis
        _viewModel = StateObject(
            wrappedValue: coordinator.makePlayerViewModel(player: player, analysis: analysis)
        )
    }
    
    var body: some View {
        PlayerView(
            viewModel: viewModel,
            player: player,
            analysis: analysis
        )
        .environmentObject(coordinator)
    }
}
