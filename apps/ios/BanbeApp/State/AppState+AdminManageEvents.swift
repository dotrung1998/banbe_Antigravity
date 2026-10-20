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
    var organizerName: String?

    enum CodingKeys: String, CodingKey {
        case id, name, status
        case startsAt = "starts_at"
        case removalReason = "removal_reason"
        case removedAt = "removed_at"
        case organizerId = "organizer_id"
    }

    init(id: String, name: String, status: String, startsAt: Date?, removalReason: String? = nil, removedAt: Date? = nil,
         organizerId: String? = nil, organizerName: String? = nil) {
        self.id = id; self.name = name; self.status = status; self.startsAt = startsAt
        self.removalReason = removalReason; self.removedAt = removedAt
        self.organizerId = organizerId; self.organizerName = organizerName
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
        var query = SupabaseService.client.from("events")
            .select("id,name,status,starts_at,removal_reason,removed_at,organizer_id")
        if let status { query = query.eq("status", value: status) }
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "_", with: " ")
        if !term.isEmpty { query = query.ilike("name", pattern: "%\(term)%") }
        let rows: [AdminEventRow] = try await query.order("starts_at", ascending: false).limit(200).execute().value
        let names = await organizerNames(for: Array(Set(rows.compactMap(\.organizerId))))
        return rows.map { row in
            var r = row
            if let org = row.organizerId { r.organizerName = names[org] }
            return r
        }
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
