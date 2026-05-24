import Foundation
import SwiftData

@Observable
final class DiscoverViewModel {
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var showNewBatchBanner: Bool = false

    // Tracks IDs newly seen this session (scrolled past upward) — written to backend in batches
    private var pendingSeenIds: Set<String> = []
    private var seenSyncTask: Task<Void, Never>? = nil

    // End-of-feed state
    var isLoadingMore: Bool = false
    var noMoreContent: Bool = false
    var currentTaglineIndex: Int = Int.random(in: 0..<Strings.Discover.endOfFeedTaglines.count)
    private var lastTaglineIndex: Int = -1

    // MARK: - Feed Refresh

    func refreshIfNeeded(modelContext: ModelContext, isForegrounded: Bool = false) {
        Task {
            await fetchLatestBatch(modelContext: modelContext, isForegrounded: isForegrounded)
        }
    }

    private func fetchLatestBatch(modelContext: ModelContext, isForegrounded: Bool) async {
        guard !isLoading else { return }
        if !isForegrounded { isLoading = true }
        errorMessage = nil

        do {
            let dtos = try await APIClient.shared.fetchRecommendations()
            await MainActor.run {
                // Fetch all existing IDs upfront — avoids per-item #Predicate captures
                let existingIds = Set(
                    (try? modelContext.fetch(FetchDescriptor<CachedRecommendation>()))?.map(\.id) ?? []
                )
                var insertedCount = 0
                for dto in dtos {
                    // Filter books without resolvable cover (RG-04)
                    guard !dto.coverURL.isEmpty else { continue }
                    guard !existingIds.contains(dto.id) else { continue }
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
                        domain: dto.domain
                    )
                    modelContext.insert(rec)
                    insertedCount += 1
                }
                self.isLoading = false
                if isForegrounded && insertedCount > 0 {
                    self.showNewBatchBanner = true
                }
            }
        } catch {
            print("[Discover] fetchRecommendations failed: \(error)")
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = Strings.Discover.networkError
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
            domain: rec.domain
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
            await fetchLatestBatch(modelContext: modelContext, isForegrounded: false)
            await MainActor.run { self.isLoadingMore = false }
        }
    }

    private func advanceTagline() {
        var next = Int.random(in: 0..<Strings.Discover.endOfFeedTaglines.count)
        // Never show the same tagline twice in a row (DISC-12)
        while next == lastTaglineIndex && Strings.Discover.endOfFeedTaglines.count > 1 {
            next = Int.random(in: 0..<Strings.Discover.endOfFeedTaglines.count)
        }
        lastTaglineIndex = currentTaglineIndex
        currentTaglineIndex = next
    }

    func dismissNewBatchBanner() {
        showNewBatchBanner = false
    }
}
