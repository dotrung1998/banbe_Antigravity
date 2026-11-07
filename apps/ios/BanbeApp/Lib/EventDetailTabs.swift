import Foundation

/// Event Detail V8 tabs (note 75): which tabs show and which one is active for a scroll position. Pure logic, port of
/// src/lib/eventDetailTabs.js through tests/fixtures/event-detail-tabs.json (tests: EventDetailTabsTests.swift and
/// tests/unit/eventDetailTabs.test.mjs) — change both together.
enum EventDetailTabs {
    /// Section ids in page order.
    static let ids = ["overview", "menu", "host", "photos", "safe"]

    /// Overview always; the others only when their section has content (never a tab to an empty one).
    static func visible(hasMenu: Bool, hasHost: Bool, hasPhotos: Bool, hasProtection: Bool) -> [String] {
        let on = ["overview": true, "menu": hasMenu, "host": hasHost, "photos": hasPhotos, "safe": hasProtection]
        return ids.filter { on[$0] ?? false }
    }

    /// Index of the active tab. `tops[i]` = the scroll offset at which section i sits right under the nav bar; `lead`
    /// = how far ahead of that a section takes over. Sections that can never scroll that far get thresholds spread over
    /// the scroll that is left; at the very bottom the last tab is always active (V8 `spy`).
    static func active(tops: [Double], scrollTop: Double, maxScroll: Double, lead: Double) -> Int {
        guard !tops.isEmpty else { return -1 }
        var a = tops.map { max(0, $0 - lead) }
        var last = 0
        for (i, v) in a.enumerated() where v <= maxScroll - 4 { last = i }
        let un = a.count - 1 - last
        if un > 0 {
            let base = a[last], span = max(maxScroll, base) - base
            for k in 1...un { a[last + k] = base + span * Double(k) / Double(un) }
        }
        var act = 0
        for (i, v) in a.enumerated() where scrollTop >= v - 1 { act = i }
        if maxScroll > 0, scrollTop >= maxScroll - 2 { act = a.count - 1 }
        return act
    }
}
