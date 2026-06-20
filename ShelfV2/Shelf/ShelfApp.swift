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
            if !appState.aiConsentAcknowledged {
                AIConsentView()
            } else if appState.hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingCoordinatorView()
            }
        }
        .animation(.easeInOut(duration: 0.35), value: appState.hasCompletedOnboarding)
        .animation(.easeInOut(duration: 0.35), value: appState.aiConsentAcknowledged)
        .task {
            // Prune books seen in previous sessions exactly once per launch (PRD REC-07).
            if !appState.hasDoneLaunchTimePrune {
                appState.hasDoneLaunchTimePrune = true
                await MainActor.run {
                    CoverBackfillService.pruneSeenItems(modelContext: modelContext)
                }
            }
            // Backfill any locally-cached books missing covers. Idempotent.
            CoverBackfillService.backfillAll(modelContext: modelContext)
        }
    }
}
