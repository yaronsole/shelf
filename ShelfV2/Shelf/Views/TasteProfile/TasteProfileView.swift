import SwiftUI
import SwiftData

struct TasteProfileView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \LocalSeedBook.addedAt, order: .reverse)
    private var seedBooks: [LocalSeedBook]

    @State private var vm = TasteProfileViewModel()
    @State private var bookForSuggestions: LocalSeedBook? = nil

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            Group {
                if seedBooks.isEmpty {
                    EmptyStateView(
                        systemImage: "person.text.rectangle",
                        title: "No taste profile yet",
                        subtitle: "Add books you love to get personalized picks.",
                        action: { vm.isShowingAddSheet = true },
                        actionLabel: Strings.TasteProfile.addBook
                    )
                } else {
                    ScrollView {
                        // Warning banner if below threshold (TASTE-04)
                        if seedBooks.count <= TasteProfileViewModel.warnThreshold {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                                Text(Strings.TasteProfile.warningBelowMin)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemOrange).opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                        }

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(seedBooks) { book in
                                SeedBookCoverView(
                                    book: book,
                                    canRemove: seedBooks.count > TasteProfileViewModel.minimumSeeds,
                                    onTap: { bookForSuggestions = book },
                                    onRemove: { vm.confirmRemove(book) }
                                )
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        vm.isShowingAddSheet = true
                    } label: {
                        Label(Strings.TasteProfile.addBook, systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $vm.isShowingAddSheet) {
            SeedBookAddSheet(vm: vm, modelContext: modelContext)
        }
        .sheet(item: $bookForSuggestions) { book in
            SimilarBooksSheet(seed: book, modelContext: modelContext)
        }
        .confirmationDialog(
            Strings.TasteProfile.removeWarning,
            isPresented: $vm.isShowingRemoveConfirm,
            titleVisibility: .visible
        ) {
            Button(Strings.TasteProfile.removeAction, role: .destructive) {
                vm.executeRemove(modelContext: modelContext, seedCount: seedBooks.count)
            }
            Button(Strings.TasteProfile.cancel, role: .cancel) {
                vm.cancelRemove()
            }
        }
    }
}

// MARK: - Cover Tile

private struct SeedBookCoverView: View {
    let book: LocalSeedBook
    let canRemove: Bool
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onTap) {
            BookCoverView(url: book.coverURL)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if canRemove {
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label(Strings.TasteProfile.removeAction, systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - Add Sheet

private struct SeedBookAddSheet: View {
    @Bindable var vm: TasteProfileViewModel
    let modelContext: ModelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SearchBar(query: $vm.searchQuery, placeholder: Strings.Onboarding.SeedSearch.searchPlaceholder) { query in
                    vm.onQueryChanged(query)
                }
                .padding(16)

                // Keep List permanently in the hierarchy — swapping it in/out
                // on every keystroke collapses the container height and causes the
                // search bar to jump. Overlay the spinner on top instead.
                List(vm.searchResults) { result in
                    Button {
                        vm.addBook(result, modelContext: modelContext)
                    } label: {
                        SearchResultRow(book: result)
                    }
                    .disabled(vm.isAddingBook)
                }
                .listStyle(.plain)
                .overlay {
                    if vm.isSearching {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.systemBackground))
                    } else if vm.searchResults.isEmpty && vm.searchQuery.count >= 2 {
                        Text("No results for \"\(vm.searchQuery)\"")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if vm.searchQuery.count < 2 {
                        Text("Type to search books")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .navigationTitle(Strings.TasteProfile.addBook)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(Strings.Common.cancel) { dismiss() }
                }
            }
            .onDisappear {
                vm.searchQuery = ""
                vm.searchResults = []
                vm.isSearching = false
            }
        }
    }
}

// MARK: - Search Bar (reusable within this file)

private struct SearchBar: View {
    @Binding var query: String
    let placeholder: String
    var onChange: (String) -> Void

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $query)
                .autocorrectionDisabled()
                .onChange(of: query) { _, new in onChange(new) }
        }
        .padding(10)
        .background(Color(.secondarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Search Result Row

private struct SearchResultRow: View {
    let book: BookSearchResult

    var body: some View {
        HStack(spacing: 12) {
            if let url = book.coverURL {
                BookCoverView(url: url, width: 36)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.subheadline.bold())
                    .lineLimit(2)
                Text(book.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
