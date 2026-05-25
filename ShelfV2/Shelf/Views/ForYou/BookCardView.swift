import SwiftUI

struct BookCardView: View {
    let rec: CachedRecommendation
    var onSave: () -> Void
    var onDismiss: () -> Void
    var onAlreadyRead: (Bool) -> Void  // true = loved it, false = didn't like it

    @State private var showAlreadyReadSheet = false
    @State private var isRemoving = false

    // Plan-spec: hero cover width = min(screenWidth × 0.45, 180).
    // Using UIScreen avoids a body-root GeometryReader that would collapse
    // intrinsic-height layout inside the parent LazyVStack.
    private var heroWidth: CGFloat {
        min(UIScreen.main.bounds.width * 0.45, 180)
    }

    var body: some View {
        VStack(spacing: 16) {
            // 1. Hero cover, centered
            BookCoverView(url: rec.coverURL, width: heroWidth)
                .padding(.top, 24)

            // 2. Title + author + era (centered)
            VStack(spacing: 4) {
                Text(rec.title)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(rec.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !rec.era.isEmpty {
                    Text(rec.era)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)

            // 3. NYT bestseller / reading time context (kept; useful signal)
            ContextRow(
                nytBestseller: rec.nytBestseller,
                nytWeeks: rec.nytWeeksOnList,
                readingTimeMinutes: rec.readingTimeMinutes
            )
            .padding(.horizontal, 16)

            // 4. Genre + comfort-zone pills + award badges (awards styled distinctly per 5.3)
            FlowingTags(
                genre: rec.genre,
                isComfortZonePush: rec.isComfortZonePush,
                awards: rec.awards
            )
            .padding(.horizontal, 16)

            // 5. "✦ Because you loved [seed]" — falls back to contextTag if no
            //    attribution. Mutually exclusive so the slot stays visually quiet.
            if !rec.becauseOf.isEmpty {
                Label("Because you loved \(rec.becauseOf)", systemImage: "sparkle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(red: 0.30, green: 0.20, blue: 0.55))
                    .padding(.horizontal, 16)
            } else if !rec.contextTag.isEmpty {
                Label(rec.contextTag, systemImage: "sparkle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color(red: 0.30, green: 0.20, blue: 0.55))
                    .padding(.horizontal, 16)
            }

            // 6. Blurb
            Text(rec.blurb)
                .font(.subheadline)
                .foregroundStyle(Color(.label))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
                .padding(.horizontal, 16)

            // 7. CTA row — Save dominant, ✓/✕ icon squares
            CTARow(
                onSave: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        isRemoving = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onSave() }
                },
                onAlreadyRead: { showAlreadyReadSheet = true },
                onPass: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        isRemoving = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onDismiss() }
                }
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
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

// MARK: - Context Row (NYT + reading time only — awards moved to FlowingTags)

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
                if nytBestseller {
                    NYTBadge(weeks: nytWeeks)
                }
                if let mins = readingTimeMinutes, mins > 0 {
                    ReadingTimeBadge(minutes: mins)
                }
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

// MARK: - Flowing Tags (genre + comfort-zone + awards in one row)

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

// MARK: - Award Badge (Phase 5 amber styling — visually distinct from genre tags)

struct AwardBadge: View {
    let text: String

    // Plan 5.3: amber background (#FAEEDA), amber-800 text (#633806), 🏆 leading.
    private static let amberBackground = Color(red: 0xFA / 255.0, green: 0xEE / 255.0, blue: 0xDA / 255.0)
    private static let amberText = Color(red: 0x63 / 255.0, green: 0x38 / 255.0, blue: 0x06 / 255.0)

    private var shortLabel: String {
        // Strip "Prize"/"Award" suffix for compactness
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

// MARK: - Tag (genre / comfort-zone pill)

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

// MARK: - CTA Row (Save dominant + ✓/✕ icon squares)

private struct CTARow: View {
    let onSave: () -> Void
    let onAlreadyRead: () -> Void
    let onPass: () -> Void

    private let iconSquareSize: CGFloat = 38

    var body: some View {
        // Plan 5.2: Save takes ~⅔ width (fills available space via maxWidth: .infinity),
        // ✓ and ✕ are 38pt squares so labels never wrap regardless of locale.
        HStack(spacing: 8) {
            Button(action: onSave) {
                HStack(spacing: 6) {
                    Image(systemName: "bookmark.fill")
                        .font(.subheadline.weight(.semibold))
                    Text("Save")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: iconSquareSize)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(red: 0.10, green: 0.35, blue: 0.85))
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Save")

            Button(action: onAlreadyRead) {
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(red: 0.10, green: 0.45, blue: 0.30))
                    .frame(width: iconSquareSize, height: iconSquareSize)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color(red: 0.10, green: 0.45, blue: 0.30), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Already read")

            Button(action: onPass) {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.label))
                    .frame(width: iconSquareSize, height: iconSquareSize)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color(.separator), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pass")
        }
    }
}
