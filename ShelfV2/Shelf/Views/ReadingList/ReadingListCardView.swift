import SwiftUI

/// Compact row for a saved book on the Shelf tab.
/// Identical layout regardless of save source (For You vs Discover) — no blurb,
/// just cover + title + author. Tap = open Amazon. Swipe-to-delete handled by parent List.
struct ReadingListCardView: View {
    let item: ReadingListItem
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            BookCoverView(url: item.coverURL, width: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(Color(.label))
                    .lineLimit(2)
                Text(item.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = AmazonLinkService.searchURL(title: item.title, author: item.author) {
                openURL(url)
            }
        }
    }
}
