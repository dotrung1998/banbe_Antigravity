import Foundation

/// Per-event market rules (migration 195): an event's own IANA time zone and its currency.
/// iOS twin of src/lib/eventMarket.js and SQL event_tz_for / event_currency_for / resolve_event_tz;
/// shared vectors: tests/fixtures/event-market.json (EventMarketTests.swift). Pure: no SwiftUI, no network.
///
/// Money amounts are integers in the currency's MINOR unit: đồng for VND, cents for USD
/// (the `events.price_vnd` column keeps its old name but follows `events.currency`).
/// Paid USD booking is not available yet (owner decision 2026-10-22); free USD events are.
enum EventMarket {
    static let vnTimeZoneID = "Asia/Ho_Chi_Minh"
    static let vnTimeZone = TimeZone(identifier: vnTimeZoneID)!

    private static let usStateZones: [String: String] = {
        var m: [String: String] = [:]
        func add(_ zone: String, _ states: [(String, String)]) {
            for (code, name) in states { m[code.lowercased()] = zone; m[name.lowercased()] = zone }
        }
        add("America/New_York", [("CT","Connecticut"),("DE","Delaware"),("DC","District of Columbia"),("FL","Florida"),("GA","Georgia"),("ME","Maine"),("MD","Maryland"),("MA","Massachusetts"),("NH","New Hampshire"),("NJ","New Jersey"),("NY","New York"),("NC","North Carolina"),("OH","Ohio"),("PA","Pennsylvania"),("RI","Rhode Island"),("SC","South Carolina"),("VT","Vermont"),("VA","Virginia"),("WV","West Virginia"),("MI","Michigan"),("IN","Indiana"),("KY","Kentucky")])
        add("America/Chicago", [("AL","Alabama"),("AR","Arkansas"),("IL","Illinois"),("IA","Iowa"),("LA","Louisiana"),("MN","Minnesota"),("MS","Mississippi"),("MO","Missouri"),("OK","Oklahoma"),("TX","Texas"),("WI","Wisconsin"),("KS","Kansas"),("NE","Nebraska"),("SD","South Dakota"),("ND","North Dakota"),("TN","Tennessee")])
        add("America/Denver", [("CO","Colorado"),("MT","Montana"),("NM","New Mexico"),("UT","Utah"),("WY","Wyoming"),("ID","Idaho")])
        add("America/Phoenix", [("AZ","Arizona")])
        add("America/Los_Angeles", [("CA","California"),("NV","Nevada"),("OR","Oregon"),("WA","Washington")])
        add("America/Anchorage", [("AK","Alaska")])
        add("Pacific/Honolulu", [("HI","Hawaii")])
        return m
    }()

    private static func country(_ c: String?) -> String {
        let t = (c ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (t.isEmpty ? "VN" : t).uppercased()
    }

    // MARK: Time zone

    /// VN (or no country) -> Asia/Ho_Chi_Minh; US -> by state code/name; anything else -> nil.
    static func eventTimeZone(countryCode: String?, stateProvince: String?) -> String? {
        switch country(countryCode) {
        case "VN": return vnTimeZoneID
        case "US": return usStateZones[(stateProvince ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
        default: return nil
        }
    }

    /// The zone the server will store: a real US zone from the client (MapKit knows multi-zone states) wins for US.
    static func resolveEventTimeZone(countryCode: String?, stateProvince: String?, clientTz: String?) -> String? {
        let tz = (clientTz ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if country(countryCode) == "US", !tz.isEmpty, tz.hasPrefix("America/") || tz == "Pacific/Honolulu",
           TimeZone(identifier: tz) != nil {
            return tz
        }
        return eventTimeZone(countryCode: countryCode, stateProvince: stateProvince)
    }

    /// A row's own zone: the stored `tz` column, else derived from its location, else Vietnam (every row before 195).
    static func rowTimeZoneID(tz: String?, countryCode: String?, stateProvince: String?) -> String {
        if let tz, !tz.isEmpty, TimeZone(identifier: tz) != nil { return tz }
        return eventTimeZone(countryCode: countryCode, stateProvince: stateProvince) ?? vnTimeZoneID
    }

    static func timeZone(_ id: String?) -> TimeZone {
        id.flatMap(TimeZone.init(identifier:)) ?? vnTimeZone
    }

    // MARK: Currency

    /// VN (or no country) -> VND, US -> USD, anything else -> nil (unsupported).
    static func eventCurrency(countryCode: String?) -> String? {
        switch country(countryCode) {
        case "VN": return "VND"
        case "US": return "USD"
        default: return nil
        }
    }

    /// A row's own currency: the stored column, else VND (every row before 195).
    static func rowCurrency(_ raw: String?) -> String { raw == "USD" ? "USD" : "VND" }

    private static func group(_ n: Int, _ sep: Character) -> String {
        let digits = Array(String(n))
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(sep) }
            out.append(ch)
        }
        return out
    }

    /// 1250 USD -> "$12.50", 1200 -> "$12", 125000 -> "$1,250"; VND -> "150.000₫". Same in every UI language.
    static func formatMoney(_ amount: Int, currency: String) -> String {
        let sign = amount < 0 ? "-" : ""
        if currency != "USD" { return sign + group(abs(amount), ".") + "₫" }
        let dollars = abs(amount) / 100, cents = abs(amount) % 100
        return sign + "$" + group(dollars, ",") + (cents > 0 ? String(format: ".%02d", cents) : "")
    }

    /// Compact form for chips/sliders: VND "150k₫" / "1,5M₫"; USD is already short.
    static func formatMoneyShort(_ amount: Int, currency: String) -> String {
        currency == "USD" ? formatMoney(amount, currency: "USD") : EventRecipe.formatVndShort(amount)
    }

    /// Host-typed price -> minor units, or nil when it isn't a price. VND ignores separators; USD allows 2 decimals.
    static func parsePriceInput(_ text: String, currency: String) -> Int? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if currency == "USD" {
            let t = s.filter { $0 != "$" && $0 != "," && !$0.isWhitespace }
            guard t.range(of: #"^[0-9]+(\.[0-9]{1,2})?$"#, options: .regularExpression) != nil else { return nil }
            let parts = t.split(separator: ".", omittingEmptySubsequences: false)
            guard let whole = Int(parts[0]) else { return nil }
            let frac = parts.count > 1 ? String((String(parts[1]) + "00").prefix(2)) : "00"
            return whole * 100 + (Int(frac) ?? 0)
        }
        let digits = s.filter { $0.isASCII && $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }

    /// Minor units -> what the price field shows when editing ("450.000", "12", "12.50").
    static func priceInputText(_ amount: Int, currency: String) -> String {
        let n = max(0, amount)
        if currency == "USD" { return "\(n / 100)" + (n % 100 > 0 ? String(format: ".%02d", n % 100) : "") }
        return group(n, ".")
    }

    /// Quick-pick prices in minor units. "Free" is 0.
    static func priceQuickPicks(currency: String) -> [Int] {
        currency == "USD" ? [0, 1000, 2000, 3000] : [0, 200_000, 300_000, 500_000]
    }

    /// Major units for comparing with a budget (USD budgets are whole dollars, VND budgets are đồng).
    static func majorAmount(_ amount: Int, currency: String) -> Double {
        currency == "USD" ? Double(amount) / 100 : Double(amount)
    }

    /// Paid booking only runs in VND today; free events book in any currency.
    static func paidBookingAvailable(currency: String, amount: Int) -> Bool {
        currency != "USD" || amount <= 0
    }

    // MARK: Wall clock

    struct ZonedParts: Equatable {
        let year: Int, month: Int, day: Int, hour: Int, minute: Int
        /// 0 = Sunday … 6 = Saturday.
        let weekday: Int
    }

    static func calendar(_ timeZone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }

    /// The wall clock of an instant in a zone.
    static func zonedParts(_ date: Date, timeZone: TimeZone) -> ZonedParts {
        let c = calendar(timeZone).dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: date)
        return ZonedParts(year: c.year ?? 0, month: c.month ?? 0, day: c.day ?? 0, hour: c.hour ?? 0,
                          minute: c.minute ?? 0, weekday: (c.weekday ?? 1) - 1)
    }

    /// Wall clock in a zone -> instant ("2027-03-06", "19:00", America/Los_Angeles). Same as SQL AT TIME ZONE.
    static func wallClockDate(date: String, time: String, timeZone: TimeZone) -> Date? {
        let d = date.split(separator: "-").map { Int($0) }
        let t = time.split(separator: ":").map { Int($0) }
        guard d.count == 3, t.count >= 2, let y = d[0], let mo = d[1], let day = d[2], let h = t[0], let mi = t[1] else { return nil }
        return calendar(timeZone).date(from: DateComponents(year: y, month: mo, day: day, hour: h, minute: mi))
    }
}
