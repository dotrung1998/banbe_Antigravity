import SwiftUI

/// The web app's "warm paper" palettes, ported from src/index.css's
/// `:root` and `[data-bb-theme="dark"]` token sets so both apps render the
/// same two themes from the same values.
struct Palette {
    let paper: Color
    let ink: Color
    let rule: Color
    let field: Color

    static let light = Palette(
        paper: Color(hex: 0xF7F4EC),
        ink: Color(hex: 0x1B1916),
        rule: Color(hex: 0x1B1916).opacity(0.16),
        field: Color(hex: 0xEEE8DA)
    )
    static let dark = Palette(
        paper: Color(hex: 0x14120E),
        ink: Color(hex: 0xF2EDE1),
        rule: Color(hex: 0xF2EDE1).opacity(0.20),
        field: Color(hex: 0x4A4439)
    )
}

enum BanbeTheme {
    /// Warning/destructive accent — the one non-palette colour the web app
    /// uses, for error copy and "Cancel booking".
    static let alert = Color(hex: 0x9A3E2D)

    /// On-photo state chips, the only coloured surfaces in the design
    /// (CHIP_COLORS in src/theme.js).
    enum Chip {
        static let going = Color(hex: 0x485834).opacity(0.74)
        static let cancelled = Color(hex: 0x8C4A30).opacity(0.72)
        static let hold = Color(hex: 0x8C6014).opacity(0.72)
        static let invite = Color(hex: 0x34545E).opacity(0.72)
        static let saved = Color(hex: 0x685430).opacity(0.74)
        static let past = Color(hex: 0x4E483A).opacity(0.70)
    }

    /// Display/title face: the web app uses Jost/Be Vietnam Pro at weight
    /// 600 with tight tracking; rounded system is the closest stock match
    /// without shipping the fonts.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    /// TASK 2 (loading GIF placement pass) — named per-context spacing
    /// around `BanbeLoadingVisual` (Components.swift), since the two call
    /// sites this ticket touches (splash, reservation-hold) need to move in
    /// OPPOSITE directions and must not drag every other
    /// `BanbeLoadingVisual` use (FaceIDLockView, Confirmed/Pulse) along
    /// with them. Both values reserve real layout space (applied via
    /// `.padding`/`VStack(spacing:)`, not a non-reflowing `.offset`), so
    /// the animation's own frame never overlaps the neighboring label.
    enum LoadingVisual {
        /// Gap between the splash tagline and the launch GIF below it
        /// (`OnboardingViews.swift`'s `SplashView`) — was 34, now pushed
        /// down ~14pt so the GIF reads as a distinct element under the
        /// tagline rather than crowding it.
        static let splashGap: CGFloat = 48
        /// Gap between the seat-hold GIF and the "Đang giữ chỗ…" label
        /// below it (`RootView.swift`'s `loadingOverlay`) — was 14, now
        /// ~14pt larger so the GIF's own rotating bounds sit clear above
        /// the text instead of nearly touching it.
        static let reservationGap: CGFloat = 28
    }
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

extension AppState {
    var palette: Palette { theme == "dark" ? .dark : .light }
}
