import Foundation
import Supabase

// L7 day-of card (docs/impl/phase3-extras.md; switch `live_activity`): finds this account's confirmed tickets and hands
// them to LiveActivityController. Completely inactive while the switch is off (any card still showing is ended).

/// bookings + the event (`events(*)`, so a server without a newer column never fails the read).
private struct EventDayBookingRow: Decodable {
    let id: UUID
    let code: String?
    let status: String?
    let paymentState: String?
    let recipientName: String?
    let events: EventDayEventRow?

    enum CodingKeys: String, CodingKey {
        case id, code, status, events
        case paymentState = "payment_state"
        case recipientName = "recipient_name"
    }
}

private struct EventDayEventRow: Decodable {
    let name: String?
    let startsAt: Date?
    let status: String?
    let area: String?
    let city: String?
    let addressLine: String?
    let countryCode: String?
    let stateProvince: String?
    let tz: String?

    enum CodingKeys: String, CodingKey {
        case name, status, area, city, tz
        case startsAt = "starts_at"
        case addressLine = "address_line"
        case countryCode = "country_code"
        case stateProvince = "state_province"
    }
}

extension AppState {
    var liveActivityEnabled: Bool { FeatureFlags.isOn(featureFlags, "live_activity") }

    /// Runs on launch, on every return to the foreground, when tickets load and when the switch changes (at most every
    /// 20 s unless forced, since tickets load often).
    func syncLiveActivities(force: Bool = false) {
        #if DEBUG
        if UITestFixture.isActive { return } // fixtures never reach ActivityKit or the server
        #endif
        let controller = LiveActivityController.shared
        // Switch off: nothing is read or started, and a card still showing ends. Signed out is handled by signOut();
        // a nil account at launch (session still restoring) must not end a card that should stay.
        guard liveActivityEnabled else {
            if controller.hasCards { Task { await controller.endAll() } }
            return
        }
        guard let uid = userID else { return }
        guard controller.activitiesAllowed else { return }
        if !force, let last = controller.lastSync, Date().timeIntervalSince(last) < 20 { return }
        controller.lastSync = Date()
        Task { [weak self] in
            guard let self, let tickets = await self.loadEventDayTickets(userID: uid),
                  self.userID == uid, self.liveActivityEnabled else { return }
            await controller.sync(tickets: tickets, lang: self.lang) { [weak self] in self?.syncLiveActivities(force: true) }
        }
    }

    /// This account's own confirmed tickets (not ones gifted to someone else) for live events. nil on a failed read,
    /// so a flaky network never ends a card that should stay.
    private func loadEventDayTickets(userID uid: UUID) async -> [EventDayTicket]? {
        do {
            let rows: [EventDayBookingRow] = try await SupabaseService.client
                .from("bookings")
                .select("id, code, status, payment_state, recipient_name, events(*)")
                .eq("user_id", value: uid.uuidString)
                .eq("status", value: "confirmed")
                .eq("payment_state", value: "confirmed")
                .execute().value
            return rows.compactMap { r in
                guard (r.recipientName ?? "").trimmingCharacters(in: .whitespaces).isEmpty,
                      let e = r.events, let start = e.startsAt,
                      e.status.map({ ["live", "ended"].contains($0) }) ?? true else { return nil } // the time rule decides the rest
                let place = (e.addressLine ?? "").trimmingCharacters(in: .whitespaces)
                let venue = place.isEmpty
                    ? [e.area, e.city].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ", ")
                    : place
                let zone = EventMarket.rowTimeZoneID(tz: e.tz, countryCode: e.countryCode, stateProvince: e.stateProvince)
                return EventDayTicket(bookingID: r.id.uuidString, eventName: e.name ?? "banbe", venue: venue,
                                      startsAt: start, ticketCode: r.code ?? "", timeZoneID: zone,
                                      market: CoreLoops.shareMarket(e.countryCode) ?? "VN")
            }
        } catch {
            #if DEBUG
            print("event-day tickets unavailable:", error)
            #endif
            return nil
        }
    }
}
