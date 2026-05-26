import SwiftUI

/// Two-column infinite-scroll wall of Reese book-club covers used as the
/// background of the welcome screen. Uses TimelineView so the scroll keeps
/// running every frame instead of relying on a one-shot withAnimation call
/// that SwiftUI can silently drop.
struct SplashCoverScrollView: View {
    // High-confidence Reese book-club ISBNs only. Open Library returns whatever cover
    // it has for an ISBN; trimmed list reduces the chance of unrelated-cover surprises.
    private static let urls: [String] = [
        "https://covers.openlibrary.org/b/isbn/9780735220683-M.jpg", // Eleanor Oliphant
        "https://covers.openlibrary.org/b/isbn/9780735224292-M.jpg", // Little Fires Everywhere
        "https://covers.openlibrary.org/b/isbn/9780399184529-M.jpg", // The Light We Lost
        "https://covers.openlibrary.org/b/isbn/9780525559023-M.jpg", // Where the Crawdads Sing
        "https://covers.openlibrary.org/b/isbn/9781524798628-M.jpg", // Daisy Jones & The Six
        "https://covers.openlibrary.org/b/isbn/9780062654175-M.jpg", // The Alice Network
        "https://covers.openlibrary.org/b/isbn/9780525541905-M.jpg", // Such a Fun Age
        "https://covers.openlibrary.org/b/isbn/9780525559931-M.jpg", // One Day in December
        "https://covers.openlibrary.org/b/isbn/9780593311318-M.jpg", // Malibu Rising
        "https://covers.openlibrary.org/b/isbn/9781250269850-M.jpg", // The Guest List
        "https://covers.openlibrary.org/b/isbn/9780778309895-M.jpg", // The Henna Artist
        "https://covers.openlibrary.org/b/isbn/9780399562488-M.jpg", // The Giver of Stars
    ]

    private let coverWidth: CGFloat = 150
    private let coverHeight: CGFloat = 215
    private let gap: CGFloat = 10
    /// Pixels per second — slow, calm scroll
    private let speed: CGFloat = 18

    @State private var start: Date = .now

    private var leftURLs: [String] {
        stride(from: 0, to: Self.urls.count, by: 2).map { Self.urls[$0] }
    }
    private var rightURLs: [String] {
        stride(from: 1, to: Self.urls.count, by: 2).map { Self.urls[$0] }
    }
    private var loopHeight: CGFloat {
        CGFloat(leftURLs.count) * (coverHeight + gap)
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { context in
                // Linear, modulo loopHeight → wraps cleanly with doubled content
                let elapsed = context.date.timeIntervalSince(start)
                let raw = CGFloat(elapsed) * speed
                let offset = -raw.truncatingRemainder(dividingBy: loopHeight)

                HStack(alignment: .top, spacing: gap) {
                    column(urls: leftURLs + leftURLs)
                    column(urls: rightURLs + rightURLs, extraTop: (coverHeight + gap) / 2)
                }
                .frame(width: geo.size.width, alignment: .center)
                .offset(y: offset)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .clipped()
        }
    }

    @ViewBuilder
    private func column(urls: [String], extraTop: CGFloat = 0) -> some View {
        VStack(spacing: gap) {
            ForEach(0..<urls.count, id: \.self) { i in
                AsyncImage(url: URL(string: urls[i])) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Rectangle().fill(Color(hex: 0xE2D9CC))
                    }
                }
                .frame(width: coverWidth, height: coverHeight)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .offset(y: extraTop)
    }
}
