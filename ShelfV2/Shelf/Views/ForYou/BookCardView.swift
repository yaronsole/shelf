import SwiftUI

struct BookCardView: View {
    let display: BookDisplay
    var onTap: () -> Void    // open detail sheet
    var onSave: () -> Void   // long press — save directly
    /// With both set, the card shows the detail page's pass / save / read it row.
    var onPass: (() -> Void)? = nil
    var onSentiment: ((Bool) -> Void)? = nil

    @State private var isRemoving = false
    @State private var askingSentiment = false

    // Back-compat: accept a CachedRecommendation directly.
    init(rec: CachedRecommendation, onTap: @escaping () -> Void, onSave: @escaping () -> Void,
         onPass: (() -> Void)? = nil, onSentiment: ((Bool) -> Void)? = nil) {
        self.display = BookDisplay(from: rec)
        self.onTap = onTap
        self.onSave = onSave
        self.onPass = onPass
        self.onSentiment = onSentiment
    }

    init(display: BookDisplay, onTap: @escaping () -> Void, onSave: @escaping () -> Void,
         onPass: (() -> Void)? = nil, onSentiment: ((Bool) -> Void)? = nil) {
        self.display = display
        self.onTap = onTap
        self.onSave = onSave
        self.onPass = onPass
        self.onSentiment = onSentiment
    }

    var body: some View {
        // The same header the detail page shows above its Overview, then (in the
        // feed) the same three actions as the detail page's bottom bar.
        VStack(spacing: 14) {
            BookHeaderSection(display: display, showSeeMore: true)
            if let onPass, let onSentiment {
                actionRow(onPass: onPass, onSentiment: onSentiment)
                    .padding(.horizontal, 16)
            }
        }
            .padding(.bottom, onPass == nil ? 20 : 16)
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

    private func actionRow(onPass: @escaping () -> Void, onSentiment: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 6) {
            Button {
                Haptics.light()
                animateRemoval { onPass() }
            } label: {
                ActionPillLabel(iconName: "xmark", iconColor: Color(hexString: "A32D2D"),
                          label: "pass", labelColor: Color(hexString: "444444"),
                          background: .white, hasBorder: true)
            }
            .buttonStyle(.plain)

            Button {
                Haptics.medium()
                animateRemoval { onSave() }
            } label: {
                ActionPillLabel(iconName: "bookmark.fill", iconColor: .white,
                          label: "save", labelColor: .white,
                          background: Color(hex: 0x1A1A1A), hasBorder: false)
            }
            .buttonStyle(.plain)

            Button {
                Haptics.light()
                askingSentiment = true
            } label: {
                ActionPillLabel(iconName: "checkmark", iconColor: Color(hexString: "3B6D11"),
                          label: "read it", labelColor: Color(hexString: "444444"),
                          background: .white, hasBorder: true)
            }
            .buttonStyle(.plain)
        }
        .confirmationDialog("did you like it?", isPresented: $askingSentiment, titleVisibility: .visible) {
            Button("loved it") { animateRemoval { onSentiment(true) } }
            Button("not for me") { animateRemoval { onSentiment(false) } }
        } message: {
            Text(display.title)
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

// MARK: - Book header (shared by the For You card and the detail page)

/// Everything about a book above the detail page's Overview, rendered the same
/// on the feed card and in BookDetailView: cover, title and author, reading time
/// and NYT badge, one row of tags and credentials (genre, stretch pick, awards,
/// accolades), the "Because you loved X — why" line, the description, and a
/// review quote. The detail page passes the structured overview's quote and
/// accolades as a fill-in for books that carry none of their own.
struct BookHeaderSection: View {
    let display: BookDisplay
    var fillQuote: (text: String, source: String)? = nil
    var fillAccolades: [String] = []
    /// The feed card ends the description with an inline "See more" (the whole
    /// card opens the detail page), so the cue costs no extra line.
    var showSeeMore: Bool = false

    private var quoteText: String { display.quote.isEmpty ? (fillQuote?.text ?? "") : display.quote }
    private var quoteSource: String { display.quote.isEmpty ? (fillQuote?.source ?? "") : display.quoteSource }

    private var accolades: [String] {
        let base = display.accolades.isEmpty ? fillAccolades : display.accolades
        // Drop accolades a badge already shows: an award with a trophy chip, or a
        // plain NYT bestseller line when the NYT badge is on.
        let awardKeys = display.awards.map {
            $0.lowercased().replacingOccurrences(of: " prize", with: "").replacingOccurrences(of: " award", with: "")
        }
        return base.filter { a in
            let l = a.lowercased()
            if display.nytBestseller && (l == "new york times bestseller" || l == "nyt bestseller") { return false }
            return !awardKeys.contains { !$0.isEmpty && l.contains($0) }
        }
    }

    private var descriptionLine: Text {
        let text = Text(display.descriptionText)
        guard showSeeMore else { return text }
        return text + Text("  See more")
            .font(.subheadline.weight(.semibold))
            .foregroundColor(Color(hexString: "4D3388"))
    }

    private var becauseLine: String {
        display.becauseOfReason.isEmpty
            ? "Because you loved \(display.becauseOf)"
            : "Because you loved \(display.becauseOf) — \(display.becauseOfReason)"
    }

    var body: some View {
        VStack(spacing: 16) {
            BookCoverView(url: display.coverURL, width: min(UIScreen.main.bounds.width * 0.45, 180))
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

            CredentialFlow(
                genre: display.genre,
                isComfortZonePush: display.isComfortZonePush,
                awards: display.awards,
                accolades: accolades
            )
            .padding(.horizontal, 16)

            if !display.becauseOf.isEmpty {
                Label(becauseLine, systemImage: "sparkle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(hexString: "4D3388"))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            } else if !display.contextTag.isEmpty {
                Label(display.contextTag, systemImage: "sparkle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color(hexString: "4D3388"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            }

            if !display.descriptionText.isEmpty {
                descriptionLine
                    .font(.subheadline)
                    .foregroundStyle(Color(.label))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            }

            if !quoteText.isEmpty {
                PullQuoteView(text: quoteText, source: quoteSource)
                    .padding(.horizontal, 16)
            }
        }
    }
}

/// A review quote set off with an accent bar: the same treatment in the feed and the PDP.
struct PullQuoteView: View {
    let text: String
    let source: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hexString: "4D3388"))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 5) {
                Text("“\(text)”")
                    .font(.callout)
                    .italic()
                    .foregroundStyle(Color(.label))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if !source.isEmpty {
                    Text("— \(source)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Credentials row

/// Genre, stretch pick, awards, and accolades in one wrapping row, so a book's
/// credentials always sit in the same place.
private struct CredentialFlow: View {
    let genre: String
    let isComfortZonePush: Bool
    let awards: [String]
    let accolades: [String]

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            if !genre.isEmpty { TagView(text: genre) }
            if isComfortZonePush {
                TagView(text: Strings.ForYou.comfortZoneLabel, isHighlighted: true)
            }
            ForEach(awards, id: \.self) { AwardBadge(text: $0) }
            ForEach(accolades, id: \.self) { AwardBadge(text: $0, icon: "rosette", shorten: false) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Lays chips out left to right, wrapping onto new lines.
private struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + lineSpacing
                x = 0
                rowHeight = 0
            }
            widest = max(widest, x + size.width)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + lineSpacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: size.width, height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Award Badge

struct AwardBadge: View {
    let text: String
    var icon: String = "trophy.fill"
    /// Awards drop "Prize"/"Award" ("Pulitzer"); accolades keep their full wording.
    var shorten: Bool = true

    private static let amberBackground = Color(hex: 0xFAEEDA)
    private static let amberText = Color(hex: 0x633806)

    private var label: String {
        guard shorten else { return text }
        return text
            .replacingOccurrences(of: " Prize", with: "")
            .replacingOccurrences(of: " Award", with: "")
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
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
