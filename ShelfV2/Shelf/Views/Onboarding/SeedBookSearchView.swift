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

            // Results
            List(vm.searchResults) { result in
                Button {
                    vm.selectBook(result)
                } label: {
                    HStack(spacing: 12) {
                        if let url = result.coverURL {
                            CoverImageView(urlString: url, cornerRadius: 4)
                                .frame(width: 36, height: 52)
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
