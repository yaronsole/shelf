import Foundation
import SwiftUI

// MARK: - DemoRecommendationsViewModel
// Serves the 5 hand-picked demo books without calling the LLM or SwiftData.
// On second refresh, surfaces the APIKeyUnlockView instead of making a network call.

@MainActor
@Observable
final class DemoRecommendationsViewModel {
    var books: [Book] = []
    var isLoading = false
    var errorMessage: String? = nil
    var pendingFollowUps: [Purchase] = []   // always empty in demo mode
    var showUnlockSheet = false
    var demoWishlist: [Book] = []

    private var hasLoadedOnce = false

    func loadIfNeeded() {
        if books.isEmpty && !isLoading {
            Task { await refresh() }
        }
    }

    func refresh() async {
        guard !isLoading else { return }

        if hasLoadedOnce {
            // User wants more — prompt for API key
            showUnlockSheet = true
            return
        }

        isLoading = true
        // Simulate the feel of a real API call
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        books = DemoData.books
        hasLoadedOnce = true
        isLoading = false
    }

    // MARK: - Reactions (in-memory only, no SwiftData)

    func thumbsUp(book: Book) {
        // Liked — nothing extra needed; wishlist happens via addToWishlist
    }

    func thumbsDown(book: Book) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            books.removeAll { $0.id == book.id }
        }
    }

    func alreadyRead(book: Book, liked: Bool) {
        if !liked {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                books.removeAll { $0.id == book.id }
            }
        }
    }

    func logPurchase(book: Book) async {
        // No-op in demo mode
    }

    func addToWishlist(book: Book) {
        guard !demoWishlist.contains(where: { $0.id == book.id }) else { return }
        demoWishlist.append(book)
    }

    func submitFollowUp(purchase: Purchase, response: FollowUpResponse) { }
    func dismissFollowUp(purchase: Purchase) { }
}
