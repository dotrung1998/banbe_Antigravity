import SwiftUI

/// The web app's "warm paper" palettes, ported from src/index.css's
/// `:root` and `[data-bb-theme="dark"]` token sets so both apps render the
/// same two themes from the same values.
struct Palette {
    let paper: Color
    let ink: Color
    let rule: Color
    let field: Color
    /// The "disputed, needs attention, but not an error" pair, for the dispute
    /// section pinned at the top of Messages and its matching entries on the
    /// payment/refund screens. A sibling of `BanbeTheme.alert` (one extra
    /// accent per distinct role), never a reuse of it: alert means something
    /// went wrong, honey means two people are still talking it out. Mirrors
    /// web's `honey`/`honeyBg` (theme.js) and index.css's own note,
    /// value-for-value in both themes.
    let honey: Color
    let honeyBg: Color
    /// Clay — Event Detail's decorative/brand accent (note 52): info-tile icons, outlined pills ("Thêm lịch",
    /// "Nhắn tin"), the seats bar, the host track-record line, the tinted glass over the cover photo. Same
    /// one-accent-per-role rule as honey: never an error (`BanbeTheme.alert`) and never the primary CTA (ink).
    /// Mirrors web's `clay`/`clayBg` (theme.js, index.css `--bb-clay*`) value-for-value in both themes.
    let clay: Color
    let clayBg: Color
    /// Wordmark tint — ink on light, bright amber on dark.
    let logo: Color
    /// Simple Shell surfaces (note 66): depth comes from three surface steps, not borders. surface1 = cards and
    /// rows, surface2 = fields, chips and sheets, surface3 = pressed states and popovers. Mirrors web
    /// `--bb-surface-1/2/3` (index.css, theme.js `surface1/2/3`) value-for-value in both themes.
    let surface1: Color
    let surface2: Color
    let surface3: Color
    /// Secondary / tertiary text (web `--bb-fg-2` / `--bb-fg-3`); ink3 stays >= 4.5:1 on every surface.
    let ink2: Color
    let ink3: Color
    /// Hairline between rows inside one group (web `--bb-divider`). `rule` stays for input and outline edges.
    let divider: Color

    static let light = Palette(
        paper: Color(hex: 0xF7F4EC),
        ink: Color(hex: 0x1B1916),
        rule: Color(hex: 0x1B1916).opacity(0.16),
        field: Color(hex: 0xEEE8DA),
        honey: Color(hex: 0x8C6014),
        honeyBg: Color(hex: 0xF0E2BE),
        clay: Color(hex: 0x9C5B3B),
        clayBg: Color(hex: 0xEFE0D2),
        logo: Color(hex: 0x1B1916),
        surface1: Color(hex: 0xFBF8F1),
        surface2: Color(hex: 0xEEE8DA),
        surface3: Color(hex: 0xE6DFCF),
        ink2: Color(hex: 0x1B1916).opacity(0.72),
        ink3: Color(hex: 0x1B1916).opacity(0.64),
        divider: Color(hex: 0x1B1916).opacity(0.10)
    )
    /// Near-black warm base; depth from the lighter surface steps (tonal elevation), not borders or shadows.
    static let dark = Palette(
        paper: Color(hex: 0x0F0E0B),
        ink: Color(hex: 0xF2EDE1),
        rule: Color(hex: 0xF2EDE1).opacity(0.18),
        // Fields sit on surface2 (was 0x3A352B, where alert text was only 4.03:1).
        field: Color(hex: 0x24211C),
        honey: Color(hex: 0xF2C46D),
        honeyBg: Color(hex: 0x3D3016),
        clay: Color(hex: 0xD8926C),
        clayBg: Color(hex: 0x3B2A20),
        logo: Color(hex: 0xF6C453),
        surface1: Color(hex: 0x1A1815),
        surface2: Color(hex: 0x24211C),
        surface3: Color(hex: 0x2E2A24),
        ink2: Color(hex: 0xF2EDE1).opacity(0.72),
        ink3: Color(hex: 0xF2EDE1).opacity(0.56),
        divider: Color(hex: 0xF2EDE1).opacity(0.10)
    )
}

enum BanbeTheme {
    /// Warning/destructive accent — the one non-palette colour the web app
    /// uses, for error copy and "Cancel booking".
    /// Dark mode swaps in a brighter coral (web's `--bb-alert` dark value) so
    /// error text/chips stay legible on the dark paper; resolved through the
    /// trait collection, so the root `.preferredColorScheme` drives it.
    static let alert = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0xE8 / 255, green: 0x71 / 255, blue: 0x5B / 255, alpha: 1)
            : UIColor(red: 0x9A / 255, green: 0x3E / 255, blue: 0x2D / 255, alpha: 1)
    })
    /// Label colour for text sitting ON an alert-filled surface.
    static let onAlert = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(red: 0x0F / 255, green: 0x0E / 255, blue: 0x0B / 255, alpha: 1) : .white
    })

    /// Guided-focus halo gold (web `--bb-attn`), decoration only, never text. Was a hard-coded literal.
    static let attn = Color(hex: 0xE0A526)

    /// On-photo state chips, the only coloured surfaces in the design
    /// (CHIP_COLORS in src/theme.js).
    enum Chip {
        static let going = Color(hex: 0x485834).opacity(0.74)
        static let cancelled = Color(hex: 0x8C4A30).opacity(0.72)
        static let hold = Color(hex: 0x8C6014).opacity(0.72)
        static let invite = Color(hex: 0x34545E).opacity(0.72)
        static let saved = Color(hex: 0x685430).opacity(0.74)
        static let past = Color(hex: 0x4E483A).opacity(0.70)
        /// Gold — starting within 24h / happening now (web CHIP_COLORS.reminder).
        static let reminder = Color(hex: 0x7A5200).opacity(0.82)
    }

    /// One shape language for discovery surfaces (note 50): cards and icon tiles share one radius,
    /// thumbnails a slightly smaller one, chips/pills are fully round (use `Capsule()`). Mirrors
    /// src/theme.js `RADIUS`.
    enum Radius {
        static let card: CGFloat = 14
        static let tile: CGFloat = 14
        static let thumb: CGFloat = 12
        /// Web's 999px; on iOS draw pills with `Capsule()`.
        static let pill: CGFloat = .infinity
    }

    /// Display/title face: the web app uses Jost/Be Vietnam Pro at weight
    /// 600 with tight tracking; rounded system is the closest stock match
    /// without shipping the fonts.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    /// TASK 2 (loading GIF placement pass) — named per-context spacing
    /// around `BanbeLoadingVisual` (Components.swift). Splash no longer
    /// uses the shared GIF (replaced by LogomotionView), so only the
    /// reservation-hold gap remains here.
    enum LoadingVisual {
        /// Gap between the seat-hold GIF and the "Đang giữ chỗ…" label
        /// below it (`RootView.swift`'s `loadingOverlay`).
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
    var palette: Palette { isDark ? .dark : .light }
}
