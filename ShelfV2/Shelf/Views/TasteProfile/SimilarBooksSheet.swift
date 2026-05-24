import SwiftUI
import SwiftData

// Bottom sheet shown when the user taps a seed book in the Taste profile.
// Fetches Claude-generated suggestions for that specific book and lets the
// user save any of them to the Reading List with one tap.
struct SimilarBooksSheet: View {
    let seed: LocalSeedBook
    let modelContext: ModelContext

    @Environment(\.dismiss) private var dismiss
    @State private var suggestions: [SuggestionDTO] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var savedIds: Set<String> = []
    // Dedup by lowercased "title|author" — IDs are random per Claude call
    @State private var seenKeys: Set<String> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Seed header
                    HStack(alignment: .top, spacing: 14) {
                        CoverImageView(urlString: seed.coverURL, cornerRadius: 6)
                            .frame(width: 60, height: 90)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Because you love")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .tracking(0.5)
                            Text(seed.title)
                                .font(.title3.bold())
                            Text(seed.author)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    Divider().padding(.horizontal, 20)

                    if isLoading {
                        VStack {
                            ProgressView()
                            Text("Finding similar reads…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else if suggestions.isEmpty {
                        Text("Couldn't find suggestions right now. Try again later.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.top, 40)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(suggestions) { s in
                                SuggestionRow(
                                    suggestion: s,
                                    isSaved: savedIds.contains(s.id),
                                    onSave: { save(s) }
                                )
                            }

                            // "Find more" CTA at the bottom of the suggestions list
                            Button(action: { Task { await loadMore() } }) {
                                HStack(spacing: 6) {
                                    if isLoadingMore {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Image(systemName: "sparkles")
                                    }
                                    Text(isLoadingMore ? "Finding more…" : "Find more like this")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(.secondarySystemFill))
                                )
                                .foregroundStyle(Color(.label))
                            }
                            .buttonStyle(.plain)
                            .disabled(isLoadingMore)
                            .padding(.top, 8)
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Similar books")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(Strings.Common.done) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .task { await loadSuggestions() }
    }

    private static func key(_ title: String, _ author: String) -> String {
        "\(title.lowercased())|\(author.lowercased())"
    }

    private func loadSuggestions() async {
        let result = await fetch()
        await MainActor.run {
            // Seed dedup keys with both this seed itself and the returned books
            self.seenKeys.insert(Self.key(self.seed.title, self.seed.author))
            for s in result {
                self.seenKeys.insert(Self.key(s.title, s.author))
            }
            self.suggestions = result
            self.isLoading = false
        }
    }

    private func loadMore() async {
        guard !isLoadingMore else { return }
        await MainActor.run { self.isLoadingMore = true }
        let result = await fetch()
        await MainActor.run {
            // Filter out any title/author we've already shown
            let fresh = result.filter { !self.seenKeys.contains(Self.key($0.title, $0.author)) }
            for s in fresh {
                self.seenKeys.insert(Self.key(s.title, s.author))
            }
            self.suggestions.append(contentsOf: fresh)
            self.isLoadingMore = false
        }
    }

    private func fetch() async -> [SuggestionDTO] {
        let request = BookSearchResult(
            id: seed.id, title: seed.title, author: seed.author, coverURL: seed.coverURL
        )
        return (try? await APIClient.shared.fetchSuggestions(for: request)) ?? []
    }

    private func save(_ s: SuggestionDTO) {
        guard !savedIds.contains(s.id) else { return }
        let item = ReadingListItem(
            id: s.id,
            title: s.title,
            author: s.author,
            coverURL: s.coverURL,
            blurb: "Suggested because you love \(seed.title)."
        )
        modelContext.insert(item)
        savedIds.insert(s.id)
    }
}

// MARK: - Row

private struct SuggestionRow: View {
    let suggestion: SuggestionDTO
    let isSaved: Bool
    let onSave: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CoverImageView(urlString: suggestion.coverURL, cornerRadius: 6)
                .frame(width: 50, height: 75)
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                    .font(.subheadline.bold())
                    .lineLimit(2)
                Text(suggestion.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onSave) {
                Image(systemName: isSaved ? "checkmark.circle.fill" : "bookmark")
                    .font(.title3)
                    .foregroundStyle(isSaved ? Color.green : Color(.label))
            }
            .buttonStyle(.plain)
            .disabled(isSaved)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemFill))
        )
    }
}
