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

    // Step 2: chain discovery suggestions keyed by seed book id
    var suggestions: [String: [SuggestionDTO]] = [:]
    var isLoadingSuggestions: Bool = false
    var addedSuggestions: Set<String> = []   // suggestion IDs added to seed list

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

    func toggleSuggestion(_ suggestion: SuggestionDTO) {
        if addedSuggestions.contains(suggestion.id) {
            addedSuggestions.remove(suggestion.id)
        } else {
            addedSuggestions.insert(suggestion.id)
        }
    }

    func isSuggestionAdded(_ suggestion: SuggestionDTO) -> Bool {
        addedSuggestions.contains(suggestion.id)
    }

    // MARK: - Step 3: Submit & Transition

    func submitAndFinish(modelContext: ModelContext, appState: AppState) {
        isSubmitting = true
        submissionError = nil

        // Snapshot values before crossing async boundary (Sendable safety)
        var allToSubmit: [(title: String, author: String, coverURL: String)] = selectedBooks.map {
            (title: $0.title, author: $0.author, coverURL: $0.coverURL ?? "")
        }
        for book in selectedBooks {
            if let subs = suggestions[book.id] {
                for s in subs where addedSuggestions.contains(s.id) {
                    allToSubmit.append((title: s.title, author: s.author, coverURL: s.coverURL))
                }
            }
        }

        Task { @MainActor in
            for item in allToSubmit {
                do {
                    try await APIClient.shared.submitSeedBook(
                        title: item.title,
                        author: item.author,
                        coverURL: item.coverURL
                    )
                    let local = LocalSeedBook(
                        id: UUID().uuidString,
                        title: item.title,
                        author: item.author,
                        coverURL: item.coverURL
                    )
                    modelContext.insert(local)
                } catch {
                    // Partial failure is acceptable per OB-11 — continue submitting others
                }
            }
            self.isSubmitting = false
            appState.isFirstGeneration = true
            appState.completeOnboarding()
        }
    }
}
