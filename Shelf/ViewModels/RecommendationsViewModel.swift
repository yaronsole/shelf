import Foundation
import SwiftData
import SwiftUI

// MARK: - DC-05: Session tracking constants
private let kDiscoverSessionCount  = "discoverSessionCount"
private let kPassedBooksSessionMap = "passedBooksSessionMap"
private let kPassSuppressionSessions = 5   // Q2 confirmed: 5 sessions

@MainActor
@Observable
final class RecommendationsViewModel {
    var books: [Book] = []
    var isLoading = false
    var errorMessage: String?
    var pendingFollowUps: [Purchase] = []

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func loadIfNeeded() {
        checkFollowUps()
        if books.isEmpty && !isLoading {
            Task { await refresh() }
        }
    }

    func refresh() async {
        guard let apiKey = Keychain.read(key: .llmAPIKey), !apiKey.isEmpty else {
            errorMessage = "No API key configured. Go to Settings."
            return
        }
        let providerRaw = Keychain.read(key: .llmProvider) ?? LLMProvider.claude.rawValue
        let provider = LLMProvider(rawValue: providerRaw) ?? .claude

        isLoading = true
        errorMessage = nil

        do {
            let seeds    = try modelContext.fetch(FetchDescriptor<SeedBook>())
            let reactions = try modelContext.fetch(FetchDescriptor<Reaction>())
            let purchases = try modelContext.fetch(FetchDescriptor<Purchase>())
            let shownBooks = try modelContext.fetch(FetchDescriptor<ShownBook>())
            let wishlistItems = try modelContext.fetch(FetchDescriptor<WishlistItem>())

            let thumbsUp  = reactions.filter { $0.type == .thumbsUp }
            let thumbsDown = reactions.filter { $0.type == .thumbsDown }
            let liked     = reactions.filter { $0.type == .alreadyReadLiked }
            let disliked  = reactions.filter { $0.type == .alreadyReadDisliked }

            // REG-02 + REG-06: Build exclusion list from BOTH ShownBook AND WishlistItem,
            //                   sorted by recency, deduplicated, capped at 100.
            // DC-05: Exclude only ShownBook entries that are within the pass suppression
            //        window; after 5 sessions a passed book becomes eligible again.
            let passedMap = (UserDefaults.standard.dictionary(forKey: kPassedBooksSessionMap)
                as? [String: Int]) ?? [:]
            let currentSession = UserDefaults.standard.integer(forKey: kDiscoverSessionCount)

            // ShownBook titles filtered for DC-05 suppression logic
            let shownTitles: [(title: String, date: Date)] = shownBooks.compactMap { shown in
                if let passedSession = passedMap[shown.title] {
                    // Temporarily suppressed — only include in exclusion if within cooldown
                    guard currentSession - passedSession < kPassSuppressionSessions else {
                        return nil  // cooldown expired → eligible for re-recommendation
                    }
                }
                return (shown.title, shown.dateShown)
            }

            // WishlistItem titles always excluded (REG-02)
            let wishlistTitles: [(title: String, date: Date)] = wishlistItems.map {
                ($0.bookTitle, $0.savedDate)
            }

            // Merge, deduplicate (keep most recent occurrence), sort by recency, cap at 100
            var seenTitles = Set<String>()
            let allExclusions = (shownTitles + wishlistTitles)
                .sorted { $0.date > $1.date }
                .compactMap { pair -> String? in
                    guard seenTitles.insert(pair.title).inserted else { return nil }
                    return pair.title
                }
            let allShownTitles = Array(allExclusions.prefix(100))  // REG-06: cap at 100

            let recommendations = try await LLMService.shared.getRecommendations(
                seeds: seeds,
                thumbsUp: thumbsUp,
                thumbsDown: thumbsDown,
                alreadyReadLiked: liked,
                alreadyReadDisliked: disliked,
                purchases: purchases,
                allShownTitles: allShownTitles,
                apiKey: apiKey,
                provider: provider
            )

            // Enrich with Google Books metadata
            var enriched: [Book] = []
            await withTaskGroup(of: Book.self) { group in
                for rec in recommendations {
                    group.addTask {
                        let meta = await GoogleBooksService.shared.enrich(title: rec.title, author: rec.author)
                        return Book(
                            title: rec.title,
                            author: rec.author,
                            asin: meta.asin,
                            isbn: meta.isbn,
                            coverURL: meta.coverURL,
                            description: meta.description,
                            reasoningBlurb: rec.reasoning,
                            attribution: rec.attribution,
                            awards: rec.badges
                        )
                    }
                }
                for await book in group {
                    enriched.append(book)
                }
            }

            // REG-03: suppress books without a resolved cover image; save to ShownBook anyway
            let withCovers = enriched.filter { book in
                guard let cover = book.coverURL, !cover.isEmpty else { return false }
                return true
            }

            // REG-03: save coverless books to ShownBook so they don't resurface
            let coverlessTitles = Set(enriched.map { $0.title }).subtracting(withCovers.map { $0.title })
            for book in enriched where coverlessTitles.contains(book.title) {
                modelContext.insert(ShownBook(title: book.title, author: book.author))
            }

            // Sort to maintain LLM order
            let orderedTitles = recommendations.map { $0.title }
            let sorted = withCovers.sorted { a, b in
                let ai = orderedTitles.firstIndex(of: a.title) ?? 0
                let bi = orderedTitles.firstIndex(of: b.title) ?? 0
                return ai < bi
            }

            // Save as ShownBooks
            for book in sorted {
                let shown = ShownBook(
                    title: book.title, author: book.author,
                    asin: book.asin, isbn: book.isbn,
                    coverURL: book.coverURL, description: book.description,
                    reasoningBlurb: book.reasoningBlurb
                )
                modelContext.insert(shown)
            }
            try modelContext.save()

            // DC-05: increment discover session count (session = load where ≥1 card shown)
            if !sorted.isEmpty {
                let newSession = currentSession + 1
                UserDefaults.standard.set(newSession, forKey: kDiscoverSessionCount)
            }

            self.books = sorted

        } catch {
            errorMessage = "Failed to load recommendations: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func thumbsUp(book: Book) {
        let reaction = Reaction(bookTitle: book.title, bookAuthor: book.author, type: .thumbsUp)
        modelContext.insert(reaction)
        try? modelContext.save()
    }

    func thumbsDown(book: Book) {
        let reaction = Reaction(bookTitle: book.title, bookAuthor: book.author, type: .thumbsDown)
        modelContext.insert(reaction)
        try? modelContext.save()
        books.removeAll { $0.id == book.id }

        // DC-05: record which session this book was passed in
        let currentSession = UserDefaults.standard.integer(forKey: kDiscoverSessionCount)
        var passedMap = (UserDefaults.standard.dictionary(forKey: kPassedBooksSessionMap)
            as? [String: Int]) ?? [:]
        passedMap[book.title] = currentSession
        UserDefaults.standard.set(passedMap, forKey: kPassedBooksSessionMap)
    }

    func alreadyRead(book: Book, liked: Bool) {
        let type: ReactionType = liked ? .alreadyReadLiked : .alreadyReadDisliked
        let reaction = Reaction(bookTitle: book.title, bookAuthor: book.author, type: type)
        modelContext.insert(reaction)
        try? modelContext.save()
        if !liked {
            books.removeAll { $0.id == book.id }
        }
    }

    func logPurchase(book: Book) async {
        let purchase = Purchase(bookTitle: book.title, bookAuthor: book.author)
        modelContext.insert(purchase)
        try? modelContext.save()

        let granted = await NotificationService.shared.requestPermission()
        if granted {
            NotificationService.shared.scheduleFollowUp(for: purchase)
        }
    }

    func addToWishlist(book: Book) {
        // REG-02: check not already in wishlist
        let existing = try? modelContext.fetch(FetchDescriptor<WishlistItem>())
        guard !(existing?.contains(where: { $0.bookTitle == book.title }) ?? false) else { return }
        let item = WishlistItem(
            bookTitle: book.title, bookAuthor: book.author,
            asin: book.asin, isbn: book.isbn,
            coverURL: book.coverURL, description: book.description,
            reasoningBlurb: book.reasoningBlurb,
            awardBadges: book.awards
        )
        modelContext.insert(item)
        try? modelContext.save()
        // Note: WishlistItem titles are included in the exclusion list on next refresh (REG-02)
    }

    func submitFollowUp(purchase: Purchase, response: FollowUpResponse) {
        purchase.followUpResponse = response.rawValue
        purchase.followUpDate = Date()
        try? modelContext.save()
        pendingFollowUps.removeAll { $0.id == purchase.id }
        NotificationService.shared.cancelFollowUp(for: purchase.id)
    }

    func dismissFollowUp(purchase: Purchase) {
        purchase.followUpDismissedCount += 1
        try? modelContext.save()
        pendingFollowUps.removeAll { $0.id == purchase.id }
    }

    private func checkFollowUps() {
        let purchases = (try? modelContext.fetch(FetchDescriptor<Purchase>())) ?? []
        pendingFollowUps = purchases.filter { $0.needsFollowUp }
    }
}
