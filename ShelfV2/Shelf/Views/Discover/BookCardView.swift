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

                // Rating (only if at least 500 ratings — Google Books data is noisy below that)
                // + Awards
                let hasRating = (rec.averageRating != nil) && ((rec.ratingsCount ?? 0) >= 500)
                if hasRating || !rec.awards.isEmpty {
                    HStack(spacing: 10) {
                        if hasRating, let r = rec.averageRating, let count = rec.ratingsCount {
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.yellow)
                                Text(String(format: "%.1f", r))
                                    .font(.caption.weight(.semibold))
                                Text("(\(count.formatted(.number.notation(.compactName))))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ForEach(rec.awards, id: \.self) { award in
                            AwardBadge(text: award)
                        }
                        Spacer()
                    }
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

                // Action buttons (DISC-08) — primary Save, secondary Read, tertiary Pass
                HStack(spacing: 8) {
                    ActionButton(
                        label: "Save",
                        icon: "bookmark.fill",
                        kind: .primary,
                        action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                isRemoving = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onSave() }
                        }
                    )
                    ActionButton(
                        label: "Read",
                        icon: "checkmark",
                        kind: .secondary,
                        action: { showAlreadyReadSheet = true }
                    )
                    ActionButton(
                        label: "Pass",
                        icon: "xmark",
                        kind: .tertiary,
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

// MARK: - Award Badge

private struct AwardBadge: View {
    let text: String

    // Map known award names to short labels + colors for visual variety
    private var icon: String { "rosette" }
    private var tint: Color {
        let lower = text.lowercased()
        if lower.contains("pulitzer") { return Color(red: 0.65, green: 0.50, blue: 0.10) }
        if lower.contains("booker") { return Color(red: 0.40, green: 0.20, blue: 0.50) }
        if lower.contains("national book") { return Color(red: 0.20, green: 0.40, blue: 0.30) }
        if lower.contains("hugo") || lower.contains("nebula") {
            return Color(red: 0.20, green: 0.30, blue: 0.55)
        }
        return Color(red: 0.45, green: 0.30, blue: 0.10)
    }

    private var shortLabel: String {
        // Strip "Prize"/"Award" suffix for compactness in the card
        text
            .replacingOccurrences(of: " Prize", with: "")
            .replacingOccurrences(of: " Award", with: "")
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
            Text(shortLabel)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .foregroundStyle(tint)
        .background(
            Capsule().fill(tint.opacity(0.12))
        )
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

private enum ActionButtonKind { case primary, secondary, tertiary }

private struct ActionButton: View {
    let label: String
    let icon: String
    let kind: ActionButtonKind
    let action: () -> Void

    private var foreground: Color {
        switch kind {
        case .primary: return .white
        case .secondary: return Color(red: 0.10, green: 0.45, blue: 0.30)
        case .tertiary: return Color(.tertiaryLabel)
        }
    }

    private var background: Color {
        switch kind {
        case .primary: return Color(red: 0.10, green: 0.35, blue: 0.85) // accent blue
        case .secondary: return Color(red: 0.10, green: 0.45, blue: 0.30).opacity(0.12) // soft green
        case .tertiary: return Color(.secondarySystemFill) // subtle grey
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                Text(label)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: kind == .primary ? .infinity : nil)
            .padding(.horizontal, kind == .primary ? 14 : 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(background)
            )
            .foregroundStyle(foreground)
        }
        .buttonStyle(.plain)
    }
}
