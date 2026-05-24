import Foundation
import SwiftData

enum OnboardingStep {
    case welcome
    case seedSearch
    case chainDiscovery
    case confirmation
}

@Observable
final class OnboardingViewModel {
    var step: OnboardingStep = .welcome
    var selectedBooks: [BookSearchResult] = []
    var searchQuery: String = ""
    var searchResults: [BookSearchResult] = []
    var isSearching: Bool = false

    // Curated grid of popular books shown above the search field
    var popularBooks: [BookSearchResult] = []
    var isLoadingPopular: Bool = false
    private var hasLoadedPopular = false

    // Step 2: chain discovery suggestions keyed by seed book id
    var suggestions: [String: [SuggestionDTO]] = [:]
    var isLoadingSuggestions: Bool = false
    var addedSuggestions: Set<String> = []   // suggestion IDs the user marked "I've read it"
    var savedSuggestions: Set<String> = []   // suggestion IDs the user marked "Save for later"

    // Step 3: submission
    var isSubmitting: Bool = false
    var submissionError: String? = nil

    var canContinueFromSearch: Bool {
        selectedBooks.count >= 3
    }

    var selectionCountText: String {
        let min = 3
        let count = selectedBooks.count
        return count < min ? "\(count) of \(min) minimum" : "\(count) selected"
    }

    // MARK: - Step 1: Seed Search

    private var searchTask: Task<Void, Never>?

    func onQueryChanged(_ newQuery: String) {
        searchTask?.cancel()
        guard newQuery.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            do {
                let results = try await GoogleBooksService.shared.search(query: newQuery)
                await MainActor.run {
                    self.searchResults = results
                    self.isSearching = false
                }
            } catch {
                await MainActor.run { self.isSearching = false }
            }
        }
    }

    func selectBook(_ book: BookSearchResult) {
        guard !selectedBooks.contains(book) else { return }
        selectedBooks.append(book)
    }

    func removeBook(_ book: BookSearchResult) {
        selectedBooks.removeAll { $0.id == book.id }
    }

    func isSelected(_ book: BookSearchResult) -> Bool {
        selectedBooks.contains(book)
    }

    // MARK: - Curated Popular Books Grid

    func loadPopularBooksIfNeeded() {
        guard !hasLoadedPopular else { return }
        hasLoadedPopular = true
        isLoadingPopular = true
        Task {
            var results: [BookSearchResult] = []
            await withTaskGroup(of: (Int, BookSearchResult?).self) { group in
                for (index, entry) in PopularBooks.books.enumerated() {
                    group.addTask {
                        let result = await GoogleBooksService.shared.lookup(title: entry.title, author: entry.author)
                        return (index, result)
                    }
                }
                var indexed: [(Int, BookSearchResult)] = []
                for await (i, book) in group {
                    if let book { indexed.append((i, book)) }
                }
                // Preserve original ordering from PopularBooks.books
                results = indexed.sorted { $0.0 < $1.0 }.map { $0.1 }
            }
            await MainActor.run {
                self.popularBooks = results
                self.isLoadingPopular = false
            }
        }
    }

    // MARK: - Step 2: Chain Discovery

    func loadSuggestions() {
        isLoadingSuggestions = true
        let booksSnapshot = selectedBooks   // capture value copy to avoid Sendable issue
        Task {
            var collected: [String: [SuggestionDTO]] = [:]
            await withTaskGroup(of: (String, [SuggestionDTO]).self) { group in
                for book in booksSnapshot {
                    group.addTask {
                        let result = (try? await APIClient.shared.fetchSuggestions(for: book)) ?? []
                        return (book.id, result)
                    }
                }
                for await (bookId, results) in group {
                    collected[bookId] = results
                }
            }
            await MainActor.run {
                self.suggestions = collected
                self.isLoadingSuggestions = false
            }
        }
    }

    // "I've read it" — adds to taste profile (seed books). Mutually exclusive with Save.
    func toggleAddToTaste(_ suggestion: SuggestionDTO) {
        if addedSuggestions.contains(suggestion.id) {
            addedSuggestions.remove(suggestion.id)
        } else {
            addedSuggestions.insert(suggestion.id)
            savedSuggestions.remove(suggestion.id)
        }
    }

    // "Save for later" — adds to Reading List, NOT to seed taste profile.
    func toggleSaveForLater(_ suggestion: SuggestionDTO) {
        if savedSuggestions.contains(suggestion.id) {
            savedSuggestions.remove(suggestion.id)
        } else {
            savedSuggestions.insert(suggestion.id)
            addedSuggestions.remove(suggestion.id)
        }
    }

    func isSuggestionAdded(_ suggestion: SuggestionDTO) -> Bool {
        addedSuggestions.contains(suggestion.id)
    }

    func isSuggestionSaved(_ suggestion: SuggestionDTO) -> Bool {
        savedSuggestions.contains(suggestion.id)
    }

    // MARK: - Step 3: Submit & Transition

    func submitAndFinish(modelContext: ModelContext, appState: AppState) {
        isSubmitting = true
        submissionError = nil

        // Books that become SEED books (taste profile): selected picks + "I've read it" suggestions
        var seedsToSubmit: [(title: String, author: String, coverURL: String)] = selectedBooks.map {
            (title: $0.title, author: $0.author, coverURL: $0.coverURL ?? "")
        }
        // Books that become READING LIST items only ("Save for later" suggestions)
        var savesToSubmit: [(title: String, author: String, coverURL: String, blurb: String)] = []

        for book in selectedBooks {
            guard let subs = suggestions[book.id] else { continue }
            for s in subs {
                if addedSuggestions.contains(s.id) {
                    seedsToSubmit.append((title: s.title, author: s.author, coverURL: s.coverURL))
                } else if savedSuggestions.contains(s.id) {
                    savesToSubmit.append((
                        title: s.title, author: s.author, coverURL: s.coverURL,
                        blurb: s.blurb.isEmpty ? "Suggested during onboarding because you love \(book.title)." : s.blurb
                    ))
                }
            }
        }

        Task { @MainActor in
            print("[Onboarding] submitting \(seedsToSubmit.count) seeds, \(savesToSubmit.count) saves…")

            // Seeds: send to backend + mirror to local SwiftData
            for (idx, item) in seedsToSubmit.enumerated() {
                do {
                    try await APIClient.shared.submitSeedBook(
                        title: item.title, author: item.author, coverURL: item.coverURL
                    )
                    let local = LocalSeedBook(
                        id: UUID().uuidString,
                        title: item.title, author: item.author, coverURL: item.coverURL
                    )
                    modelContext.insert(local)
                    print("[Onboarding] ✓ seed #\(idx + 1): \(item.title)")
                } catch {
                    print("[Onboarding] ✗ seed #\(idx + 1) (\(item.title)): \(error)")
                }
            }

            // Saves: insert directly into local Reading List (no backend reading-list endpoint)
            for save in savesToSubmit {
                let item = ReadingListItem(
                    id: UUID().uuidString,
                    title: save.title, author: save.author,
                    coverURL: save.coverURL, blurb: save.blurb
                )
                modelContext.insert(item)
                print("[Onboarding] ✓ saved to reading list: \(save.title)")
            }

            self.isSubmitting = false
            appState.isFirstGeneration = true
            appState.completeOnboarding()
        }
    }
}
