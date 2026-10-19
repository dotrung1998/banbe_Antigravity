import Foundation
import Supabase

// Discovery Home + Search + host recipe data (note 50). Web twin: BanBeContext.jsx (`eventFill`,
// `homeFilters`, `openSearch`) and src/lib/useHostBenchmarks.js. Every RPC here is best-effort: migration
// 186 may not be deployed, and a missing function must never break Home or the create flow — it only means
// no fill badges and no benchmark numbers (tips only).

/// Recent Search queries, on this device only (web: localStorage `banbe_recent_searches_v1`). Max 8,
/// newest first, de-duplicated accent/case-insensitively. A convenience, never synced.
enum RecentSearches {
    static let key = "banbe.recentSearches.v1"
    static let max = 8

    static func load(_ defaults: UserDefaults = .standard) -> [String] {
        Array((defaults.stringArray(forKey: key) ?? []).prefix(max))
    }
    static func save(_ list: [String], _ defaults: UserDefaults = .standard) {
        defaults.set(Array(list.prefix(max)), forKey: key)
    }
    static func push(_ list: [String], _ query: String) -> [String] {
        let t = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return list }
        let k = SearchMatch.normalize(t)
        return Array(([t] + list.filter { SearchMatch.normalize($0) != k }).prefix(max))
    }
}

extension AppState {
    // MARK: Seat fill (get_public_event_fill)

    private struct FillRow: Decodable {
        let eventId: String
        let booked: Int
        let capacity: Int
        enum CodingKeys: String, CodingKey { case eventId = "event_id", booked, capacity }
    }

    /// Counts bookings with the SAME booking_holds_seat() rule hold_seats enforces (migration 186), because
    /// `seats_remaining` is never decremented after insert. A missing function (not deployed) or an error
    /// leaves `eventFill` untouched, so no badge is ever guessed.
    func loadPublicEventFill(ids: [String]) async {
        let liveIDs = Array(ids.prefix(300))
        guard !liveIDs.isEmpty else { return }
        do {
            let rows: [FillRow] = try await SupabaseService.client
                .rpc("get_public_event_fill", params: ["p_event_ids": liveIDs])
                .execute().value
            var next = eventFill
            for r in rows { next[r.eventId] = (r.booked, r.capacity) }
            eventFill = next
        } catch {
            #if DEBUG
            print("get_public_event_fill unavailable (migration 186 not applied?):", error)
            #endif
        }
    }

    // MARK: One normalized item per feed event

    static let catalogKeys: Set<String> = Set(EventCatalog.all.map(\.key))

    /// The demo catalogue's own simulated "today" (src/data/events.js TODAY = 8 July 2026), Vietnam midnight.
    static let catalogSimulatedToday: Date = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = AppState.vietnamTimeZone
        return cal.date(from: DateComponents(year: 2026, month: 7, day: 8))!
    }()

    /// Real start of an event for date chips, badges and Search. Real events: their `starts_at`. Demo
    /// events: the live row's `starts_at` when there is one, else the catalogue date shifted by (real today −
    /// simulated today) — the same offset their "in N days" label already uses (web `catalogStartMs`).
    /// The demo wall clock is read from the catalogue's own "dd.MM ▪︎ HH:mm" label in Vietnam time:
    /// events.json's `startDate` was serialized on a non-Vietnam machine and is hours off.
    func discoveryStart(for e: CatalogEvent, now: Date = Date()) -> Date? {
        guard Self.catalogKeys.contains(e.key) else { return e.startDate }
        if let live = homeLiveEvents[e.key]?.startsAt { return live }
        let label = EventCatalog.all.first(where: { $0.key == e.key })?.when ?? e.when
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = AppState.vietnamTimeZone
        guard let dm = label.firstMatch(of: #/(\d{1,2})\.(\d{2})/#), let day = Int(dm.1), let month = Int(dm.2) else { return nil }
        let tm = label.firstMatch(of: #/(\d{1,2}):(\d{2})/#)
        let hour = tm.flatMap { Int($0.1) } ?? 19
        let minute = tm.flatMap { Int($0.2) } ?? 0
        guard let wall = cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute)) else { return nil }
        let shift = cal.startOfDay(for: now).timeIntervalSince(Self.catalogSimulatedToday)
        return wall.addingTimeInterval(shift)
    }

    /// Banbe Pulse score by event id — the same ranking the Pulse viewer uses (Popular sort + label).
    var pulseScores: [String: Double] {
        Dictionary(pulseDaily.map { ($0.eventId, $0.score) }, uniquingKeysWith: { a, _ in a })
    }

    func discoveryItem(for e: CatalogEvent, now: Date = Date(), scores: [String: Double]? = nil) -> HomeDiscovery.Item {
        let fill = eventFill[e.key]
        let price: Int?
        if Self.catalogKeys.contains(e.key) {
            let lower = e.price.lowercased()
            if lower.contains("miễn phí") || lower.contains("free") { price = 0 }
            else { let v = e.priceVnd; price = v > 0 ? v : nil }
        } else {
            price = e.priceVnd
        }
        let distance = located == true ? haversineKm(from: userCoords, to: e) : nil
        return HomeDiscovery.Item(
            key: e.key, startsAt: discoveryStart(for: e, now: now), priceVnd: price,
            catKeys: [e.catKey, e.cat2Key].compactMap { $0 },
            booked: fill?.booked, capacity: fill?.capacity, soldOut: e.soldOut,
            distanceKm: distance, popularity: (scores ?? pulseScores)[e.key]
        )
    }

    /// Card meta line: "area · distance · category" (note 50). Real events used to repeat the category
    /// ("Supper club ▪︎ Supper club ▪︎ Quận 3": `fromReal`'s meta already starts with it).
    func metaLine(for event: CatalogEvent, distanceKm: Double?) -> String {
        let area = event.locationLabel ?? event.location?.area
        let km = distanceKm.map { String(format: "%.1f", $0).replacingOccurrences(of: ".", with: ",") + " km" }
        let cat = event.catDisplay.isEmpty ? event.cat : event.catDisplay
        return [area, km, cat.isEmpty ? nil : trStatus(cat)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    func setHomeFilters(_ next: HomeDiscovery.Filters) { homeFilters = next }

    private static var vnCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = AppState.vietnamTimeZone
        return cal
    }

    /// Photo badge: "TODAY · 19:00" / "TMRW · 19:00" / "SAT 24/10 · 19:00", in Vietnam time.
    func discoveryDateBadge(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }
        let cal = Self.vnCalendar
        let c = cal.dateComponents([.weekday, .day, .month, .hour, .minute], from: date)
        let wd = (c.weekday ?? 1) - 1
        let time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        let day: String
        if cal.isDate(date, inSameDayAs: now) { day = T("HÔM NAY", "TODAY") }
        else if let tmrw = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(date, inSameDayAs: tmrw) { day = T("MAI", "TMRW") }
        else {
            let vi = ["CN", "T2", "T3", "T4", "T5", "T6", "T7"][wd]
            let en = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"][wd]
            day = "\(T(vi, en)) \(c.day ?? 1)/\(c.month ?? 1)"
        }
        return "\(day) · \(time)"
    }

    /// Search row: "T7, 24.10 · 19:00" in Vietnam time.
    func discoveryWhenLabel(_ date: Date?) -> String {
        guard let date else { return "" }
        let c = Self.vnCalendar.dateComponents([.weekday, .day, .month, .hour, .minute], from: date)
        let wd = (c.weekday ?? 1) - 1
        let vi = ["CN", "Th 2", "Th 3", "Th 4", "Th 5", "Th 6", "Th 7"][wd]
        let en = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][wd]
        return String(format: "%@, %02d.%02d · %02d:%02d", T(vi, en), c.day ?? 1, c.month ?? 1, c.hour ?? 0, c.minute ?? 0)
    }

    // MARK: Search screen

    func openSearch(from frame: CGRect? = nil) {
        searchEntranceFrom = (frame?.width ?? 0) > 0 ? frame : nil
        // From Home: an overlay over the live Home (no screen switch, nothing unmounted or reloaded).
        if screen == .home {
            searchBackScreen = .home
            searchOverlayOpen = true
            return
        }
        if screen != .search { searchBackScreen = screen }
        screen = .search
    }

    /// "See on map": Map opens fresh with the query already applied (no keyboard).
    func seeSearchOnMap(_ query: String) {
        mapExploreState = nil
        mapExploreSeedQuery = query
        screen = .mapExplore
    }

    // MARK: Host benchmarks + audience demand (create flow)

    private struct BenchmarkParams: Encodable {
        let cat: String
        let city: String
        enum CodingKeys: String, CodingKey { case cat = "p_cat_key", city = "p_city" }
    }

    /// One request per category+city per session. nil = cold start / offline / not deployed (tips only).
    func hostBenchmarks(cat rawCat: String, city rawCity: String) async -> HostBenchmarks? {
        let cat = rawCat.trimmingCharacters(in: .whitespaces).lowercased()
        let city = rawCity.trimmingCharacters(in: .whitespaces).lowercased()
        let key = "\(cat)|\(city)"
        if let cached = hostBenchmarksCache[key] { return cached }
        #if DEBUG
        if UITestFixture.isActive { return nil }
        #endif
        guard isSignedIn else { return nil }
        var result: HostBenchmarks?
        do {
            let b: HostBenchmarks = try await SupabaseService.client
                .rpc("get_host_benchmarks", params: BenchmarkParams(cat: cat, city: city))
                .execute().value
            result = b.success == false ? nil : b
        } catch {
            #if DEBUG
            print("get_host_benchmarks unavailable (migration 186 not applied?):", error)
            #endif
        }
        hostBenchmarksCache[key] = result
        return result
    }

    private struct DemandRow: Decodable {
        let interestedPeople: Int?
        enum CodingKeys: String, CodingKey { case interestedPeople = "interested_people" }
    }

    /// "120+ people on banbe are into Supper clubs" — floored to 10s server-side, nil under 10.
    func audienceDemand(cat rawCat: String) async -> Int? {
        let cat = rawCat.trimmingCharacters(in: .whitespaces).lowercased()
        guard !cat.isEmpty else { return nil }
        if let cached = audienceDemandCache[cat] { return cached }
        #if DEBUG
        if UITestFixture.isActive { return nil }
        #endif
        guard isSignedIn else { return nil }
        var result: Int?
        do {
            let row: DemandRow = try await SupabaseService.client
                .rpc("get_audience_demand", params: ["p_cat_key": cat])
                .execute().value
            result = row.interestedPeople
        } catch {
            #if DEBUG
            print("get_audience_demand unavailable (migration 186 not applied?):", error)
            #endif
        }
        audienceDemandCache[cat] = result
        return result
    }

    /// Editing: show the goal the host picked last time (host-only read).
    func loadEventHostGoal(eventID: String) async {
        do {
            let goal: String? = try await SupabaseService.client
                .rpc("get_event_host_goal", params: ["p_event_id": eventID])
                .execute().value
            if let goal, EventRecipe.hostGoals.contains(goal), createEditEventId == eventID { createHostGoal = goal }
        } catch {
            #if DEBUG
            print("get_event_host_goal unavailable (migration 186 not applied?):", error)
            #endif
        }
    }

    private struct HostGoalParams: Encodable {
        let eventID: String
        let goal: String?
        enum CodingKeys: String, CodingKey { case eventID = "p_event_id", goal = "p_goal" }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(eventID, forKey: .eventID)
            // An explicit null (not an omitted key) so PostgREST still finds the 2-argument function.
            if let goal { try c.encode(goal, forKey: .goal) } else { try c.encodeNil(forKey: .goal) }
        }
    }

    /// Host-only side table, best-effort like keywords/visibility. On edit it is always written so a host
    /// can clear an earlier answer.
    func saveEventHostGoal(eventID: String, goal: String?) async {
        do {
            let _: JSONValue = try await SupabaseService.client
                .rpc("set_event_host_goal", params: HostGoalParams(eventID: eventID, goal: goal))
                .execute().value
        } catch {
            #if DEBUG
            print("set_event_host_goal failed (migration 186 not applied?):", error)
            #endif
        }
    }
}
