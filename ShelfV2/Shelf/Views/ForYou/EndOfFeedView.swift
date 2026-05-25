import SwiftUI

struct EndOfFeedView: View {
    let taglineIndex: Int
    var isLoading: Bool
    var onLoadMore: () -> Void

    private var pair: (witty: String, cta: String) {
        let taglines = Strings.ForYou.endOfFeedTaglines
        return taglines[taglineIndex % taglines.count]
    }

    var body: some View {
        VStack(spacing: 16) {
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 1)
                .padding(.horizontal, 40)

            Image(systemName: "books.vertical")
                .font(.system(size: 32))
                .foregroundStyle(Color(.tertiaryLabel))

            Text(pair.witty)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button(action: onLoadMore) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                } else {
                    Text(pair.cta)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                }
            }
            .buttonStyle(.bordered)
            .disabled(isLoading)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}
