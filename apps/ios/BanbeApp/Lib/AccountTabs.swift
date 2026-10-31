import Foundation

/// Note 69: which Account tabs exist. The tabs come back after note 67, but they follow Hosting mode instead of
/// being fixed:
///   Hosting off, not admin  → no tabs (one page)
///   Hosting off, admin      → Personal · Admin
///   Hosting on              → Host · Personal (Host first and selected when hosting turns on), then Admin for admins
/// Web twin: src/lib/accountTabs.js.
enum AccountTabs {
    static func tabs(isAdmin: Bool, hostMode: Bool) -> [String] {
        var out: [String] = hostMode ? ["host", "personal"] : (isAdmin ? ["personal"] : [])
        if isAdmin { out.append("admin") }
        return out
    }

    /// The tab to show: the stored one while it still exists, otherwise the first tab (Personal when there are none).
    static func resolve(_ selected: String, tabs: [String]) -> String {
        tabs.contains(selected) ? selected : (tabs.first ?? "personal")
    }
}
