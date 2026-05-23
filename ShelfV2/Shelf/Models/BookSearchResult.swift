import Foundation

// Transient struct used only for Google Books search results in onboarding.
// Not persisted to SwiftData.
struct BookSearchResult: Identifiable, Equatable, Hashable {
    let id: String         // Google Books volume ID
    let title: String
    let author: String
    let coverURL: String?  // nil if Google Books has no cover

    var displayTitle: String {
        let max = Strings.Onboarding.SeedSearch.chipTitleMaxLength
        return title.count > max ? String(title.prefix(max)) + "…" : title
    }
}
