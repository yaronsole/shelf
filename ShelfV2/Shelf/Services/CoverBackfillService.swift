import Foundation
import SwiftData

// One-shot scan for SwiftData rows whose coverURL is empty, looks each up via
// Google Books, and persists the result. Called on app launch.
enum CoverBackfillService {
    static func backfillAll(modelContext: ModelContext) {
        Task { @MainActor in
            await backfillSeeds(modelContext: modelContext)
            await backfillReadingList(modelContext: modelContext)
            await backfillRecommendations(modelContext: modelContext)
        }
    }

    @MainActor
    private static func backfillSeeds(modelContext: ModelContext) async {
        let seeds = (try? modelContext.fetch(FetchDescriptor<LocalSeedBook>())) ?? []
        for seed in seeds where seed.coverURL.isEmpty {
            if let cover = await lookup(title: seed.title, author: seed.author) {
                seed.coverURL = cover
            }
        }
    }

    @MainActor
    private static func backfillReadingList(modelContext: ModelContext) async {
        let items = (try? modelContext.fetch(FetchDescriptor<ReadingListItem>())) ?? []
        for item in items where item.coverURL.isEmpty {
            if let cover = await lookup(title: item.title, author: item.author) {
                item.coverURL = cover
            }
        }
    }

    @MainActor
    private static func backfillRecommendations(modelContext: ModelContext) async {
        let recs = (try? modelContext.fetch(FetchDescriptor<CachedRecommendation>())) ?? []
        for rec in recs where rec.coverURL.isEmpty {
            if let cover = await lookup(title: rec.title, author: rec.author) {
                rec.coverURL = cover
            }
        }
    }

    private static func lookup(title: String, author: String) async -> String? {
        guard let result = await GoogleBooksService.shared.lookup(title: title, author: author),
              let cover = result.coverURL,
              !cover.isEmpty else { return nil }
        return cover
    }
}
