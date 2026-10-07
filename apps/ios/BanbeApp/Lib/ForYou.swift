import Foundation

// Deterministic "For You" matching. No network, no AI, no randomness: the
// same preferences + the same events + the same `now` always give the same
// ordered list. Rules are documented in
// .claude/notes/34-onboarding-for-you-criteria.md — keep the two in sync.

/// Everything the matcher needs about one event, already normalized.
struct ForYouCandidate: Equatable {
    let key: String
    /// Category ids (catKey, cat2Key) — only ids in the shared interest taxonomy count.
    let categories: [String]
    /// Whole currency units + ISO code. `currency == nil` means "cannot compare"
    /// (e.g. a US event: the schema only stores `price_vnd`, and we never invent an FX rate).
    let priceAmount: Int?
    let priceCurrency: String?
    let isFree: Bool
    let startsAt: Date?
    let timeZone: TimeZone?
    /// Discoverable now: not cancelled, not ended, not sold out.
    let isBookable: Bool
}

struct ForYouMatch: Equatable {
    let key: String
    let score: Int
    let reasons: [String]
}

enum ForYou {
    /// Documented category affinity for each goal (soft signal, +10 each, capped at +20).
    static let goalAffinity: [String: Set<String>] = [
        "meet_people": ["supper", "popup", "music"],
        "learn": ["gallery", "fashion"],
        "experiences": ["supper", "fashion", "gallery", "music", "popup"],
        "networking": ["popup", "fashion", "supper"],
    ]

    // MARK: time zone (events are normalized to THEIR timezone, not the device's)

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

    /// VN → Asia/Ho_Chi_Minh (the app's own convention); US → by state; anything else → nil (unknown).
    static func timeZone(countryCode: String?, stateProvince: String?) -> TimeZone? {
        switch (countryCode ?? "VN").uppercased() {
        case "VN": return TimeZone(identifier: "Asia/Ho_Chi_Minh")
        case "US":
            guard let s = stateProvince?.trimmingCharacters(in: .whitespaces).lowercased(),
                  let id = usStateZones[s] else { return nil }
            return TimeZone(identifier: id)
        default: return nil
        }
    }

    /// Price currency of an event row. `price_vnd` is the only stored price,
    /// so it is VND for Vietnam (and legacy rows with no country); for any
    /// other country the currency is unknown and budget comparison is skipped.
    static func priceCurrency(countryCode: String?) -> String? {
        (countryCode ?? "VN").uppercased() == "VN" ? "VND" : nil
    }

    // MARK: matching

    /// nil = excluded (a hard rule failed) or no positive signal at all.
    static func match(_ e: ForYouCandidate, prefs p: EventPreferences, now: Date = Date()) -> ForYouMatch? {
        guard e.isBookable else { return nil }
        if let s = e.startsAt, s < now { return nil }

        var score = 0
        var reasons: [String] = []

        // 1. Interests — HARD when explicitly chosen: an event whose known
        //    category is outside the chosen set is not "for you". Events with
        //    no known category pass (unknown data never excludes).
        let interests = p.declaredInterests
        let known = e.categories.filter { c in EventPrefTaxonomy.interests.contains { $0.id == c } }
        if !interests.isEmpty, !known.isEmpty {
            guard known.contains(where: interests.contains) else { return nil }
            score += 50; reasons.append("interest")
        }

        // 2. Budget — HARD cap only when currencies are comparable.
        if let b = p.budget {
            if b.tier == "free" {
                guard e.isFree else { return nil }
                score += 20; reasons.append("budget")
            } else if e.isFree {
                if b.tier != EventPrefTaxonomy.noPreference { score += 10; reasons.append("budget") }
            } else if let cap = BudgetRegion.forCurrency(b.currency).cap(tier: b.tier),
                      let amount = e.priceAmount, let cur = e.priceCurrency,
                      cur == BudgetRegion.forCurrency(b.currency).currency {
                guard amount <= cap else { return nil }
                score += 20; reasons.append("budget")
            }
            // flexible / no_preference / currency not comparable → neutral
        }

        // 3. Goals — soft affinity.
        let goalHits = p.declaredGoals.filter { g in
            !(goalAffinity[g] ?? []).isDisjoint(with: Set(e.categories))
        }.count
        if goalHits > 0 { score += min(goalHits, 2) * 10; reasons.append("goal") }

        // 4. Availability — soft, in the EVENT's timezone. Only compared when
        //    the user picked a concrete value and the event time/zone are known.
        let avail = p.declaredAvailability
        if !avail.isEmpty, let s = e.startsAt, let tz = e.timeZone {
            var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
            let weekday = cal.component(.weekday, from: s)           // 1 = Sunday … 7 = Saturday
            let isWeekend = weekday == 1 || weekday == 7
            let hour = cal.component(.hour, from: s)
            let isDaytime = hour < 17
            let dayPicked = avail.filter { $0 == "weekdays" || $0 == "weekends" }
            let timePicked = avail.filter { $0 == "daytime" || $0 == "evening" }
            var fit = 0, miss = 0
            if !dayPicked.isEmpty { dayPicked.contains(isWeekend ? "weekends" : "weekdays") ? (fit += 1) : (miss += 1) }
            if !timePicked.isEmpty { timePicked.contains(isDaytime ? "daytime" : "evening") ? (fit += 1) : (miss += 1) }
            if miss > 0 { score -= 15 } else if fit > 0 { score += 10; reasons.append("time") }
        }

        // 5. Languages — events carry no language field yet, so this is
        //    deliberately neutral (never excludes, never scores).

        // Recency tie-break: events within 14 days get up to +5.
        if let s = e.startsAt {
            let days = s.timeIntervalSince(now) / 86_400
            if days <= 14 { score += max(0, 5 - Int(days / 3)) }
        }

        // Needs at least one affirmative signal besides the recency nudge.
        guard !reasons.isEmpty, score > 0 else { return nil }
        return ForYouMatch(key: e.key, score: score, reasons: reasons)
    }

    /// Ordered matches: score desc, then soonest start, then key (total order → stable).
    static func rank(_ events: [ForYouCandidate], prefs: EventPreferences, now: Date = Date()) -> [ForYouMatch] {
        let byKey = Dictionary(events.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        return events.compactMap { match($0, prefs: prefs, now: now) }.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            let sa = byKey[a.key]?.startsAt ?? .distantFuture, sb = byKey[b.key]?.startsAt ?? .distantFuture
            if sa != sb { return sa < sb }
            return a.key < b.key
        }
    }
}
