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
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if appState.hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingCoordinatorView()
            }
        }
        .animation(.easeInOut(duration: 0.35), value: appState.hasCompletedOnboarding)
        .task {
            // Backfill any locally-cached books missing covers (e.g. from earlier
            // builds where covers were empty). Idempotent — no-op for rows with covers.
            CoverBackfillService.backfillAll(modelContext: modelContext)
        }
    }
}
