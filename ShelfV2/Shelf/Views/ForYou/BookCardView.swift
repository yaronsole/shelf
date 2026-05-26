import SwiftUI

struct BookCardView: View {
    let display: BookDisplay
    var onTap: () -> Void    // open detail sheet
    var onSave: () -> Void   // long press — save directly

    @State private var isRemoving = false

    // Back-compat: accept a CachedRecommendation directly.
    init(rec: CachedRecommendation, onTap: @escaping () -> Void, onSave: @escaping () -> Void) {
        self.display = BookDisplay(from: rec)
        self.onTap = onTap
        self.onSave = onSave
    }

    init(display: BookDisplay, onTap: @escaping () -> Void, onSave: @escaping () -> Void) {
        self.display = display
        self.onTap = onTap
        self.onSave = onSave
    }

    private var heroWidth: CGFloat {
        min(UIScreen.main.bounds.width * 0.45, 180)
    }

    var body: some View {
        VStack(spacing: 16) {
            BookCoverView(url: display.coverURL, width: heroWidth)
                .padding(.top, 24)

            VStack(spacing: 4) {
                Text(display.title)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(display.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !display.era.isEmpty {
                    Text(display.era)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)

            ContextRow(
                nytBestseller: display.nytBestseller,
                nytWeeks: display.nytWeeksOnList,
                readingTimeMinutes: display.readingTimeMinutes
            )
            .padding(.horizontal, 16)

            FlowingTags(
                genre: display.genre,
                isComfortZonePush: display.isComfortZonePush,
                awards: display.awards
            )
            .padding(.horizontal, 16)

            if !display.becauseOf.isEmpty {
                Label("Because you loved \(display.becauseOf)", systemImage: "sparkle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(red: 0.30, green: 0.20, blue: 0.55))
                    .padding(.horizontal, 16)
            } else if !display.contextTag.isEmpty {
                Label(display.contextTag, systemImage: "sparkle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color(red: 0.30, green: 0.20, blue: 0.55))
                    .padding(.horizontal, 16)
            }

            Text(display.blurb)
                .font(.subheadline)
                .foregroundStyle(Color(.label))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
                .padding(.horizontal, 16)

            // Gesture hint label
            Text("tap · long press")
                .font(.caption2)
                .foregroundStyle(Color(.tertiaryLabel))
                .padding(.bottom, 16)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.07), radius: 12, x: 0, y: 4)
        .opacity(isRemoving ? 0 : 1)
        .scaleEffect(isRemoving ? 0.96 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture(minimumDuration: 0.45) {
            Haptics.medium()
            animateRemoval { onSave() }
        }
    }

    private func animateRemoval(then action: @escaping () -> Void) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            isRemoving = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { action() }
    }
}

// MARK: - Context Row

struct ContextRow: View {
    let nytBestseller: Bool
    let nytWeeks: Int?
    let readingTimeMinutes: Int?

    private var hasAnyContent: Bool {
        nytBestseller || (readingTimeMinutes ?? 0) > 0
    }

    var body: some View {
        if hasAnyContent {
            HStack(spacing: 8) {
                if nytBestseller { NYTBadge(weeks: nytWeeks) }
                if let mins = readingTimeMinutes, mins > 0 { ReadingTimeBadge(minutes: mins) }
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

// MARK: - Flowing Tags

private struct FlowingTags: View {
    let genre: String
    let isComfortZonePush: Bool
    let awards: [String]

    var body: some View {
        HStack(spacing: 6) {
            if !genre.isEmpty { TagView(text: genre) }
            if isComfortZonePush {
                TagView(text: Strings.ForYou.comfortZoneLabel, isHighlighted: true)
            }
            ForEach(awards, id: \.self) { AwardBadge(text: $0) }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Award Badge

struct AwardBadge: View {
    let text: String

    private static let amberBackground = Color(hex: 0xFAEEDA)
    private static let amberText = Color(hex: 0x633806)

    private var shortLabel: String {
        text
            .replacingOccurrences(of: " Prize", with: "")
            .replacingOccurrences(of: " Award", with: "")
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "trophy.fill")
                .font(.caption2)
            Text(shortLabel)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .foregroundStyle(Self.amberText)
        .background(Capsule().fill(Self.amberBackground))
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
