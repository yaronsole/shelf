import SwiftUI

// Async cover image with a consistent placeholder. Used everywhere a book cover appears.
struct CoverImageView: View {
    let urlString: String
    var cornerRadius: CGFloat = 8

    // Google Books returns ~128px thumbnails by default; bump to zoom=3 for
    // sharper rendering on Retina displays.
    private var hiResURL: URL? {
        let upgraded = urlString
            .replacingOccurrences(of: "&zoom=1", with: "&zoom=3")
            .replacingOccurrences(of: "?zoom=1", with: "?zoom=3")
        return URL(string: upgraded)
    }

    var body: some View {
        AsyncImage(url: hiResURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .failure, .empty:
                Rectangle()
                    .fill(Color(.secondarySystemFill))
                    .overlay(
                        Image(systemName: "book.closed")
                            .font(.title2)
                            .foregroundStyle(Color(.tertiaryLabel))
                    )
            @unknown default:
                Rectangle()
                    .fill(Color(.secondarySystemFill))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
