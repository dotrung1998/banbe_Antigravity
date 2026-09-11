import SwiftUI

/// The web app's "warm paper" palette (src/index.css's light `:root`
/// tokens — --bb-bg/--bb-fg) ported directly so event cards read the same
/// on iOS as they do on web, instead of falling back to system colors.
/// Light-mode only for now — the web app also has a dark palette
/// (`--bb-bg: #14120E` etc.) and a toggle for it; that's future work here.
enum BanbeTheme {
    static let paper = Color(hex: 0xF7F4EC)
    static let ink = Color(hex: 0x1B1916)
    static let rule = Color(hex: 0x1B1916).opacity(0.16)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
