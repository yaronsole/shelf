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
    @State private var savedIds: Set<String> = []

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

    private func loadSuggestions() async {
        let request = BookSearchResult(
            id: seed.id, title: seed.title, author: seed.author, coverURL: seed.coverURL
        )
        let result = (try? await APIClient.shared.fetchSuggestions(for: request)) ?? []
        await MainActor.run {
            self.suggestions = result
            self.isLoading = false
        }
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
