import Foundation
import SwiftData

@Observable
@MainActor
final class ListDetailViewModel {
    let slug: String
    var detail: ListDetailDTO? = nil
    var isLoading: Bool = false
    var errorMessage: String? = nil

    // Per-book status overlay so tapping animates immediately rather than
    // waiting for the next round-trip. Initialized from the server response;
    // mutated on tap/long-press.
    var statusOverlay: [String: ListUserStatus?] = [:]

    init(slug: String) {
        self.slug = slug
    }

    func loadIfNeeded() {
        guard detail == nil else { return }
        load()
    }

    func load() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let result = try await APIClient.shared.fetchListDetail(slug: slug)
                self.detail = result
                // Seed the overlay from server-provided user_status so we have
                // a single source of truth in the view body.
                var seeded: [String: ListUserStatus?] = [:]
                for b in result.books { seeded[b.bookId] = b.userStatus }
                self.statusOverlay = seeded
                self.isLoading = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    func status(for bookId: String) -> ListUserStatus? {
        // The overlay returns Optional<Optional<...>> when present; flatten.
        if let cached = statusOverlay[bookId] { return cached }
        return detail?.books.first { $0.bookId == bookId }?.userStatus
    }

    /// Tap → mark as read (or unmark if already read).
    /// Also mirrors to SwiftData LocalSeedBook so the Taste tab reflects the
    /// addition immediately. UI updates optimistically before the API call.
    func toggleRead(_ book: ListBookDTO, modelContext: ModelContext) {
        let current = status(for: book.bookId)
        if current == .read {
            // Unmark
            statusOverlay[book.bookId] = .some(nil)
            Task {
                do {
                    try await APIClient.shared.deleteListReaction(slug: slug, bookId: book.bookId)
                    removeMatchingLocalSeed(title: book.title, author: book.author, modelContext: modelContext)
                } catch {
                    // Roll back optimistic UI
                    self.statusOverlay[book.bookId] = .some(.read)
                }
            }
        } else {
            // Mark as read
            statusOverlay[book.bookId] = .some(.read)
            Task {
                do {
                    try await APIClient.shared.reactToListBook(
                        slug: slug,
                        bookId: book.bookId,
                        title: book.title,
                        author: book.author,
                        coverURL: book.coverURL,
                        kind: .read
                    )
                    insertLocalSeedIfMissing(book: book, modelContext: modelContext)
                } catch {
                    self.statusOverlay[book.bookId] = .some(current)
                }
            }
        }
    }

    /// Detail-sheet "Read it" → record an already-read action via SeedWriter and
    /// optimistically show the `.read` badge.
    ///
    /// This deliberately routes through `SeedWriter.recordAlreadyRead` rather than
    /// the list `.read` react endpoint, because:
    ///   • `SeedWriter` is the single source of truth for "books you've read", and
    ///     it can express sentiment (loved → seed; disliked → reaction only).
    ///   • Going through `reactToListBook(kind: .read)` here would double-seed the
    ///     same book in the shared "title|author" id space (it has no concept of a
    ///     dislike), so we keep all already-read writes in one place.
    /// We still set the local `.read` overlay so the cover shows the green check.
    func markRead(_ book: ListBookDTO, liked: Bool, modelContext: ModelContext) {
        let current = status(for: book.bookId)
        statusOverlay[book.bookId] = .some(.read)
        Task {
            let ok = await SeedWriter.recordAlreadyRead(
                title: book.title,
                author: book.author,
                coverURL: book.coverURL,
                liked: liked,
                modelContext: modelContext
            )
            if !ok {
                // Roll back optimistic UI if the writes failed.
                self.statusOverlay[book.bookId] = .some(current)
            }
        }
    }

    /// Long-press → save to Shelf (or unsave if already saved).
    /// Writes both to backend AND local ReadingListItem so the Shelf tab reflects it.
    func toggleSave(_ book: ListBookDTO, modelContext: ModelContext) {
        let current = status(for: book.bookId)
        if current == .saved {
            statusOverlay[book.bookId] = .some(nil)
            removeMatchingLocalReadingListItem(title: book.title, author: book.author, modelContext: modelContext)
            Task {
                do {
                    try await APIClient.shared.deleteListReaction(slug: slug, bookId: book.bookId)
                } catch {
                    self.statusOverlay[book.bookId] = .some(.saved)
                }
            }
        } else {
            statusOverlay[book.bookId] = .some(.saved)
            insertLocalReadingListItemIfMissing(book: book, modelContext: modelContext)
            Task {
                do {
                    try await APIClient.shared.reactToListBook(
                        slug: slug,
                        bookId: book.bookId,
                        title: book.title,
                        author: book.author,
                        coverURL: book.coverURL,
                        kind: .saved
                    )
                } catch {
                    self.statusOverlay[book.bookId] = .some(current)
                }
            }
        }
    }

    private func insertLocalReadingListItemIfMissing(book: ListBookDTO, modelContext: ModelContext) {
        let titleKey = book.title.lowercased()
        let authorKey = book.author.lowercased()
        let descriptor = FetchDescriptor<ReadingListItem>()
        if let existing = try? modelContext.fetch(descriptor) {
            let match = existing.first { item in
                item.title.lowercased() == titleKey && item.author.lowercased() == authorKey
            }
            if match != nil { return }
        }
        let item = ReadingListItem(
            id: UUID().uuidString,
            title: book.title,
            author: book.author,
            coverURL: book.coverURL,
            blurb: "Saved from a curated list."
        )
        modelContext.insert(item)
    }

    private func removeMatchingLocalReadingListItem(title: String, author: String, modelContext: ModelContext) {
        let titleKey = title.lowercased()
        let authorKey = author.lowercased()
        let descriptor = FetchDescriptor<ReadingListItem>()
        guard let existing = try? modelContext.fetch(descriptor) else { return }
        for item in existing where item.title.lowercased() == titleKey && item.author.lowercased() == authorKey {
            modelContext.delete(item)
        }
    }

    // MARK: - Local SwiftData mirror

    private func insertLocalSeedIfMissing(book: ListBookDTO, modelContext: ModelContext) {
        let titleKey = book.title.lowercased()
        let authorKey = book.author.lowercased()
        // Check if a matching seed already exists locally
        let descriptor = FetchDescriptor<LocalSeedBook>()
        if let existing = try? modelContext.fetch(descriptor) {
            let match = existing.first { seed in
                seed.title.lowercased() == titleKey && seed.author.lowercased() == authorKey
            }
            if match != nil { return }
        }
        let local = LocalSeedBook(
            id: UUID().uuidString,
            title: book.title,
            author: book.author,
            coverURL: book.coverURL
        )
        modelContext.insert(local)
    }

    private func removeMatchingLocalSeed(title: String, author: String, modelContext: ModelContext) {
        let titleKey = title.lowercased()
        let authorKey = author.lowercased()
        let descriptor = FetchDescriptor<LocalSeedBook>()
        guard let existing = try? modelContext.fetch(descriptor) else { return }
        for seed in existing where seed.title.lowercased() == titleKey && seed.author.lowercased() == authorKey {
            modelContext.delete(seed)
        }
    }
}
