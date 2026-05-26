import SwiftUI
import SwiftData

/// Bottom sheet shown when the user taps a seed book in the Taste profile.
/// Serves from pre-computed cache when fresh (<24h); falls back to live fetch.
struct SimilarBooksSheet: View {
    let seed: LocalSeedBook
    let modelContext: ModelContext

    @Environment(\.dismiss) private var dismiss

    // Unique ID per app session so display selection rotates across sessions
    @State private var sessionId = UUID().uuidString

    @State private var suggestions: [CachedSuggestion] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var servedFromCache = false

    // Live-fetch state (used when cache is empty/stale or on pull-to-refresh)
    @State private var liveFetchExcludeKeys: [String] = []
    @State private var liveSuggestions: [SuggestionDTO] = []
    @State private var hiddenIds: Set<String> = []

    private var visibleLive: [SuggestionDTO] {
        liveSuggestions.filter { !hiddenIds.contains($0.id) }
    }
    private var visibleCached: [CachedSuggestion] {
        suggestions.filter { !hiddenIds.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
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

    private var cachedContent: some View {
        Group {
            if visibleCached.isEmpty {
                Text("No more suggestions for this book right now.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 40)
            } else {
                ForEach(visibleCached) { s in
                    CachedSuggestionCard(
                        suggestion: s,
                        onSave: { saveCached(s) },
                        onPass: { hiddenIds.insert(s.id) },
                        onAlreadyRead: { alreadyReadCached(s) }
                    )
                    .padding(.horizontal, 16)
                }
            }

            findMoreButton { Task { await loadMoreLive() } }
        }
    }

    private var liveContent: some View {
        Group {
            if visibleLive.isEmpty {
                Text("No more suggestions for this book right now.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 40)
            } else {
                ForEach(visibleLive) { s in
                    SuggestionCard(
                        suggestion: s,
                        onSave: { saveLive(s) },
                        onPass: { hiddenIds.insert(s.id) },
                        onAlreadyRead: { alreadyReadLive(s) }
                    )
                    .padding(.horizontal, 16)
                }
            }

            findMoreButton { Task { await loadMoreLive() } }
        }
    }

    private func findMoreButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoadingMore {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "sparkles")
                }
                Text(isLoadingMore ? "Finding more…" : "Find more like this")
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

    // MARK: - Load logic

    private func initialLoad() async {
        // Serve from cache if usable — no spinner, instant display.
        if SimilarBooksCacheService.isCacheUsable(seed) {
            let cached = SimilarBooksCacheService.displaySuggestions(for: seed, sessionId: sessionId)
            await MainActor.run {
                self.suggestions = cached
                self.servedFromCache = true
                self.isLoading = false
            }
            return
        }
        // Fall back to live fetch
        await liveFetchInitial()
    }

    private func forceRefresh() async {
        await MainActor.run {
            self.isLoading = true
            self.servedFromCache = false
            self.liveSuggestions = []
            self.liveFetchExcludeKeys = []
            self.hiddenIds = []
        }
        await liveFetchInitial()
    }

    private func liveFetchInitial() async {
        let seedKey = Self.key(seed.title, seed.author)
        let savedKeys = (try? modelContext.fetch(FetchDescriptor<ReadingListItem>()))?
            .map { Self.key($0.title, $0.author) } ?? []
        let history = Self.loadHistory(for: seed)

        var keys: [String] = []
        for k in [seedKey] + savedKeys + history where !keys.contains(k) {
            keys.append(k)
        }

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
        await MainActor.run { self.isLoadingMore = true }
        let results = await fetch(exclude: liveFetchExcludeKeys, count: 5)
        await MainActor.run {
            let newKeys = results.map { Self.key($0.title, $0.author) }
            self.liveFetchExcludeKeys.append(contentsOf: newKeys)
            Self.appendHistory(newKeys, for: self.seed)
            if self.servedFromCache {
                // Append live results below cached ones
                self.liveSuggestions.append(contentsOf: results)
                self.servedFromCache = false
            } else {
                self.liveSuggestions.append(contentsOf: results)
            }
            self.isLoadingMore = false
        }
    }

    // MARK: - Actions (cached path)

    private func saveCached(_ s: CachedSuggestion) {
        let item = ReadingListItem(
            id: s.id, title: s.title, author: s.author, coverURL: s.coverURL,
            blurb: s.blurb.isEmpty ? "Suggested because you love \(seed.title)." : s.blurb
        )
        modelContext.insert(item)
        hiddenIds.insert(s.id)
        ToastManager.shared.show(.savedToShelf)
    }

    private func alreadyReadCached(_ s: CachedSuggestion) {
        let title = s.title; let author = s.author; let coverURL = s.coverURL
        Task { @MainActor in
            do {
                try await APIClient.shared.submitSeedBook(title: title, author: author, coverURL: coverURL)
                let local = LocalSeedBook(id: UUID().uuidString, title: title, author: author, coverURL: coverURL)
                modelContext.insert(local)
            } catch {
                print("[SimilarBooks] failed to seed liked book: \(error)")
            }
        }
        hiddenIds.insert(s.id)
        ToastManager.shared.show(.reactedRead)
    }

    // MARK: - Actions (live path)

    private func saveLive(_ s: SuggestionDTO) {
        let item = ReadingListItem(
            id: s.id, title: s.title, author: s.author, coverURL: s.coverURL,
            blurb: s.blurb.isEmpty ? "Suggested because you love \(seed.title)." : s.blurb
        )
        modelContext.insert(item)
        hiddenIds.insert(s.id)
        ToastManager.shared.show(.savedToShelf)
    }

    private func alreadyReadLive(_ s: SuggestionDTO) {
        let title = s.title; let author = s.author; let coverURL = s.coverURL
        Task { @MainActor in
            do {
                try await APIClient.shared.submitSeedBook(title: title, author: author, coverURL: coverURL)
                let local = LocalSeedBook(id: UUID().uuidString, title: title, author: author, coverURL: coverURL)
                modelContext.insert(local)
            } catch {
                print("[SimilarBooks] failed to seed liked book: \(error)")
            }
        }
        hiddenIds.insert(s.id)
        ToastManager.shared.show(.reactedRead)
    }

    // MARK: - Fetch helper

    private func fetch(exclude: [String], count: Int) async -> [SuggestionDTO] {
        let request = BookSearchResult(id: seed.id, title: seed.title, author: seed.author, coverURL: seed.coverURL)
        return (try? await APIClient.shared.fetchSuggestions(for: request, count: count, exclude: exclude)) ?? []
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

// MARK: - Card for cached suggestions

private struct CachedSuggestionCard: View {
    let suggestion: CachedSuggestion
    let onSave: () -> Void
    let onPass: () -> Void
    let onAlreadyRead: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BookCoverView(url: suggestion.coverURL)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(suggestion.title)
                        .font(.title3.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Text(suggestion.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ContextRow(
                    nytBestseller: suggestion.nytBestseller,
                    nytWeeks: suggestion.nytWeeksOnList,
                    readingTimeMinutes: suggestion.readingTimeMinutes
                )

                if !suggestion.contextTag.isEmpty {
                    Label(suggestion.contextTag, systemImage: "sparkle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color(red: 0.30, green: 0.20, blue: 0.55))
                }

                if !suggestion.genre.isEmpty || !suggestion.era.isEmpty || !suggestion.awards.isEmpty {
                    HStack(spacing: 6) {
                        if !suggestion.genre.isEmpty { TinyTag(text: suggestion.genre) }
                        if !suggestion.era.isEmpty  { TinyTag(text: suggestion.era) }
                        ForEach(suggestion.awards, id: \.self) { AwardBadge(text: $0) }
                    }
                }

                if !suggestion.blurb.isEmpty {
                    Text(suggestion.blurb)
                        .font(.subheadline)
                        .foregroundStyle(Color(.label))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }

                HStack(spacing: 8) {
                    CardActionButton(label: "Save",     icon: "bookmark.fill", kind: .primary,    action: onSave)
                    CardActionButton(label: "Read it",  icon: "checkmark",     kind: .secondary,  action: onAlreadyRead)
                    CardActionButton(label: "Pass",     icon: "xmark",         kind: .tertiary,   action: onPass)
                }
                .padding(.top, 4)
            }
            .padding(14)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)
    }
}

// MARK: - Card for live SuggestionDTO (kept for fallback / load-more path)

private struct SuggestionCard: View {
    let suggestion: SuggestionDTO
    let onSave: () -> Void
    let onPass: () -> Void
    let onAlreadyRead: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BookCoverView(url: suggestion.coverURL)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(suggestion.title)
                        .font(.title3.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Text(suggestion.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ContextRow(
                    nytBestseller: suggestion.nytBestseller,
                    nytWeeks: suggestion.nytWeeksOnList,
                    readingTimeMinutes: suggestion.readingTimeMinutes
                )

                if !suggestion.contextTag.isEmpty {
                    Label(suggestion.contextTag, systemImage: "sparkle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color(red: 0.30, green: 0.20, blue: 0.55))
                }

                if !suggestion.genre.isEmpty || !suggestion.era.isEmpty || !suggestion.awards.isEmpty {
                    HStack(spacing: 6) {
                        if !suggestion.genre.isEmpty { TinyTag(text: suggestion.genre) }
                        if !suggestion.era.isEmpty  { TinyTag(text: suggestion.era) }
                        ForEach(suggestion.awards, id: \.self) { AwardBadge(text: $0) }
                    }
                }

                if !suggestion.blurb.isEmpty {
                    Text(suggestion.blurb)
                        .font(.subheadline)
                        .foregroundStyle(Color(.label))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }

                HStack(spacing: 8) {
                    CardActionButton(label: "Save",     icon: "bookmark.fill", kind: .primary,    action: onSave)
                    CardActionButton(label: "Read it",  icon: "checkmark",     kind: .secondary,  action: onAlreadyRead)
                    CardActionButton(label: "Pass",     icon: "xmark",         kind: .tertiary,   action: onPass)
                }
                .padding(.top, 4)
            }
            .padding(14)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)
    }
}

private struct TinyTag: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(Color(.secondaryLabel))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color(.secondarySystemFill)))
    }
}

private enum CardActionKind { case primary, secondary, tertiary }

private struct CardActionButton: View {
    let label: String
    let icon: String
    let kind: CardActionKind
    let action: () -> Void

    private var foreground: Color {
        switch kind {
        case .primary: return .white
        case .secondary: return Color(red: 0.10, green: 0.45, blue: 0.30)
        case .tertiary: return Color(.tertiaryLabel)
        }
    }
    private var background: Color {
        switch kind {
        case .primary: return Color(red: 0.10, green: 0.35, blue: 0.85)
        case .secondary: return Color(red: 0.10, green: 0.45, blue: 0.30).opacity(0.12)
        case .tertiary: return Color(.secondarySystemFill)
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                Text(label)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: kind == .primary ? .infinity : nil)
            .padding(.horizontal, kind == .primary ? 14 : 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(background))
            .foregroundStyle(foreground)
        }
        .buttonStyle(.plain)
    }
}
