import SwiftUI

/// Curated-lists browser. Fetches /v1/lists and shows each list as a gradient
/// card. Tapping a card navigates to ListDetailView.
///
/// Discover doubles as the app's universal book search: the shared
/// `BookSearchView` puts a search box at the top, shows the curated lists while
/// the box is empty, and swaps in "read it / save" search results once the user
/// types. (Search used to live only in the Taste tab.)
struct DiscoverView: View {
    @State private var vm = DiscoverViewModel()

    var body: some View {
        NavigationStack {
            BookSearchView(placeholder: "Search for any book…") {
                listsContent
            }
            .navigationDestination(for: String.self) { slug in
                ListDetailView(slug: slug)
            }
            .onAppear { vm.loadIfNeeded() }
        }
    }

    /// The curated-lists scroll view, shown when the search box is empty.
    private var listsContent: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
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
                    ForEach(vm.lists) { list in
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
