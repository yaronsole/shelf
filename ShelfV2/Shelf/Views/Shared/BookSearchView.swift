import SwiftUI
import SwiftData

/// Reusable "search any book → mark read / save" surface.
///
/// • Search box (debounced 300ms; Open Library with a Google Books fallback).
/// • Each result row offers "read it" (asks loved / didn't-like, then routes
///   through `SeedWriter`) and "save" (→ reading list), matching the For You
///   seed grid's rows so search looks the same everywhere it appears.
/// • While the query is empty the host's `idle` content is shown instead of
///   results, so the same component drops inline into Discover (curated lists
///   when idle, search results when typing) or into a bare sheet (Taste tab).
///
/// State (added / saved sets, query) is per-instance and resets when the view is
/// recreated — same as the For You grid.
struct BookSearchView<Idle: View>: View {
    @Environment(\.modelContext) private var modelContext

    private let placeholder: String
    private let idle: Idle

    @State private var query: String = ""
    @State private var results: [BookSearchResult] = []
    @State private var isSearching: Bool = false
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var addedIds: Set<String> = []
    @State private var savedIds: Set<String> = []
    @State private var pendingRead: PendingReadBook? = nil

    init(placeholder: String = "Search for a book…", @ViewBuilder idle: () -> Idle) {
        self.placeholder = placeholder
        self.idle = idle()
    }

    private var isSearchingMode: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBox
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            if isSearchingMode {
                resultsList
            } else {
                idle
            }
        }
        .sheet(item: $pendingRead) { pending in
            AlreadyReadSheet(
                title: pending.title,
                onLoved: { confirmRead(pending, liked: true) },
                onDidntLike: { confirmRead(pending, liked: false) }
            )
        }
    }

    // MARK: - Subviews

    private var searchBox: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $query)
                .autocorrectionDisabled()
                .onChange(of: query) { _, newValue in performSearch(query: newValue) }
            if isSearchingMode {
                Button("Cancel") {
                    query = ""
                    results = []
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

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if isSearching && results.isEmpty {
                    ProgressView()
                        .padding(.vertical, 32)
                        .frame(maxWidth: .infinity)
                } else if results.isEmpty {
                    Text("No results for \"\(query)\"")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 32)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(results) { result in
                        BookSearchResultRow(
                            book: result,
                            isAdded: addedIds.contains(result.id),
                            isSaved: savedIds.contains(result.id),
                            onMarkRead: { markRead(result) },
                            onSave: { save(result) }
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Search

    private func performSearch(query newQuery: String) {
        searchTask?.cancel()
        let trimmed = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            isSearching = false
            return
        }
        searchTask = Task {
            // 300ms debounce: if the user keeps typing, this Task is cancelled.
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            await MainActor.run { self.isSearching = true }
            var found = await OpenLibraryService.shared.search(query: trimmed)
            if found.isEmpty {
                found = (try? await GoogleBooksService.shared.search(query: trimmed)) ?? []
            }
            if Task.isCancelled { return }
            await MainActor.run {
                self.results = found
                self.isSearching = false
            }
        }
    }

    // MARK: - Actions

    /// "Mark as read" asks for sentiment first: loved books become seeds,
    /// disliked books register a negative reaction only (see SeedWriter).
    private func markRead(_ book: BookSearchResult) {
        guard !addedIds.contains(book.id) else { return }
        Haptics.light()
        pendingRead = PendingReadBook(
            id: book.id, title: book.title, author: book.author, coverURL: book.coverURL ?? ""
        )
    }

    private func confirmRead(_ pending: PendingReadBook, liked: Bool) {
        guard !addedIds.contains(pending.id) else { return }
        addedIds.insert(pending.id)
        Task { @MainActor in
            let ok = await SeedWriter.recordAlreadyRead(
                title: pending.title,
                author: pending.author,
                coverURL: pending.coverURL,
                liked: liked,
                modelContext: modelContext
            )
            if !ok { addedIds.remove(pending.id) }
        }
    }

    private func save(_ book: BookSearchResult) {
        guard !savedIds.contains(book.id) else { return }
        Haptics.medium()
        savedIds.insert(book.id)
        let item = ReadingListItem(
            id: UUID().uuidString,
            title: book.title,
            author: book.author,
            coverURL: book.coverURL ?? "",
            blurb: "Saved from search."
        )
        modelContext.insert(item)
    }
}

// Convenience init for hosts with no idle content (e.g. the Taste add sheet).
extension BookSearchView where Idle == EmptyView {
    init(placeholder: String = "Search for a book…") {
        self.init(placeholder: placeholder) { EmptyView() }
    }
}

// MARK: - Data

/// A book the user tapped "read it" on, awaiting a loved / didn't-like choice.
struct PendingReadBook: Identifiable {
    let id: String
    let title: String
    let author: String
    let coverURL: String
}

// MARK: - Result Row

/// Canonical search-result row: 36pt cover + title/author, with trailing
/// "read it" (loved/disliked) and "save" buttons. Shared so search looks the
/// same on Discover, the Taste tab, and (visually) the For You grid.
struct BookSearchResultRow: View {
    let book: BookSearchResult
    let isAdded: Bool
    let isSaved: Bool
    let onMarkRead: () -> Void
    let onSave: () -> Void

    var body: some View {
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
