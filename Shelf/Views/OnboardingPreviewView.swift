import SwiftUI

// MARK: - Data

struct PreviewScreen {
    let headline: String
    let subheadline: String
    let animationType: PreviewAnimationType
}

enum PreviewAnimationType { case bookCard, wishlistFlyIn, tileFlip }

// OB-01: Updated subheadline on first screen — warmer, more human copy
private let previewScreens: [PreviewScreen] = [
    PreviewScreen(
        headline: "Books picked for you.",
        subheadline: "Tell it once. It gets you.",
        animationType: .bookCard
    ),
    PreviewScreen(
        headline: "Your wishlist builds itself.",
        subheadline: "Like a book. It's saved forever.",
        animationType: .wishlistFlyIn
    ),
    PreviewScreen(
        headline: "It starts with what you love.",
        subheadline: "Tell Shelf your taste and it takes it from there.",
        animationType: .tileFlip
    )
]

// MARK: - OnboardingPreviewView

struct OnboardingPreviewView: View {
    @Environment(AppStateManager.self) var appState
    @State private var currentPage = 0

    var body: some View {
        ZStack {
            Color(hex: "1C1C1E").ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    ForEach(Array(previewScreens.enumerated()), id: \.offset) { index, screen in
                        PreviewPageView(screen: screen, isActive: currentPage == index)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: .infinity)

                // Bottom controls
                VStack(spacing: 20) {
                    // Page dots
                    HStack(spacing: 8) {
                        ForEach(0..<previewScreens.count, id: \.self) { i in
                            Capsule()
                                .fill(i == currentPage
                                      ? Color(hex: "D4AF37")
                                      : Color.white.opacity(0.3))
                                .frame(width: i == currentPage ? 20 : 8, height: 8)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: currentPage)
                        }
                    }

                    // CTA — swaps on last page
                    ZStack {
                        if currentPage < previewScreens.count - 1 {
                            Button {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    currentPage += 1
                                }
                            } label: { Text("Next") }
                            .buttonStyle(ShelfPrimaryButtonStyle())
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                            .id("next")
                        } else {
                            Button { appState.completePreview() } label: {
                                Text("Tell Shelf your taste →")
                            }
                            .buttonStyle(ShelfPrimaryButtonStyle())
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                            .id("cta")
                        }
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentPage)

                    // Skip
                    Button { appState.completePreview() } label: {
                        Text("Skip")
                            .font(.system(size: 15))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
    }
}

// MARK: - PreviewPageView

struct PreviewPageView: View {
    let screen: PreviewScreen
    let isActive: Bool

    var body: some View {
        VStack(spacing: 32) {
            ZStack {
                switch screen.animationType {
                case .bookCard:     BookCoverGridPreview(isActive: isActive)   // OB-01
                case .wishlistFlyIn: AnimatedWishlistPreview(isActive: isActive)
                case .tileFlip:     AnimatedTilePreview(isActive: isActive)
                }
            }
            .frame(height: 300)

            VStack(spacing: 10) {
                Text(screen.headline)
                    .font(.custom("Georgia", size: 28)).bold()
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(screen.subheadline)
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding(.top, 56)
    }
}

// MARK: - Screen 1: BookCoverGridPreview (OB-01)
// Real cover grid fetched from GoogleBooksService for 12 diverse hardcoded books.

struct BookCoverGridPreview: View {
    let isActive: Bool

    // 12 diverse books — real covers fetched via GoogleBooksService
    private let seedBooks: [(title: String, author: String)] = [
        ("The Secret History",                        "Donna Tartt"),
        ("Normal People",                             "Sally Rooney"),
        ("Piranesi",                                  "Susanna Clarke"),
        ("Project Hail Mary",                         "Andy Weir"),
        ("Tomorrow and Tomorrow and Tomorrow",        "Gabrielle Zevin"),
        ("Lessons in Chemistry",                      "Bonnie Garmus"),
        ("A Gentleman in Moscow",                     "Amor Towles"),
        ("Remarkably Bright Creatures",               "Shelby Van Pelt"),
        ("The Midnight Library",                      "Matt Haig"),
        ("Fourth Wing",                               "Rebecca Yarros"),
        ("Demon Copperhead",                          "Barbara Kingsolver"),
        ("The Seven Husbands of Evelyn Hugo",         "Taylor Jenkins Reid")
    ]

    @State private var coverURLs: [String] = []

    var body: some View {
        ZStack {
            if coverURLs.isEmpty {
                // Placeholder shimmer tiles while covers load
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 8
                ) {
                    ForEach(0..<12, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(hex: "2C2C2E"))
                            .frame(height: 88)
                    }
                }
                .padding(.horizontal, 28)
            } else {
                // Real cover grid
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 8
                ) {
                    ForEach(Array(coverURLs.enumerated()), id: \.offset) { _, urlString in
                        AsyncImage(url: URL(string: urlString)) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().aspectRatio(contentMode: .fill)
                            default:
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(hex: "2C2C2E"))
                            }
                        }
                        .frame(height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
                    }
                }
                .padding(.horizontal, 28)
                // Fade top/bottom edges for a polished look
                .mask(
                    LinearGradient(
                        colors: [.clear, .black, .black, .clear],
                        locations: [0, 0.08, 0.92, 1.0],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .onAppear { if isActive { fetchCovers() } }
        .onChange(of: isActive) { _, newValue in
            if newValue && coverURLs.isEmpty { fetchCovers() }
        }
    }

    private func fetchCovers() {
        Task {
            var indexed = [(Int, String?)]()
            await withTaskGroup(of: (Int, String?).self) { group in
                for (i, book) in seedBooks.enumerated() {
                    group.addTask {
                        let meta = await GoogleBooksService.shared.enrich(
                            title: book.title, author: book.author
                        )
                        return (i, meta.coverURL)
                    }
                }
                for await result in group {
                    indexed.append(result)
                }
            }
            indexed.sort { $0.0 < $1.0 }
            let urls = indexed.compactMap { $0.1 }
            withAnimation(.easeInOut(duration: 0.5)) {
                coverURLs = urls
            }
        }
    }
}

// MARK: - Screen 2: AnimatedWishlistPreview (unchanged)

struct AnimatedWishlistPreview: View {
    let isActive: Bool

    @State private var cardOffset: CGFloat = 50
    @State private var cardScale: CGFloat = 1
    @State private var cardOpacity: Double = 1
    @State private var showSlot = false
    @State private var heartScale: CGFloat = 0
    @State private var heartOpacity: Double = 0

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                // Destination shelf row
                HStack(spacing: 6) {
                    ForEach(0..<4) { i in
                        if i == 1 {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(showSlot ? Color(hex: "3D2B1F") : Color(hex: "2C2C2E"))
                                .frame(width: 48, height: 70)
                                .overlay(
                                    showSlot
                                    ? Text("📖").font(.system(size: 18)).opacity(1)
                                    : nil
                                )
                                .scaleEffect(showSlot ? 1 : 0.01)
                                .animation(.spring(response: 0.4, dampingFraction: 0.6), value: showSlot)
                        } else {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(hex: "2C2C2E"))
                                .frame(width: 48, height: 70)
                        }
                    }
                }

                Spacer()

                // Source card
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: "1F3D2B"))
                        .frame(width: 44, height: 64)
                        .overlay(Text("🦅").font(.system(size: 20)))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Piranesi")
                            .font(.custom("Georgia", size: 14)).bold()
                            .foregroundStyle(.white)
                        Text("Susanna Clarke")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color(hex: "2C2C2E"))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .offset(y: cardOffset)
                .scaleEffect(cardScale)
                .opacity(cardOpacity)
            }

            // Floating heart
            Text("❤️")
                .font(.system(size: 36))
                .scaleEffect(heartScale)
                .opacity(heartOpacity)
        }
        .padding(.horizontal, 36)
        .onChange(of: isActive) { _, newValue in
            if newValue { runAnimation() } else { reset() }
        }
        .onAppear { if isActive { runAnimation() } }
    }

    private func reset() {
        cardOffset = 50; cardScale = 1; cardOpacity = 1
        showSlot = false; heartScale = 0; heartOpacity = 0
    }

    private func runAnimation() {
        reset()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                cardOffset = -100; cardScale = 0.35; cardOpacity = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            showSlot = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                heartScale = 1.2; heartOpacity = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.spring(response: 0.3)) { heartScale = 1.0 }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut(duration: 0.4)) { heartOpacity = 0 }
        }
    }
}

// MARK: - Screen 3: AnimatedTilePreview (unchanged)

struct AnimatedTilePreview: View {
    let isActive: Bool

    @State private var visibleTiles: Set<Int> = []
    @State private var selectedTile: Int? = nil

    private let tiles: [(String, String)] = [
        ("🕯️", "Dark academia"), ("💔", "Gut-punch endings"),
        ("🧠", "Mind-benders"),  ("☕", "Comfort reads")
    ]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { index, tile in
                VStack(spacing: 6) {
                    Text(tile.0).font(.system(size: 26))
                    Text(tile.1)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 80)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(selectedTile == index
                              ? Color(hex: "D4AF37").opacity(0.2)
                              : Color(hex: "2C2C2E"))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    selectedTile == index
                                    ? Color(hex: "D4AF37")
                                    : Color.clear,
                                    lineWidth: 1.5
                                )
                        )
                )
                .rotation3DEffect(
                    .degrees(visibleTiles.contains(index) ? 0 : -90),
                    axis: (x: 1, y: 0, z: 0)
                )
                .opacity(visibleTiles.contains(index) ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: visibleTiles)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selectedTile)
            }
        }
        .padding(.horizontal, 28)
        .onChange(of: isActive) { _, newValue in
            if newValue { runAnimation() } else { reset() }
        }
        .onAppear { if isActive { runAnimation() } }
    }

    private func reset() { visibleTiles = []; selectedTile = nil }

    private func runAnimation() {
        reset()
        for i in 0..<tiles.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 + Double(i) * 0.15) {
                visibleTiles.insert(i)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            selectedTile = 0
        }
    }
}
