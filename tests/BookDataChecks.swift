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
        print("PASS: legacy/current DTO decoding, fractional/null timestamps, Up next default and persistence")
    }
}
