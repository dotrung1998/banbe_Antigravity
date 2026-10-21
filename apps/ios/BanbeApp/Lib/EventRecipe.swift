import Foundation

// "Recipe for success" for event creation: ingredient checks, score, outcome estimate, per-option hints.
// iOS twin of src/lib/eventRecipe.js — keep both and their tests in sync (EventRecipeTests.swift mirrors
// tests/unit/eventRecipe.test.mjs). Pure: no SwiftUI, no network, no `Date()` inside.
//
// Honesty rules (the whole point of this file):
// - A number is shown only when it came from get_host_benchmarks (migration 186), which already refuses
//   slices under 5 events / 3 organizers. Each ingredient says whether it is `data` (with its n) or a `tip`.
// - Without data an ingredient never judges a choice as bad on a guess: e.g. a Tuesday is "good" with a
//   general tip, not "improve". Only objective gaps (empty field, < 3 photos) are flagged without data.
// - The recipe NEVER blocks submitting.

/// The raw `get_host_benchmarks(p_cat_key, p_city)` jsonb. Every field is optional: a slice under the
/// privacy threshold comes back null, a cold start has `level == nil`, and an older server may omit keys.
struct HostBenchmarks: Decodable, Equatable {
    var success: Bool?
    var level: String?
    var n: Int?
    var freeShare: Double?
    var price: Price?
    var fill: Fill?
    var slots: [Slot]?
    var wellFilled: Group?
    var others: Group?
    var keywords: [String]?

    struct Price: Decodable, Equatable {
        var n: Int?
        var p25: Double?
        var median: Double?
        var p75: Double?
        var min: Double?
        var max: Double?
        var histogram: [Int]?
    }
    struct Fill: Decodable, Equatable {
        var n: Int?
        var medianFill: Double?
        var medianCapacity: Double?
        var medianBooked: Double?
        enum CodingKeys: String, CodingKey {
            case n, medianFill = "median_fill", medianCapacity = "median_capacity", medianBooked = "median_booked"
        }
    }
    struct Slot: Decodable, Equatable {
        /// ISO weekday: 1 = Monday ... 7 = Sunday (Postgres extract(isodow)).
        var dow: Int?
        /// afternoon | evening | late
        var slot: String?
        var n: Int?
        var medianFill: Double?
        enum CodingKeys: String, CodingKey { case dow, slot, n, medianFill = "median_fill" }
    }
    struct Group: Decodable, Equatable {
        var n: Int?
        var medianPhotos: Double?
        var introShare: Double?
        var includedShare: Double?
        var medianLeadDays: Double?
        enum CodingKeys: String, CodingKey {
            case n, medianPhotos = "median_photos", introShare = "intro_share",
                 includedShare = "included_share", medianLeadDays = "median_lead_days"
        }
    }

    enum CodingKeys: String, CodingKey {
        case success, level, n, freeShare = "free_share", price, fill, slots
        case wellFilled = "well_filled", others, keywords
    }
}

// Postgres `numeric` may arrive as 12 or 12.0; counts decode either way instead of failing the whole payload.
extension HostBenchmarks.Price {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        n = c.lenientInt(.n); p25 = c.lenientDouble(.p25); median = c.lenientDouble(.median); p75 = c.lenientDouble(.p75)
        min = c.lenientDouble(.min); max = c.lenientDouble(.max)
        histogram = (try? c.decodeIfPresent([Double].self, forKey: .histogram))?.map { Int($0) }
    }
    enum CodingKeys: String, CodingKey { case n, p25, median, p75, min, max, histogram }
}
extension HostBenchmarks.Fill {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        n = c.lenientInt(.n); medianFill = c.lenientDouble(.medianFill)
        medianCapacity = c.lenientDouble(.medianCapacity); medianBooked = c.lenientDouble(.medianBooked)
    }
}
extension HostBenchmarks.Slot {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dow = c.lenientInt(.dow); slot = try? c.decodeIfPresent(String.self, forKey: .slot)
        n = c.lenientInt(.n); medianFill = c.lenientDouble(.medianFill)
    }
}
extension HostBenchmarks.Group {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        n = c.lenientInt(.n); medianPhotos = c.lenientDouble(.medianPhotos); introShare = c.lenientDouble(.introShare)
        includedShare = c.lenientDouble(.includedShare); medianLeadDays = c.lenientDouble(.medianLeadDays)
    }
}
extension HostBenchmarks {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try? c.decodeIfPresent(Bool.self, forKey: .success)
        level = try? c.decodeIfPresent(String.self, forKey: .level)
        n = c.lenientInt(.n); freeShare = c.lenientDouble(.freeShare)
        price = try? c.decodeIfPresent(Price.self, forKey: .price)
        fill = try? c.decodeIfPresent(Fill.self, forKey: .fill)
        slots = try? c.decodeIfPresent([Slot].self, forKey: .slots)
        wellFilled = try? c.decodeIfPresent(Group.self, forKey: .wellFilled)
        others = try? c.decodeIfPresent(Group.self, forKey: .others)
        keywords = try? c.decodeIfPresent([String].self, forKey: .keywords)
    }
}

private extension KeyedDecodingContainer {
    func lenientDouble(_ key: Key) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Double(s) }
        return nil
    }
    func lenientInt(_ key: Key) -> Int? {
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i }
        return lenientDouble(key).map { Int($0) }
    }
}

enum EventRecipe {
    static let hostGoals = ["fill_seats", "regular_crowd", "try_idea", "small_premium"]
    static let goalLabels: [String: (vi: String, en: String)] = [
        "fill_seats": ("Kín mọi chỗ", "Fill every seat"),
        "regular_crowd": ("Xây nhóm khách quen", "Build a regular crowd"),
        "try_idea": ("Thử ý tưởng mới", "Try a new idea"),
        "small_premium": ("Nhỏ & cao cấp", "Small & premium"),
    ]
    static let positionLabels: [String: (vi: String, en: String)] = [
        "free": ("miễn phí", "free"), "below": ("dưới mức thường", "below typical"),
        "typical": ("mức thường gặp", "typical"), "premium": ("cao cấp", "premium"),
    ]
    /// Same numbering as CreateEventView's steps (0 = Host).
    enum Step { static let basics = 1, when = 2, tickets = 3, photos = 4 }

    private static let offsetMin = 420 // Vietnam, same convention as HomeDiscovery
    private static let minPhotos = 3
    private static let tipPhotos = 5
    private static let tipLeadDays = 14
    private static let descGoodChars = 120
    private static let dayMs: Double = 86_400_000

    /// Normalized by the caller from the create form.
    struct Draft: Equatable {
        var name = ""
        var description = ""
        var intro = ""
        var includedCount = 0
        var keywords: [String] = []
        /// nil / 0 = free.
        var priceVnd: Int?
        var seats: Int?
        var startsAt: Date?
        var photos = 0
        var chatGreeting = ""
    }

    enum Status: String { case good, improve, missing }
    enum Source: String { case data, tip }

    struct Fix: Equatable {
        let step: Int
        let field: String
    }
    struct BestSlot: Equatable {
        let dow: Int
        let slot: String
        let fill: Double
    }

    /// One ingredient. Facts are optional and only set by the ingredients they belong to (same keys as web).
    struct Check: Equatable, Identifiable {
        /// title | photos | description | included | keywords | price | seats | timing | lead | greeting
        let id: String
        var status: Status
        var source: Source
        var n: Int? = nil
        let fix: Fix
        var words: Int? = nil
        var shouting = false
        var target: Int? = nil
        var have: Int? = nil
        var chars: Int? = nil
        var share: Double? = nil
        var suggestions: [String] = []
        var position: String? = nil
        var median: Double? = nil
        var p25: Double? = nil
        var p75: Double? = nil
        var typicalGuests: Double? = nil
        var medianFill: Double? = nil
        var dow: Int? = nil
        var slot: String? = nil
        var ownFill: Double? = nil
        var best: BestSlot? = nil
        var days: Int? = nil
    }

    struct Outcome: Equatable {
        let guests: Int
        let revenueVnd: Int
        /// similar | full
        let basis: String
        let fill: Double?
    }

    // MARK: Helpers

    /// JS Math.round (half up), so both platforms print the same numbers.
    static func jsRound(_ x: Double) -> Int { Int((x + 0.5).rounded(.down)) }

    private static func words(_ s: String) -> [Substring] {
        s.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isWhitespace)
    }

    /// ISO weekday (1 = Monday) and the benchmark slot, in Vietnam time.
    static func localParts(_ date: Date) -> (dow: Int, slot: String) {
        let ms = date.timeIntervalSince1970 * 1000 + Double(offsetMin) * 60_000
        let days = Int((ms / dayMs).rounded(.down))
        let sundayBased = ((days + 4) % 7 + 7) % 7
        let dow = (sundayBased + 6) % 7 + 1
        let hour = Int((ms - Double(days) * dayMs) / 3_600_000)
        return (dow, hour < 17 ? "afternoon" : hour < 21 ? "evening" : "late")
    }

    /// Benchmarks are usable only when the RPC answered with a level (nil level = cold start).
    static func hasBenchmarks(_ b: HostBenchmarks?) -> Bool {
        guard let b, b.success != false, let level = b.level, !level.isEmpty else { return false }
        return true
    }

    private static func slotIndex(_ b: HostBenchmarks?, dow: Int, slot: String) -> Int? {
        b?.slots?.firstIndex { $0.dow == dow && $0.slot == slot }
    }
    private static func bestSlotIndex(_ b: HostBenchmarks?) -> Int? {
        guard let cells = b?.slots, !cells.isEmpty else { return nil }
        var best = 0
        for i in cells.indices where (cells[i].medianFill ?? 0) > (cells[best].medianFill ?? 0) { best = i }
        return best
    }

    // MARK: Checks

    static func checks(_ d: Draft, benchmarks: HostBenchmarks?, goal: String?, now: Date) -> [Check] {
        let b = hasBenchmarks(benchmarks) ? benchmarks : nil
        var out: [Check] = []

        // 1. Title — says what it is, not shouting.
        do {
            let w = words(d.name)
            let letters = String(d.name.unicodeScalars.filter { CharacterSet.letters.contains($0) })
            let shouting = letters.count > 4 && letters == letters.uppercased()
            let status: Status = w.isEmpty ? .missing : (w.count < 3 || w.count > 10 || shouting) ? .improve : .good
            out.append(Check(id: "title", status: status, source: .tip, fix: Fix(step: Step.basics, field: "name"),
                             words: w.count, shouting: shouting))
        }

        // 2. Photos — what well-filled similar events had, else a general 5.
        do {
            let dataTarget = b?.wellFilled?.medianPhotos
            let target = dataTarget.map { max(minPhotos, Int($0.rounded(.up))) } ?? tipPhotos
            let n = d.photos
            out.append(Check(id: "photos", status: n < minPhotos ? .missing : n >= target ? .good : .improve,
                             source: dataTarget != nil ? .data : .tip, n: dataTarget != nil ? b?.wellFilled?.n : nil,
                             fix: Fix(step: Step.photos, field: "photos"), target: target, have: n))
        }

        // 3. Description.
        do {
            let len = d.description.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count
            out.append(Check(id: "description", status: len == 0 ? .missing : len >= descGoodChars ? .good : .improve,
                             source: .tip, fix: Fix(step: Step.basics, field: "description"), target: descGoodChars, chars: len))
        }

        // 4. Included items.
        do {
            let share = b?.wellFilled?.includedShare
            out.append(Check(id: "included", status: d.includedCount > 0 ? .good : .missing,
                             source: share != nil ? .data : .tip, n: share != nil ? b?.wellFilled?.n : nil,
                             fix: Fix(step: Step.basics, field: "included"), share: share))
        }

        // 5. Keywords (+ suggestions other hosts in this slice actually use).
        do {
            let have = d.keywords.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
            let pool = b?.keywords ?? []
            let suggestions = Array(pool.filter { !have.contains($0.lowercased()) }.prefix(5))
            out.append(Check(id: "keywords", status: have.count >= 3 ? .good : have.isEmpty ? .missing : .improve,
                             source: pool.isEmpty ? .tip : .data, n: b != nil ? b?.n : nil,
                             fix: Fix(step: Step.basics, field: "keywords"), have: have.count, suggestions: suggestions))
        }

        // 6. Price — within the typical band of similar events (premium goal relaxes the top).
        do {
            let price = d.priceVnd ?? 0
            let p = b?.price
            var status: Status = .good
            var position: String?
            if let p, price > 0 {
                position = pricePosition(price, p)
                if position == "premium" && goal != "small_premium" { status = .improve }
            } else if p != nil && price == 0 {
                position = "free"
            }
            out.append(Check(id: "price", status: status, source: p != nil ? .data : .tip, n: p?.n,
                             fix: Fix(step: Step.tickets, field: "price"), position: position,
                             median: p?.median, p25: p?.p25, p75: p?.p75))
        }

        // 7. Seats — compared with how many guests similar events actually welcome.
        do {
            let seats = d.seats ?? 0
            let f = b?.fill
            var status: Status = seats > 0 ? .good : .missing
            if let f, seats > 0, let typical = f.medianBooked {
                let limit = goal == "fill_seats" ? max(typical * 1.5, typical + 5) : max(typical * 2, typical + 10)
                if Double(seats) > limit { status = .improve }
            }
            out.append(Check(id: "seats", status: status, source: f != nil ? .data : .tip, n: f?.n,
                             fix: Fix(step: Step.tickets, field: "seats"), typicalGuests: f?.medianBooked, medianFill: f?.medianFill))
        }

        // 8. Day & time — this slot's fill vs the best slot, only where both cells cleared the k-threshold.
        if let startsAt = d.startsAt {
            let (dow, slot) = localParts(startsAt)
            let ownIndex = slotIndex(b, dow: dow, slot: slot)
            let bestIndex = bestSlotIndex(b)
            let own = ownIndex.flatMap { b?.slots?[$0] }
            let best = bestIndex.flatMap { b?.slots?[$0] }
            var status: Status = .good
            if let own, let best, (best.medianFill ?? 0) - (own.medianFill ?? 0) > 0.1 { status = .improve }
            var bestFact: BestSlot?
            if let best, ownIndex == nil || bestIndex != ownIndex {
                bestFact = BestSlot(dow: best.dow ?? 0, slot: best.slot ?? "", fill: best.medianFill ?? 0)
            }
            out.append(Check(id: "timing", status: status, source: own != nil ? .data : .tip, n: own?.n,
                             fix: Fix(step: Step.when, field: "date"), dow: dow, slot: slot,
                             ownFill: own?.medianFill, best: bestFact))
        } else {
            out.append(Check(id: "timing", status: .missing, source: .tip, fix: Fix(step: Step.when, field: "date")))
        }

        // 9. Lead time — how far ahead well-filled events were submitted.
        do {
            let dataDays = b?.wellFilled?.medianLeadDays
            let target = dataDays.map(jsRound) ?? tipLeadDays
            let source: Source = dataDays != nil ? .data : .tip
            if let startsAt = d.startsAt {
                let days = Int(((startsAt.timeIntervalSince(now) * 1000) / dayMs).rounded(.down))
                out.append(Check(id: "lead", status: days >= target ? .good : .improve, source: source,
                                 n: dataDays != nil ? b?.wellFilled?.n : nil,
                                 fix: Fix(step: Step.when, field: "date"), target: target, days: days))
            } else {
                out.append(Check(id: "lead", status: .missing, source: source, fix: Fix(step: Step.when, field: "date"), target: target))
            }
        }

        // 10. Opening message.
        out.append(Check(id: "greeting",
                         status: d.chatGreeting.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .improve : .good,
                         source: .tip, fix: Fix(step: Step.basics, field: "greeting")))
        return out
    }

    static func score(_ checks: [Check]) -> (good: Int, total: Int) {
        (checks.filter { $0.status == .good }.count, checks.count)
    }

    /// Where a paid price sits in the similar-events band.
    static func pricePosition(_ price: Int, _ p: HostBenchmarks.Price?) -> String? {
        guard let p, price > 0 else { return price == 0 ? "free" : nil }
        let v = Double(price)
        if let p25 = p.p25, v < p25 { return "below" }
        if let p75 = p.p75, v > p75 { return "premium" }
        return "typical"
    }

    /// Turns price × seats into outcomes ("~11 guests, ~3.3M₫"). Uses the similar-events median fill when there
    /// is one; otherwise reports the full-house figure and says so (basis "full"), never an invented rate.
    static func estimateOutcome(priceVnd: Int, seats: Int, medianFill: Double?) -> Outcome? {
        guard seats > 0 else { return nil }
        let fill = medianFill.flatMap { $0 > 0 ? min($0, 1) : nil }
        let guests = fill.map { max(1, jsRound(Double(seats) * $0)) } ?? seats
        let price = priceVnd > 0 ? priceVnd : 0
        return Outcome(guests: guests, revenueVnd: guests * price, basis: fill != nil ? "similar" : "full", fill: fill)
    }

    // MARK: Copy (shared wording with eventRecipe.js; T(vi, en) is the caller's translator)

    typealias Translate = (String, String) -> String

    private static let dowVI = ["", "Thứ 2", "Thứ 3", "Thứ 4", "Thứ 5", "Thứ 6", "Thứ 7", "Chủ nhật"]
    private static let dowEN = ["", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private static let slotVI = ["afternoon": "ban ngày", "evening": "buổi tối", "late": "đêm muộn"]
    private static let slotEN = ["afternoon": "daytime", "evening": "evening", "late": "late night"]

    static func slotLabel(dow: Int, slot: String, _ T: Translate) -> String {
        let i = (1...7).contains(dow) ? dow : 0
        return T("\(dowVI[i]) \(slotVI[slot] ?? "")", "\(dowEN[i]) \(slotEN[slot] ?? "")")
    }

    static func pct(_ x: Double?) -> String { "\(jsRound((x ?? 0) * 100))%" }

    /// "3,3M₫" / "3M₫" / "250k₫" — the same short money the web recipe prints.
    // Draggable price slider over the market histogram (owner, 2026-10-21). Web twin: priceToFraction /
    // fractionToPrice in src/lib/eventRecipe.js.
    static let priceSliderStep = 10_000

    /// Where `v` sits on the market track, 0…1 (nil without a usable range).
    static func priceToFraction(_ v: Int, _ p: HostBenchmarks.Price) -> Double? {
        guard let lo = p.min, let hi = p.max else { return nil }
        let span = hi - lo
        guard span > 0 else { return 0.5 }
        return min(max((Double(v) - lo) / span, 0), 1)
    }

    /// The price at track position `f` (0…1), snapped to `step`, kept inside min…max.
    static func fractionToPrice(_ f: Double, _ p: HostBenchmarks.Price, step: Int = priceSliderStep) -> Int {
        let lo = p.min ?? 0, hi = p.max ?? lo
        let raw = lo + min(max(f, 0), 1) * (hi - lo)
        let s = Double(step)
        let snapped = (raw / s).rounded() * s
        let lowest = (lo / s).rounded(.up) * s, highest = (hi / s).rounded(.down) * s
        guard lowest <= highest else { return Int(raw.rounded()) }   // a market narrower than one step
        return Int(max(lowest, min(highest, snapped)))
    }

    static func formatVndShort(_ v: Double?) -> String {
        guard let v else { return "" }
        if v >= 1_000_000 {
            let m = v / 1_000_000
            let s = v.truncatingRemainder(dividingBy: 1_000_000) == 0 ? String(format: "%.0f", m) : String(format: "%.1f", m)
            return s.replacingOccurrences(of: ".", with: ",") + "M₫"
        }
        if v >= 1000 { return "\(jsRound(v / 1000))k₫" }
        return "\(num(v))₫"
    }
    static func formatVndShort(_ v: Int) -> String { formatVndShort(Double(v)) }

    /// A number the way JS template strings print it (12, not 12.0).
    static func num(_ v: Double) -> String {
        v == v.rounded() && abs(v) < 1e15 ? String(Int(v)) : String(v)
    }

    /// Title + the "Why?" text for one ingredient. `detail` names its evidence.
    static func copy(_ c: Check, _ T: Translate) -> (title: String, detail: String) {
        let evidence = c.source == .data && (c.n ?? 0) > 0
            ? T("Dựa trên \(c.n!) sự kiện tương tự.", "Based on \(c.n!) similar events.")
            : T("Mẹo chung của banbe.", "General banbe tip.")
        let target = c.target ?? 0
        let have = c.have ?? 0
        switch c.id {
        case "title":
            let detail: String
            if c.status == .missing { detail = T("Thêm tên sự kiện.", "Add an event name.") }
            else if c.shouting { detail = T("Tránh viết HOA toàn bộ — khó đọc hơn.", "Avoid ALL CAPS — it reads harder.") }
            else {
                detail = T("3–10 từ, nói rõ khách sẽ làm gì (vd. \"Supper club 6 món, Quận 3\").",
                           "3–10 words that say what guests will do (e.g. \"6-course supper club, District 3\").") + " " + evidence
            }
            return (T("Tên nói rõ đây là gì", "A title that says what it is"), detail)
        case "photos":
            let body = c.source == .data
                ? T("Sự kiện kín chỗ thường có \(target)+ ảnh. Bạn có \(have).", "Events that filled well had \(target)+ photos. You have \(have).")
                : T("Ảnh cho khách thấy không khí. Bạn có \(have).", "Photos show guests the vibe. You have \(have).")
            return (T("Ít nhất \(target) ảnh", "At least \(target) photos"), body + " " + evidence)
        case "description":
            let chars = c.chars ?? 0
            return (T("Mô tả đủ để khách quyết định", "A description guests can decide on"),
                    T("Khoảng \(target)+ ký tự: diễn ra thế nào, dành cho ai, cần mang gì. Hiện có \(chars).",
                      "About \(target)+ characters: how it goes, who it's for, what to bring. Now \(chars)."))
        case "included":
            let body = c.share != nil
                ? T("\(pct(c.share)) sự kiện kín chỗ có ghi mục bao gồm.", "\(pct(c.share)) of well-filled events listed what's included.")
                : T("Khách đặt chỗ dễ hơn khi biết giá đã gồm những gì.", "Guests book more easily when they know what the price covers.")
            return (T("Ghi rõ những gì bao gồm", "List what's included"), body + " " + evidence)
        case "keywords":
            let list = c.suggestions.joined(separator: ", ")
            let more = c.suggestions.isEmpty ? "" : " " + T("Host khác hay dùng: \(list).", "Other hosts use: \(list).")
            return (T("3+ từ khoá tìm kiếm", "3+ search keywords"),
                    T("Từ khoá giúp khách tìm thấy bạn trên Bản đồ và Tìm kiếm.", "Keywords help guests find you in Map and Search.") + more)
        case "price":
            let band = c.p25 != nil ? "\(formatVndShort(c.p25))–\(formatVndShort(c.p75))" : ""
            let title = T("Giá phù hợp", "A price that fits")
            guard c.source == .data else {
                return (title, T("Sự kiện giá thấp thường được đặt sát ngày — hãy chia sẻ sớm và nhắc lại tuần cuối.",
                                 "Low-priced events tend to book late — share early and again in the final week.") + " " + evidence)
            }
            let pos: String
            switch c.position {
            case "free": pos = T("Miễn phí — khách đặt dễ, nhưng tỉ lệ vắng cao hơn.", "Free — easy to book, but more no-shows.")
            case "below": pos = T("Thấp hơn mức thường gặp (\(band)) — dễ kín chỗ.", "Below the typical \(band) — easier to fill.")
            case "typical": pos = T("Trong mức thường gặp \(band).", "Within the typical \(band).")
            case "premium": pos = T("Cao hơn mức thường gặp \(band) — nói rõ vì sao đáng giá.", "Above the typical \(band) — say clearly why it's worth it.")
            default: pos = T("Mức thường gặp: \(band).", "Typical: \(band).")
            }
            return (title, pos + " " + evidence)
        case "seats":
            let body = c.typicalGuests.map {
                T("Sự kiện tương tự thường đón khoảng \(num($0)) khách.", "Similar events usually welcome about \(num($0)) guests.")
            } ?? T("Nhóm nhỏ (10–20) nhanh kín chỗ hơn và tạo cảm giác đông vui.", "Small groups (10–20) fill sooner and feel lively.")
            return (T("Số chỗ vừa sức", "Seats you can fill"), body + " " + evidence)
        case "timing":
            let title = T("Ngày & giờ", "Day & time")
            if c.status == .missing { return (title, T("Chọn ngày và giờ.", "Pick a date and time.")) }
            if c.source == .data, let dow = c.dow, let slot = c.slot {
                let label = slotLabel(dow: dow, slot: slot, T)
                let own = T("\(label) thường kín \(pct(c.ownFill)).", "\(label) usually fills \(pct(c.ownFill)).")
                let best = c.best.map { b in
                    " " + T("Tốt nhất: \(slotLabel(dow: b.dow, slot: b.slot, T)) (\(pct(b.fill))).",
                            "Best: \(slotLabel(dow: b.dow, slot: b.slot, T)) (\(pct(b.fill))).")
                } ?? ""
                return (title, own + best + " " + evidence)
            }
            return (title, T("Tối thứ 6 và thứ 7 thường bán vé tốt nhất, nhưng chênh lệch giữa các ngày không lớn.",
                             "Friday and Saturday evenings tend to sell best, but the gap between days is small.") + " " + evidence)
        case "lead":
            let body = c.source == .data
                ? T("Sự kiện kín chỗ thường được đăng trước khoảng \(target) ngày.", "Events that filled were posted about \(target) days ahead.")
                : T("Phần lớn vé bán trong tuần cuối, nhưng có thời gian chia sẻ sớm vẫn giúp ích.", "Most tickets sell in the final week, but time to share early still helps.")
            let left = c.days.map { " " + T("Còn \(max($0, 0)) ngày.", "\(max($0, 0)) days to go.") } ?? ""
            return (T("Đăng trước \(target)+ ngày", "Post \(target)+ days ahead"), body + left + " " + evidence)
        case "greeting":
            return (T("Lời chào khi khách nhắn", "An opening message"),
                    T("Khách nhắn tin hỏi trước khi đặt — một lời chào sẵn giúp họ yên tâm.",
                      "Guests often message before booking — a ready greeting reassures them."))
        default:
            return (c.id, "")
        }
    }
}
