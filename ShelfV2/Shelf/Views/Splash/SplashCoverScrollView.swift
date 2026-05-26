import SwiftUI

/// Two-column infinite-scroll wall of Reese book-club covers used as the
/// background of the welcome screen. Uses TimelineView so the scroll keeps
/// running every frame instead of relying on a one-shot withAnimation call
/// that SwiftUI can silently drop.
struct SplashCoverScrollView: View {
    // Curated mix of popular, well-photographed book covers from our curated lists
    // (Reese / Oprah / Obama / NYT / Booker / Pulitzer / Goodreads). All chosen for
    // high recognizability and reliable Open Library cover matches.
    private static let urls: [String] = [
        // Reese
        "https://covers.openlibrary.org/b/isbn/9780735220683-M.jpg", // Eleanor Oliphant
        "https://covers.openlibrary.org/b/isbn/9780735224292-M.jpg", // Little Fires Everywhere
        "https://covers.openlibrary.org/b/isbn/9780399184529-M.jpg", // The Light We Lost
        "https://covers.openlibrary.org/b/isbn/9781524798628-M.jpg", // Daisy Jones & The Six
        "https://covers.openlibrary.org/b/isbn/9780525541905-M.jpg", // Such a Fun Age
        "https://covers.openlibrary.org/b/isbn/9780525559023-M.jpg", // Where the Crawdads Sing
        // Obama / NYT / Booker / Pulitzer crossover
        "https://covers.openlibrary.org/b/isbn/9780812995343-M.jpg", // Lincoln in the Bardo
        "https://covers.openlibrary.org/b/isbn/9780399590504-M.jpg", // Educated
        "https://covers.openlibrary.org/b/isbn/9781524763138-M.jpg", // Becoming
        "https://covers.openlibrary.org/b/isbn/9780385542364-M.jpg", // The Underground Railroad
        "https://covers.openlibrary.org/b/isbn/9780593321201-M.jpg", // Tomorrow, and Tomorrow
        "https://covers.openlibrary.org/b/isbn/9780802162175-M.jpg", // The Covenant of Water
        "https://covers.openlibrary.org/b/isbn/9781455563920-M.jpg", // Pachinko
        "https://covers.openlibrary.org/b/isbn/9780525657743-M.jpg", // Crying in H Mart
        "https://covers.openlibrary.org/b/isbn/9780525536291-M.jpg", // The Vanishing Half
        "https://covers.openlibrary.org/b/isbn/9780374611996-M.jpg", // Intermezzo
        "https://covers.openlibrary.org/b/isbn/9780385550369-M.jpg", // James (Percival Everett)
        "https://covers.openlibrary.org/b/isbn/9780593472620-M.jpg", // The God of the Woods
        "https://covers.openlibrary.org/b/isbn/9781668050200-M.jpg", // The Ministry of Time
        "https://covers.openlibrary.org/b/isbn/9780802163783-M.jpg", // Orbital
    ]

    private let coverWidth: CGFloat = 130
    private let coverHeight: CGFloat = 190
    private let gap: CGFloat = 12
    /// Pixels per second — slow ambient scroll so it sits in the background.
    private let speed: CGFloat = 8

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
