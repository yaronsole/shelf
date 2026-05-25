import SwiftUI
import SwiftData

/// Shown in the For You tab when the user has < 3 seeds.
/// • Default view: instructional line, search box, popular-picks grid, list shortcuts.
/// • Search mode (query ≥ 2 chars): search box + results list (popular picks + shortcuts hidden).
struct EmptyForYouView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var popularPicks: [PopularPickItem] = []
    @State private var searchQuery: String = ""
    @State private var searchResults: [BookSearchResult] = []
    @State private var isSearching: Bool = false
    @State private var searchTask: Task<Void, Never>? = nil
    // Local "added" sets so the row reflects the action immediately and we can
    // ignore double-taps; these are per-session and reset when the view is
    // re-created.
    @State private var addedBookIds: Set<String> = []
    @State private var savedBookIds: Set<String> = []

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
        .onAppear { loadPopularPicksIfNeeded() }
    }

    // MARK: - Sections

    private var instructionalLine: some View {
        Text("Pick books you've loved to unlock personalized picks.")
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
                ],
                spacing: gridSpacing
            ) {
                ForEach(popularPicks.prefix(6)) { pick in
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

    private var footerLine: some View {
        Text("Pick at least 3 to unlock personalized recs ✦")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.top, 8)
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

    private func addAsSeed(_ book: BookSearchResult) {
        guard !addedBookIds.contains(book.id) else { return }
        Haptics.light()
        addedBookIds.insert(book.id)
        let coverURL = book.coverURL ?? ""
        Task { @MainActor in
            do {
                try await APIClient.shared.submitSeedBook(
                    title: book.title, author: book.author, coverURL: coverURL
                )
                let local = LocalSeedBook(
                    id: UUID().uuidString,
                    title: book.title, author: book.author, coverURL: coverURL
                )
                modelContext.insert(local)
            } catch {
                // Roll back UI feedback so user can retry
                addedBookIds.remove(book.id)
            }
        }
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
        addedBookIds.insert(pick.id)
        Task { @MainActor in
            do {
                try await APIClient.shared.submitSeedBook(
                    title: pick.title, author: pick.author, coverURL: pick.coverURL
                )
                let local = LocalSeedBook(
                    id: UUID().uuidString,
                    title: pick.title, author: pick.author, coverURL: pick.coverURL
                )
                modelContext.insert(local)
            } catch {
                addedBookIds.remove(pick.id)
            }
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

    private func loadPopularPicksIfNeeded() {
        guard popularPicks.isEmpty else { return }
        Task {
            let firstSix = Array(PopularBooks.books.prefix(6))
            var items: [PopularPickItem] = []
            await withTaskGroup(of: (Int, PopularPickItem?).self) { group in
                for (index, entry) in firstSix.enumerated() {
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
                items = indexed.sorted { $0.0 < $1.0 }.map { $0.1 }
            }
            await MainActor.run { self.popularPicks = items }
        }
    }
}

// MARK: - Data

private struct PopularPickItem: Identifiable {
    let title: String
    let author: String
    let coverURL: String
    var id: String { "\(title)|\(author)".lowercased() }
}

// MARK: - Search Result Row

private struct SearchResultRow: View {
    let book: BookSearchResult
    let isAdded: Bool
    let isSaved: Bool
    let onMarkRead: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            BookCoverView(url: book.coverURL ?? "", width: 50)
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
