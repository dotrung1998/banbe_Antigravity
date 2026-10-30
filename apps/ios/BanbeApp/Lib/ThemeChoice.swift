import SwiftUI

/// Theme choice vs. the theme actually shown (note 66). The choice is "light", "dark" or "system"; "system"
/// follows the device. New installs start on "system"; a saved light/dark choice is kept as it was.
/// Mirrors src/lib/themeChoice.js.
enum ThemeChoice {
    static let all = ["system", "light", "dark"]

    /// `fresh` = nothing saved yet on this device (new install) → "system".
    static func normalize(_ value: String?, fresh: Bool) -> String {
        if let value, all.contains(value) { return value }
        return fresh ? "system" : "light"
    }

    /// "light" or "dark".
    static func resolve(_ choice: String, systemIsDark: Bool) -> String {
        if choice == "system" { return systemIsDark ? "dark" : "light" }
        return choice == "dark" ? "dark" : "light"
    }

    /// The root override: nil lets the device decide.
    static func colorScheme(for choice: String) -> ColorScheme? {
        switch choice {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }
}

extension AppState {
    /// The theme actually drawn ("light" | "dark"); `theme` is the choice and may be "system".
    var resolvedTheme: String { ThemeChoice.resolve(theme, systemIsDark: systemIsDark) }
    var isDark: Bool { resolvedTheme == "dark" }
}
