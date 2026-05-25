import UIKit

/// Tiny façade over UIImpactFeedbackGenerator so call sites stay short and
/// the chosen intensities are documented in one place.
enum Haptics {
    static func light() {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.impactOccurred()
    }

    static func medium() {
        let g = UIImpactFeedbackGenerator(style: .medium)
        g.impactOccurred()
    }
}
