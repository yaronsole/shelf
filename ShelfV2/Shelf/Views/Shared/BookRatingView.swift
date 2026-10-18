import SwiftUI

/// Optional book metadata. Loading and failure deliberately occupy no space.
struct BookRatingView: View {
    let rating: BookRatingDTO
    @State private var showSource = false

    var body: some View {
        Group {
            if rating.isDisplayable() {
                Button { showSource = true } label: {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) {
                            RatingStars(score: rating.score)
                            scoreAndInfo
                        }
                        VStack(spacing: 4) {
                            RatingStars(score: rating.score)
                            scoreAndInfo
                        }
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 8)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(rating.score.formatted(.number.precision(.fractionLength(1)))) out of 5 stars")
                .accessibilityHint("Shows rating source")
                .popover(isPresented: $showSource) {
                    Text("Ratings from Hardcover")
                        .font(.subheadline)
                        .padding(20)
                        .presentationCompactAdaptation(.popover)
                }
            }
        }
    }

    private var scoreAndInfo: some View {
        HStack(spacing: 6) {
            Text(rating.score, format: .number.precision(.fractionLength(1)))
                .monospacedDigit()
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Clip each star separately so the gaps never count toward the rating.
private struct RatingStars: View {
    let score: Double

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5) { index in
                Image(systemName: "star")
                    .foregroundStyle(.secondary)
                    .overlay {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.primary)
                            .mask {
                                GeometryReader { geometry in
                                    Rectangle()
                                        .frame(width: geometry.size.width * min(max(score - Double(index), 0), 1))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                    }
            }
        }
        .accessibilityHidden(true)
    }
}
