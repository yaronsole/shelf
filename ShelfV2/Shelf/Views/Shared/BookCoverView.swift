import SwiftUI

/// Canonical book cover render. Every cover in the app uses this view.
///
/// Two construction modes:
///   - Fixed width:  `BookCoverView(url: ..., width: 60)` → 60 × 90, cornerRadius 4
///   - Flexible:     `BookCoverView(url: ...)` → fills container width at 2:3
///                   (same 1.5× ratio; cell width is determined by the parent grid)
///
/// Rule: call sites never set `.frame`/`.aspectRatio`/`.cornerRadius` on a cover.
/// All cover dimensions flow from this component.
struct BookCoverView: View {
    let url: String
    let width: CGFloat?  // nil → fill the container at 2:3

    init(url: String, width: CGFloat) {
        self.url = url
        self.width = width
    }

    init(url: String) {
        self.url = url
        self.width = nil
    }

    var body: some View {
        Group {
            if let w = width {
                imageContainer
                    .frame(width: w, height: w * 1.5)
            } else {
                imageContainer
                    .aspectRatio(2/3, contentMode: .fit)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var imageContainer: some View {
        Rectangle()
            .fill(Color(.secondarySystemFill))
            .overlay {
                CachedCoverImage(url: hiResURL)
            }
    }

    private var hiResURL: URL? {
        let upgraded = url
            .replacingOccurrences(of: "&zoom=1", with: "&zoom=3")
            .replacingOccurrences(of: "?zoom=1", with: "?zoom=3")
        return URL(string: upgraded)
    }
}

extension BookCoverView {
    /// Single source of truth for "does this book have a usable cover?".
    /// Valid iff the URL string is non-empty after trimming. Surfaces filter
    /// cover-less books with this instead of rendering the `book.closed`
    /// placeholder (Phase 2 regression guard). Mirrors the backend's
    /// `_has_valid_cover`.
    static func hasValidCover(_ url: String?) -> Bool {
        !(url ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Cached cover loader

/// Process-wide in-memory cache of decoded cover images, keyed by hi-res URL.
/// It outlives individual view lifetimes, so the For You feed's LazyVStack
/// recycling (and `@Query` mutations from `markSeenIfScrolledPast`) no longer
/// drop already-fetched covers.
private final class CoverImageCache {
    static let shared = CoverImageCache()
    private let cache = NSCache<NSURL, UIImage>()
    private init() { cache.countLimit = 500 }

    func image(for url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }
    func insert(_ image: UIImage, for url: URL) { cache.setObject(image, forKey: url as NSURL) }
}

/// Drop-in replacement for the cover `AsyncImage`. Stock `AsyncImage` fires its
/// request once on instantiation; when a row is recycled mid-flight (request
/// cancelled) or a fetch fails, the recreated view lands on `.empty`/`.failure`
/// and latches on the placeholder permanently — the top-of-feed bug.
///
/// This instead:
///   • reads decoded images from `CoverImageCache`, so a recreated row shows
///     instantly without re-fetching;
///   • loads in `.task(id: url)`, so a recreated or previously-failed view
///     re-issues the request rather than getting stuck on a stale phase;
///   • on failure/cancel leaves the placeholder and retries on next appearance.
///
/// Visual output is identical to the old AsyncImage: success → resizable
/// `scaledToFill`; otherwise the `book.closed` symbol (over the parent's
/// `secondarySystemFill` rectangle).
private struct CachedCoverImage: View {
    let url: URL?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "book.closed")
                    .font(.title2)
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { return }
        if let cached = CoverImageCache.shared.image(for: url) {
            image = cached
            return
        }
        // Recreated view starts fresh — never inherit a prior failed state.
        image = nil
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            let (data, _) = try await URLSession.shared.data(for: request)
            if Task.isCancelled { return }
            guard let ui = UIImage(data: data) else { return }
            CoverImageCache.shared.insert(ui, for: url)
            image = ui
        } catch {
            // Cancelled (scrolled away) or network error: stay on the placeholder.
            // `.task(id:)` re-runs on reappearance, so the next appear retries.
        }
    }
}
