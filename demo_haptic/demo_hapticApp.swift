import SwiftUI

@main
struct HapticoApp: App {
    // MARK: - Properties
    
    @StateObject private var coordinator: AppCoordinator
    
    // MARK: - Initialization
    
    init() {
        // Create DI container and coordinator
        let container = DIContainer()
        _coordinator = StateObject(wrappedValue: container.makeAppCoordinator())
    }
    
    // MARK: - Scene
    
    var body: some Scene {
        WindowGroup {
            RootView(coordinator: coordinator)
        }
    }
}
