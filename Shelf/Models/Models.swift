import Foundation
import SwiftData

// MARK: - SeedBook
@Model
final class SeedBook {
    var id: UUID
    var title: String
    var author: String
    var dateAdded: Date
    // OB-02: true = user loved this book (positive signal),
    //         false = user read & disliked (negative anti-signal)
    var isLiked: Bool

    init(title: String, author: String, isLiked: Bool = true) {
        self.id = UUID()
        self.title = title
        self.author = author
        self.dateAdded = Date()
        self.isLiked = isLiked
    }
}

// MARK: - ShownBook
@Model
final class ShownBook {
    var id: UUID
    var title: String
    var author: String
    var asin: String?
    var isbn: String?
    var coverURL: String?
    var description: String?
    var reasoningBlurb: String?
    var dateShown: Date

    init(title: String, author: String, asin: String? = nil, isbn: String? = nil,
         coverURL: String? = nil, description: String? = nil, reasoningBlurb: String? = nil) {
        self.id = UUID()
        self.title = title
        self.author = author
        self.asin = asin
        self.isbn = isbn
        self.coverURL = coverURL
        self.description = description
        self.reasoningBlurb = reasoningBlurb
        self.dateShown = Date()
    }
}

// MARK: - ReactionType
enum ReactionType: String, Codable {
    case thumbsUp
    case thumbsDown
    case alreadyReadLiked
    case alreadyReadDisliked
}

// MARK: - Reaction
@Model
final class Reaction {
    var id: UUID
    var bookTitle: String
    var bookAuthor: String
    var reactionType: String // stored as raw value
    var timestamp: Date

    var type: ReactionType {
        ReactionType(rawValue: reactionType) ?? .thumbsUp
    }

    init(bookTitle: String, bookAuthor: String, type: ReactionType) {
        self.id = UUID()
        self.bookTitle = bookTitle
        self.bookAuthor = bookAuthor
        self.reactionType = type.rawValue
        self.timestamp = Date()
    }
}

// MARK: - FollowUpResponse
enum FollowUpResponse: String, Codable {
    case lovedIt
    case itWasFine
    case didntFinish
}

// MARK: - Purchase
@Model
final class Purchase {
    var id: UUID
    var bookTitle: String
    var bookAuthor: String
    var purchaseDate: Date
    var followUpResponse: String?    // FollowUpResponse raw value
    var followUpDate: Date?
    var followUpDismissedCount: Int  // track how many times dismissed

    var response: FollowUpResponse? {
        guard let r = followUpResponse else { return nil }
        return FollowUpResponse(rawValue: r)
    }

    var needsFollowUp: Bool {
        guard followUpResponse == nil else { return false }
        guard followUpDismissedCount < 2 else { return false }
        return Date().timeIntervalSince(purchaseDate) >= 7 * 24 * 3600
    }

    init(bookTitle: String, bookAuthor: String) {
        self.id = UUID()
        self.bookTitle = bookTitle
        self.bookAuthor = bookAuthor
        self.purchaseDate = Date()
        self.followUpDismissedCount = 0
    }
}

// MARK: - WishlistItem
@Model
final class WishlistItem {
    var id: UUID
    var bookTitle: String
    var bookAuthor: String
    var asin: String?
    var isbn: String?
    var coverURL: String?
    var description: String?
    var reasoningBlurb: String?
    var awardBadgesRaw: String?   // comma-separated badge strings
    var savedDate: Date

    /// Decoded badge list (derived from awardBadgesRaw)
    var awardBadges: [String]? {
        guard let raw = awardBadgesRaw, !raw.isEmpty else { return nil }
        return raw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    init(bookTitle: String, bookAuthor: String, asin: String? = nil, isbn: String? = nil,
         coverURL: String? = nil, description: String? = nil,
         reasoningBlurb: String? = nil, awardBadges: [String]? = nil) {
        self.id = UUID()
        self.bookTitle = bookTitle
        self.bookAuthor = bookAuthor
        self.asin = asin
        self.isbn = isbn
        self.coverURL = coverURL
        self.description = description
        self.reasoningBlurb = reasoningBlurb
        self.awardBadgesRaw = awardBadges?.joined(separator: ",")
        self.savedDate = Date()
    }
}
