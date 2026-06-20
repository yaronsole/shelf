import Foundation

/// Builds the single-book share payload used by the detail surfaces' share
/// button, so the shared text is identical wherever it's invoked.
///
/// Payload (blank-line separated, reads cleanly in Messages/Notes which
/// auto-linkify the URLs):
///   1. "Title by Author"
///   2. the canonical Amazon deeplink (via `AmazonLinkService` — regression
///      guard RG-01, never hand-build an Amazon URL at a call site)
///   3. an App Store fallback line
enum BookShareService {
    static func shareText(title: String, author: String) -> String {
        var lines = ["\(title) by \(author)"]
        if let amazon = AmazonLinkService.searchURL(title: title, author: author) {
            lines.append(amazon.absoluteString)
        }
        lines.append("Find your next read on Shelf: \(AppLinks.appStoreURL)")
        return lines.joined(separator: "\n\n")
    }
}
