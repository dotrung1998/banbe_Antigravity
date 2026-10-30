import Foundation

/// The dock's slots, pure (note 66, Simple Shell). Switch `simple_shell` OFF = today's five tabs
/// (home, map, schedule, inbox, profile) with the "+" beside the bar for hosts only. ON = home, schedule,
/// [create], inbox, profile: Map leaves the dock and becomes a Home view (Home's cards | list | map toggle), and
/// while Map is showing the dock lights Home. The centre slot is the create button: a real Button, never a tab,
/// never selected, skipped by scrub-to-select and by the root tab swipe. Web twin: src/screens/BottomTabBar.jsx.
enum DockLayout {
    static let createSlot = "create"

    /// Tab screens in dock order: what RootView's root tab swipe walks. The create slot is not a screen.
    static func dockOrder(simpleShell: Bool) -> [Screen] {
        simpleShell ? [.home, .schedule, .inbox, .profile] : [.home, .mapExplore, .schedule, .inbox, .profile]
    }

    /// Every slot left to right (ids match `tab.<id>`), including the centre create slot when ON.
    static func slots(simpleShell: Bool) -> [String] {
        simpleShell ? ["home", "schedule", createSlot, "inbox", "profile"] : ["home", "map", "schedule", "inbox", "profile"]
    }

    static func tabID(for screen: Screen) -> String? {
        switch screen {
        case .home: return "home"
        case .mapExplore: return "map"
        case .schedule: return "schedule"
        case .inbox: return "inbox"
        case .profile: return "profile"
        default: return nil
        }
    }

    /// The tab lit for `screen`. ON: Map is a Home view, so `mapExplore` lights Home.
    static func highlight(for screen: Screen, simpleShell: Bool) -> String? {
        if simpleShell && screen == .mapExplore { return "home" }
        return tabID(for: screen)
    }

    /// The tab a scrub at slot `index` lands on: nil for the create slot (and out of range), so dragging across the
    /// "+" never selects it.
    static func tab(atSlot index: Int, simpleShell: Bool) -> String? {
        let s = slots(simpleShell: simpleShell)
        guard s.indices.contains(index), s[index] != createSlot else { return nil }
        return s[index]
    }
}
