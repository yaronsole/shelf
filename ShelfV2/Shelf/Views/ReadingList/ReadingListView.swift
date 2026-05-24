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
                            ReadingListRowView(
                                item: item,
                                isExpanded: vm.expandedItemId == item.id,
                                onToggleExpand: { vm.toggleExpand(item.id) }
                            )
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
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
                                } label: {
                                    Label(Strings.ReadingList.remove, systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(Strings.ReadingList.tabTitle)
            .navigationBarTitleDisplayMode(.large)
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

// MARK: - Row

private struct ReadingListRowView: View {
    let item: ReadingListItem
    let isExpanded: Bool
    let onToggleExpand: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CoverImageView(urlString: item.coverURL, cornerRadius: 6)
                .frame(width: 56, height: 80)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.bold())
                    .lineLimit(2)

                Text(item.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(item.blurb)
                    .font(.caption)
                    .foregroundStyle(Color(.label))
                    .lineLimit(isExpanded ? nil : 2)
                    .animation(.easeInOut(duration: 0.2), value: isExpanded)

                HStack(spacing: 12) {
                    Button(isExpanded ? Strings.ReadingList.showLess : Strings.ReadingList.showMore) {
                        onToggleExpand()
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)

                    if let url = amazonSearchURL {
                        Link(destination: url) {
                            Label("Amazon", systemImage: "arrow.up.right.square")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // PRD RG-01: clean search URL, no affiliate tag injection.
    private var amazonSearchURL: URL? {
        let q = "\(item.title) \(item.author)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://www.amazon.com/s?k=\(q)&i=stripbooks")
    }
}
