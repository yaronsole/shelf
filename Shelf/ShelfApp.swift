import SwiftUI
import SwiftData

@main
struct ShelfApp: App {
    @State private var appState = AppStateManager()
    @State private var milestoneManager = MilestoneManager()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SeedBook.self,
            ShownBook.self,
            Reaction.self,
            Purchase.self,
            WishlistItem.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Schema changed during development — wipe the store and start fresh.
            print("ModelContainer failed (\(error)). Deleting store and retrying.")
            if let storeURL = config.url {
                try? FileManager.default.removeItem(at: storeURL)
            }
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Could not create ModelContainer after reset: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(milestoneManager)
        }
        .modelContainer(sharedModelContainer)
    }
}

// MARK: - RootView

struct RootView: View {
    @Environment(AppStateManager.self) var appState

    var body: some View {
        Group {
            switch appState.stage {
            case .preview:    OnboardingPreviewView()
            case .tasteSetup: TasteSetupView()
            case .demo:       MainTabView(isDemo: true)
            case .live:       MainTabView(isDemo: false)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: appState.stage)
    }
}
