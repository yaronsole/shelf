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
            // Cover image — prominent, full width. Phase 5 will re-design this card around a centered hero.
            BookCoverView(url: rec.coverURL)

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

                // Context row: NYT bestseller · reading time · awards
                ContextRow(
                    nytBestseller: rec.nytBestseller,
                    nytWeeks: rec.nytWeeksOnList,
                    readingTimeMinutes: rec.readingTimeMinutes,
                    awards: rec.awards
                )

                // Editorial context — single sparkle line with a cultural hook
                if !rec.contextTag.isEmpty {
                    Label(rec.contextTag, systemImage: "sparkle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color(red: 0.30, green: 0.20, blue: 0.55))
                }

                // Tags row
                HStack(spacing: 6) {
                    TagView(text: rec.genre)
                    TagView(text: rec.era)
                    if rec.isComfortZonePush {
                        TagView(text: Strings.ForYou.comfortZoneLabel, isHighlighted: true)
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

// MARK: - Context Row (NYT + reading time + awards)

struct ContextRow: View {
    let nytBestseller: Bool
    let nytWeeks: Int?
    let readingTimeMinutes: Int?
    let awards: [String]

    private var hasAnyContent: Bool {
        nytBestseller || readingTimeMinutes != nil || !awards.isEmpty
    }

    var body: some View {
        if hasAnyContent {
            HStack(spacing: 8) {
                if nytBestseller {
                    NYTBadge(weeks: nytWeeks)
                }
                if let mins = readingTimeMinutes, mins > 0 {
                    ReadingTimeBadge(minutes: mins)
                }
                ForEach(awards, id: \.self) { AwardBadge(text: $0) }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct NYTBadge: View {
    let weeks: Int?

    private var label: String {
        guard let w = weeks, w > 0 else { return "NYT Bestseller" }
        let weekWord = w == 1 ? "wk" : "wks"
        return "NYT Bestseller · \(w) \(weekWord) on list"
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.caption2.weight(.bold))
            Text(label)
                .font(.caption2.weight(.bold))
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .foregroundStyle(.white)
        .background(Capsule().fill(Color(red: 0.10, green: 0.10, blue: 0.10)))
    }
}

private struct ReadingTimeBadge: View {
    let minutes: Int
    private var label: String {
        if minutes < 60 { return "\(minutes) min" }
        let h = Double(minutes) / 60
        return h < 10 ? String(format: "~%.1fh read", h) : "~\(Int(h.rounded()))h read"
    }
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "clock")
                .font(.caption2)
            Text(label)
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .foregroundStyle(Color(.secondaryLabel))
        .background(Capsule().fill(Color(.secondarySystemFill)))
    }
}

// MARK: - Award Badge

struct AwardBadge: View {
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
        case .tertiary: return Color(.label)
        }
    }

    private var background: Color {
        switch kind {
        case .primary: return Color(red: 0.10, green: 0.35, blue: 0.85)
        case .secondary: return Color(red: 0.10, green: 0.45, blue: 0.30).opacity(0.12)
        case .tertiary: return .clear
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
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                kind == .tertiary ? Color(.separator) : .clear,
                                lineWidth: 1
                            )
                    )
            )
            .foregroundStyle(foreground)
        }
        .buttonStyle(.plain)
    }
}
