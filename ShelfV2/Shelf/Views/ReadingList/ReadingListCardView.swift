import SwiftUI

/// Full ForYou-style card for a saved book on the Shelf tab.
/// Tap anywhere = open Amazon deeplink. Swipe-to-delete handled by the parent List.
struct ReadingListCardView: View {
    let item: ReadingListItem
    @Environment(\.openURL) private var openURL

    private var heroWidth: CGFloat {
        min(UIScreen.main.bounds.width * 0.45, 180)
    }

    var body: some View {
        VStack(spacing: 16) {
            // Cover
            BookCoverView(url: item.coverURL, width: heroWidth)
                .padding(.top, 24)

            // Title + author + era
            VStack(spacing: 4) {
                Text(item.title)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !item.era.isEmpty {
                    Text(item.era)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)

            // Context row (NYT + reading time) — omit if both absent
            ContextRow(
                nytBestseller: item.nytBestseller,
                nytWeeks: item.nytWeeksOnList,
                readingTimeMinutes: item.readingTimeMinutes
            )
            .padding(.horizontal, 16)

            // Genre pill — omit if absent
            if !item.genre.isEmpty {
                HStack(spacing: 6) {
                    GenrePill(text: item.genre)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
            }

            // "Because you loved X" — omit if absent
            if !item.becauseOf.isEmpty {
                Label("Because you loved \(item.becauseOf)", systemImage: "sparkle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(hexString: "4D3388"))
                    .padding(.horizontal, 16)
            }

            // Full blurb — no truncation per spec §7
            Text(item.blurb)
                .font(.subheadline)
                .foregroundStyle(Color(.label))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.07), radius: 12, x: 0, y: 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = AmazonLinkService.searchURL(title: item.title, author: item.author) {
                openURL(url)
            }
        }
    }
}

private struct GenrePill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(Color(.secondaryLabel))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color(.secondarySystemFill)))
    }
}
