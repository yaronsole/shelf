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
        // Keychain survives app uninstall on iOS, but UserDefaults does not.
        // If we don't see our "has launched" marker AND the user hasn't completed
        // onboarding, treat this as a fresh install: wipe the stale anonymous
        // token so the user gets a fresh user_id on the backend instead of
        // inheriting the previous install's seed/reaction history.
        //
        // Existing users (who completed onboarding before this fix shipped) are
        // protected by the onboardingComplete check so their identity persists.
        let alreadyMarked = UserDefaults.standard.bool(forKey: Keys.hasLaunchedOnce)
        let onboardingDone = UserDefaults.standard.bool(forKey: Keys.onboardingComplete)
        if !alreadyMarked && !onboardingDone {
            KeychainService.delete(key: .anonymousToken)
        }
        if !alreadyMarked {
            UserDefaults.standard.set(true, forKey: Keys.hasLaunchedOnce)
        }
        self.hasCompletedOnboarding = onboardingDone
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
        static let hasLaunchedOnce    = "com.ysole.shelf.hasLaunchedOnce"
    }
}
