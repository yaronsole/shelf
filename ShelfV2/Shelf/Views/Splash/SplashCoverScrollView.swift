import SwiftUI

/// Two-column infinite-scroll wall of Reese book-club covers used as the
/// background of the welcome screen. Uses TimelineView so the scroll keeps
/// running every frame instead of relying on a one-shot withAnimation call
/// that SwiftUI can silently drop.
struct SplashCoverScrollView: View {
    // Open Library returns whatever cover an ISBN maps to — some of the broader Reese
    // list ISBNs were resolving to unrelated books (Enlightenment Now, Bath Haus, etc.).
    // Trimmed to the ones visually confirmed correct in screenshots.
    private static let urls: [String] = [
        "https://covers.openlibrary.org/b/isbn/9780735220683-M.jpg", // Eleanor Oliphant
        "https://covers.openlibrary.org/b/isbn/9780735224292-M.jpg", // Little Fires Everywhere
        "https://covers.openlibrary.org/b/isbn/9780399184529-M.jpg", // The Light We Lost
        "https://covers.openlibrary.org/b/isbn/9781524798628-M.jpg", // Daisy Jones & The Six
        "https://covers.openlibrary.org/b/isbn/9780525541905-M.jpg", // Such a Fun Age
        "https://covers.openlibrary.org/b/isbn/9780062654175-M.jpg", // The Alice Network
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
                    column(urls: rightURLs + rightURLs)
                }
                .frame(width: geo.size.width, alignment: .center)
                .offset(y: offset)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .clipped()
        }
    }

    @ViewBuilder
    private func column(urls: [String]) -> some View {
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
    }
}
