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
    var awards: [String] = []
    var contextTag: String = ""
    var acclaim: String = ""
    var nytBestseller: Bool = false
    var nytWeeksOnList: Int? = nil
    var readingTimeMinutes: Int? = nil
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
        readingTimeMinutes: Int? = nil
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
        self.awards = awards
        self.contextTag = contextTag
        self.acclaim = acclaim
        self.nytBestseller = nytBestseller
        self.nytWeeksOnList = nytWeeksOnList
        self.readingTimeMinutes = readingTimeMinutes
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

    init(
        id: String,
        title: String,
        author: String,
        coverURL: String,
        blurb: String,
        domain: String = Domain.books.rawValue
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.coverURL = coverURL
        self.blurb = blurb
        self.savedAt = Date()
        self.domain = domain
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
