import Foundation
import SwiftData
import CryptoKit

/// Shared writer for "I've already read this" actions, used by the For You
/// empty state and the Discover detail sheet.
///
/// Semantics (locked design — "seeds = books you loved"):
///   • LOVED  → record an `alreadyReadLiked` reaction AND seed the book
///              (LocalSeedBook + server seed) so it informs future recs and
///              appears in Taste.
///   • DISLIKED → record an `alreadyReadDisliked` reaction ONLY. It must NOT be
///              seeded (that would pollute the loved-seed list). Because the
///              reaction now carries title/author (see APIClient.submitReaction
///              + backend add_reaction fallback), a dislike still registers as a
///              negative signal and lands in the recommendation exclusion list.
///
/// Books with no cover are still seeded; they're simply never displayed
/// elsewhere (existing rule).
enum SeedWriter {

    /// Records an already-read action.
    ///
    /// On `liked`, a `LocalSeedBook` is inserted immediately (so `seedBooks`
    /// reflects it right away) and rolled back if the network writes throw.
    /// Returns `true` if all writes succeeded.
    @MainActor
    @discardableResult
    static func recordAlreadyRead(
        title: String,
        author: String,
        coverURL: String,
        liked: Bool,
        modelContext: ModelContext
    ) async -> Bool {
        let kind: ReactionKind = liked ? .alreadyReadLiked : .alreadyReadDisliked
        let bookId = stableBookId(title: title, author: author)

        // Optimistically seed loved books (dedup on title|author lowercased).
        var insertedSeed: LocalSeedBook? = nil
        if liked && !isAlreadySeeded(title: title, author: author, modelContext: modelContext) {
            let local = LocalSeedBook(
                id: UUID().uuidString, title: title, author: author, coverURL: coverURL
            )
            modelContext.insert(local)
            insertedSeed = local
        }

        do {
            // The reaction always carries title/author/cover so the backend can
            // use it for exclusion + sentiment even with no recommendation entry.
            try await APIClient.shared.submitReaction(
                bookId: bookId, kind: kind,
                title: title, author: author, coverURL: coverURL
            )
            if insertedSeed != nil {
                try await APIClient.shared.submitSeedBook(
                    title: title, author: author, coverURL: coverURL
                )
            }
            return true
        } catch {
            // Roll back the local insert so we never show a seed the backend
            // never recorded (mirrors EmptyForYouView's addAsSeed handling).
            if let local = insertedSeed {
                modelContext.delete(local)
            }
            return false
        }
    }

    // MARK: - Helpers

    @MainActor
    private static func isAlreadySeeded(
        title: String, author: String, modelContext: ModelContext
    ) -> Bool {
        let titleKey = title.lowercased()
        let authorKey = author.lowercased()
        let existing = (try? modelContext.fetch(FetchDescriptor<LocalSeedBook>())) ?? []
        return existing.contains {
            $0.title.lowercased() == titleKey && $0.author.lowercased() == authorKey
        }
    }

    /// Mirrors the backend's `book_id_hash`: sha1("title|author") lowercased &
    /// trimmed, first 16 hex chars — so a reaction shares the curated-list id
    /// space for the same book.
    static func stableBookId(title: String, author: String) -> String {
        let t = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let a = author.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = Insecure.SHA1.hash(data: Data("\(t)|\(a)".utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(16))
    }
}
