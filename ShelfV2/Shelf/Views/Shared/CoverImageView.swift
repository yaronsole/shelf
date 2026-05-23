import SwiftUI

// Async cover image with a consistent placeholder. Used everywhere a book cover appears.
struct CoverImageView: View {
    let urlString: String
    var cornerRadius: CGFloat = 8

    var body: some View {
        AsyncImage(url: URL(string: urlString)) { phase in
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
