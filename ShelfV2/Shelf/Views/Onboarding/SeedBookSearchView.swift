import SwiftUI

struct SeedBookSearchView: View {
    @Bindable var vm: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text(Strings.Onboarding.SeedSearch.title)
                    .font(.largeTitle.bold())
                Text(Strings.Onboarding.SeedSearch.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 12)

            // Selected chips (OB-04)
            if !vm.selectedBooks.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(vm.selectedBooks) { book in
                            SelectedChip(book: book) {
                                vm.removeBook(book)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .frame(height: 44)
                .padding(.bottom, 8)
            }

            // Search field
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(Strings.Onboarding.SeedSearch.searchPlaceholder, text: $vm.searchQuery)
                    .autocorrectionDisabled()
                    .onChange(of: vm.searchQuery) { _, new in vm.onQueryChanged(new) }
                if vm.isSearching {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(12)
            .background(Color(.secondarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            // Results: search list when typing, curated grid when empty
            if vm.searchQuery.count >= 2 {
                List(vm.searchResults) { result in
                    Button {
                        vm.selectBook(result)
                    } label: {
                        HStack(spacing: 12) {
                            if let url = result.coverURL {
                                BookCoverView(url: url, width: 36)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(Color(.label))
                                    .lineLimit(2)
                                Text(result.author)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if vm.isSelected(result) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color(.label))
                            }
                        }
                    }
                    .listRowBackground(vm.isSelected(result) ? Color(.secondarySystemFill) : Color.clear)
                }
                .listStyle(.plain)
            } else {
                PopularBooksGrid(vm: vm)
            }

            // Progress + CTA (OB-05)
            VStack(spacing: 8) {
                HStack {
                    Text(vm.selectionCountText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !vm.canContinueFromSearch {
                        Spacer()
                        Text(Strings.Onboarding.SeedSearch.encouragement)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button(Strings.Onboarding.SeedSearch.continueCTA) {
                    vm.step = .chainDiscovery
                    vm.loadSuggestions()
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(vm.canContinueFromSearch ? Color(.label) : Color(.systemFill))
                .foregroundStyle(vm.canContinueFromSearch ? Color(.systemBackground) : Color(.tertiaryLabel))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .disabled(!vm.canContinueFromSearch)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(.regularMaterial)
        }
        .onAppear { vm.loadPopularBooksIfNeeded() }
    }
}

// MARK: - Popular Books Grid

private struct PopularBooksGrid: View {
    @Bindable var vm: OnboardingViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Popular picks")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                if vm.isLoadingPopular && vm.popularBooks.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView().padding(.vertical, 32)
                        Spacer()
                    }
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(vm.popularBooks) { book in
                            PopularBookTile(
                                book: book,
                                isSelected: vm.isSelected(book),
                                isSaved: vm.isSaved(book),
                                onToggleSelect: {
                                    if vm.isSelected(book) { vm.removeBook(book) } else { vm.selectBook(book) }
                                },
                                onToggleSave: { vm.toggleSaveBook(book) }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }
        }
    }
}

private struct PopularBookTile: View {
    let book: BookSearchResult
    let isSelected: Bool
    let isSaved: Bool
    let onToggleSelect: () -> Void
    let onToggleSave: () -> Void

    @State private var isPressing = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                BookCoverView(url: book.coverURL ?? "")
                    .scaleEffect(isPressing ? 0.93 : 1)
                    .animation(.easeInOut(duration: 0.12), value: isPressing)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(4)
                } else if isSaved {
                    Image(systemName: "bookmark.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(4)
                }
            }
            .onTapGesture { onToggleSelect() }
            .onLongPressGesture(minimumDuration: 0.45, pressing: { pressing in
                isPressing = pressing
            }, perform: {
                onToggleSave()
            })

            Text(book.title)
                .font(.caption2.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(.label))
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Chip

private struct SelectedChip: View {
    let book: BookSearchResult
    let onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: 6) {
                if let url = book.coverURL {
                    AsyncImage(url: URL(string: url)) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                        } else {
                            Color(.secondarySystemFill)
                        }
                    }
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                Text(book.displayTitle)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemFill))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
