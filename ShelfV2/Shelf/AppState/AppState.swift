import Foundation
import SwiftUI

@Observable
final class AppState {
    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: Keys.onboardingComplete) }
    }

    // Set to true when onboarding submission is in-flight and the first batch is generating.
    var isFirstGeneration: Bool = false

    // Per-launch flags — reset each app launch (not persisted).
    var hasDoneLaunchTimePrune: Bool = false

    // Set to true when a new For You batch arrives after onboarding; cleared when user taps For You.
    var hasForYouBadge: Bool = false

    // When non-nil, MainTabView selects this tab on first appear then clears it.
    var pendingInitialTab: Int? = nil

    init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Keys.onboardingComplete)
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    func resetAll() {
        hasCompletedOnboarding = false
        isFirstGeneration = false
        UserDefaults.standard.removeObject(forKey: Keys.onboardingComplete)
        KeychainService.delete(key: .anonymousToken)
    }

    private enum Keys {
        static let onboardingComplete = "com.ysole.shelf.onboardingComplete"
    }
}
