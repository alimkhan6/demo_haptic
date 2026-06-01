import SwiftUI

/// Factory responsible for creating the entire app with proper dependency injection
/// Note: This is now simplified - most factory logic moved to DIContainer
@MainActor
final class AppFactory {
    // MARK: - Properties
    
    private let container: DIContainerProtocol
    
    // MARK: - Initialization
    
    init(container: DIContainerProtocol? = nil) {
        self.container = container ?? DIContainer()
    }
    
    // MARK: - Factory Methods
    
    /// Create the root coordinator for the app
    func makeAppCoordinator() -> AppCoordinator {
        return container.makeAppCoordinator()
    }
    
    /// Create the root view for the app
    func makeRootView(coordinator: AppCoordinator) -> some View {
        return RootView(coordinator: coordinator)
    }
}
