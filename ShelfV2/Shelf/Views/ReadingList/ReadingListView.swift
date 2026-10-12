import SwiftUI
import SwiftData

struct ReadingListView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ReadingListItem.savedAt, order: .reverse)
    private var items: [ReadingListItem]

    @State private var selectedItem: ReadingListItem?
    @State private var vm = ReadingListViewModel()
    @State private var itemForSentiment: ReadingListItem? = nil

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
                        ForEach(items.sorted { $0.isUpNext != $1.isUpNext ? $0.isUpNext : $0.savedAt > $1.savedAt }) { item in
                            ReadingListCardView(item: item, onOpen: { selectedItem = item })
                                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button {
                                        itemForSentiment = item
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
        .sheet(item: $selectedItem) { item in
            BookDetailSheet(
                book: ListBookDTO(bookId: item.id, title: item.title, author: item.author,
                    year: nil, coverURL: item.coverURL, userStatus: .saved, description: ""),
                listTitle: "Your shelf",
                onReadLoved: { vm.markAsRead(item, liked: true, modelContext: modelContext) },
                onReadDisliked: { vm.markAsRead(item, liked: false, modelContext: modelContext) },
                onSave: { vm.toggleUpNext(item, modelContext: modelContext) },
                onBuy: {
                    if let url = AmazonLinkService.searchURL(title: item.title, author: item.author) { openURL(url) }
                },
                recommendationContext: item.blurb,
                saveLabel: item.isUpNext ? "unpin" : "up next",
                saveIcon: item.isUpNext ? "pin.slash" : "pin.fill"
            )
        }
        // Action-sheet style prompt — much more reliable than a chained sheet
        // and renders instantly (no white-screen race).
        .confirmationDialog(
            "Did you love it?",
            isPresented: Binding(
                get: { itemForSentiment != nil },
                set: { if !$0 { itemForSentiment = nil } }
            ),
            titleVisibility: .visible,
            presenting: itemForSentiment
        ) { item in
            Button("Loved it") {
                vm.markAsRead(item, liked: true, modelContext: modelContext)
            }
            Button("Didn't like it") {
                vm.markAsRead(item, liked: false, modelContext: modelContext)
            }
            Button("Cancel", role: .cancel) { }
        } message: { item in
            Text(item.title)
        }
    }
}
