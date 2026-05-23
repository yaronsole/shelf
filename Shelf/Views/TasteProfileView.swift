import SwiftUI

// MARK: - TasteProfileView
// Shows an evolving one-line read on the user's taste.
// Appears in Settings after 5+ total reactions.

struct TasteProfileView: View {
    @Environment(MilestoneManager.self) var milestones

    private var profileText: String {
        let vibeLabels = UserDefaults.standard.stringArray(forKey: "selectedVibeLabels") ?? []
        return generateTasteProfile(
            vibeLabels: vibeLabels,
            totalLikes: milestones.totalLikes,
            totalPasses: milestones.totalPasses
        )
    }

    var body: some View {
        if milestones.totalReactions >= 5 {
            VStack(spacing: 6) {
                Text("SHELF'S READ ON YOU")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(1.5)

                Text(profileText)
                    .font(.custom("Georgia", size: 15)).italic()
                    .foregroundStyle(Color(hex: "D4AF37"))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(Color(hex: "2C2C2E"))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        }
    }

    // MARK: - Generation Logic

    private func generateTasteProfile(vibeLabels: [String], totalLikes: Int, totalPasses: Int) -> String {
        let total = totalLikes + totalPasses
        guard total >= 5 else {
            return "Keep reacting to books — Shelf is building your profile."
        }

        let likeRate = total > 0 ? Double(totalLikes) / Double(total) : 0.5
        let isPicky  = likeRate < 0.4
        let isEager  = likeRate > 0.65

        if vibeLabels.count >= 3 {
            let a = vibeLabels[0].lowercased()
            let b = vibeLabels[1].lowercased()
            return "You contain multitudes — \(a) one day, \(b) the next."
        }

        if let dominant = vibeLabels.first {
            let base = "You gravitate toward \(dominant.lowercased())"
            if isEager  { return base + ", and you know what you love when you see it." }
            if isPicky  { return base + ", and you're not afraid to be picky." }
            return base + "."
        }

        if isEager  { return "You know what you love and you're not shy about it." }
        if isPicky  { return "High standards. Shelf respects it." }
        return "Your taste is taking shape. Keep going."
    }
}
