import SwiftUI
import SwiftData

struct ReadingListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ReadingListItem.savedAt, order: .reverse)
    private var items: [ReadingListItem]

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
                        ForEach(items) { item in
                            ReadingListCardView(item: item)
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
                ToastManager.shared.show(.reactedRead)
            }
            Button("Didn't like it") {
                vm.markAsRead(item, liked: false, modelContext: modelContext)
                ToastManager.shared.show(.reactedPass)
            }
            Button("Cancel", role: .cancel) { }
        } message: { item in
            Text(item.title)
        }
    }
}
