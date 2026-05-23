import SwiftUI

// MARK: - REG-04: Shared badge component — ALWAYS use this, never inline capsule styling
// Badge color = accent color (not hardcoded yellow/orange)

struct AwardBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.15))
            .foregroundStyle(Color.accentColor)
            .clipShape(Capsule())
    }
}

struct BadgeRow: View {
    let badges: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(badges, id: \.self) { badge in
                    AwardBadge(text: badge)
                }
            }
        }
    }
}
