import SwiftUI
import SwiftData

struct OnboardingCoordinatorView: View {
    @Environment(AppState.self) private var appState
    @Query private var seedBooks: [LocalSeedBook]
    @State private var vm = OnboardingViewModel()

    var body: some View {
        switch vm.step {
        case .welcome:
            WelcomeView {
                if appState.useNewOnboarding {
                    // New flow: the Welcome CTA finishes onboarding directly —
                    // no seed-search step. Seeds are gathered later from Discover
                    // and the softened For You grid.
                    finishWelcomeOnly()
                } else {
                    // Legacy flow (flag off): welcome → seed search.
                    withAnimation(.easeInOut(duration: 0.3)) {
                        vm.step = .seedSearch
                    }
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading)
            ))

        case .seedSearch:
            SeedBookSearchView(vm: vm)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
        }
    }

    /// Completes the welcome-only onboarding. A brand-new user (no seeds yet)
    /// lands on Discover and gets a For You badge nudging them back once they've
    /// added books. Returning/seeded users keep the For You default (tab 0) — we
    /// do not reorder tabs.
    private func finishWelcomeOnly() {
        if seedBooks.isEmpty {
            appState.pendingInitialTab = 1   // Discover
            appState.hasForYouBadge = true
            // Lock the For You feed so it gathers seeds first and asks before
            // switching to personalized recs (rather than auto-generating).
            appState.forYouFeedUnlocked = false
        }
        appState.completeOnboarding()
    }
}
