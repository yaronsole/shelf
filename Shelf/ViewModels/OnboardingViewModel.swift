import Foundation
import SwiftData

@MainActor
@Observable
final class OnboardingViewModel {
    var searchQuery = ""
    var searchResults: [Book] = []
    var isSearching = false
    var apiKey = ""
    var selectedProvider: LLMProvider = .claude
    var currentStep: OnboardingStep = .apiKey

    // OB-02: track positive and negative signals separately
    var likedBooks: [Book] = []
    var dislikedBooks: [Book] = []

    enum OnboardingStep {
        case apiKey, bookSearch, done
    }

    var canProceedFromAPIKey: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }
    // OB-02: require at least 5 liked books to finish onboarding
    var canFinish: Bool { likedBooks.count >= 5 }
    var totalReacted: Int { likedBooks.count + dislikedBooks.count }

    func searchBooks() async {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        searchResults = (try? await GoogleBooksService.shared.search(query: searchQuery)) ?? []
        isSearching = false
    }

    // OB-02: reaction state for a given book
    func reaction(for book: Book) -> Bool? {
        if likedBooks.contains(where: { $0.title == book.title && $0.author == book.author }) { return true }
        if dislikedBooks.contains(where: { $0.title == book.title && $0.author == book.author }) { return false }
        return nil
    }

    // OB-02: tap "Loved it" or "Didn't like" for a search result
    func react(to book: Book, liked: Bool) {
        // Remove from both lists first (allows toggling)
        likedBooks.removeAll { $0.title == book.title && $0.author == book.author }
        dislikedBooks.removeAll { $0.title == book.title && $0.author == book.author }
        if liked {
            likedBooks.append(book)
        } else {
            dislikedBooks.append(book)
        }
    }

    func removeReaction(for book: Book) {
        likedBooks.removeAll { $0.title == book.title && $0.author == book.author }
        dislikedBooks.removeAll { $0.title == book.title && $0.author == book.author }
    }

    func saveAndFinish(modelContext: ModelContext) {
        // Save API key
        Keychain.save(key: .llmAPIKey, value: apiKey)
        Keychain.save(key: .llmProvider, value: selectedProvider.rawValue)

        // OB-02: save liked books as positive seeds, disliked as negative seeds
        for book in likedBooks {
            let seed = SeedBook(title: book.title, author: book.author, isLiked: true)
            modelContext.insert(seed)
        }
        for book in dislikedBooks {
            let seed = SeedBook(title: book.title, author: book.author, isLiked: false)
            modelContext.insert(seed)
        }
        try? modelContext.save()
    }
}
