import SwiftUI

/// Note 83 (iOS): the app's font choice, Account › Personal › Settings › "Font & more display". Each choice is ONE
/// typeface for the whole app (web twin: src/lib/fontPref.js):
/// - `current`: today's Apple system font (the default; the app as it always was),
/// - `serif`: Iowan Old Style (ships with iOS; the v2.3 cards' serif),
/// - `beVietnam`: Be Vietnam Pro (bundled, SIL Open Font License, Resources/Fonts/BeVietnamPro-OFL.txt).
/// Per device (UserDefaults). Every text in the app reads it through `Font.app(...)`; the app root is keyed on the
/// choice (`BanbeApp`), so a change applies everywhere at once.
enum AppFontChoice: String, CaseIterable, Identifiable {
    case current, serif, beVietnam
    var id: String { rawValue }

    /// The family a custom choice draws with; nil = the system font.
    var family: String? {
        switch self {
        case .current: return nil
        case .serif: return "Iowan Old Style"
        case .beVietnam: return "Be Vietnam Pro"
        }
    }
}

enum AppFontPref {
    static let key = "banbe.fontChoice"
    static var choice: AppFontChoice {
        AppFontChoice(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .current
    }
    static func set(_ c: AppFontChoice) { UserDefaults.standard.set(c.rawValue, forKey: key) }

    /// Default point sizes of the text styles (Large); a custom face scales from these with Dynamic Type.
    static func size(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline, .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        @unknown default: return 17
        }
    }
}

extension Font {
    /// `.system(size:weight:design:)` in the chosen face. A fixed size, like the system call it replaces (it does
    /// not scale with Dynamic Type). Monospaced text stays the system's monospaced face (codes, timers).
    static func app(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        app(size: size, weight: weight, design: design, choice: AppFontPref.choice)
    }

    static func app(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default, choice: AppFontChoice) -> Font {
        guard design != .monospaced, let family = choice.family else {
            return .system(size: size, weight: weight, design: design)
        }
        return .custom(family, fixedSize: size).weight(weight)
    }

    /// A text style (`.footnote`, `.headline`…) in the chosen face, scaling with Dynamic Type like the system style.
    static func app(_ style: Font.TextStyle, design: Font.Design? = nil, weight: Font.Weight? = nil) -> Font {
        app(style, design: design, weight: weight, choice: AppFontPref.choice)
    }

    static func app(_ style: Font.TextStyle, design: Font.Design? = nil, weight: Font.Weight? = nil, choice: AppFontChoice) -> Font {
        guard design != .monospaced, let family = choice.family else {
            return .system(style, design: design, weight: weight)
        }
        let w = weight ?? (style == .headline ? .semibold : .regular)
        return .custom(family, size: AppFontPref.size(style), relativeTo: style).weight(w)
    }
}
