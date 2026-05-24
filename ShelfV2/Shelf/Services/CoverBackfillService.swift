import Foundation
import SwiftData

// One-shot scan for SwiftData rows whose coverURL is empty, looks each up via
// Google Books, and persists the result. Called on app launch.
enum CoverBackfillService {
    // Frequency cap: when a session ends, any book marked isSeen has been
    // "viewed once" — increment viewCount, reset the seen flag, and eliminate
    // (mark reacted) once it hits 2 cumulative views.
    @MainActor
    static func pruneSeenItems(modelContext: ModelContext) {
        let seen = (try? modelContext.fetch(
            FetchDescriptor<CachedRecommendation>(predicate: #Predicate { $0.isSeen })
        )) ?? []
        var capped = 0
        for rec in seen {
            rec.viewCount += 1
            rec.isSeen = false
            if rec.viewCount >= 2 {
                rec.isReacted = true   // permanently filtered out
                capped += 1
            }
        }
        print("[CoverBackfill] frequency-capped \(capped) books (out of \(seen.count) seen)")
    }

    static func backfillAll(modelContext: ModelContext) {
        print("[CoverBackfill] starting…")
        Task { @MainActor in
            await backfillSeeds(modelContext: modelContext)
            await backfillReadingList(modelContext: modelContext)
            await backfillRecommendations(modelContext: modelContext)
            print("[CoverBackfill] done.")
        }
    }

    @MainActor
    private static func backfillSeeds(modelContext: ModelContext) async {
        let seeds = (try? modelContext.fetch(FetchDescriptor<LocalSeedBook>())) ?? []
        let empties = seeds.filter { $0.coverURL.isEmpty }
        print("[CoverBackfill] LocalSeedBook: \(empties.count)/\(seeds.count) empty")
        for seed in empties {
            if let cover = await lookup(title: seed.title, author: seed.author) {
                seed.coverURL = cover
                print("[CoverBackfill]   ✓ seed: \(seed.title)")
            } else {
                print("[CoverBackfill]   ✗ seed: \(seed.title)")
            }
        }
    }

    @MainActor
    private static func backfillReadingList(modelContext: ModelContext) async {
        let items = (try? modelContext.fetch(FetchDescriptor<ReadingListItem>())) ?? []
        let empties = items.filter { $0.coverURL.isEmpty }
        print("[CoverBackfill] ReadingListItem: \(empties.count)/\(items.count) empty")
        for item in empties {
            if let cover = await lookup(title: item.title, author: item.author) {
                item.coverURL = cover
                print("[CoverBackfill]   ✓ saved: \(item.title)")
            } else {
                print("[CoverBackfill]   ✗ saved: \(item.title)")
            }
        }
    }

    @MainActor
    private static func backfillRecommendations(modelContext: ModelContext) async {
        let recs = (try? modelContext.fetch(FetchDescriptor<CachedRecommendation>())) ?? []
        let empties = recs.filter { $0.coverURL.isEmpty }
        print("[CoverBackfill] CachedRecommendation: \(empties.count)/\(recs.count) empty")
        for rec in empties {
            if let cover = await lookup(title: rec.title, author: rec.author) {
                rec.coverURL = cover
                print("[CoverBackfill]   ✓ rec: \(rec.title)")
            } else {
                print("[CoverBackfill]   ✗ rec: \(rec.title)")
            }
        }
    }

    private static func lookup(title: String, author: String) async -> String? {
        if let cover = await OpenLibraryService.shared.lookupCoverURL(title: title, author: author) {
            return cover
        }
        guard let result = await GoogleBooksService.shared.lookup(title: title, author: author),
              let cover = result.coverURL,
              !cover.isEmpty else { return nil }
        return cover
    }
}
