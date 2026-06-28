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
        // First launch shows the splash (WelcomeView) first. The AI-usage
        // disclosure is no longer a first-run gate; it remains discoverable in
        // Settings → About (AIDisclosureView), which satisfies App Store
        // disclosure. (AIConsentView / aiConsentAcknowledged are intentionally
        // left in place, unwired, so the gate can be restored if needed.)
        Group {
            if appState.hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingCoordinatorView()
            }
        }
        .animation(.easeInOut(duration: 0.35), value: appState.hasCompletedOnboarding)
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
