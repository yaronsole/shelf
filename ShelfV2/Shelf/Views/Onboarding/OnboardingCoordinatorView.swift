import SwiftUI

// Owns the OnboardingViewModel and routes between onboarding steps.
struct OnboardingCoordinatorView: View {
    @State private var vm = OnboardingViewModel()

    var body: some View {
        switch vm.step {
        case .welcome:
            WelcomeView {
                withAnimation(.easeInOut(duration: 0.3)) {
                    vm.step = .seedSearch
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

        case .chainDiscovery:
            ChainDiscoveryView(vm: vm)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))

        case .confirmation:
            ConfirmationView(vm: vm)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
        }
    }
}
