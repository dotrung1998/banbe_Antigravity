import Foundation

/// Event Detail's sticky action bar: which state it is in, the seat presets, and the total shown in the CTA.
/// Mirrors src/lib/reserveBar.js (tests: BanbeAppTests/ReserveBarTests.swift and tests/unit/reserveBar.test.mjs)
/// — change both together.
enum ReserveBar {
    /// Same cap as Reserve's stepper and `qtyPlus`.
    static let maxQty = 6
    static let presets = [1, 2, 4]

    enum State: String { case ticket, pending, cancelled, ended, soldOut, blocked, reserve }

    /// "200.000₫" / "Miễn phí" / "Free" -> (free, unit in VND; 0 when free or unparseable).
    static func parsePrice(_ price: String) -> (free: Bool, unit: Int) {
        let lower = price.lowercased()
        if lower.contains("miễn phí") || lower.contains("free") { return (true, 0) }
        guard let range = price.range(of: "[\\d.]+", options: .regularExpression) else { return (false, 0) }
        return (false, Int(price[range].replacingOccurrences(of: ".", with: "")) ?? 0)
    }

    /// Total for `qty` seats in the catalogue's own Vietnamese form ("400.000₫" or "Miễn phí"); translate with trStatus.
    static func totalPrice(_ price: String, qty: Int) -> String {
        let p = parsePrice(price)
        if p.free { return "Miễn phí" }
        return vnd(p.unit * max(1, qty))
    }

    /// First match wins, in the order the old inline chain used: a booking beats every closed state, cancelled beats
    /// ended/sold out (a cancelled event's stale seatsRemaining can say either), and the criteria block applies only
    /// when nothing else does.
    static func state(booking: Bool, ticket: Bool, cancelled: Bool, ended: Bool, soldOut: Bool, blocked: Bool) -> State {
        if booking { return ticket ? .ticket : .pending }
        if cancelled { return .cancelled }
        if ended { return .ended }
        if soldOut { return .soldOut }
        if blocked { return .blocked }
        return .reserve
    }

    static func clampQty(_ n: Int) -> Int { min(maxQty, max(1, n)) }

    private static func vnd(_ n: Int) -> String {
        let digits = Array(String(n))
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(".") }
            out.append(ch)
        }
        return out + "₫"
    }
}
