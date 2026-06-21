import Foundation

/// External links surfaced in-app. Both are PLACEHOLDERS until the listings
/// exist — Yaron fills these before App Store submission (plan open items
/// `APP_STORE_URL`, `PRIVACY_POLICY_URL`).
enum AppLinks {
    static let appStoreURL = "https://apps.apple.com/app/id0000000000"
    // Hosted policy URL — used in App Store Connect (the in-app screen renders
    // PrivacyPolicyView instead). Fill once GitHub Pages is live.
    static let privacyPolicyURL = "https://example.com/shelf-privacy"
    // Privacy/deletion contact, shown in the in-app + hosted policy.
    // PLACEHOLDER — fill with the dedicated address before submission.
    static let privacyEmail = "PRIVACY_EMAIL_PLACEHOLDER"
}
