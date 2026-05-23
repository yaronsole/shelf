import SwiftUI
import SwiftData

struct WishlistView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WishlistItem.savedDate, order: .reverse) private var items: [WishlistItem]
    @State private var alreadyReadItem: WishlistItem?

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView(
                        "Your wishlist is empty",
                        systemImage: "bookmark",
                        description: Text("Save books from the Discover tab to find them later")
                    )
                } else {
                    List {
                        ForEach(items) { item in
                            WishlistRow(item: item, onBought: {
                                Task { await logPurchase(item: item) }
                            })
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                // Delete
                                Button(role: .destructive) {
                                    modelContext.delete(item)
                                    try? modelContext.save()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                // Mark as Read
                                Button {
                                    alreadyReadItem = item
                                } label: {
                                    Label("Read", systemImage: "checkmark.circle")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Wishlist")
            .sheet(item: $alreadyReadItem) { item in
                WishlistAlreadyReadSheet(item: item) { liked in
                    let type: ReactionType = liked ? .alreadyReadLiked : .alreadyReadDisliked
                    let reaction = Reaction(bookTitle: item.bookTitle, bookAuthor: item.bookAuthor, type: type)
                    modelContext.insert(reaction)
                    try? modelContext.save()
                    alreadyReadItem = nil
                }
                .presentationDetents([.fraction(0.35)])
            }
        }
    }

    private func logPurchase(item: WishlistItem) async {
        let purchase = Purchase(bookTitle: item.bookTitle, bookAuthor: item.bookAuthor)
        modelContext.insert(purchase)
        try? modelContext.save()
        let granted = await NotificationService.shared.requestPermission()
        if granted {
            NotificationService.shared.scheduleFollowUp(for: purchase)
        }
    }
}

// MARK: - Wishlist Row

struct WishlistRow: View {
    let item: WishlistItem
    let onBought: () -> Void

    @State private var showBlurb = false

    // REG-01: Use search URL fallback (same logic as Book.amazonKindleURL)
    var amazonURL: URL? {
        if let asin = item.asin, asin.count == 10, asin.allSatisfy({ $0.isLetter || $0.isNumber }) {
            return URL(string: "https://www.amazon.com/dp/\(asin)")
        }
        if let isbn = item.isbn, !isbn.isEmpty {
            return URL(string: "https://www.amazon.com/s?k=\(isbn)&i=stripbooks")
        }
        let query = "\(item.bookTitle) \(item.bookAuthor)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://www.amazon.com/s?k=\(query)&i=stripbooks")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: item.coverURL ?? "")) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .overlay(Image(systemName: "book").foregroundStyle(.gray))
                }
                .frame(width: 44, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 4))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.bookTitle)
                        .font(.subheadline.bold())
                        .lineLimit(2)
                    Text(item.bookAuthor)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // REG-04: Use shared AwardBadge component (not inline capsule styling)
                    if let badges = item.awardBadges, !badges.isEmpty {
                        BadgeRow(badges: badges)
                    }

                    HStack(spacing: 8) {
                        if let url = amazonURL {
                            Link(destination: url) {
                                Label("Buy on Kindle", systemImage: "cart")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange)
                                    .foregroundColor(.white)
                                    .clipShape(Capsule())
                            }
                        }
                        Button(action: onBought) {
                            Label("I Bought It", systemImage: "checkmark")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.15))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            // Reasoning blurb with More/Less toggle
            if let blurb = item.reasoningBlurb, !blurb.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(blurb)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(showBlurb ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showBlurb.toggle() }
                    } label: {
                        Text(showBlurb ? "Less" : "More")
                            .font(.caption.bold())
                            .foregroundStyle(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Already Read sheet (Wishlist version)

struct WishlistAlreadyReadSheet: View {
    let item: WishlistItem
    let onResponse: (Bool) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("Did you like it?")
                .font(.title2.bold())
            Text("\"\(item.bookTitle)\"")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Button {
                    onResponse(true)
                } label: {
                    Label("Loved it", systemImage: "heart.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Button {
                    onResponse(false)
                } label: {
                    Label("Didn't like it", systemImage: "hand.thumbsdown.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .foregroundColor(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal)
        }
        .padding()
    }
}
