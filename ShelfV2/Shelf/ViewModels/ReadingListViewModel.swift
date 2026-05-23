import Foundation
import SwiftData

@Observable
final class ReadingListViewModel {
    var expandedItemId: String? = nil

    func toggleExpand(_ id: String) {
        expandedItemId = expandedItemId == id ? nil : id
    }

    func remove(_ item: ReadingListItem, modelContext: ModelContext) {
        modelContext.delete(item)
    }

    func markAsRead(_ item: ReadingListItem, liked: Bool, modelContext: ModelContext) {
        // Record the reaction on the backend
        Task { try? await APIClient.shared.submitReaction(bookId: item.id, kind: liked ? .alreadyReadLiked : .alreadyReadDisliked) }
        // Remove from local reading list
        modelContext.delete(item)
    }
}
