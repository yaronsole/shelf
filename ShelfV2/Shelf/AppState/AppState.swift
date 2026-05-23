import Foundation
import SwiftUI

@Observable
final class AppState {
    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: Keys.onboardingComplete) }
    }

    // Set to true when onboarding submission is in-flight and the first batch is generating.
    var isFirstGeneration: Bool = false

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
