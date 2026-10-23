import Foundation

// Admin > Manage events (migrations 188 + 189, note 54). Admins can remove (hide, records kept), restore, and
// permanently purge never-booked events, one or many at a time; the server decides who may and what's allowed
// (is_platform_admin + the account gate, row locks, money-in-play blockers). Web twin: src/lib/adminEvents.js +
// src/screens/AdminManageEvents.jsx.
//
// TESTING-PHASE: `wipeEventsTesting` (admin_wipe_events_testing) permanently erases ANY event with everything tied to
// it. iOS only, and only while the admin feature switch "admin_event_wipe" is on (seeded off). Remove it, the
// AdminManageEventsView wipe action and the AdminFeaturesView switch row before public release (note 54).

struct AdminEventRow: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let status: String
    let startsAt: Date?
    let removalReason: String?
    let removedAt: Date?
    let organizerId: String?
    // Expanded-row details (2026-10-21).
    var createdAt: Date? = nil
    var submittedAt: Date? = nil
    var priceVnd: Int? = nil
    var capacity: Int? = nil
    var seatsRemaining: Int? = nil
    var area: String? = nil
    /// Location + migration 195's zone/currency, so the start time reads in the venue's zone and the price in its
    /// own currency (`tz`/`currency` are absent on a server without 195).
    var countryCode: String? = nil
    var stateProvince: String? = nil
    var tz: String? = nil
    var currency: String? = nil
    var timeZone: TimeZone { EventMarket.timeZone(EventMarket.rowTimeZoneID(tz: tz, countryCode: countryCode, stateProvince: stateProvince)) }
    var rowCurrency: String { EventMarket.rowCurrency(currency) }
    // Filled from the organizers lookup (not columns of `events`).
    var organizerName: String?
    /// The organizer row was found (false = deleted, or not readable).
    var organizerFound = true
    /// The organizer still has an owner or user (both go NULL when that account is deleted).
    var organizerHasAccount = true

    enum CodingKeys: String, CodingKey {
        case id, name, status, capacity, area
        case startsAt = "starts_at"
        case removalReason = "removal_reason"
        case removedAt = "removed_at"
        case organizerId = "organizer_id"
        case createdAt = "created_at"
        case submittedAt = "submitted_at"
        case priceVnd = "price_vnd"
        case seatsRemaining = "seats_remaining"
        case countryCode = "country_code"
        case stateProvince = "state_province"
        case tz, currency
    }

    init(id: String, name: String, status: String, startsAt: Date?, removalReason: String? = nil, removedAt: Date? = nil,
         organizerId: String? = "fx-org", organizerName: String? = nil, organizerFound: Bool = true, organizerHasAccount: Bool = true,
         createdAt: Date? = nil, submittedAt: Date? = nil, priceVnd: Int? = nil, capacity: Int? = nil, seatsRemaining: Int? = nil,
         area: String? = nil) {
        self.id = id; self.name = name; self.status = status; self.startsAt = startsAt
        self.removalReason = removalReason; self.removedAt = removedAt
        self.organizerId = organizerId; self.organizerName = organizerName
        self.organizerFound = organizerFound; self.organizerHasAccount = organizerHasAccount
        self.createdAt = createdAt; self.submittedAt = submittedAt; self.priceVnd = priceVnd
        self.capacity = capacity; self.seatsRemaining = seatsRemaining; self.area = area
    }

    /// The host account is gone: see `AdminManagedEvents.isOrphan`.
    var isOrphan: Bool {
        AdminManagedEvents.isOrphan(organizerId: organizerId, organizerFound: organizerFound,
                                    organizerHasAccount: organizerHasAccount, organizerName: organizerName)
    }
}

/// Pure rules for Admin > Manage events (2026-10-21). Web twin: isOrphanEvent / needsAnotherPage in
/// src/lib/adminEvents.js.
enum AdminManagedEvents {
    /// What api/_lib/organizerCleanup.js renames an organizer to when its owner deletes their account.
    static let deletedOrganizerName = "Deleted organizer"
    static let pageSize = 500
    static let cap = 5000

    /// True when the event's host account is gone: no organizer, an organizer row that no longer exists, an organizer
    /// with neither owner nor user (profiles cascade SET NULL on account deletion), or one anonymized by the
    /// account-deletion cleanup. Only banbe can settle such an event now.
    static func isOrphan(organizerId: String?, organizerFound: Bool, organizerHasAccount: Bool, organizerName: String?) -> Bool {
        guard organizerId != nil, organizerFound else { return true }
        return !organizerHasAccount || organizerName == deletedOrganizerName
    }

    static func needsAnotherPage(lastPageCount: Int, totalSoFar: Int, pageSize: Int = pageSize, cap: Int = cap) -> Bool {
        lastPageCount == pageSize && totalSoFar < cap
    }
}

/// What still ties an event to money or an open conversation (admin_event_removal_check).
struct AdminEventCheck: Decodable, Equatable {
    let eventId: String
    let found: Bool
    let activeBookings: Int
    let unsettledRefunds: Int
    let openDisputes: Int
    let bookingsEver: Int
    let removable: Bool
    let purgeable: Bool

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id", found, removable, purgeable
        case activeBookings = "active_bookings", unsettledRefunds = "unsettled_refunds"
        case openDisputes = "open_disputes", bookingsEver = "bookings_ever"
    }

    init(eventId: String, found: Bool = true, activeBookings: Int = 0, unsettledRefunds: Int = 0, openDisputes: Int = 0,
         bookingsEver: Int = 0, removable: Bool = true, purgeable: Bool = false) {
        self.eventId = eventId; self.found = found; self.activeBookings = activeBookings
        self.unsettledRefunds = unsettledRefunds; self.openDisputes = openDisputes; self.bookingsEver = bookingsEver
        self.removable = removable; self.purgeable = purgeable
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        eventId = try c.decode(String.self, forKey: .eventId)
        found = try c.decodeIfPresent(Bool.self, forKey: .found) ?? false
        activeBookings = try c.decodeIfPresent(Int.self, forKey: .activeBookings) ?? 0
        unsettledRefunds = try c.decodeIfPresent(Int.self, forKey: .unsettledRefunds) ?? 0
        openDisputes = try c.decodeIfPresent(Int.self, forKey: .openDisputes) ?? 0
        bookingsEver = try c.decodeIfPresent(Int.self, forKey: .bookingsEver) ?? 0
        removable = try c.decodeIfPresent(Bool.self, forKey: .removable) ?? false
        purgeable = try c.decodeIfPresent(Bool.self, forKey: .purgeable) ?? false
    }

    var isBlocked: Bool { activeBookings > 0 || unsettledRefunds > 0 || openDisputes > 0 }
}

struct AdminEventActionResult: Decodable, Equatable {
    let eventId: String
    let ok: Bool
    let error: String?
    enum CodingKeys: String, CodingKey { case eventId = "event_id", ok, error }
}

/// One admin event action's outcome: how many went through, and why the others didn't.
struct AdminEventActionOutcome: Equatable {
    var error: String?          // whole-call refusal (NOT_AUTHORIZED, REASON_REQUIRED, NOT_ENABLED, NOT_DEPLOYED…)
    var done = 0
    var skipped: [AdminEventActionResult] = []
    var ok: Bool { error == nil }
}

enum AdminEventAction: String {
    case remove = "admin_remove_events"
    case restore = "admin_restore_events"
    case purge = "admin_purge_events"
    case wipeTesting = "admin_wipe_events_testing"   // TESTING-PHASE
}

extension AppState {
    /// Every event an admin may manage (RLS events_select_admin lets an admin read all of them). `status` nil = all.
    func loadAdminManagedEvents(status: String?, search: String) async throws -> [AdminEventRow] {
        #if DEBUG
        if UITestFixture.isActive { return UITestFixture.adminManagedEvents.filter { status == nil || $0.status == status } }
        #endif
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "_", with: " ")
        // Paged (2026-10-21): a single .limit(200) cut off older events, which is where orphaned drafts/ended sit.
        var rows: [AdminEventRow] = []
        var page = 0
        while true {
            let batch: [AdminEventRow] = try await EventMarketColumns.retrying {
            var query = SupabaseService.client.from("events")
                .select("id,name,status,starts_at,created_at,submitted_at,price_vnd,capacity,seats_remaining,area,removal_reason,removed_at,organizer_id,country_code,state_province" + (EventMarketColumns.missing ? "" : ",tz,currency"))
            if let status { query = query.eq("status", value: status) }
            if !term.isEmpty { query = query.ilike("name", pattern: "%\(term)%") }
            let from = page * AdminManagedEvents.pageSize
            return try await query
                .order("starts_at", ascending: false, nullsFirst: false).order("id")
                .range(from: from, to: from + AdminManagedEvents.pageSize - 1).execute().value
            }
            rows += batch
            page += 1
            if !AdminManagedEvents.needsAnotherPage(lastPageCount: batch.count, totalSoFar: rows.count) { break }
        }
        let owners = await adminOrganizerOwners(Array(Set(rows.compactMap(\.organizerId))))
        return rows.map { row in
            var r = row
            if let org = row.organizerId {
                let o = owners[org]
                r.organizerName = o?.name
                r.organizerFound = o != nil
                r.organizerHasAccount = o.map { $0.ownerID != nil || $0.userID != nil } ?? false
            }
            return r
        }
    }

    /// Name and owner of each organizer, for the orphan check (admins can read organizers).
    private func adminOrganizerOwners(_ ids: [String]) async -> [String: (name: String, ownerID: String?, userID: String?)] {
        guard !ids.isEmpty else { return [:] }
        struct Row: Decodable {
            let id: String; let name: String?; let ownerID: String?; let userID: String?
            enum CodingKeys: String, CodingKey { case id, name, ownerID = "owner_id", userID = "user_id" }
        }
        var out: [String: (name: String, ownerID: String?, userID: String?)] = [:]
        for chunk in stride(from: 0, to: ids.count, by: 200).map({ Array(ids[$0..<min($0 + 200, ids.count)]) }) {
            guard let rows: [Row] = try? await SupabaseService.client.from("organizers")
                .select("id,name,owner_id,user_id").in("id", values: chunk).execute().value else { continue }
            for r in rows { out[r.id] = (r.name ?? "", r.ownerID, r.userID) }
        }
        return out
    }

    func adminEventChecks(_ ids: [String]) async -> [String: AdminEventCheck] {
        guard !ids.isEmpty else { return [:] }
        #if DEBUG
        if UITestFixture.isActive {
            return Dictionary(uniqueKeysWithValues: ids.map { id in (id, UITestFixture.adminEventChecks[id] ?? AdminEventCheck(eventId: id)) })
        }
        #endif
        struct Params: Encodable { let p_event_ids: [String] }
        struct Reply: Decodable { let success: Bool?; let events: [AdminEventCheck]? }
        var out: [String: AdminEventCheck] = [:]
        for chunk in stride(from: 0, to: ids.count, by: 200).map({ Array(ids[$0..<min($0 + 200, ids.count)]) }) {
            guard let r: Reply = try? await SupabaseService.client
                .rpc("admin_event_removal_check", params: Params(p_event_ids: chunk)).execute().value,
                  r.success == true else { continue }
            for c in r.events ?? [] { out[c.eventId] = c }
        }
        return out
    }

    /// Runs one admin event action over `ids`. `reason` is required by remove and purge, ignored otherwise.
    func runAdminEventAction(_ action: AdminEventAction, ids: [String], reason: String = "") async -> AdminEventActionOutcome {
        guard !ids.isEmpty else { return AdminEventActionOutcome(error: "INVALID_VALUE") }
        #if DEBUG
        if UITestFixture.isActive { return UITestFixture.runAdminEventAction(action, ids: ids, reason: reason, app: self) }
        #endif
        struct Reply: Decodable {
            let success: Bool?; let error: String?
            let removed: Int?; let restored: Int?; let purged: Int?; let wiped: Int?
            let results: [AdminEventActionResult]?
        }
        do {
            let reply: Reply
            switch action {
            case .remove, .purge:
                struct P: Encodable { let p_event_ids: [String]; let p_reason: String }
                reply = try await SupabaseService.client.rpc(action.rawValue, params: P(p_event_ids: ids, p_reason: reason)).execute().value
            case .restore, .wipeTesting:
                struct P: Encodable { let p_event_ids: [String] }
                reply = try await SupabaseService.client.rpc(action.rawValue, params: P(p_event_ids: ids)).execute().value
            }
            guard reply.success == true else { return AdminEventActionOutcome(error: reply.error ?? "UNKNOWN") }
            let done = reply.removed ?? reply.restored ?? reply.purged ?? reply.wiped ?? 0
            return AdminEventActionOutcome(error: nil, done: done, skipped: (reply.results ?? []).filter { !$0.ok })
        } catch {
            return AdminEventActionOutcome(error: RewardsLogic.isFunctionMissing(error) ? "NOT_DEPLOYED" : "NETWORK")
        }
    }

    /// The host's own events an admin removed (shown on Dashboard; the reason arrived as a notification).
    var myRemovedEvents: [RealEventSummary] { myOrgEventSummaries.filter { $0.status == "removed" } }
}
