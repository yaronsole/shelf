import SwiftUI

/// Canonical book cover render. Every cover in the app uses this view.
///
/// Two construction modes:
///   - Fixed width:  `BookCoverView(url: ..., width: 60)` → 60 × 90, cornerRadius 4
///   - Flexible:     `BookCoverView(url: ...)` → fills container width at 2:3
///                   (same 1.5× ratio; cell width is determined by the parent grid)
///
/// Rule: call sites never set `.frame`/`.aspectRatio`/`.cornerRadius` on a cover.
/// All cover dimensions flow from this component.
struct BookCoverView: View {
    let url: String
    let width: CGFloat?  // nil → fill the container at 2:3

    init(url: String, width: CGFloat) {
        self.url = url
        self.width = width
    }

    init(url: String) {
        self.url = url
        self.width = nil
    }

    var body: some View {
        Group {
            if let w = width {
                imageContainer
                    .frame(width: w, height: w * 1.5)
            } else {
                imageContainer
                    .aspectRatio(2/3, contentMode: .fit)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var imageContainer: some View {
        Rectangle()
            .fill(Color(.secondarySystemFill))
            .overlay {
                AsyncImage(url: hiResURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty, .failure:
                        Image(systemName: "book.closed")
                            .font(.title2)
                            .foregroundStyle(Color(.tertiaryLabel))
                    @unknown default:
                        Color.clear
                    }
                }
            }
    }

    private var hiResURL: URL? {
        let upgraded = url
            .replacingOccurrences(of: "&zoom=1", with: "&zoom=3")
            .replacingOccurrences(of: "?zoom=1", with: "?zoom=3")
        return URL(string: upgraded)
    }
}
