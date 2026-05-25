import SwiftUI

extension Color {
    /// Parse a hex int: `Color(hex: 0xFAEEDA)`. Alpha = 1.
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    /// Parse a hex string with or without leading `#`. Returns gray on parse failure.
    init(hexString: String) {
        var sanitized = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.hasPrefix("#") { sanitized.removeFirst() }
        guard sanitized.count == 6, let value = UInt32(sanitized, radix: 16) else {
            self.init(.gray)
            return
        }
        self.init(hex: value)
    }
}
