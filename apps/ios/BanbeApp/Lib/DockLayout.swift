import Foundation

/// The dock's slots, pure (note 66, Simple Shell). Switch `simple_shell` OFF = today's five tabs
/// (home, map, schedule, inbox, profile) with the "+" beside the bar for hosts only. ON = home, schedule,
/// [create], inbox, profile: Map leaves the dock and becomes a Home view (Home's cards | list | map toggle), and
/// while Map is showing the dock lights Home. The centre slot is the create button: a real Button, never a tab and
/// never selected, and skipped by the root tab swipe. A scrub released over it opens the "+" menu (`scrubTarget`).
/// Web twin: src/lib/dockLayout.js; shared scrub cases: tests/fixtures/dock-scrub.json.
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

    /// The tab at slot `index`: nil for the create slot (and out of range), so the "+" is never a selected tab.
    static func tab(atSlot index: Int, simpleShell: Bool) -> String? {
        let s = slots(simpleShell: simpleShell)
        guard s.indices.contains(index), s[index] != createSlot else { return nil }
        return s[index]
    }

    /// What a dock scrub is over (plan item 3): a real tab, or the centre create slot.
    enum ScrubTarget: Equatable {
        case tab(String)
        case create
    }

    /// The slot under a touch at `fraction` of the bar's width (0 = leading edge, 1 = trailing edge; clamped, so a
    /// drag past either end reads as that end's slot). Every slot is an equal 1/count slice. Over the centre slot it
    /// is `.create`: released there, the "+" menu opens (the same menu a tap opens); the selected tab never changes.
    static func scrubTarget(fraction: Double, simpleShell: Bool) -> ScrubTarget {
        let s = slots(simpleShell: simpleShell)
        let f = fraction.isFinite ? min(1, max(0, fraction)) : 0
        let i = min(s.count - 1, max(0, Int((f * Double(s.count)).rounded(.down))))
        return s[i] == createSlot ? .create : .tab(s[i])
    }
}

/// Dock shrink-on-scroll decision, pure (2026-11-05, note 47). `offsetY` is 0 at the top and more negative further
/// down; `delta` is the change since the last sample (negative = scrolling down). `travel` is the signed run in the
/// current direction: it restarts when the direction reverses, so the dock flips only after `threshold` points one
/// way. Always full size near the top. Shared fixture: tests/fixtures/dock-collapse.json (web `dockCollapseStep`).
enum DockCollapse {
    static let threshold = 24.0

    static func next(collapsed: Bool, travel: Double, offsetY: Double, delta: Double) -> (collapsed: Bool, travel: Double) {
        if offsetY >= -4 { return (false, 0) }
        if delta == 0 { return (collapsed, travel) }
        let run = (delta < 0) == (travel < 0) && travel != 0 ? travel + delta : delta
        let t = min(threshold, max(-threshold, run))
        if t <= -threshold { return (true, t) }
        if t >= threshold { return (false, t) }
        return (collapsed, t)
    }
}
