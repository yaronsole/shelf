import Foundation
import SwiftData

enum OnboardingStep {
    case welcome
    case seedSearch
}

@Observable
final class OnboardingViewModel {
    var step: OnboardingStep = .welcome
    var selectedBooks: [BookSearchResult] = []
    var savedBooks: [BookSearchResult] = []
    var searchQuery: String = ""
    var searchResults: [BookSearchResult] = []
    var isSearching: Bool = false

    var popularBooks: [BookSearchResult] = []
    var isLoadingPopular: Bool = false
    private var hasLoadedPopular = false

    var isSubmitting: Bool = false
    var submissionError: String? = nil

    var canContinue: Bool {
        selectedBooks.count >= 3
    }

    var selectionCountText: String {
        let min = 3
        let count = selectedBooks.count
        return count < min ? "\(count) of \(min) minimum" : "\(count) selected"
    }

    // MARK: - Search

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
            var results = await OpenLibraryService.shared.search(query: newQuery)
            if results.isEmpty {
                results = (try? await GoogleBooksService.shared.search(query: newQuery)) ?? []
            }
            await MainActor.run {
                self.searchResults = results
                self.isSearching = false
            }
        }
    }

    func selectBook(_ book: BookSearchResult) {
        guard !selectedBooks.contains(book) else { return }
        savedBooks.removeAll { $0.id == book.id }
        selectedBooks.append(book)
    }

    func removeBook(_ book: BookSearchResult) {
        selectedBooks.removeAll { $0.id == book.id }
    }

    func isSelected(_ book: BookSearchResult) -> Bool {
        selectedBooks.contains(book)
    }

    func toggleSaveBook(_ book: BookSearchResult) {
        if let idx = savedBooks.firstIndex(where: { $0.id == book.id }) {
            savedBooks.remove(at: idx)
        } else {
            selectedBooks.removeAll { $0.id == book.id }
            savedBooks.append(book)
        }
    }

    func isSaved(_ book: BookSearchResult) -> Bool {
        savedBooks.contains(where: { $0.id == book.id })
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
                        if let cover = await OpenLibraryService.shared.lookupCoverURL(title: entry.title, author: entry.author) {
                            let stableId = "\(entry.title)|\(entry.author)".lowercased()
                            return (index, BookSearchResult(id: stableId, title: entry.title, author: entry.author, coverURL: cover))
                        }
                        let result = await GoogleBooksService.shared.lookup(title: entry.title, author: entry.author)
                        return (index, result)
                    }
                }
                var indexed: [(Int, BookSearchResult)] = []
                for await (i, book) in group {
                    if let book { indexed.append((i, book)) }
                }
                results = indexed.sorted { $0.0 < $1.0 }.map { $0.1 }
            }
            await MainActor.run {
                self.popularBooks = results
                self.isLoadingPopular = false
            }
        }
    }

    // MARK: - Submit & Transition

    func submitAndFinish(modelContext: ModelContext, appState: AppState) {
        isSubmitting = true
        submissionError = nil

        let seedsToSubmit: [(title: String, author: String, coverURL: String)] = selectedBooks.map {
            (title: $0.title, author: $0.author, coverURL: $0.coverURL ?? "")
        }
        let savesToSubmit: [(title: String, author: String, coverURL: String, blurb: String)] = savedBooks.map {
            (title: $0.title, author: $0.author, coverURL: $0.coverURL ?? "",
             blurb: "Saved during onboarding.")
        }

        Task { @MainActor in
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

            for save in savesToSubmit {
                let item = ReadingListItem(
                    id: UUID().uuidString,
                    title: save.title, author: save.author,
                    coverURL: save.coverURL, blurb: save.blurb
                )
                modelContext.insert(item)
            }

            self.isSubmitting = false
            appState.isFirstGeneration = true
            // Land on Discover tab (index 1) after onboarding — For You generates in the background.
            appState.pendingInitialTab = 1
            appState.completeOnboarding()
        }
    }
}
