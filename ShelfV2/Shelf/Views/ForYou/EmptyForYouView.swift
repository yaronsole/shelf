import SwiftUI

/// Shown in the For You tab when the user has < 3 seeds OR has no personalized recs.
/// Contains a search box placeholder (wired in Phase 7), six popular-picks covers,
/// and two shortcut cards into curated lists (Phase 6 wires the destination).
struct EmptyForYouView: View {
    @State private var popularPicks: [PopularPickItem] = []
    @State private var searchQuery: String = ""

    private let horizontalPadding: CGFloat = 16
    private let gridSpacing: CGFloat = 12

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                instructionalLine
                searchBox
                popularPicksSection
                browseListSection
                footerLine
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 16)
        }
        .onAppear { loadPopularPicksIfNeeded() }
    }

    // MARK: - Sections

    private var instructionalLine: some View {
        Text("Pick books you've loved to unlock personalized picks.")
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
    }

    private var searchBox: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search for a book…", text: $searchQuery)
                .autocorrectionDisabled()
                .disabled(true)  // wired in Phase 7
        }
        .padding(10)
        .background(Color(.secondarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var popularPicksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("POPULAR PICKS")
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: gridSpacing),
                    GridItem(.flexible(), spacing: gridSpacing),
                ],
                spacing: gridSpacing
            ) {
                ForEach(popularPicks.prefix(6)) { pick in
                    BookCoverView(url: pick.coverURL)
                }
            }
        }
    }

    private var browseListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("OR BROWSE A LIST")
            VStack(spacing: 12) {
                ListShortcutCard(
                    title: "Oprah's Book Club",
                    subtitle: "Since 1996",
                    colorStart: Color(hex: 0x534AB7),
                    colorEnd: Color(hex: 0x7F77DD)
                )
                ListShortcutCard(
                    title: "Reese's Book Club",
                    subtitle: "Hello Sunshine",
                    colorStart: Color(hex: 0xD67C5C),
                    colorEnd: Color(hex: 0xF2B69A)
                )
            }
        }
    }

    private var footerLine: some View {
        Text("Pick at least 3 to unlock personalized recs ✦")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.top, 8)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(0.8)
    }

    private func loadPopularPicksIfNeeded() {
        guard popularPicks.isEmpty else { return }
        Task {
            let firstSix = Array(PopularBooks.books.prefix(6))
            var items: [PopularPickItem] = []
            await withTaskGroup(of: (Int, PopularPickItem?).self) { group in
                for (index, entry) in firstSix.enumerated() {
                    group.addTask {
                        if let cover = await OpenLibraryService.shared.lookupCoverURL(title: entry.title, author: entry.author) {
                            return (index, PopularPickItem(title: entry.title, author: entry.author, coverURL: cover))
                        }
                        if let result = await GoogleBooksService.shared.lookup(title: entry.title, author: entry.author) {
                            return (index, PopularPickItem(title: result.title, author: result.author, coverURL: result.coverURL ?? ""))
                        }
                        return (index, nil)
                    }
                }
                var indexed: [(Int, PopularPickItem)] = []
                for await (i, item) in group {
                    if let item { indexed.append((i, item)) }
                }
                items = indexed.sorted { $0.0 < $1.0 }.map { $0.1 }
            }
            await MainActor.run { self.popularPicks = items }
        }
    }
}

// MARK: - Data

private struct PopularPickItem: Identifiable {
    let title: String
    let author: String
    let coverURL: String
    var id: String { "\(title)|\(author)".lowercased() }
}

// MARK: - List Shortcut Card

private struct ListShortcutCard: View {
    let title: String
    let subtitle: String
    let colorStart: Color
    let colorEnd: Color

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
            Image(systemName: "arrow.right")
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 76)
        .background(
            LinearGradient(
                colors: [colorStart, colorEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Color hex helper

private extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
