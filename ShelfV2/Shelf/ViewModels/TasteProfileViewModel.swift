import Foundation
import SwiftData

@Observable
final class TasteProfileViewModel {
    var isShowingAddSheet: Bool = false
    var isAddingBook: Bool = false

    // Search state reused from onboarding search
    var searchQuery: String = ""
    var searchResults: [BookSearchResult] = []
    var isSearching: Bool = false

    // Remove confirmation
    var bookToRemove: LocalSeedBook? = nil
    var isShowingRemoveConfirm: Bool = false

    private var searchTask: Task<Void, Never>?

    static let minimumSeeds = 3
    static let warnThreshold = 3

    // MARK: - Search (same logic as OnboardingViewModel)

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

    // MARK: - Add Seed Book

    func addBook(_ book: BookSearchResult, modelContext: ModelContext) {
        isAddingBook = true
        let title = book.title
        let author = book.author
        let coverURL = book.coverURL ?? ""
        Task { @MainActor in
            do {
                try await APIClient.shared.submitSeedBook(title: title, author: author, coverURL: coverURL)
                let local = LocalSeedBook(id: UUID().uuidString, title: title, author: author, coverURL: coverURL)
                modelContext.insert(local)
                self.isAddingBook = false
                self.isShowingAddSheet = false
                self.searchQuery = ""
                self.searchResults = []
            } catch {
                self.isAddingBook = false
            }
        }
    }

    // MARK: - Remove Seed Book

    func confirmRemove(_ book: LocalSeedBook) {
        bookToRemove = book
        isShowingRemoveConfirm = true
    }

    func executeRemove(modelContext: ModelContext, seedCount: Int) {
        guard let book = bookToRemove else { return }
        // Block deletion at 2 seeds (TASTE-04)
        guard seedCount > TasteProfileViewModel.minimumSeeds else { return }
        Task {
            try? await APIClient.shared.deleteSeedBook(id: book.id)
        }
        modelContext.delete(book)
        bookToRemove = nil
        isShowingRemoveConfirm = false
    }

    func cancelRemove() {
        bookToRemove = nil
        isShowingRemoveConfirm = false
    }
}
