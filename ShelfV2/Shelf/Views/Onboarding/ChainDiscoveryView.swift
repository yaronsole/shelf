import SwiftUI

struct ChainDiscoveryView: View {
    @Bindable var vm: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text(Strings.Onboarding.ChainDiscovery.title)
                    .font(.largeTitle.bold())
                Text(Strings.Onboarding.ChainDiscovery.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 16)

            if vm.isLoadingSuggestions {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        ForEach(vm.selectedBooks) { book in
                            if let subs = vm.suggestions[book.id], !subs.isEmpty {
                                SuggestionRow(
                                    seedTitle: book.title,
                                    suggestions: subs,
                                    addedIds: vm.addedSuggestions,
                                    onToggle: { vm.toggleSuggestion($0) }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }
            }

            // CTA
            HStack(spacing: 12) {
                Button(Strings.Onboarding.ChainDiscovery.skipCTA) {
                    vm.step = .confirmation
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Button(Strings.Onboarding.ChainDiscovery.continueCTA) {
                    vm.step = .confirmation
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(.label))
                .foregroundStyle(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(.regularMaterial)
        }
    }
}

// MARK: - Suggestion Row per seed book

private struct SuggestionRow: View {
    let seedTitle: String
    let suggestions: [SuggestionDTO]
    let addedIds: Set<String>
    var onToggle: (SuggestionDTO) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(Strings.Onboarding.ChainDiscovery.sectionPrefix) \(seedTitle)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(suggestions) { suggestion in
                        SuggestionCard(
                            suggestion: suggestion,
                            isAdded: addedIds.contains(suggestion.id)
                        ) {
                            onToggle(suggestion)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Suggestion Card

private struct SuggestionCard: View {
    let suggestion: SuggestionDTO
    let isAdded: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    CoverImageView(urlString: suggestion.coverURL, cornerRadius: 8)
                        .frame(width: 100, height: 144)

                    if isAdded {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                            .padding(6)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.title)
                        .font(.caption.bold())
                        .lineLimit(2)
                        .frame(width: 100, alignment: .leading)
                    Text(suggestion.author)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: 100, alignment: .leading)
                }
                .padding(.top, 6)
            }
        }
        .buttonStyle(.plain)
        .opacity(isAdded ? 1 : 0.85)
        .scaleEffect(isAdded ? 1 : 0.97)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isAdded)
    }
}
