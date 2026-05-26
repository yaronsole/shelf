import SwiftUI

/// Two-column infinite-scroll wall of Reese book-club covers used as the
/// background of the welcome screen. Uses TimelineView so the scroll keeps
/// running every frame instead of relying on a one-shot withAnimation call
/// that SwiftUI can silently drop.
struct SplashCoverScrollView: View {
    private static let urls: [String] = [
        "https://covers.openlibrary.org/b/isbn/9780735220683-M.jpg",
        "https://covers.openlibrary.org/b/isbn/9780062654175-M.jpg",
        "https://covers.openlibrary.org/b/isbn/9780735224292-M.jpg",
        "https://covers.openlibrary.org/b/isbn/9780399184529-M.jpg",
        "https://covers.openlibrary.org/b/isbn/9781501137846-M.jpg",
        "https://covers.openlibrary.org/b/isbn/9781250127358-M.jpg",
        "https://covers.openlibrary.org/b/isbn/9781501156700-M.jpg",
        "https://covers.openlibrary.org/b/isbn/9780525559931-M.jpg",
        "https://covers.openlibrary.org/b/isbn/9780525559023-M.jpg",
        "https://covers.openlibrary.org/b/isbn/9780571333011-M.jpg",
        "https://covers.openlibrary.org/b/isbn/9781524798628-M.jpg",
        "https://covers.openlibrary.org/b/isbn/9780062422682-M.jpg",
        "https://covers.openlibrary.org/b/isbn/9780593099148-M.jpg",
        "https://covers.openlibrary.org/b/isbn/9780399562488-M.jpg",
        "https://covers.openlibrary.org/b/isbn/9780525541905-M.jpg",
        "https://covers.openlibrary.org/b/isbn/9780778309895-M.jpg",
        "https://covers.openlibrary.org/b/isbn/9780525536291-M.jpg",
        "https://covers.openlibrary.org/b/isbn/9781250269850-M.jpg",
        "https://covers.openlibrary.org/b/isbn/9781982130749-M.jpg",
        "https://covers.openlibrary.org/b/isbn/9780593102602-M.jpg",
        "https://covers.openlibrary.org/b/isbn/9781501171345-M.jpg",
        "https://covers.openlibrary.org/b/isbn/9780593311318-M.jpg",
        "https://covers.openlibrary.org/b/isbn/9781538753033-M.jpg",
        "https://covers.openlibrary.org/b/isbn/9780062977502-M.jpg",
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
