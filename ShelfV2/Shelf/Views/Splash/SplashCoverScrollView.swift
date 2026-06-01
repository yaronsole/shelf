import SwiftUI

/// Two-column infinite-scroll wall of Reese book-club covers used as the
/// background of the welcome screen. Uses TimelineView so the scroll keeps
/// running every frame instead of relying on a one-shot withAnimation call
/// that SwiftUI can silently drop.
///
/// The covers are BUNDLED LOCAL ASSETS (Assets.xcassets/SplashCovers), not
/// network images. This is the very first screen a new user sees, and it's the
/// one screen we can't prefetch — so on a fresh TestFlight install with an empty
/// URL cache, loading these over the network made them pop in one-by-one. Local
/// assets render instantly and offline. The art is static/curated, so bundling
/// costs us nothing in flexibility (changing the wall already meant a code
/// change). See SplashCovers/ for the imageset → book mapping below.
struct SplashCoverScrollView: View {
    // Curated mix of popular, well-photographed covers from our lists
    // (Reese / Oprah / Obama / NYT / Booker / Pulitzer / Goodreads). Order here
    // maps 1:1 to Assets.xcassets/SplashCovers/SplashCover00…19.
    private static let coverAssets: [String] = [
        "SplashCover00", // Eleanor Oliphant Is Completely Fine
        "SplashCover01", // Little Fires Everywhere
        "SplashCover02", // The Light We Lost
        "SplashCover03", // Daisy Jones & The Six
        "SplashCover04", // Such a Fun Age
        "SplashCover05", // Where the Crawdads Sing
        "SplashCover06", // Lincoln in the Bardo
        "SplashCover07", // Educated
        "SplashCover08", // Becoming
        "SplashCover09", // The Underground Railroad
        "SplashCover10", // Tomorrow, and Tomorrow, and Tomorrow
        "SplashCover11", // The Covenant of Water
        "SplashCover12", // Pachinko
        "SplashCover13", // Crying in H Mart
        "SplashCover14", // The Vanishing Half
        "SplashCover15", // Intermezzo
        "SplashCover16", // James (Percival Everett)
        "SplashCover17", // The God of the Woods
        "SplashCover18", // The Ministry of Time
        "SplashCover19", // Orbital
    ]

    private let coverWidth: CGFloat = 130
    private let coverHeight: CGFloat = 190
    private let gap: CGFloat = 12
    /// Pixels per second — slow ambient scroll so it sits in the background.
    private let speed: CGFloat = 8

    @State private var start: Date = .now

    private var leftCovers: [String] {
        stride(from: 0, to: Self.coverAssets.count, by: 2).map { Self.coverAssets[$0] }
    }
    private var rightCovers: [String] {
        stride(from: 1, to: Self.coverAssets.count, by: 2).map { Self.coverAssets[$0] }
    }
    private var loopHeight: CGFloat {
        CGFloat(leftCovers.count) * (coverHeight + gap)
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { context in
                // Linear, modulo loopHeight → wraps cleanly with doubled content
                let elapsed = context.date.timeIntervalSince(start)
                let raw = CGFloat(elapsed) * speed
                let offset = -raw.truncatingRemainder(dividingBy: loopHeight)

                HStack(alignment: .top, spacing: gap) {
                    column(names: leftCovers + leftCovers)
                    column(names: rightCovers + rightCovers)
                }
                .frame(width: geo.size.width, alignment: .center)
                .offset(y: offset)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .clipped()
        }
    }

    @ViewBuilder
    private func column(names: [String]) -> some View {
        VStack(spacing: gap) {
            ForEach(0..<names.count, id: \.self) { i in
                Image(names[i])
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: coverWidth, height: coverHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}
