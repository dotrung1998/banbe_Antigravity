import Foundation
import Supabase

/// "Cancelled / expired" list housekeeping for Tickets & Bookings.
///
/// Removing a row here hides it from THIS account's list only. The booking row
/// itself is never deleted: it is the financial record behind any refund claim,
/// and the organizer keeps their own view of it. That matches how "delete my
/// copy" already works for refund disputes (migration 134).
///
/// Rows leave the list in two ways:
///   * the user removes them (one, several or all), or
///   * 30 days after this device first showed them as cancelled/expired.
///     `bookings` carries no "cancelled at" timestamp, so the clock starts when
///     the row first lands in the section rather than at the booking's creation
///     date, which could be months before a late cancellation.
/// A row whose refund is still open is never auto-removed.
@MainActor
final class TicketRetentionStore: ObservableObject {
    static let shared = TicketRetentionStore()
    static let retention: TimeInterval = 30 * 24 * 3600

    @Published private(set) var hidden: Set<UUID> = []
    private var firstSeen: [String: Date] = [:]
    private var loadedFor: String?

    private func key(_ suffix: String, _ user: UUID) -> String { "ticketRetention.\(suffix).\(user.uuidString)" }

    private func load(for user: UUID) {
        guard loadedFor != user.uuidString else { return }
        loadedFor = user.uuidString
        let d = UserDefaults.standard
        hidden = Set((d.stringArray(forKey: key("hidden", user)) ?? []).compactMap(UUID.init(uuidString:)))
        firstSeen = (d.dictionary(forKey: key("seen", user)) as? [String: Date]) ?? [:]
    }

    private func save(for user: UUID) {
        let d = UserDefaults.standard
        d.set(hidden.map(\.uuidString), forKey: key("hidden", user))
        d.set(firstSeen, forKey: key("seen", user))
    }

    /// Call with the ids currently in the section. Starts the 30-day clock for new
    /// rows and hides the ones past it, except `protected` (open refund).
    func reconcile(user: UUID, inactive: [UUID], protected: Set<UUID>, now: Date = Date()) {
        load(for: user)
        var changed = false
        for id in inactive where firstSeen[id.uuidString] == nil {
            firstSeen[id.uuidString] = now
            changed = true
        }
        for id in inactive where !hidden.contains(id) && !protected.contains(id) {
            if let seen = firstSeen[id.uuidString], now.timeIntervalSince(seen) >= Self.retention {
                hidden.insert(id)
                changed = true
            }
        }
        if changed { save(for: user) }
    }

    func isHidden(_ id: UUID, user: UUID) -> Bool {
        load(for: user)
        return hidden.contains(id)
    }

    func remove(_ ids: Set<UUID>, user: UUID) {
        load(for: user)
        hidden.formUnion(ids)
        save(for: user)
        Task { await push(ids, user: user) }
    }

    // MARK: - Account sync (migration 176)

    private struct HiddenRow: Codable { let userId: UUID; let bookingId: UUID
        enum CodingKeys: String, CodingKey { case userId = "user_id", bookingId = "booking_id" } }

    private func push(_ ids: Set<UUID>, user: UUID) async {
        guard !ids.isEmpty else { return }
        do {
            try await SupabaseService.client.from("ticket_list_hidden")
                .upsert(ids.map { HiddenRow(userId: user, bookingId: $0) }, onConflict: "user_id,booking_id", ignoreDuplicates: true)
                .execute()
        } catch { print("ticket_list_hidden push failed:", error) }
    }

    /// Merges the hidden ids other devices saved to the account into this one and
    /// shares any that only exist here, so web and iOS show the same list.
    func sync(user: UUID) async {
        load(for: user)
        do {
            let rows: [HiddenRow] = try await SupabaseService.client.from("ticket_list_hidden")
                .select("user_id, booking_id").eq("user_id", value: user.uuidString).execute().value
            let remote = Set(rows.map(\.bookingId))
            let localOnly = hidden.subtracting(remote)
            if !remote.isSubset(of: hidden) { hidden.formUnion(remote); save(for: user) }
            await push(localOnly, user: user)
        } catch { print("ticket_list_hidden sync failed:", error) }
    }
}
