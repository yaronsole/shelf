import Foundation

/// External links surfaced in-app. Both are PLACEHOLDERS until the listings
/// exist — Yaron fills these before App Store submission (plan open items
/// `APP_STORE_URL`, `PRIVACY_POLICY_URL`).
enum AppLinks {
    static let appStoreURL = "https://apps.apple.com/app/id6775563720"
    /// True once a real App Store listing URL has replaced the placeholder.
    static var hasAppStoreURL: Bool { !appStoreURL.contains("id0000000000") }
    // Hosted policy URL for App Store Connect (the in-app screen renders
    // PrivacyPolicyView instead). Hosted via GitHub Pages (repo: shelf-privacy).
    static let privacyPolicyURL = "https://yaronsole.github.io/shelf-privacy/"
    // Privacy/deletion contact, shown in the in-app + hosted policy.
    static let privacyEmail = "shelf.app.privacy@gmail.com"
}
