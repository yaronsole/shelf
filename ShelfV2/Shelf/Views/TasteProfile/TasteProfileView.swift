import SwiftUI
import SwiftData

struct TasteProfileView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \LocalSeedBook.addedAt, order: .reverse)
    private var seedBooks: [LocalSeedBook]

    @State private var vm = TasteProfileViewModel()
    @State private var bookForSuggestions: LocalSeedBook? = nil
    @State private var isShowingSettings = false

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
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(Strings.Settings.title)
                }
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
            SeedBookAddSheet()
        }
        .sheet(item: $bookForSuggestions) { book in
            SimilarBooksSheet(seed: book, modelContext: modelContext)
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        .alert("remove from taste?", isPresented: $vm.isShowingRemoveConfirm) {
            Button("remove", role: .destructive) {
                vm.executeRemove(modelContext: modelContext, seedCount: seedBooks.count)
                ToastManager.shared.show(.removedFromTaste)
            }
            Button("cancel", role: .cancel) {
                vm.cancelRemove()
            }
        } message: {
            if let book = vm.bookToRemove {
                Text("we'll stop using \(book.title) to find books like it.")
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
        BookCoverView(url: book.coverURL)
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .onLongPressGesture(minimumDuration: 0.45) {
                guard canRemove else { return }
                Haptics.medium()
                onRemove()
            }
    }
}

// MARK: - Add Sheet

/// Adding a book to the taste profile now uses the shared `BookSearchView`, so
/// the search rows here look identical to Discover / For You and carry the same
/// "read it" (loved / didn't-like → seed) and "save" CTAs. The sheet just wraps
/// it in a NavigationStack with a Cancel button.
private struct SeedBookAddSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            BookSearchView(placeholder: Strings.Onboarding.SeedSearch.searchPlaceholder)
                .navigationTitle(Strings.TasteProfile.addBook)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(Strings.Common.cancel) { dismiss() }
                    }
                }
        }
    }
}
