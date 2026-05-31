import Foundation
import SwiftData

@Observable
final class TasteProfileViewModel {
    var isShowingAddSheet: Bool = false

    // Remove confirmation
    var bookToRemove: LocalSeedBook? = nil
    var isShowingRemoveConfirm: Bool = false

    static let minimumSeeds = 3
    static let warnThreshold = 3

    // Adding books now flows through the shared BookSearchView (its own search +
    // "read it" / "save" CTAs route through SeedWriter), so this view model only
    // owns sheet presentation and seed removal.

    // MARK: - Remove Seed Book

    func confirmRemove(_ book: LocalSeedBook) {
        bookToRemove = book
        isShowingRemoveConfirm = true
    }

    func executeRemove(modelContext: ModelContext, seedCount: Int) {
        guard let book = bookToRemove else { return }
        guard seedCount > TasteProfileViewModel.minimumSeeds else { return }
        Task {
            try? await APIClient.shared.deleteSeedBook(id: book.id)
        }
        SimilarBooksCacheService.invalidate(seed: book)
        modelContext.delete(book)
        bookToRemove = nil
        isShowingRemoveConfirm = false
    }

    func cancelRemove() {
        bookToRemove = nil
        isShowingRemoveConfirm = false
    }
}
