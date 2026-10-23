import Foundation

/// Event Detail's sticky action bar: which state it is in, the seat presets, and the total shown in the CTA.
/// Mirrors src/lib/reserveBar.js (tests: BanbeAppTests/ReserveBarTests.swift and tests/unit/reserveBar.test.mjs)
/// — change both together.
enum ReserveBar {
    /// Same cap as Reserve's stepper and `qtyPlus`.
    static let maxQty = 6
    static let presets = [1, 2, 3]  // "1 vé · 2 vé · 3 vé" (note 52 mockup); the stepper covers 4–6

    /// `currencyUnavailable`: a PAID event in a currency banbe can't take bookings in yet (USD, migration 195) —
    /// a clear disabled bar, never an error after tapping.
    enum State: String { case ticket, pending, cancelled, ended, soldOut, currencyUnavailable, blocked, reserve }

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

    /// Total for `qty` seats from the event's own price (minor unit of `currency`): "400.000₫", "$25" or "Miễn phí"
    /// (translate with trStatus).
    static func totalPrice(amount: Int, currency: String, qty: Int) -> String {
        amount <= 0 ? "Miễn phí" : EventMarket.formatMoney(amount * max(1, qty), currency: currency)
    }

    /// First match wins, in the order the old inline chain used: a booking beats every closed state, cancelled beats
    /// ended/sold out (a cancelled event's stale seatsRemaining can say either), a paid booking that isn't open in the
    /// event's currency beats the criteria block (meeting the criteria wouldn't make it bookable), and the criteria
    /// block applies only when nothing else does.
    static func state(booking: Bool, ticket: Bool, cancelled: Bool, ended: Bool, soldOut: Bool,
                      currencyUnavailable: Bool = false, blocked: Bool) -> State {
        if booking { return ticket ? .ticket : .pending }
        if cancelled { return .cancelled }
        if ended { return .ended }
        if soldOut { return .soldOut }
        if currencyUnavailable { return .currencyUnavailable }
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
