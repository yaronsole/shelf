import Foundation
import SwiftData

@Observable
final class ForYouViewModel {
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var showNewBatchBanner: Bool = false
    // Flips true after the first successful batch lands, so emptying the feed
    // later doesn't bounce the user back to the "your shelf is being built"
    // first-generation state.
    var didReceiveFirstBatch: Bool = false

    // Incremented every time a fetch actually inserts new recs. The view watches
    // this to decide whether to light the For You tab badge (only when the user
    // isn't currently viewing the feed). Using a tick rather than didReceiveFirstBatch
    // means the badge can re-light for later batches (e.g. the nightly rotation),
    // not just the very first one.
    var newBatchTick: Int = 0

    // Tracks IDs newly seen this session (scrolled past upward) — written to backend in batches
    private var pendingSeenIds: Set<String> = []
    private var seenSyncTask: Task<Void, Never>? = nil

    // End-of-feed state
    var isLoadingMore: Bool = false
    var noMoreContent: Bool = false
    var currentTaglineIndex: Int = Int.random(in: 0..<Strings.ForYou.endOfFeedTaglines.count)
    private var lastTaglineIndex: Int = -1
    // Incremented after a Load-more completes — the view watches this and
    // scrolls to the top of the feed.
    var scrollToTopTick: Int = 0

    // MARK: - Feed Refresh

    func refreshIfNeeded(modelContext: ModelContext, isForegrounded: Bool = false) {
        Task {
            await fetchLatestBatch(modelContext: modelContext, isForegrounded: isForegrounded, force: false)
        }
    }

    private func fetchLatestBatch(modelContext: ModelContext, isForegrounded: Bool, force: Bool) async {
        // User-initiated force fetches (Generate more) bypass the in-flight guard —
        // otherwise an auto-refresh started by onAppear can block the explicit tap.
        if !force {
            guard !isLoading else { return }
        }
        if !isForegrounded && !force { isLoading = true }
        errorMessage = nil

        do {
            let dtos = try await APIClient.shared.fetchRecommendations(force: force)
            await MainActor.run {
                // Build lookups: by id (for update-in-place) AND by title|author
                // (for cross-batch dedup so the same book never appears twice).
                let existing = (try? modelContext.fetch(FetchDescriptor<CachedRecommendation>())) ?? []
                let byId = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
                let existingKeys = Set(existing.map { Self.bookKey(title: $0.title, author: $0.author) })

                var insertedCount = 0
                var seenKeysThisBatch = Set<String>()
                for dto in dtos {
                    if let rec = byId[dto.id] {
                        // Backfill fields that may have been empty in earlier responses
                        if rec.coverURL.isEmpty && !dto.coverURL.isEmpty {
                            rec.coverURL = dto.coverURL
                        }
                        if rec.blurb.isEmpty && !dto.blurb.isEmpty {
                            rec.blurb = dto.blurb
                        }
                        if rec.awards.isEmpty && !dto.awards.isEmpty {
                            rec.awards = dto.awards
                        }
                        if rec.contextTag.isEmpty && !dto.contextTag.isEmpty {
                            rec.contextTag = dto.contextTag
                        }
                        if rec.acclaim.isEmpty && !dto.acclaim.isEmpty {
                            rec.acclaim = dto.acclaim
                        }
                        if !rec.nytBestseller && dto.nytBestseller {
                            rec.nytBestseller = true
                            rec.nytWeeksOnList = dto.nytWeeksOnList
                        }
                        if rec.readingTimeMinutes == nil {
                            rec.readingTimeMinutes = dto.readingTimeMinutes
                        }
                        if rec.becauseOfReason.isEmpty && !dto.becauseOfReason.isEmpty {
                            rec.becauseOfReason = dto.becauseOfReason
                        }
                        if rec.bookDescription.isEmpty && !dto.bookDescription.isEmpty {
                            rec.bookDescription = dto.bookDescription
                        }
                        if rec.averageRating == nil { rec.averageRating = dto.averageRating }
                        if rec.ratingsCount == nil { rec.ratingsCount = dto.ratingsCount }
                        continue
                    }
                    // Filter books without resolvable cover for *new* inserts (RG-04)
                    guard BookCoverView.hasValidCover(dto.coverURL) else { continue }
                    // Cross-batch dedup: skip books already in cache OR earlier
                    // in this same response with the same title|author
                    let key = Self.bookKey(title: dto.title, author: dto.author)
                    guard !existingKeys.contains(key), !seenKeysThisBatch.contains(key) else { continue }
                    seenKeysThisBatch.insert(key)
                    let rec = CachedRecommendation(
                        id: dto.id,
                        title: dto.title,
                        author: dto.author,
                        coverURL: dto.coverURL,
                        blurb: dto.blurb,
                        genre: dto.genre,
                        era: dto.era,
                        isComfortZonePush: dto.isComfortZonePush,
                        batchId: dto.batchId,
                        domain: dto.domain,
                        awards: dto.awards,
                        contextTag: dto.contextTag,
                        acclaim: dto.acclaim,
                        nytBestseller: dto.nytBestseller,
                        nytWeeksOnList: dto.nytWeeksOnList,
                        readingTimeMinutes: dto.readingTimeMinutes,
                        becauseOf: dto.becauseOf,
                        becauseOfReason: dto.becauseOfReason,
                        bookDescription: dto.bookDescription,
                        averageRating: dto.averageRating,
                        ratingsCount: dto.ratingsCount
                    )
                    modelContext.insert(rec)
                    insertedCount += 1
                }
                self.isLoading = false
                if isForegrounded && insertedCount > 0 {
                    self.showNewBatchBanner = true
                }
                if insertedCount > 0 {
                    // Once any batch lands, the "Your shelf is being built"
                    // empty state shouldn't reappear if the feed later empties.
                    self.didReceiveFirstBatch = true
                    // Signal the view that fresh recs arrived (for badge gating).
                    self.newBatchTick += 1
                }
            }
        } catch {
            print("[Discover] fetchRecommendations failed: \(error)")
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = Strings.ForYou.networkError
            }
        }
    }

    // MARK: - Seen Tracking (REC-07)

    func markSeen(_ id: String, modelContext: ModelContext) {
        pendingSeenIds.insert(id)
        // Update SwiftData immediately using a captured constant (not a struct property)
        let seenId = id
        Task { @MainActor in
            if let rec = try? modelContext.fetch(
                FetchDescriptor<CachedRecommendation>(
                    predicate: #Predicate { $0.id == seenId }
                )
            ).first {
                rec.isSeen = true
                rec.seenAt = Date()
            }
        }
        scheduleSyncSeen()
    }

    private func scheduleSyncSeen() {
        seenSyncTask?.cancel()
        // Batch writes: sync within 30 seconds of last seen event (REC-09)
        seenSyncTask = Task {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, !pendingSeenIds.isEmpty else { return }
            let ids = Array(pendingSeenIds)
            pendingSeenIds.removeAll()
            try? await APIClient.shared.submitSeenBooks(bookIds: ids)
        }
    }

    // Flush any pending seen IDs immediately (e.g. on app background)
    func flushPendingSeen() {
        seenSyncTask?.cancel()
        guard !pendingSeenIds.isEmpty else { return }
        let ids = Array(pendingSeenIds)
        pendingSeenIds.removeAll()
        Task { try? await APIClient.shared.submitSeenBooks(bookIds: ids) }
    }

    // MARK: - Reactions (REC-08)

    func save(_ rec: CachedRecommendation, modelContext: ModelContext) {
        let item = ReadingListItem(
            id: rec.id,
            title: rec.title,
            author: rec.author,
            coverURL: rec.coverURL,
            blurb: rec.blurb,
            domain: rec.domain,
            genre: rec.genre,
            era: rec.era,
            becauseOf: rec.becauseOf,
            readingTimeMinutes: rec.readingTimeMinutes,
            nytBestseller: rec.nytBestseller,
            nytWeeksOnList: rec.nytWeeksOnList
        )
        modelContext.insert(item)
        removeFromFeed(rec, modelContext: modelContext)
        Task { try? await APIClient.shared.submitReaction(bookId: rec.id, kind: .save) }
    }

    func dismiss(_ rec: CachedRecommendation, modelContext: ModelContext) {
        removeFromFeed(rec, modelContext: modelContext)
        Task { try? await APIClient.shared.submitReaction(bookId: rec.id, kind: .dismiss) }
    }

    func markAlreadyRead(_ rec: CachedRecommendation, liked: Bool, modelContext: ModelContext) {
        removeFromFeed(rec, modelContext: modelContext)
        let kind: ReactionKind = liked ? .alreadyReadLiked : .alreadyReadDisliked
        Task { try? await APIClient.shared.submitReaction(bookId: rec.id, kind: kind) }

        // Loved it → also seed the book so it informs future recs and shows up in Taste
        if liked {
            let title = rec.title
            let author = rec.author
            let coverURL = rec.coverURL
            // Skip if a local seed for this book already exists
            let titleKey = title.lowercased()
            let authorKey = author.lowercased()
            let descriptor = FetchDescriptor<LocalSeedBook>()
            let alreadySeeded = ((try? modelContext.fetch(descriptor)) ?? []).contains {
                $0.title.lowercased() == titleKey && $0.author.lowercased() == authorKey
            }
            if !alreadySeeded {
                let local = LocalSeedBook(id: UUID().uuidString, title: title, author: author, coverURL: coverURL)
                modelContext.insert(local)
                Task {
                    try? await APIClient.shared.submitSeedBook(title: title, author: author, coverURL: coverURL)
                }
            }
        }
    }

    private func removeFromFeed(_ rec: CachedRecommendation, modelContext: ModelContext) {
        rec.isReacted = true
        // SwiftData state updated immediately; backend call is async (REC-08)
    }

    // MARK: - End of Feed

    func loadMore(modelContext: ModelContext) {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        advanceTagline()
        Task {
            // force=true tells the backend to generate a fresh batch immediately
            // rather than returning cached recs
            await fetchLatestBatch(modelContext: modelContext, isForegrounded: false, force: true)
            await MainActor.run {
                self.isLoadingMore = false
                self.scrollToTopTick += 1   // signal ForYouView to scroll back to the top
            }
        }
    }

    private func advanceTagline() {
        var next = Int.random(in: 0..<Strings.ForYou.endOfFeedTaglines.count)
        // Never show the same tagline twice in a row (DISC-12)
        while next == lastTaglineIndex && Strings.ForYou.endOfFeedTaglines.count > 1 {
            next = Int.random(in: 0..<Strings.ForYou.endOfFeedTaglines.count)
        }
        lastTaglineIndex = currentTaglineIndex
        currentTaglineIndex = next
    }

    func dismissNewBatchBanner() {
        showNewBatchBanner = false
    }

    // Canonical dedup key — same logic the backend uses for exclude lists.
    static func bookKey(title: String, author: String) -> String {
        "\(title.lowercased().trimmingCharacters(in: .whitespaces))|\(author.lowercased().trimmingCharacters(in: .whitespaces))"
    }
}
