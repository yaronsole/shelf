import SwiftUI

/// Compact row for a saved book on the Shelf tab.
/// Tap opens the book detail. Reading context is retained; actions live on the detail.
struct ReadingListCardView: View {
    let item: ReadingListItem
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: 12) {
                BookCoverView(url: item.coverURL, width: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(Color(.label))
                        .lineLimit(2)
                    if item.isUpNext {
                        Label("Up next", systemImage: "pin.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(hexString: "4D3388"))
                    }
                    Text(item.author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if !item.becauseOf.isEmpty {
                        Text("Because you loved \(item.becauseOf)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View details for \(item.title)")
    }
}
