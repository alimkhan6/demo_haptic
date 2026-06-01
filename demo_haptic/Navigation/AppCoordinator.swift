import Foundation
import Combine

@MainActor
final class AppCoordinator: ObservableObject {
    // MARK: - Published Properties
    
    @Published var currentScreen: Screen = .input
    
    // MARK: - Dependencies
    
    private let container: DIContainerProtocol
    
    // MARK: - Screen Definition
    
    enum Screen {
        case input
        case player(player: SynchronizedPlayer, analysis: AudioAnalysis)
    }
    
    // MARK: - Initialization
    
    init(container: DIContainerProtocol) {
        self.container = container
    }
    
    // MARK: - Factory Methods
    
    /// Create InputViewModel using DI Container
    func makeInputViewModel() -> InputViewModel {
        return container.makeInputViewModel()
    }
    
    /// Create PlayerViewModel using DI Container
    func makePlayerViewModel(player: SynchronizedPlayer, analysis: AudioAnalysis) -> PlayerViewModel {
        return container.makePlayerViewModel(player: player, analysis: analysis)
    }
    
    /// Get current player and analysis from screen state
    func getCurrentPlayerState() -> (player: SynchronizedPlayer, analysis: AudioAnalysis)? {
        if case .player(let player, let analysis) = currentScreen {
            return (player, analysis)
        }
        return nil
    }
    
    // MARK: - Navigation Methods
    
    func showInput() {
        if case .player(let player, _) = currentScreen {
            player.pause()
        }
        currentScreen = .input
    }
    
    func showPlayer(audioURL: URL, analysis: AudioAnalysis) {
        let syncPlayer = container.makeSynchronizedPlayer()
        
        do {
            try syncPlayer.prepare(audioURL: audioURL, analysis: analysis)
            currentScreen = .player(player: syncPlayer, analysis: analysis)
        } catch {
            // Handle error - log and stay on input screen
            // In production, this should be logged to analytics/crash reporting
            let errorMessage = error.localizedDescription
            NSLog("❌ [AppCoordinator] Failed to prepare player: \(errorMessage)")
        }
    }
    
    func reset() {
        showInput()
    }
}
