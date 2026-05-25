import SwiftUI
import SwiftData

// Bottom sheet shown when the user taps a seed book in the Taste profile.
// Pulls Claude-generated suggestions for that book and shows them as full
// Discover-style cards with Save / Read / Pass CTAs.
struct SimilarBooksSheet: View {
    let seed: LocalSeedBook
    let modelContext: ModelContext

    @Environment(\.dismiss) private var dismiss
    @State private var suggestions: [SuggestionDTO] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    // Dedup keys passed to the backend exclude list — lowercased title|author
    @State private var excludeKeys: [String] = []
    // Locally-dismissed IDs (Pass / Save / Read removes from view)
    @State private var hiddenIds: Set<String> = []

    private var visibleSuggestions: [SuggestionDTO] {
        suggestions.filter { !hiddenIds.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Seed header
                    HStack(alignment: .top, spacing: 14) {
                        BookCoverView(url: seed.coverURL, width: 60)
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
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    if isLoading {
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("Finding similar reads…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else if visibleSuggestions.isEmpty {
                        Text("No more suggestions for this book right now.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.top, 40)
                    } else {
                        ForEach(visibleSuggestions) { s in
                            SuggestionCard(
                                suggestion: s,
                                onSave: { save(s) },
                                onPass: { hide(s) },
                                onAlreadyRead: { _ in hide(s) }
                            )
                            .padding(.horizontal, 16)
                        }
                    }

                    // "Find more" CTA always shown (unless initial load)
                    if !isLoading {
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
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.secondarySystemFill))
                            )
                            .foregroundStyle(Color(.label))
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoadingMore)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
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
        .task { await initialLoad() }
    }

    // MARK: - Loading

    private static func key(_ title: String, _ author: String) -> String {
        "\(title.lowercased())|\(author.lowercased())"
    }

    private func initialLoad() async {
        // Seed exclude with this seed itself + any books already in Reading List for this user
        let seedKey = Self.key(seed.title, seed.author)
        let savedKeys: [String] = (try? modelContext.fetch(FetchDescriptor<ReadingListItem>()))?
            .map { Self.key($0.title, $0.author) } ?? []
        let initialExclude = ([seedKey] + savedKeys).reduce(into: [String]()) { acc, k in
            if !acc.contains(k) { acc.append(k) }
        }
        excludeKeys = initialExclude

        let result = await fetch(count: 5)
        await MainActor.run {
            for s in result {
                self.excludeKeys.append(Self.key(s.title, s.author))
            }
            self.suggestions = result
            self.isLoading = false
        }
    }

    private func loadMore() async {
        guard !isLoadingMore else { return }
        await MainActor.run { self.isLoadingMore = true }
        let result = await fetch(count: 5)
        await MainActor.run {
            for s in result {
                self.excludeKeys.append(Self.key(s.title, s.author))
            }
            self.suggestions.append(contentsOf: result)
            self.isLoadingMore = false
        }
    }

    private func fetch(count: Int) async -> [SuggestionDTO] {
        let request = BookSearchResult(
            id: seed.id, title: seed.title, author: seed.author, coverURL: seed.coverURL
        )
        return (try? await APIClient.shared.fetchSuggestions(
            for: request, count: count, exclude: excludeKeys
        )) ?? []
    }

    // MARK: - Actions

    private func save(_ s: SuggestionDTO) {
        let item = ReadingListItem(
            id: s.id,
            title: s.title,
            author: s.author,
            coverURL: s.coverURL,
            blurb: s.blurb.isEmpty ? "Suggested because you love \(seed.title)." : s.blurb
        )
        modelContext.insert(item)
        hide(s)
    }

    private func hide(_ s: SuggestionDTO) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            hiddenIds.insert(s.id)
        }
    }
}

// MARK: - Suggestion Card (Discover-style)

private struct SuggestionCard: View {
    let suggestion: SuggestionDTO
    let onSave: () -> Void
    let onPass: () -> Void
    let onAlreadyRead: (Bool) -> Void

    @State private var showAlreadyReadSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BookCoverView(url: suggestion.coverURL)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(suggestion.title)
                        .font(.title3.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Text(suggestion.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Context row: NYT bestseller, reading time
                ContextRow(
                    nytBestseller: suggestion.nytBestseller,
                    nytWeeks: suggestion.nytWeeksOnList,
                    readingTimeMinutes: suggestion.readingTimeMinutes
                )

                // Editorial context — single sparkle line with a cultural hook
                if !suggestion.contextTag.isEmpty {
                    Label(suggestion.contextTag, systemImage: "sparkle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color(red: 0.30, green: 0.20, blue: 0.55))
                }

                if !suggestion.genre.isEmpty || !suggestion.era.isEmpty || !suggestion.awards.isEmpty {
                    HStack(spacing: 6) {
                        if !suggestion.genre.isEmpty {
                            TinyTag(text: suggestion.genre)
                        }
                        if !suggestion.era.isEmpty {
                            TinyTag(text: suggestion.era)
                        }
                        ForEach(suggestion.awards, id: \.self) { AwardBadge(text: $0) }
                    }
                }

                if !suggestion.blurb.isEmpty {
                    Text(suggestion.blurb)
                        .font(.subheadline)
                        .foregroundStyle(Color(.label))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }

                HStack(spacing: 8) {
                    CardActionButton(label: "Save", icon: "bookmark.fill", kind: .primary, action: onSave)
                    CardActionButton(label: "Read", icon: "checkmark", kind: .secondary) {
                        showAlreadyReadSheet = true
                    }
                    CardActionButton(label: "Pass", icon: "xmark", kind: .tertiary, action: onPass)
                }
                .padding(.top, 4)
            }
            .padding(14)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)
        .sheet(isPresented: $showAlreadyReadSheet) {
            AlreadyReadSheet(
                title: suggestion.title,
                onLoved: { onAlreadyRead(true) },
                onDidntLike: { onAlreadyRead(false) }
            )
        }
    }
}

private struct TinyTag: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(Color(.secondaryLabel))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color(.secondarySystemFill)))
    }
}

private enum CardActionKind { case primary, secondary, tertiary }

private struct CardActionButton: View {
    let label: String
    let icon: String
    let kind: CardActionKind
    let action: () -> Void

    private var foreground: Color {
        switch kind {
        case .primary: return .white
        case .secondary: return Color(red: 0.10, green: 0.45, blue: 0.30)
        case .tertiary: return Color(.tertiaryLabel)
        }
    }
    private var background: Color {
        switch kind {
        case .primary: return Color(red: 0.10, green: 0.35, blue: 0.85)
        case .secondary: return Color(red: 0.10, green: 0.45, blue: 0.30).opacity(0.12)
        case .tertiary: return Color(.secondarySystemFill)
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                Text(label)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: kind == .primary ? .infinity : nil)
            .padding(.horizontal, kind == .primary ? 14 : 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(background))
            .foregroundStyle(foreground)
        }
        .buttonStyle(.plain)
    }
}
