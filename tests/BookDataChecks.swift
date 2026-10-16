import Foundation
import SwiftData

// Run with the app's actual model and DTO files; no network or credentials.
@main
struct BookDataChecks {
    @MainActor static func main() throws {
        let decoder = JSONDecoder()
        let legacy = Data(#"{"book_id":"a","title":"Book","author":"Writer","cover_url":"cover"}"#.utf8)
        let book = try decoder.decode(ListBookDTO.self, from: legacy)
        precondition(book.lovedCount == nil && book.rank == nil)
        let current = Data(#"{"order":"popular","updated_at":"2026-10-12T10:30:00.123456+00:00","books":[{"book_id":"b","title":"Book","author":"Writer","cover_url":"cover","loved_count":7,"rank":1}]}"#.utf8)
        let leaderboard = try decoder.decode(CommunityLeaderboardDTO.self, from: current)
        precondition(leaderboard.books[0].lovedCount == 7)
        precondition(leaderboard.books[0].rank == 1)
        precondition(leaderboard.updateLabel != nil)
        let noDate = Data(#"{"order":"recent","updated_at":null,"books":[]}"#.utf8)
        let empty = try decoder.decode(CommunityLeaderboardDTO.self, from: noDate)
        precondition(empty.updateLabel == nil)

        // External scores are optional and never become an old or invalid badge.
        let ratingNow = ISO8601DateFormatter().date(from: "2026-10-16T20:00:00Z")!
        let ratingJSON = Data(#"{"rating":{"score":4.1242,"source":"Hardcover","fetched_at":"2026-10-16T19:59:59.123456+00:00"}}"#.utf8)
        let rating = try decoder.decode(BookRatingResponse.self, from: ratingJSON).rating!
        precondition(rating.isDisplayable(at: ratingNow))
        precondition(!rating.isDisplayable(at: ratingNow.addingTimeInterval(7 * 24 * 60 * 60)))
        precondition(!rating.isDisplayable(at: ratingNow.addingTimeInterval(-60)))
        for value in [#"{"rating":null}"#, #"{}"#] {
            let absent = try decoder.decode(BookRatingResponse.self, from: Data(value.utf8))
            precondition(absent.rating == nil)
        }
        for value in [#"{"score":6,"source":"Hardcover","fetched_at":"2026-10-16T19:59:59Z"}"#,
                      #"{"score":4,"source":"Shelf","fetched_at":"2026-10-16T19:59:59Z"}"#,
                      #"{"score":4,"source":"Hardcover","fetched_at":"invalid"}"#] {
            let invalid = try decoder.decode(BookRatingDTO.self, from: Data(value.utf8))
            precondition(!invalid.isDisplayable(at: ratingNow))
        }

        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: ReadingListItem.self, configurations: configuration)
        let context = container.mainContext
        let saved = ReadingListItem(id: "saved", title: "Book", author: "Writer", coverURL: "", blurb: "An original recommendation")
        precondition(!saved.isUpNext)
        context.insert(saved)
        saved.isUpNext = true
        try context.save()
        let readContext = ModelContext(container)
        let restored = try readContext.fetch(FetchDescriptor<ReadingListItem>())
        precondition(restored.count == 1 && restored[0].isUpNext)
        precondition(restored[0].blurb == "An original recommendation")
        print("PASS: legacy/current DTOs, optional/fresh/valid ratings, timestamps, Up next persistence")
    }
}
