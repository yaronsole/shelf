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
                                    savedIds: vm.savedSuggestions,
                                    onAddToTaste: { vm.toggleAddToTaste($0) },
                                    onSaveForLater: { vm.toggleSaveForLater($0) }
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
    let savedIds: Set<String>
    let onAddToTaste: (SuggestionDTO) -> Void
    let onSaveForLater: (SuggestionDTO) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            (Text(Strings.Onboarding.ChainDiscovery.sectionPrefix + " ")
             + Text(seedTitle).italic()
             + Text(" " + Strings.Onboarding.ChainDiscovery.sectionSuffix))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(suggestions) { suggestion in
                        SuggestionCard(
                            suggestion: suggestion,
                            isAddedToTaste: addedIds.contains(suggestion.id),
                            isSavedForLater: savedIds.contains(suggestion.id),
                            onAddToTaste: { onAddToTaste(suggestion) },
                            onSaveForLater: { onSaveForLater(suggestion) }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Suggestion Card

private struct SuggestionCard: View {
    let suggestion: SuggestionDTO
    let isAddedToTaste: Bool
    let isSavedForLater: Bool
    let onAddToTaste: () -> Void
    let onSaveForLater: () -> Void

    @State private var isPressing = false
    private let cardWidth: CGFloat = 132

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                CoverImageView(urlString: suggestion.coverURL, cornerRadius: 8)
                    .frame(width: cardWidth, height: cardWidth * 1.5)
                    .scaleEffect(isPressing ? 0.93 : 1)
                    .animation(.easeInOut(duration: 0.12), value: isPressing)

                if isAddedToTaste {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(6)
                } else if isSavedForLater {
                    Image(systemName: "bookmark.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(6)
                }
            }
            .onTapGesture { onAddToTaste() }
            .onLongPressGesture(minimumDuration: 0.45, pressing: { pressing in
                isPressing = pressing
            }, perform: {
                onSaveForLater()
            })

            Text(suggestion.title)
                .font(.caption.bold())
                .lineLimit(2)
                .frame(width: cardWidth, alignment: .leading)
            Text(suggestion.author)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: cardWidth, alignment: .leading)
        }
    }
}
