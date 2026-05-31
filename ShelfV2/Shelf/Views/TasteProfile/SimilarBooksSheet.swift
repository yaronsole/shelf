import SwiftUI
import SwiftData

/// Bottom sheet shown when the user taps a seed book in the Taste profile.
/// Serves from pre-computed cache when fresh (<24h); falls back to live fetch.
/// Cards use the For You visual style — tap opens BookDetailView, long-press saves.
struct SimilarBooksSheet: View {
    let seed: LocalSeedBook
    let modelContext: ModelContext

    @Environment(\.dismiss) private var dismiss

    @State private var suggestions: [CachedSuggestion] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var servedFromCache = false

    // Live-fetch state (used when cache is empty/stale or on pull-to-refresh)
    @State private var liveFetchExcludeKeys: [String] = []
    @State private var liveSuggestions: [SuggestionDTO] = []
    @State private var hiddenIds: Set<String> = []

    // title|author keys for books the user has already saved (Shelf) or read/seeded (Taste);
    // these are filtered out of the displayed suggestions.
    @State private var ownedKeys: Set<String> = []

    // Detail-sheet state — wired to BookDetailView (same pattern as ForYouView)
    @State private var selectedDisplay: SuggestionDetailContext? = nil

    private var visibleLive: [SuggestionDTO] {
        liveSuggestions.filter {
            !hiddenIds.contains($0.id) && !ownedKeys.contains(Self.key($0.title, $0.author))
        }
    }
    private var visibleCached: [CachedSuggestion] {
        suggestions.filter {
            !hiddenIds.contains($0.id) && !ownedKeys.contains(Self.key($0.title, $0.author))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    seedHeader

                    if isLoading {
                        loadingView
                    } else if servedFromCache {
                        cachedContent
                    } else {
                        liveContent
                    }
                }
                .padding(.bottom, 24)
            }
            .refreshable { await forceRefresh() }
            .navigationTitle("Similar books")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(Strings.Common.done) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .task { await initialLoad() }
        .sheet(item: $selectedDisplay) { ctx in
            BookDetailView(
                display: ctx.display,
                onSave: { saveContext(ctx) },
                onPass: { hiddenIds.insert(ctx.id) },
                onSentiment: { liked in
                    if liked {
                        seedFromContext(ctx)
                    }
                    hiddenIds.insert(ctx.id)
                    ToastManager.shared.show(liked ? .reactedRead : .reactedPass)
                }
            )
        }
    }

    // MARK: - Sub-views

    private var seedHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            BookCoverView(url: seed.coverURL, width: 60)
            VStack(alignment: .leading, spacing: 4) {
                Text("Because you love")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text(seed.title)
                    .font(.title3.bold())
                Text(seed.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Finding similar reads…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    @ViewBuilder
    private var cachedContent: some View {
        if visibleCached.isEmpty {
            emptyState
        } else {
            ForEach(visibleCached) { s in
                let ctx = SuggestionDetailContext(
                    id: s.id,
                    display: BookDisplay(from: s, becauseOf: seed.title),
                    source: .cached(s)
                )
                BookCardView(
                    display: ctx.display,
                    onTap: { selectedDisplay = ctx },
                    onSave: {
                        saveContext(ctx)
                        ToastManager.shared.show(.savedToShelf)
                    }
                )
                .padding(.horizontal, 16)
            }
        }
        findMoreButton { Task { await loadMoreLive() } }
    }

    @ViewBuilder
    private var liveContent: some View {
        if visibleLive.isEmpty {
            emptyState
        } else {
            ForEach(visibleLive) { s in
                let ctx = SuggestionDetailContext(
                    id: s.id,
                    display: BookDisplay(from: s, becauseOf: seed.title),
                    source: .live(s)
                )
                BookCardView(
                    display: ctx.display,
                    onTap: { selectedDisplay = ctx },
                    onSave: {
                        saveContext(ctx)
                        ToastManager.shared.show(.savedToShelf)
                    }
                )
                .padding(.horizontal, 16)
            }
        }
        findMoreButton { Task { await loadMoreLive() } }
    }

    private var emptyState: some View {
        Text("No more suggestions for this book right now.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.top, 40)
    }

    private func findMoreButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoadingMore {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "sparkles")
                }
                Text(isLoadingMore ? "Digging up more…" : "Show me different ones")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemFill)))
            .foregroundStyle(Color(.label))
        }
        .buttonStyle(.plain)
        .disabled(isLoadingMore)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Save / seed actions

    private func saveContext(_ ctx: SuggestionDetailContext) {
        let display = ctx.display
        let item = ReadingListItem(
            id: ctx.id,
            title: display.title,
            author: display.author,
            coverURL: display.coverURL,
            blurb: display.blurb.isEmpty ? "Suggested because you love \(seed.title)." : display.blurb,
            genre: display.genre,
            era: display.era,
            becauseOf: display.becauseOf,
            readingTimeMinutes: display.readingTimeMinutes,
            nytBestseller: display.nytBestseller,
            nytWeeksOnList: display.nytWeeksOnList
        )
        modelContext.insert(item)
        hiddenIds.insert(ctx.id)
    }

    /// "Loved it" → also add to seeds (same as before)
    private func seedFromContext(_ ctx: SuggestionDetailContext) {
        let title = ctx.display.title
        let author = ctx.display.author
        let coverURL = ctx.display.coverURL
        Task { @MainActor in
            do {
                try await APIClient.shared.submitSeedBook(title: title, author: author, coverURL: coverURL)
                let local = LocalSeedBook(id: UUID().uuidString, title: title, author: author, coverURL: coverURL)
                modelContext.insert(local)
            } catch {
                print("[SimilarBooks] failed to seed liked book: \(error)")
            }
        }
    }

    // MARK: - Load logic

    private func initialLoad() async {
        let owned = loadOwnedKeys()
        if SimilarBooksCacheService.isCacheUsable(seed) {
            // Fresh per-open nonce → the cached deck re-rolls on every sheet open.
            let rotationKey = UUID().uuidString
            let cached = SimilarBooksCacheService.displaySuggestions(for: seed, rotationKey: rotationKey)
            await MainActor.run {
                self.ownedKeys = owned
                self.suggestions = cached
                self.servedFromCache = true
                self.isLoading = false
            }
            return
        }
        await MainActor.run { self.ownedKeys = owned }
        await liveFetchInitial()
    }

    private func forceRefresh() async {
        await MainActor.run {
            self.isLoading = true
            self.servedFromCache = false
            self.liveSuggestions = []
            self.liveFetchExcludeKeys = []
            self.hiddenIds = []
            self.ownedKeys = loadOwnedKeys()
        }
        await liveFetchInitial()
    }

    private func liveFetchInitial() async {
        let keys = baseExcludeKeys()
        let results = await fetch(exclude: keys, count: 5)
        await MainActor.run {
            let newKeys = results.map { Self.key($0.title, $0.author) }
            self.liveFetchExcludeKeys = keys + newKeys
            Self.appendHistory(newKeys, for: self.seed)
            self.liveSuggestions = results
            self.isLoading = false
        }
    }

    private func loadMoreLive() async {
        guard !isLoadingMore else { return }
        await MainActor.run {
            self.isLoadingMore = true
            // Opened from cache → liveFetchExcludeKeys is still empty; seed it from
            // persisted history + saved so the CTA returns genuinely-new books.
            if self.liveFetchExcludeKeys.isEmpty {
                self.liveFetchExcludeKeys = self.baseExcludeKeys()
            }
        }
        let results = await fetch(exclude: liveFetchExcludeKeys, count: 5)
        await MainActor.run {
            let newKeys = results.map { Self.key($0.title, $0.author) }
            self.liveFetchExcludeKeys.append(contentsOf: newKeys)
            Self.appendHistory(newKeys, for: self.seed)
            self.liveSuggestions.append(contentsOf: results)
            self.servedFromCache = false
            self.isLoadingMore = false
        }
    }

    /// Keys we never want the backend to return: this seed, books the user has
    /// already saved or read/seeded, plus the per-seed suggestion history.
    private func baseExcludeKeys() -> [String] {
        let seedKey = Self.key(seed.title, seed.author)
        let history = Self.loadHistory(for: seed)
        var keys: [String] = [seedKey]
        for k in loadOwnedKeys() where !keys.contains(k) { keys.append(k) }
        for k in history where !keys.contains(k) { keys.append(k) }
        return keys
    }

    /// title|author keys for every book the user has saved to the Shelf
    /// (ReadingListItem) or added as a Taste seed / marked read (LocalSeedBook).
    private func loadOwnedKeys() -> Set<String> {
        let saved = (try? modelContext.fetch(FetchDescriptor<ReadingListItem>()))?
            .map { Self.key($0.title, $0.author) } ?? []
        let seeds = (try? modelContext.fetch(FetchDescriptor<LocalSeedBook>()))?
            .map { Self.key($0.title, $0.author) } ?? []
        return Set(saved + seeds)
    }

    // MARK: - Fetch helper

    private func fetch(exclude: [String], count: Int) async -> [SuggestionDTO] {
        let request = BookSearchResult(id: seed.id, title: seed.title, author: seed.author, coverURL: seed.coverURL)
        let results = (try? await APIClient.shared.fetchSuggestions(for: request, count: count, exclude: exclude)) ?? []
        // Cover-image regression guard: never surface cover-less books (parity with the cache write).
        return results.filter { !$0.coverURL.isEmpty }
    }

    // MARK: - History persistence

    private static func key(_ title: String, _ author: String) -> String {
        "\(title.lowercased())|\(author.lowercased())"
    }

    private static func historyKey(for seed: LocalSeedBook) -> String {
        "shelf.suggestionHistory.\(seed.title.lowercased())|\(seed.author.lowercased())"
    }

    private static let historyCap = 100

    private static func loadHistory(for seed: LocalSeedBook) -> [String] {
        UserDefaults.standard.stringArray(forKey: historyKey(for: seed)) ?? []
    }

    private static func appendHistory(_ keys: [String], for seed: LocalSeedBook) {
        var merged = loadHistory(for: seed)
        for k in keys where !merged.contains(k) { merged.append(k) }
        if merged.count > historyCap { merged = Array(merged.suffix(historyCap)) }
        UserDefaults.standard.set(merged, forKey: historyKey(for: seed))
    }
}

// MARK: - Suggestion context (lets us route either cached or live through one sheet)

struct SuggestionDetailContext: Identifiable {
    let id: String
    let display: BookDisplay
    let source: Source

    enum Source {
        case cached(CachedSuggestion)
        case live(SuggestionDTO)
    }
}
