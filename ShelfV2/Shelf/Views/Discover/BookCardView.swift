import SwiftUI

struct BookCardView: View {
    let rec: CachedRecommendation
    var onSave: () -> Void
    var onDismiss: () -> Void
    var onAlreadyRead: (Bool) -> Void  // true = loved it, false = didn't like it

    @State private var showAlreadyReadSheet = false
    @State private var isRemoving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cover image — prominent, full width
            CoverImageView(urlString: rec.coverURL, cornerRadius: 0)
                .aspectRatio(3/4, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipped()

            VStack(alignment: .leading, spacing: 12) {
                // Title + Author
                VStack(alignment: .leading, spacing: 3) {
                    Text(rec.title)
                        .font(.title3.bold())
                        .fixedSize(horizontal: false, vertical: true)

                    Text(rec.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Tags row
                HStack(spacing: 6) {
                    TagView(text: rec.genre)
                    TagView(text: rec.era)
                    if rec.isComfortZonePush {
                        TagView(text: Strings.Discover.comfortZoneLabel, isHighlighted: true)
                    }
                }

                // Blurb — always fully visible, never truncated (DISC-05)
                Text(rec.blurb)
                    .font(.subheadline)
                    .foregroundStyle(Color(.label))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)

                // Action buttons (DISC-08)
                HStack(spacing: 10) {
                    ActionButton(
                        label: Strings.Discover.Actions.save,
                        icon: "bookmark",
                        style: .primary,
                        action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                isRemoving = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onSave() }
                        }
                    )
                    ActionButton(
                        label: Strings.Discover.Actions.alreadyRead,
                        icon: "checkmark.circle",
                        style: .secondary,
                        action: { showAlreadyReadSheet = true }
                    )
                    ActionButton(
                        label: Strings.Discover.Actions.dismiss,
                        icon: "xmark",
                        style: .secondary,
                        action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                isRemoving = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onDismiss() }
                        }
                    )
                }
                .padding(.top, 4)
            }
            .padding(16)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.07), radius: 12, x: 0, y: 4)
        .opacity(isRemoving ? 0 : 1)
        .scaleEffect(isRemoving ? 0.96 : 1)
        .sheet(isPresented: $showAlreadyReadSheet) {
            AlreadyReadSheet(
                title: rec.title,
                onLoved: { onAlreadyRead(true) },
                onDidntLike: { onAlreadyRead(false) }
            )
        }
    }
}

// MARK: - Tag

private struct TagView: View {
    let text: String
    var isHighlighted: Bool = false

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(isHighlighted ? Color(.systemOrange) : Color(.secondaryLabel))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isHighlighted
                          ? Color(.systemOrange).opacity(0.12)
                          : Color(.secondarySystemFill))
            )
    }
}

// MARK: - Action Button

private enum ActionButtonStyle { case primary, secondary }

private struct ActionButton: View {
    let label: String
    let icon: String
    let style: ActionButtonStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                Text(label)
                    .font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: style == .primary ? .infinity : nil)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(style == .primary
                          ? Color(.label)
                          : Color(.secondarySystemFill))
            )
            .foregroundStyle(style == .primary ? Color(.systemBackground) : Color(.label))
        }
        .buttonStyle(.plain)
    }
}
