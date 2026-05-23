import SwiftUI
import SwiftData

@main
struct ShelfApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(for: [
                    CachedRecommendation.self,
                    ReadingListItem.self,
                    LocalSeedBook.self,
                ])
                .environment(appState)
        }
    }
}

private struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingCoordinatorView()
            }
        }
        .animation(.easeInOut(duration: 0.35), value: appState.hasCompletedOnboarding)
    }
}
