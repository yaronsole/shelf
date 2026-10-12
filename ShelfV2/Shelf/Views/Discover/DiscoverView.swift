import SwiftUI
import SwiftData

/// Curated-lists browser. Fetches /v1/lists and shows each list as a gradient
/// card. Tapping a card navigates to ListDetailView.
///
/// Discover doubles as the app's universal book search: the shared
/// `BookSearchView` puts a search box at the top, shows the curated lists while
/// the box is empty, and swaps in "read it / save" search results once the user
/// types. (Search used to live only in the Taste tab.)
struct DiscoverView: View {
    @State private var vm = DiscoverViewModel()
    @State private var leaderboard: CommunityLeaderboardDTO?

    var body: some View {
        NavigationStack {
            BookSearchView(placeholder: "Search for any book…") {
                listsContent
            }
            .navigationDestination(for: String.self) { slug in
                ListDetailView(slug: slug)
            }
            .onAppear { vm.loadIfNeeded() }
            .task { leaderboard = try? await APIClient.shared.fetchLeaderboard(order: "popular") }
        }
    }

    /// The curated-lists scroll view, shown when the search box is empty.
    private var listsContent: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if let leaderboard {
                    NavigationLink {
                        CommunityLeaderboardView()
                    } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Most loved on Shelf").font(.title3.bold())
                                    Text("Reader favorites · All time")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                            if !leaderboard.books.isEmpty {
                                HStack(alignment: .bottom, spacing: 12) {
                                    ForEach(Array(leaderboard.books.prefix(3))) { book in
                                        BookCoverView(url: book.coverURL, width: 58)
                                            .accessibilityLabel(book.title)
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if vm.isLoading && vm.lists.isEmpty {
                    ProgressView()
                        .padding(.top, 60)
                } else if let errorMessage = vm.errorMessage {
                    EmptyStateView(
                        systemImage: "exclamationmark.icloud",
                        title: "Couldn't load lists",
                        subtitle: errorMessage,
                        action: { vm.load() },
                        actionLabel: Strings.Common.retry
                    )
                    .padding(.top, 60)
                } else if vm.lists.isEmpty {
                    Text(Strings.Discover.comingSoon)
                        .foregroundStyle(.secondary)
                        .padding(.top, 60)
                } else {
                    ForEach(vm.lists.filter { leaderboard == nil || $0.slug != "loved_by_readers" }) { list in
                        NavigationLink(value: list.slug) {
                            ListCatalogCard(list: list)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - List Catalog Card

private struct ListCatalogCard: View {
    let list: ListMetadataDTO

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(list.title)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text(list.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                Spacer(minLength: 8)
                Text("\(list.bookCount) books")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.white.opacity(0.18)))
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.right")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    Color(hexString: list.colorStart),
                    Color(hexString: list.colorEnd)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}


/// A global book leaderboard: read books retain their rank, unlike the discovery
/// list that hides them. Counts come only from explicit, contributing loves.
private struct CommunityLeaderboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @State private var order = "popular"
    @State private var result: CommunityLeaderboardDTO?
    @State private var isLoading = true
    @State private var failed = false
    @State private var selectedBook: ListBookDTO?
    @State private var actions = ListDetailViewModel(slug: "loved_by_readers")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Loved by readers").font(.largeTitle.bold())
                Picker("Order books", selection: $order) {
                    Text("Most loved").tag("popular")
                    Text("Recently loved").tag("recent")
                }
                .pickerStyle(.segmented)
                Text(order == "popular"
                     ? "Ranked by readers who marked each book as loved. All time; equal counts share a rank."
                     : "Books most recently marked as loved. Counts show all-time loves.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let label = result?.updateLabel {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                }
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                } else if failed {
                    EmptyStateView(systemImage: "exclamationmark.icloud",
                        title: "Couldn't load reader favorites", subtitle: "Please try again.",
                        action: { Task { await load() } }, actionLabel: "Retry")
                } else if let result, !result.books.isEmpty {
                    LazyVStack(spacing: 0) {
                        ForEach(result.books) { book in
                            Button { selectedBook = book } label: {
                                HStack(alignment: .center, spacing: 12) {
                                    if order == "popular", let rank = book.rank {
                                        Text("\(rank)").font(.title3.monospacedDigit().weight(.semibold))
                                            .foregroundStyle(.secondary).frame(minWidth: 30)
                                    }
                                    BookCoverView(url: book.coverURL, width: 48)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(book.title).font(.headline).multilineTextAlignment(.leading)
                                        Text(book.author).font(.subheadline).foregroundStyle(.secondary)
                                        if let count = book.lovedCount {
                                            Text("\(count) \(count == 1 ? "reader" : "readers") loved it")
                                                .font(.caption.weight(.medium))
                                                .foregroundStyle(Color(hexString: "4D3388"))
                                        }
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    if actions.status(for: book.bookId) == .read {
                                        Image(systemName: "checkmark.circle").accessibilityLabel("Read")
                                    } else if actions.status(for: book.bookId) == .saved {
                                        Image(systemName: "bookmark.fill").accessibilityLabel("Saved")
                                    }
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Save to shelf", systemImage: "bookmark") {
                                    if actions.status(for: book.bookId) != .saved {
                                        actions.toggleSave(book, modelContext: modelContext)
                                    }
                                }
                            }
                            Divider()
                        }
                    }
                } else {
                    EmptyStateView(systemImage: "books.vertical", title: "Reader favorites are taking shape",
                        subtitle: "Books will appear here after readers mark them as loved and the list updates.")
                }
            }
            .padding(16)
        }
        .task(id: order) { await load() }
        .refreshable { await load() }
        .sheet(item: $selectedBook) { book in
            BookDetailSheet(book: book, listTitle: "Loved by readers",
                onReadLoved: { actions.markRead(book, liked: true, modelContext: modelContext) },
                onReadDisliked: { actions.markRead(book, liked: false, modelContext: modelContext) },
                onSave: {
                    if actions.status(for: book.bookId) != .saved { actions.toggleSave(book, modelContext: modelContext) }
                },
                onBuy: {
                    if let url = AmazonLinkService.searchURL(title: book.title, author: book.author) { openURL(url) }
                })
        }
    }

    @MainActor private func load() async {
        let requestedOrder = order
        isLoading = true
        failed = false
        result = nil
        do {
            let response = try await APIClient.shared.fetchLeaderboard(order: requestedOrder)
            guard !Task.isCancelled, requestedOrder == order else { return }
            result = response
            actions.statusOverlay = Dictionary(uniqueKeysWithValues: response.books.map { ($0.bookId, $0.userStatus) })
            isLoading = false
        } catch {
            guard !Task.isCancelled, requestedOrder == order else { return }
            failed = true
            isLoading = false
        }
    }
}
