import SwiftUI
import SwiftData

struct ReadingListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ReadingListItem.savedAt, order: .reverse)
    private var items: [ReadingListItem]

    @State private var vm = ReadingListViewModel()
    @State private var itemForSentiment: ReadingListItem? = nil
    @State private var showSentimentSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    EmptyStateView(
                        systemImage: "bookmark",
                        title: Strings.ReadingList.emptyTitle,
                        subtitle: Strings.ReadingList.emptySubtitle
                    )
                } else {
                    List {
                        ForEach(items) { item in
                            ReadingListCardView(item: item)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowSeparator(.hidden)
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button {
                                        itemForSentiment = item
                                        showSentimentSheet = true
                                    } label: {
                                        Label(Strings.ReadingList.markAsRead, systemImage: "checkmark.circle")
                                    }
                                    .tint(.green)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        vm.remove(item, modelContext: modelContext)
                                        ToastManager.shared.show(.removedFromShelf)
                                    } label: {
                                        Label(Strings.ReadingList.remove, systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $showSentimentSheet) {
            if let item = itemForSentiment {
                AlreadyReadSheet(
                    title: item.title,
                    onLoved: { vm.markAsRead(item, liked: true, modelContext: modelContext) },
                    onDidntLike: { vm.markAsRead(item, liked: false, modelContext: modelContext) }
                )
            }
        }
    }
}
