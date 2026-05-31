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

    // Set to true when a new For You batch arrives *while the user isn't looking
    // at For You*; cleared as soon as they view the For You tab. Gated by
    // isViewingForYou so a normal refresh while the user is already on the feed
    // never lights the badge (that was the "badge shows all the time" bug).
    var hasForYouBadge: Bool = false

    // Whether For You is the currently active/visible tab. Drives badge gating.
    // Not persisted — recomputed from the selected tab each launch.
    var isViewingForYou: Bool = false

    // When non-nil, MainTabView selects this tab on first appear then clears it.
    var pendingInitialTab: Int? = nil

    // Phase 3 entry switch. When true (default), onboarding is welcome-only and
    // brand-new users land on Discover; the old welcome → seed-search flow stays
    // in the codebase behind this flag so it can be flipped back for a TestFlight
    // round without reverting code. Not persisted — it's a build-time default.
    var useNewOnboarding: Bool = true

    // Whether the user has graduated from the seed-gathering For You grid to the
    // personalized feed. Persisted. Defaults true so anyone who already has a feed
    // (existing installs, or the legacy welcome → seed-search flow) is never bounced
    // back to the grid. A brand-new welcome-only user starts locked (set false on
    // completion) and unlocks by tapping "See my picks" — so reaching the seed
    // threshold no longer yanks them straight into generation.
    var forYouFeedUnlocked: Bool {
        didSet { UserDefaults.standard.set(forYouFeedUnlocked, forKey: Keys.forYouFeedUnlocked) }
    }

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

        // Default to unlocked when the key was never written, so existing users
        // (and the legacy seed-search flow) keep their feed. Only the new
        // welcome-only flow explicitly locks it (see finishWelcomeOnly).
        if UserDefaults.standard.object(forKey: Keys.forYouFeedUnlocked) == nil {
            self.forYouFeedUnlocked = true
        } else {
            self.forYouFeedUnlocked = UserDefaults.standard.bool(forKey: Keys.forYouFeedUnlocked)
        }
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    /// Graduates the user from the seed-gathering grid to the personalized feed.
    func unlockForYouFeed() {
        forYouFeedUnlocked = true
    }

    func resetAll() {
        hasCompletedOnboarding = false
        isFirstGeneration = false
        forYouFeedUnlocked = true
        UserDefaults.standard.removeObject(forKey: Keys.onboardingComplete)
        UserDefaults.standard.removeObject(forKey: Keys.forYouFeedUnlocked)
        KeychainService.delete(key: .anonymousToken)
    }

    private enum Keys {
        static let onboardingComplete = "com.ysole.shelf.onboardingComplete"
        static let hasLaunchedOnce    = "com.ysole.shelf.hasLaunchedOnce"
        static let forYouFeedUnlocked = "com.ysole.shelf.forYouFeedUnlocked"
    }
}
