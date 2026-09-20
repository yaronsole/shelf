import Foundation
import SwiftData

// MARK: - CachedRecommendation
// Mirrors a book from the server's RecommendationBatch. Cached locally so the feed
// loads instantly even with poor connectivity.
@Model
final class CachedRecommendation {
    @Attribute(.unique) var id: String
    var title: String
    var author: String
    var coverURL: String
    var blurb: String
    var genre: String
    var era: String
    var isComfortZonePush: Bool
    var fetchedAt: Date
    var batchId: String
    var domain: String
    var isSeen: Bool
    var seenAt: Date?
    var isReacted: Bool
    // Staging: recs that arrive mid-session start unsurfaced so they don't
    // reshuffle the feed under the user; surfaced via the "new picks" banner.
    var isSurfaced: Bool = true
    var awards: [String] = []
    var contextTag: String = ""
    var acclaim: String = ""
    var nytBestseller: Bool = false
    var nytWeeksOnList: Int? = nil
    var readingTimeMinutes: Int? = nil
    // Seed book most responsible for this pick (Phase 2 attribution).
    // Empty when Claude returned no attribution or the value didn't match a seed.
    var becauseOf: String = ""
    // Phase 3 PDP enrichment (all defaulted → no SwiftData migration needed).
    var becauseOfReason: String = ""   // short, specific clause: why this follows from the seed
    var bookDescription: String = ""   // full Google Books description (expandable in the PDP)
    // Frequency cap: incremented at launch when isSeen flips from true.
    // Eliminated (marked reacted) once viewCount >= 2.
    var viewCount: Int = 0

    init(
        id: String,
        title: String,
        author: String,
        coverURL: String,
        blurb: String,
        genre: String,
        era: String,
        isComfortZonePush: Bool,
        batchId: String,
        domain: String = Domain.books.rawValue,
        awards: [String] = [],
        contextTag: String = "",
        acclaim: String = "",
        nytBestseller: Bool = false,
        nytWeeksOnList: Int? = nil,
        readingTimeMinutes: Int? = nil,
        becauseOf: String = "",
        becauseOfReason: String = "",
        bookDescription: String = "",
        isSurfaced: Bool = true
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.coverURL = coverURL
        self.blurb = blurb
        self.genre = genre
        self.era = era
        self.isComfortZonePush = isComfortZonePush
        self.fetchedAt = Date()
        self.batchId = batchId
        self.domain = domain
        self.isSeen = false
        self.isReacted = false
        self.isSurfaced = isSurfaced
        self.awards = awards
        self.contextTag = contextTag
        self.acclaim = acclaim
        self.nytBestseller = nytBestseller
        self.nytWeeksOnList = nytWeeksOnList
        self.readingTimeMinutes = readingTimeMinutes
        self.becauseOf = becauseOf
        self.becauseOfReason = becauseOfReason
        self.bookDescription = bookDescription
    }
}

// MARK: - ReadingListItem
// Books the user has saved to read later. Local-only in v2.0.
@Model
final class ReadingListItem {
    @Attribute(.unique) var id: String
    var title: String
    var author: String
    var coverURL: String
    var blurb: String
    var savedAt: Date
    var domain: String
    // v2.1: rich card fields copied from CachedRecommendation at save time.
    // Older saves that lack these fields display abbreviated cards (omit empty lines).
    var genre: String = ""
    var era: String = ""
    var becauseOf: String = ""
    var readingTimeMinutes: Int? = nil
    var nytBestseller: Bool = false
    var nytWeeksOnList: Int? = nil

    init(
        id: String,
        title: String,
        author: String,
        coverURL: String,
        blurb: String,
        domain: String = Domain.books.rawValue,
        genre: String = "",
        era: String = "",
        becauseOf: String = "",
        readingTimeMinutes: Int? = nil,
        nytBestseller: Bool = false,
        nytWeeksOnList: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.coverURL = coverURL
        self.blurb = blurb
        self.savedAt = Date()
        self.domain = domain
        self.genre = genre
        self.era = era
        self.becauseOf = becauseOf
        self.readingTimeMinutes = readingTimeMinutes
        self.nytBestseller = nytBestseller
        self.nytWeeksOnList = nytWeeksOnList
    }
}

// MARK: - LocalSeedBook
// Lightweight local mirror of the user's seed books. Used to display the taste
// profile screen without a network round-trip.
@Model
final class LocalSeedBook {
    @Attribute(.unique) var id: String
    var title: String
    var author: String
    var coverURL: String
    var addedAt: Date
    var domain: String
    // v2.1: pre-computed similar books cache (JSON-encoded [CachedSuggestion]).
    // Refreshed on app foreground when >8h stale.
    var similarBooksData: Data = Data()
    var similarBooksUpdatedAt: Date? = nil
    var similarBooksGenerationToken: String = ""

    init(
        id: String,
        title: String,
        author: String,
        coverURL: String,
        domain: String = Domain.books.rawValue
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.coverURL = coverURL
        self.addedAt = Date()
        self.domain = domain
    }
}
