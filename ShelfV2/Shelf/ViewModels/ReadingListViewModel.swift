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
        // Record the reaction on the backend (no-op for Discover-saved items whose
        // id isn't in recommendation_col, but harmless).
        Task { try? await APIClient.shared.submitReaction(bookId: item.id, kind: liked ? .alreadyReadLiked : .alreadyReadDisliked) }

        // Loved it → also seed the book so it informs future recs and shows up in Taste.
        // Mirrors the ForYouViewModel.markAlreadyRead seeding behavior so both
        // "I loved this" surfaces feed back into the user's taste consistently.
        if liked {
            let title = item.title
            let author = item.author
            let coverURL = item.coverURL
            let titleKey = title.lowercased()
            let authorKey = author.lowercased()
            let descriptor = FetchDescriptor<LocalSeedBook>()
            let alreadySeeded = ((try? modelContext.fetch(descriptor)) ?? []).contains {
                $0.title.lowercased() == titleKey && $0.author.lowercased() == authorKey
            }
            if !alreadySeeded {
                let local = LocalSeedBook(id: UUID().uuidString, title: title, author: author, coverURL: coverURL)
                modelContext.insert(local)
                Task {
                    try? await APIClient.shared.submitSeedBook(title: title, author: author, coverURL: coverURL)
                }
            }
        }

        // Remove from local reading list
        modelContext.delete(item)
    }
}
