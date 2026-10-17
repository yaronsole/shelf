import SwiftUI

/// Optional book metadata. Loading and failure deliberately occupy no space.
struct BookRatingView: View {
    let rating: BookRatingDTO
    @State private var showSource = false

    var body: some View {
        Group {
            if rating.isDisplayable() {
                Button { showSource = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.secondary)
                        Text(rating.score, format: .number.precision(.fractionLength(1)))
                            .monospacedDigit()
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
}
