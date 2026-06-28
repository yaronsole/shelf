import Foundation
import SwiftData

// MARK: - CachedSuggestion (Codable mirror of SuggestionDTO)

struct CachedSuggestion: Codable, Identifiable {
    let id: String
    let title: String
    let author: String
    let coverURL: String
    let blurb: String
    let genre: String
    let era: String
    let awards: [String]
    let contextTag: String
    let nytBestseller: Bool
    let nytWeeksOnList: Int?
    let readingTimeMinutes: Int?
    // Phase 3 PDP enrichment (optional → older cached blobs decode fine as nil)
    let bookDescription: String?
    let averageRating: Double?
    let ratingsCount: Int?
}

extension CachedSuggestion {
    init(from dto: SuggestionDTO) {
        id = dto.id
        title = dto.title
        author = dto.author
        coverURL = dto.coverURL
        blurb = dto.blurb
        genre = dto.genre
        era = dto.era
        awards = dto.awards
        contextTag = dto.contextTag
        nytBestseller = dto.nytBestseller
        nytWeeksOnList = dto.nytWeeksOnList
        readingTimeMinutes = dto.readingTimeMinutes
        bookDescription = dto.bookDescription
        averageRating = dto.averageRating
        ratingsCount = dto.ratingsCount
    }
}

// MARK: - Cache service

enum SimilarBooksCacheService {
    static let staleThreshold: TimeInterval = 8 * 3600    // 8 hours → trigger background refresh
    static let validThreshold:  TimeInterval = 24 * 3600  // 24 hours → still show in modal
    static let candidateCount = 18
    static let displayCount = 5
    static let maxParallel = 2
    static let staggerSeconds: UInt64 = 500_000_000 // 0.5s in nanoseconds

    // MARK: - Foreground refresh trigger

    static func refreshAllIfNeeded(seeds: [LocalSeedBook], modelContext: ModelContext) {
        let stale = seeds.filter { isStale($0) }
        guard !stale.isEmpty else { return }
        Task {
            var batches: [[LocalSeedBook]] = []
            var i = 0
            while i < stale.count {
                batches.append(Array(stale[i..<min(i + maxParallel, stale.count)]))
                i += maxParallel
            }
            for batch in batches {
                await withTaskGroup(of: Void.self) { group in
                    for (offset, seed) in batch.enumerated() {
                        group.addTask {
                            if offset > 0 {
                                try? await Task.sleep(nanoseconds: staggerSeconds * UInt64(offset))
                            }
                            await refresh(seed: seed, modelContext: modelContext)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Freshness checks

    static func isStale(_ seed: LocalSeedBook) -> Bool {
        guard let updatedAt = seed.similarBooksUpdatedAt else { return true }
        return Date().timeIntervalSince(updatedAt) > staleThreshold
    }

    static func isCacheUsable(_ seed: LocalSeedBook) -> Bool {
        guard let updatedAt = seed.similarBooksUpdatedAt,
              !seed.similarBooksData.isEmpty else { return false }
        return Date().timeIntervalSince(updatedAt) <= validThreshold
    }

    // MARK: - Reading cache

    static func allCachedSuggestions(for seed: LocalSeedBook) -> [CachedSuggestion] {
        guard !seed.similarBooksData.isEmpty else { return [] }
        return (try? JSONDecoder().decode([CachedSuggestion].self, from: seed.similarBooksData)) ?? []
    }

    // Return displayCount items chosen pseudo-randomly using a per-open rotationKey
    // so the visible set re-rolls every time the sheet is opened (within-session repeats
    // vanish). The deck itself still comes from cache; only WHICH displayCount show changes.
    static func displaySuggestions(for seed: LocalSeedBook, rotationKey: String) -> [CachedSuggestion] {
        let all = allCachedSuggestions(for: seed)
        guard all.count > displayCount else { return all }
        let hashInput = "\(rotationKey)|\(seed.similarBooksGenerationToken)"
        var h: UInt64 = 14695981039346656037
        for byte in hashInput.utf8 {
            h ^= UInt64(byte)
            h = h &* 1099511628211
        }
        var indices = Array(0..<all.count)
        var rng = h
        for i in stride(from: indices.count - 1, through: 1, by: -1) {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            let j = Int(rng >> 33) % (i + 1)
            indices.swapAt(i, j)
        }
        return indices.prefix(displayCount).map { all[$0] }
    }

    // MARK: - Cache write

    @MainActor
    static func refresh(seed: LocalSeedBook, modelContext: ModelContext) async {
        let seedKey = "\(seed.title.lowercased())|\(seed.author.lowercased())"
        let savedKeys = (try? modelContext.fetch(FetchDescriptor<ReadingListItem>()))
            .map { items in items.map { "\($0.title.lowercased())|\($0.author.lowercased())" } } ?? []
        let history = UserDefaults.standard.stringArray(
            forKey: "shelf.suggestionHistory.\(seedKey)") ?? []

        var excludeKeys = [seedKey] + savedKeys + history

        let request = BookSearchResult(
            id: seed.id, title: seed.title, author: seed.author, coverURL: seed.coverURL
        )
        guard let results = try? await APIClient.shared.fetchSuggestions(
            for: request, count: candidateCount, exclude: excludeKeys
        ) else { return }

        // Apply cover-image filter (regression guard)
        let filtered = results.filter { BookCoverView.hasValidCover($0.coverURL) }
        guard !filtered.isEmpty else { return }

        let candidates = filtered.map { CachedSuggestion(from: $0) }
        guard let data = try? JSONEncoder().encode(candidates) else { return }

        seed.similarBooksData = data
        seed.similarBooksUpdatedAt = Date()
        seed.similarBooksGenerationToken = UUID().uuidString
    }

    // Invalidate cache for a specific seed (called when seed is removed from Taste).
    static func invalidate(seed: LocalSeedBook) {
        seed.similarBooksData = Data()
        seed.similarBooksUpdatedAt = nil
        seed.similarBooksGenerationToken = ""
    }
}
