import Foundation

/// Hosting Home guided empty states (Calm Pass pilot). "Coming up" used to vanish when no live event was ahead, so a
/// host with only pending events saw blank space under Submitted events. It now always says what is true. Only real
/// counts drive it. Web twin: src/lib/hostHomeEmpty.js; shared cases: tests/fixtures/host-home-empty.json.
enum HostHomeEmpty {
    enum ComingUp: String, Equatable { case needsFix, pending, quiet }
    enum KpiState: String, Equatable { case hidden, tiles, loading, error, empty }

    /// Which guided state "Coming up" shows, or nil when the list shows (or the hero already shows the next event and
    /// nothing waits). Needs fixing wins over pending because the host can act on it.
    static func comingUp(upcoming: Int, hasHero: Bool, pending: Int, needsFix: Int) -> ComingUp? {
        if upcoming > 0 { return nil }
        if needsFix > 0 { return .needsFix }
        if pending > 0 { return .pending }
        return hasHero ? nil : .quiet
    }

    /// Numbers already on screen stay through a reload or a failed refresh; before the first request lands it reads
    /// as loading.
    static func kpiState(hasOrganizer: Bool, loading: Bool, error: Bool, tiles: Int, hasReport: Bool) -> KpiState {
        if !hasOrganizer { return .hidden }
        if tiles > 0 { return .tiles }
        if loading { return .loading }
        if error { return .error }
        return hasReport ? .empty : .loading
    }

    /// Heading for the numbers: the range Reports actually used (it follows the Reports range picker).
    static func rangeHeading(_ range: ReportsRangeDays, _ T: (String, String) -> String) -> String {
        switch range {
        case .days7: return T("7 ngày qua", "Last 7 days")
        case .days30: return T("30 ngày qua", "Last 30 days")
        case .days90: return T("90 ngày qua", "Last 90 days")
        case .custom: return T("Khoảng ngày đã chọn", "Your chosen dates")
        }
    }
}
