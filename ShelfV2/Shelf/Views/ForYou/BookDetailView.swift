import SwiftUI

/// Full-screen detail sheet for a recommendation.
/// Triggered by a single tap on a For You card.
/// Three equal-weight pill CTAs at the bottom: pass / save / read it.
struct BookDetailView: View {
    let rec: CachedRecommendation
    var onSave: () -> Void
    var onPass: () -> Void
    var onReadIt: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Cover
                    BookCoverView(url: rec.coverURL, width: min(UIScreen.main.bounds.width * 0.45, 180))
                        .padding(.top, 24)

                    // Title + author + era
                    VStack(spacing: 4) {
                        Text(rec.title)
                            .font(.title3.bold())
                            .multilineTextAlignment(.center)
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

                    // Context row (NYT + reading time)
                    ContextRow(
                        nytBestseller: rec.nytBestseller,
                        nytWeeks: rec.nytWeeksOnList,
                        readingTimeMinutes: rec.readingTimeMinutes
                    )
                    .padding(.horizontal, 16)

                    // Genre + comfort-zone + awards
                    FlowingTagsDetail(
                        genre: rec.genre,
                        isComfortZonePush: rec.isComfortZonePush,
                        awards: rec.awards
                    )
                    .padding(.horizontal, 16)

                    // "Because you loved X"
                    if !rec.becauseOf.isEmpty {
                        Label("Because you loved \(rec.becauseOf)", systemImage: "sparkle")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color(hexString: "4D3388"))
                            .padding(.horizontal, 16)
                    } else if !rec.contextTag.isEmpty {
                        Label(rec.contextTag, systemImage: "sparkle")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color(hexString: "4D3388"))
                            .padding(.horizontal, 16)
                    }

                    // Full blurb — no truncation per spec §8
                    Text(rec.blurb)
                        .font(.subheadline)
                        .foregroundStyle(Color(.label))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(3)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 120) // clearance for bottom pill bar
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color(.secondaryLabel))
                            .font(.title3)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                ctaBar
            }
        }
    }

    // MARK: - 3-pill CTA bar (H3 layout — §8)

    private var ctaBar: some View {
        HStack(spacing: 6) {
            // Pass pill
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

            // Save pill (hero — dark background)
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

            // Read it pill
            Button {
                Haptics.light()
                onReadIt()
                dismiss()
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

// MARK: - Flowing tags (local copy for detail view — same as BookCardView)

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
