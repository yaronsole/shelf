import SwiftUI
import SwiftData

/// Shown in the For You tab when the user has < 3 seeds.
/// • Default view: instructional line, search box, popular-picks grid, list shortcuts.
/// • Search mode (query ≥ 2 chars): search box + results list (popular picks + shortcuts hidden).
struct EmptyForYouView: View {
    @Environment(\.modelContext) private var modelContext

    /// Called when the user chooses to graduate from the seed grid to the
    /// personalized feed (the "See my picks" affordance / prompt).
    var onSeePicks: () -> Void

    // Drives the progress framing ("<count> of 3"). Updates live as the user
    // adds loved books from any surface; at 3 we offer to switch to the real feed.
    @Query private var seedBooks: [LocalSeedBook]
    private let seedThreshold = 3

    // One-time "keep adding vs. see picks" prompt, shown when the user first
    // reaches the threshold. After it's been offered we don't nag — the
    // persistent "See my picks" button stays available in the footer.
    @State private var showPicksPrompt = false
    @State private var hasOfferedPicks = false

    // Shared store: covers are fetched once per launch and can be warmed early
    // (from app launch on Discover) so the grid is ready by the time For You opens.
    // `let` (not `var`) so it stays out of the synthesized memberwise init and
    // doesn't drop the init's access below the `onSeePicks` caller in ForYouView.
    private let picksStore = PopularPicksStore.shared
    @State private var searchQuery: String = ""
    @State private var searchResults: [BookSearchResult] = []
    @State private var isSearching: Bool = false
    @State private var searchTask: Task<Void, Never>? = nil
    // Local "added" sets so the row reflects the action immediately and we can
    // ignore double-taps; these are per-session and reset when the view is
    // re-created.
    @State private var addedBookIds: Set<String> = []
    @State private var savedBookIds: Set<String> = []
    // Book awaiting a loved / didn't-like choice. Presenting the sheet is what a
    // "mark as read" tap now does; the actual seed/reaction write happens only
    // after the user picks a sentiment (see confirmRead).
    @State private var pendingRead: PendingRead? = nil

    private let horizontalPadding: CGFloat = 16
    private let gridSpacing: CGFloat = 12

    private var isInSearchMode: Bool {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !isInSearchMode {
                    instructionalLine
                }
                searchBox
                if isInSearchMode {
                    searchResultsSection
                } else {
                    popularPicksSection
                    browseListSection
                    footerLine
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 16)
        }
        .navigationDestination(for: String.self) { slug in
            ListDetailView(slug: slug)
        }
        .sheet(item: $pendingRead) { pending in
            AlreadyReadSheet(
                title: pending.title,
                onLoved: { confirmRead(pending, liked: true) },
                onDidntLike: { confirmRead(pending, liked: false) }
            )
        }
        .onAppear {
            picksStore.prefetch()
            offerPicksIfReady()
        }
        .onChange(of: seedBooks.count) { _, _ in
            offerPicksIfReady()
        }
        .alert("That's \(seedThreshold) books", isPresented: $showPicksPrompt) {
            Button("Keep adding", role: .cancel) { }
            Button("See my picks") { onSeePicks() }
        } message: {
            Text("Add a few more, or start seeing your personalized picks now?")
        }
    }

    /// Offers the one-time prompt the first time the user reaches the threshold.
    private func offerPicksIfReady() {
        guard seedBooks.count >= seedThreshold, !hasOfferedPicks else { return }
        hasOfferedPicks = true
        showPicksPrompt = true
    }

    // MARK: - Sections

    private var instructionalLine: some View {
        Text("Add a few books you've loved and your picks start taking shape.")
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
    }

    private var searchBox: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search for a book…", text: $searchQuery)
                .autocorrectionDisabled()
                .onChange(of: searchQuery) { _, newValue in
                    performSearch(query: newValue)
                }
            if isInSearchMode {
                Button("Cancel") {
                    searchQuery = ""
                    searchResults = []
                    isSearching = false
                    searchTask?.cancel()
                }
                .font(.subheadline)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var popularPicksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("POPULAR PICKS")
            Text("Tap a cover to mark as read · Hold to save")
                .font(.caption)
                .foregroundStyle(.tertiary)
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: gridSpacing),
                    GridItem(.flexible(), spacing: gridSpacing),
                    GridItem(.flexible(), spacing: gridSpacing),
                ],
                spacing: gridSpacing
            ) {
                ForEach(picksStore.items) { pick in
                    PopularPickTile(
                        pick: pick,
                        isAdded: addedBookIds.contains(pick.id),
                        isSaved: savedBookIds.contains(pick.id),
                        onTap: { addPopularAsSeed(pick) },
                        onLongPress: { savePopularToShelf(pick) }
                    )
                }
            }
        }
    }

    private var browseListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("OR BROWSE A LIST")
            VStack(spacing: 12) {
                NavigationLink(value: "oprah_book_club") {
                    ListShortcutCard(
                        title: "Oprah's Book Club",
                        subtitle: "Since 1996",
                        colorStart: Color(hex: 0x534AB7),
                        colorEnd: Color(hex: 0x7F77DD)
                    )
                }
                .buttonStyle(.plain)
                NavigationLink(value: "reese_book_club") {
                    ListShortcutCard(
                        title: "Reese's Book Club",
                        subtitle: "Hello Sunshine",
                        colorStart: Color(hex: 0xD67C5C),
                        colorEnd: Color(hex: 0xF2B69A)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isSearching && searchResults.isEmpty {
                ProgressView().padding(.vertical, 24).frame(maxWidth: .infinity)
            } else if searchResults.isEmpty {
                Text("No results for \"\(searchQuery)\"")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(searchResults) { result in
                    SearchResultRow(
                        book: result,
                        isAdded: addedBookIds.contains(result.id),
                        isSaved: savedBookIds.contains(result.id),
                        onMarkRead: { addAsSeed(result) },
                        onSave: { saveToShelf(result) }
                    )
                    .padding(.vertical, 6)
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private var footerLine: some View {
        let count = min(seedBooks.count, seedThreshold)
        if seedBooks.count >= seedThreshold {
            // Reached the threshold: a persistent way to graduate to the feed
            // (the prompt offers this once; this keeps it available afterward).
            Button {
                Haptics.medium()
                onSeePicks()
            } label: {
                Text("See my picks ✦")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(hex: 0x1A1A1A))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        } else {
            VStack(spacing: 10) {
                // Three-segment progress bar that fills as loved books are added.
                HStack(spacing: 6) {
                    ForEach(0..<seedThreshold, id: \.self) { i in
                        Capsule()
                            .fill(i < count ? Color(hex: 0x1A1A1A) : Color(.secondarySystemFill))
                            .frame(width: 28, height: 6)
                    }
                }
                Text("\(count) of \(seedThreshold) added")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.top, 8)
            .animation(.easeInOut(duration: 0.25), value: count)
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(0.8)
    }

    private func performSearch(query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }
        searchTask = Task {
            // 300ms debounce: if the user keeps typing, this Task gets cancelled
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            await MainActor.run { self.isSearching = true }
            let results = await OpenLibraryService.shared.search(query: trimmed)
            if Task.isCancelled { return }
            await MainActor.run {
                self.searchResults = results
                self.isSearching = false
            }
        }
    }

    // "Mark as read" now asks for sentiment first: loved books become seeds,
    // disliked books register a negative reaction only (see SeedWriter).
    private func addAsSeed(_ book: BookSearchResult) {
        guard !addedBookIds.contains(book.id) else { return }
        Haptics.light()
        pendingRead = PendingRead(
            id: book.id, title: book.title, author: book.author, coverURL: book.coverURL ?? ""
        )
    }

    private func saveToShelf(_ book: BookSearchResult) {
        guard !savedBookIds.contains(book.id) else { return }
        Haptics.medium()
        savedBookIds.insert(book.id)
        let item = ReadingListItem(
            id: UUID().uuidString,
            title: book.title,
            author: book.author,
            coverURL: book.coverURL ?? "",
            blurb: "Saved from search."
        )
        modelContext.insert(item)
    }

    // Popular-picks variants (same id space — "title|author" lowercased — so
    // the addedBookIds/savedBookIds sets are shared with search results and
    // the cover reflects state if the same book appears in both).

    private func addPopularAsSeed(_ pick: PopularPickItem) {
        guard !addedBookIds.contains(pick.id) else { return }
        Haptics.light()
        pendingRead = PendingRead(
            id: pick.id, title: pick.title, author: pick.author, coverURL: pick.coverURL
        )
    }

    /// Commits the user's loved / didn't-like choice for a pending book.
    /// Optimistically flips the cover to its "read" state, then delegates the
    /// seed + reaction writes to SeedWriter; rolls the cover back on failure.
    private func confirmRead(_ pending: PendingRead, liked: Bool) {
        guard !addedBookIds.contains(pending.id) else { return }
        addedBookIds.insert(pending.id)
        Task { @MainActor in
            let ok = await SeedWriter.recordAlreadyRead(
                title: pending.title,
                author: pending.author,
                coverURL: pending.coverURL,
                liked: liked,
                modelContext: modelContext
            )
            if !ok { addedBookIds.remove(pending.id) }
        }
    }

    private func savePopularToShelf(_ pick: PopularPickItem) {
        guard !savedBookIds.contains(pick.id) else { return }
        Haptics.medium()
        savedBookIds.insert(pick.id)
        let item = ReadingListItem(
            id: UUID().uuidString,
            title: pick.title,
            author: pick.author,
            coverURL: pick.coverURL,
            blurb: "Saved from popular picks."
        )
        modelContext.insert(item)
    }

}

// MARK: - Popular Picks Store (preloadable)

/// Holds the popular-picks covers for the seed grid. Fetches a generous slice of
/// the curated list once per launch; `prefetch()` is idempotent so it can be
/// warmed early (from app launch while the user is on Discover) and again from
/// the grid's `onAppear` without re-fetching.
@Observable
final class PopularPicksStore {
    static let shared = PopularPicksStore()
    private init() {}

    private(set) var items: [PopularPickItem] = []
    private var isLoading = false
    private var hasLoaded = false

    func prefetch() {
        guard !hasLoaded, !isLoading else { return }
        isLoading = true
        Task {
            // Covers are fetched concurrently; entries whose lookup fails are
            // dropped, so the rendered count may be slightly under 24.
            let subset = Array(PopularBooks.books.prefix(24))
            var loaded: [PopularPickItem] = []
            await withTaskGroup(of: (Int, PopularPickItem?).self) { group in
                for (index, entry) in subset.enumerated() {
                    group.addTask {
                        if let cover = await OpenLibraryService.shared.lookupCoverURL(title: entry.title, author: entry.author) {
                            return (index, PopularPickItem(title: entry.title, author: entry.author, coverURL: cover))
                        }
                        if let result = await GoogleBooksService.shared.lookup(title: entry.title, author: entry.author) {
                            return (index, PopularPickItem(title: result.title, author: result.author, coverURL: result.coverURL ?? ""))
                        }
                        return (index, nil)
                    }
                }
                var indexed: [(Int, PopularPickItem)] = []
                for await (i, item) in group {
                    if let item { indexed.append((i, item)) }
                }
                loaded = indexed.sorted { $0.0 < $1.0 }.map { $0.1 }
            }
            await MainActor.run {
                self.items = loaded
                self.isLoading = false
                self.hasLoaded = true
            }
        }
    }
}

// MARK: - Data

struct PopularPickItem: Identifiable {
    let title: String
    let author: String
    let coverURL: String
    var id: String { "\(title)|\(author)".lowercased() }
}

/// A book the user tapped "mark as read" on, awaiting a loved / didn't-like
/// choice. `id` is carried from the originating row (PopularPickItem.id, which
/// is "title|author", or BookSearchResult.id, which is an Open Library work
/// key) so confirmRead flips the *same* cell the user tapped — search results
/// and popular picks live in different id spaces.
private struct PendingRead: Identifiable {
    let id: String
    let title: String
    let author: String
    let coverURL: String
}

// MARK: - Search Result Row

private struct SearchResultRow: View {
    let book: BookSearchResult
    let isAdded: Bool
    let isSaved: Bool
    let onMarkRead: () -> Void
    let onSave: () -> Void

    var body: some View {
        // 36pt cover + subheadline/caption typography to match the Taste tab's
        // search rows. For You keeps its trailing mark-read + save buttons.
        HStack(spacing: 12) {
            BookCoverView(url: book.coverURL ?? "", width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.subheadline.bold())
                    .lineLimit(2)
                Text(book.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(action: onMarkRead) {
                Image(systemName: isAdded ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.title2)
                    .foregroundStyle(isAdded
                                     ? Color(red: 0.10, green: 0.45, blue: 0.30)
                                     : Color(.secondaryLabel))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark as read")
            Button(action: onSave) {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .font(.title2)
                    .foregroundStyle(isSaved
                                     ? Color(red: 0.09, green: 0.37, blue: 0.65)
                                     : Color(.secondaryLabel))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Save to shelf")
        }
    }
}

// MARK: - Popular Pick Tile (tap = read, long-press = save; mirrors onboarding)

private struct PopularPickTile: View {
    let pick: PopularPickItem
    let isAdded: Bool
    let isSaved: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var isPressing = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            BookCoverView(url: pick.coverURL)
                .overlay(
                    Rectangle()
                        .fill(.black)
                        .opacity(isAdded ? 0.15 : 0)
                        .allowsHitTesting(false)
                )
                .scaleEffect(isPressing ? 0.95 : 1.0)
                .animation(.easeInOut(duration: 0.12), value: isPressing)

            if isAdded {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white, Color(red: 0.23, green: 0.43, blue: 0.07))
                    .background(Circle().fill(.white).padding(2))
                    .padding(6)
                    .transition(.scale.combined(with: .opacity))
            } else if isSaved {
                Image(systemName: "bookmark.fill")
                    .font(.title3)
                    .foregroundStyle(Color(red: 0.09, green: 0.37, blue: 0.65))
                    .background(Circle().fill(.white).padding(2))
                    .padding(6)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onLongPressGesture(
            minimumDuration: 0.45,
            pressing: { pressing in
                withAnimation { isPressing = pressing }
            },
            perform: { onLongPress() }
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isAdded)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSaved)
    }
}

// MARK: - List Shortcut Card

private struct ListShortcutCard: View {
    let title: String
    let subtitle: String
    let colorStart: Color
    let colorEnd: Color

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
            Image(systemName: "arrow.right")
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 76)
        .background(
            LinearGradient(
                colors: [colorStart, colorEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
