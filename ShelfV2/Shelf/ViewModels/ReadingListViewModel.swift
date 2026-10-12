import Foundation
import SwiftData

@Observable
@MainActor
final class ReadingListViewModel {
    func toggleUpNext(_ item: ReadingListItem, modelContext: ModelContext) {
        let wasUpNext = item.isUpNext
        let items = (try? modelContext.fetch(FetchDescriptor<ReadingListItem>())) ?? []
        for saved in items { saved.isUpNext = false }
        item.isUpNext = !wasUpNext
    }

    func remove(_ item: ReadingListItem, modelContext: ModelContext) {
        // Capture values before deletion; a deleted SwiftData object cannot be
        // safely reinserted after an autosave.
        let restored = ReadingListItem(id: item.id, title: item.title, author: item.author,
            coverURL: item.coverURL, blurb: item.blurb, domain: item.domain,
            genre: item.genre, era: item.era, becauseOf: item.becauseOf,
            readingTimeMinutes: item.readingTimeMinutes, nytBestseller: item.nytBestseller,
            nytWeeksOnList: item.nytWeeksOnList)
        restored.savedAt = item.savedAt
        restored.isUpNext = item.isUpNext
        modelContext.delete(item)
        ToastManager.shared.show(.removedFromShelf, undo: {
            if restored.isUpNext {
                let items = (try? modelContext.fetch(FetchDescriptor<ReadingListItem>())) ?? []
                restored.isUpNext = !items.contains { $0.isUpNext }
            }
            modelContext.insert(restored)
        })
    }

    func markAsRead(_ item: ReadingListItem, liked: Bool, modelContext: ModelContext) {
        Task {
            let ok = await SeedWriter.recordAlreadyRead(title: item.title, author: item.author,
                coverURL: item.coverURL, liked: liked, modelContext: modelContext)
            if ok {
                modelContext.delete(item)
                ToastManager.shared.show(liked ? .reactedRead : .reactedPass)
            }
        }
    }
}
