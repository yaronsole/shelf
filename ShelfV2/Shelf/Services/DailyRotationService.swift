import Foundation
import SwiftData

/// Replaces the oldest N ForYou items once per calendar day (local time).
/// Triggered on scenePhase .active; runs asynchronously so it never blocks UI.
@Observable
final class DailyRotationService {
    static let shared = DailyRotationService()
    private init() {}

    static let rotationCount = 5
    private static let lastRotationKey = "shelf.lastRotationDate"

    /// Set to true when a rotation completes. ForYouView watches this to fire TST-8.
    var didCompleteRotationThisSession = false
    var rotationCompletedAt: Date? = nil

    // MARK: - Trigger

    func triggerIfNeeded(modelContext: ModelContext, seedCount: Int) {
        guard shouldRotate(seedCount: seedCount) else { return }
        Task {
            await rotate(modelContext: modelContext)
        }
    }

    private func shouldRotate(seedCount: Int) -> Bool {
        guard seedCount >= 1 else { return false }
        let today = todayString()
        let last = UserDefaults.standard.string(forKey: Self.lastRotationKey) ?? ""
        return today != last
    }

    private func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter.string(from: Calendar.current.startOfDay(for: Date()))
    }

    // MARK: - Rotation logic

    @MainActor
    private func rotate(modelContext: ModelContext) async {
        let all = (try? modelContext.fetch(
            FetchDescriptor<CachedRecommendation>(
                predicate: #Predicate { !$0.isReacted },
                sortBy: [SortDescriptor(\CachedRecommendation.fetchedAt, order: .forward)]
            )
        )) ?? []

        // Need at least rotationCount items to rotate; fewer → just regenerate normally
        guard all.count >= Self.rotationCount else {
            UserDefaults.standard.set(todayString(), forKey: Self.lastRotationKey)
            return
        }

        // Identify the oldest N items to retire
        let toRetire = Array(all.prefix(Self.rotationCount))

        // Request N new recs before retiring the old ones — don't delete until confirmed
        do {
            let newDtos = try await APIClient.shared.fetchRecommendations(force: true)
            guard !newDtos.isEmpty else { return }

            // Insert new recs (same dedup logic as ForYouViewModel)
            let existing = (try? modelContext.fetch(FetchDescriptor<CachedRecommendation>())) ?? []
            let byId = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
            let existingKeys = Set(existing.map { ForYouViewModel.bookKey(title: $0.title, author: $0.author) })
            var seenThisBatch = Set<String>()
            var inserted = 0

            for dto in newDtos {
                if byId[dto.id] != nil { continue }
                guard BookCoverView.hasValidCover(dto.coverURL) else { continue }
                let key = ForYouViewModel.bookKey(title: dto.title, author: dto.author)
                guard !existingKeys.contains(key), !seenThisBatch.contains(key) else { continue }
                seenThisBatch.insert(key)

                let rec = CachedRecommendation(
                    id: dto.id, title: dto.title, author: dto.author,
                    coverURL: dto.coverURL, blurb: dto.blurb,
                    genre: dto.genre, era: dto.era,
                    isComfortZonePush: dto.isComfortZonePush,
                    batchId: dto.batchId, domain: dto.domain,
                    awards: dto.awards, contextTag: dto.contextTag,
                    acclaim: dto.acclaim, nytBestseller: dto.nytBestseller,
                    nytWeeksOnList: dto.nytWeeksOnList,
                    readingTimeMinutes: dto.readingTimeMinutes,
                    becauseOf: dto.becauseOf,
                    becauseOfReason: dto.becauseOfReason,
                    bookDescription: dto.bookDescription,
                    averageRating: dto.averageRating,
                    ratingsCount: dto.ratingsCount
                )
                modelContext.insert(rec)
                inserted += 1
                if inserted >= Self.rotationCount { break }
            }

            // Only retire old ones if we got at least some new ones
            if inserted > 0 {
                for rec in toRetire {
                    rec.isReacted = true
                }
            }

            UserDefaults.standard.set(todayString(), forKey: Self.lastRotationKey)
            didCompleteRotationThisSession = true
            rotationCompletedAt = Date()

        } catch {
            print("[DailyRotation] failed: \(error) — leaving existing feed intact")
        }
    }
}
