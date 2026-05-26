import SwiftUI

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

    @State private var scrollOffset: CGFloat = 0

    private let coverWidth: CGFloat = 155
    private let coverHeight: CGFloat = 220
    private let gap: CGFloat = 8

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
        HStack(alignment: .top, spacing: gap) {
            coverColumn(urls: leftURLs + leftURLs, extraTop: 0)
            coverColumn(urls: rightURLs + rightURLs, extraTop: (coverHeight + gap) / 2)
        }
        .offset(y: scrollOffset)
        .onAppear {
            withAnimation(.linear(duration: 40).repeatForever(autoreverses: false)) {
                scrollOffset = -loopHeight
            }
        }
    }

    @ViewBuilder
    private func coverColumn(urls: [String], extraTop: CGFloat) -> some View {
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
