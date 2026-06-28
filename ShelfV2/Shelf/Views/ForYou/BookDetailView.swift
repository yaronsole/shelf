import SwiftUI

// MARK: - BookDisplay — generic data for the detail view

/// Decoupled view-model for BookDetailView so the same UI can render a
/// CachedRecommendation, a CachedSuggestion, or a live SuggestionDTO.
struct BookDisplay {
    let title: String
    let author: String
    let coverURL: String
    let blurb: String
    let era: String
    let genre: String
    let isComfortZonePush: Bool
    let awards: [String]
    let contextTag: String
    let becauseOf: String
    let nytBestseller: Bool
    let nytWeeksOnList: Int?
    let readingTimeMinutes: Int?
    // Phase 3 PDP enrichment
    let becauseOfReason: String
    let bookDescription: String
}

extension BookDisplay {
    init(from rec: CachedRecommendation) {
        self.init(
            title: rec.title, author: rec.author, coverURL: rec.coverURL,
            blurb: rec.blurb, era: rec.era, genre: rec.genre,
            isComfortZonePush: rec.isComfortZonePush, awards: rec.awards,
            contextTag: rec.contextTag, becauseOf: rec.becauseOf,
            nytBestseller: rec.nytBestseller, nytWeeksOnList: rec.nytWeeksOnList,
            readingTimeMinutes: rec.readingTimeMinutes,
            becauseOfReason: rec.becauseOfReason, bookDescription: rec.bookDescription
        )
    }

    init(from s: CachedSuggestion, becauseOf: String) {
        self.init(
            title: s.title, author: s.author, coverURL: s.coverURL,
            blurb: s.blurb, era: s.era, genre: s.genre,
            isComfortZonePush: false, awards: s.awards,
            contextTag: s.contextTag, becauseOf: becauseOf,
            nytBestseller: s.nytBestseller, nytWeeksOnList: s.nytWeeksOnList,
            readingTimeMinutes: s.readingTimeMinutes,
            becauseOfReason: "", bookDescription: s.bookDescription ?? ""
        )
    }

    init(from s: SuggestionDTO, becauseOf: String) {
        self.init(
            title: s.title, author: s.author, coverURL: s.coverURL,
            blurb: s.blurb, era: s.era, genre: s.genre,
            isComfortZonePush: false, awards: s.awards,
            contextTag: s.contextTag, becauseOf: becauseOf,
            nytBestseller: s.nytBestseller, nytWeeksOnList: s.nytWeeksOnList,
            readingTimeMinutes: s.readingTimeMinutes,
            becauseOfReason: "", bookDescription: s.bookDescription
        )
    }
}

// MARK: - BookDetailView

/// Full-screen detail sheet for a book.
/// Triggered by a single tap on a card in For You / SimilarBooks.
/// Three equal-weight pill CTAs at the bottom: pass / save / read it.
struct BookDetailView: View {
    let display: BookDisplay
    var onSave: () -> Void
    var onPass: () -> Void
    /// Called with the user's sentiment after they tap "read it" → "loved it" / "didn't like".
    /// Inlined into this view so we don't have to chain a second sheet (which causes
    /// the white-screen race when SwiftUI dismisses one sheet and presents another).
    var onSentiment: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var inSentimentMode: Bool = false
    @State private var descExpanded: Bool = false

    // Back-compat init that accepts CachedRecommendation directly.
    init(
        rec: CachedRecommendation,
        onSave: @escaping () -> Void,
        onPass: @escaping () -> Void,
        onSentiment: @escaping (Bool) -> Void
    ) {
        self.display = BookDisplay(from: rec)
        self.onSave = onSave
        self.onPass = onPass
        self.onSentiment = onSentiment
    }

    init(
        display: BookDisplay,
        onSave: @escaping () -> Void,
        onPass: @escaping () -> Void,
        onSentiment: @escaping (Bool) -> Void
    ) {
        self.display = display
        self.onSave = onSave
        self.onPass = onPass
        self.onSentiment = onSentiment
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    BookCoverView(url: display.coverURL, width: min(UIScreen.main.bounds.width * 0.45, 180))
                        .padding(.top, 24)

                    VStack(spacing: 4) {
                        Text(display.title)
                            .font(.title3.bold())
                            .multilineTextAlignment(.center)
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

                    FlowingTagsDetail(
                        genre: display.genre,
                        isComfortZonePush: display.isComfortZonePush,
                        awards: display.awards
                    )
                    .padding(.horizontal, 16)

                    if !display.becauseOf.isEmpty {
                        Label(becauseLine, systemImage: "sparkle")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color(hexString: "4D3388"))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                    } else if !display.contextTag.isEmpty {
                        Label(display.contextTag, systemImage: "sparkle")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color(hexString: "4D3388"))
                            .padding(.horizontal, 16)
                    }

                    Text(display.blurb)
                        .font(.subheadline)
                        .foregroundStyle(Color(.label))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)

                    if !display.bookDescription.isEmpty {
                        expandableDescription
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                    }

                    Color.clear.frame(height: 120)   // clears the bottom CTA bar
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: BookShareService.shareText(title: display.title, author: display.author)) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(Color(.secondaryLabel))
                            .font(.title3)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color(.secondaryLabel))
                            .font(.title3)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                primaryCtaBar
            }
            .overlay {
                // Centered modal overlay (no chained sheet → no white-screen race)
                if inSentimentMode {
                    sentimentOverlay
                        .transition(.opacity)
                        .zIndex(50)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: inSentimentMode)
        }
    }

    // MARK: - Phase 3 helpers

    private var becauseLine: String {
        display.becauseOfReason.isEmpty
            ? "Because you loved \(display.becauseOf)"
            : "Because you loved \(display.becauseOf) — \(display.becauseOfReason)"
    }

    private var isDescriptionLong: Bool { display.bookDescription.count > 220 }

    private var expandableDescription: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("OVERVIEW")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.8)
            Text(display.bookDescription)
                .font(.subheadline)
                .foregroundStyle(Color(.secondaryLabel))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
                .lineLimit(descExpanded || !isDescriptionLong ? nil : 4)
            if isDescriptionLong {
                Button(descExpanded ? "Read less" : "Read more") {
                    withAnimation(.easeInOut(duration: 0.2)) { descExpanded.toggle() }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(hexString: "4D3388"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var primaryCtaBar: some View {
        HStack(spacing: 6) {
            Button {
                Haptics.light()
                onPass()
                dismiss()
            } label: {
                PillLabel(iconName: "xmark", iconColor: Color(hexString: "A32D2D"),
                          label: "pass", labelColor: Color(hexString: "444444"),
                          background: .white, hasBorder: true)
            }
            .buttonStyle(.plain)

            Button {
                Haptics.medium()
                onSave()
                dismiss()
            } label: {
                PillLabel(iconName: "bookmark.fill", iconColor: .white,
                          label: "save", labelColor: .white,
                          background: Color(hex: 0x1A1A1A), hasBorder: false)
            }
            .buttonStyle(.plain)

            Button {
                Haptics.light()
                withAnimation { inSentimentMode = true }
            } label: {
                PillLabel(iconName: "checkmark", iconColor: Color(hexString: "3B6D11"),
                          label: "read it", labelColor: Color(hexString: "444444"),
                          background: .white, hasBorder: true)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 24)
        .background(
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    /// Centered modal popup — rendered as an overlay (not a sheet) so it stacks
    /// cleanly over BookDetailView without the SwiftUI sheet-on-sheet race.
    private var sentimentOverlay: some View {
        ZStack {
            // Dimmed backdrop — tap to dismiss
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation { inSentimentMode = false }
                }

            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text("did you like it?")
                        .font(.title3.bold())
                        .foregroundStyle(Color(.label))
                    Text(display.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                VStack(spacing: 10) {
                    Button {
                        Haptics.medium()
                        onSentiment(true)
                        dismiss()
                    } label: {
                        Label("loved it", systemImage: "heart.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(hexString: "D04763"))
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        Haptics.light()
                        onSentiment(false)
                        dismiss()
                    } label: {
                        Label("not for me", systemImage: "hand.thumbsdown")
                            .font(.headline)
                            .foregroundStyle(Color(hexString: "444444"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.white)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .strokeBorder(Color(hexString: "DDDDDD"), lineWidth: 0.5)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 8)
            .padding(.horizontal, 32)
        }
    }
}

// MARK: - Pill button label

private struct PillLabel: View {
    let iconName: String
    let iconColor: Color
    let label: String
    let labelColor: Color
    let background: Color
    let hasBorder: Bool

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(labelColor)
        }
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(background)
                .overlay(
                    hasBorder
                    ? RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color(hexString: "DDDDDD"), lineWidth: 0.5)
                    : nil
                )
        )
    }
}

// MARK: - Flowing tags (local copy for detail view)

private struct FlowingTagsDetail: View {
    let genre: String
    let isComfortZonePush: Bool
    let awards: [String]

    var body: some View {
        HStack(spacing: 6) {
            if !genre.isEmpty { DetailTag(text: genre) }
            if isComfortZonePush { DetailTag(text: Strings.ForYou.comfortZoneLabel, highlighted: true) }
            ForEach(awards, id: \.self) { AwardBadge(text: $0) }
            Spacer(minLength: 0)
        }
    }
}

private struct DetailTag: View {
    let text: String
    var highlighted: Bool = false
    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(highlighted ? Color(.systemOrange) : Color(.secondaryLabel))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(highlighted
                               ? Color(.systemOrange).opacity(0.12)
                               : Color(.secondarySystemFill))
            )
    }
}
