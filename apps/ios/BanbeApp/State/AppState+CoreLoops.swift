import Foundation
import UIKit

// Phase 2-3 core loops (docs/impl/phase2-core-loops.md, phase3-extras.md L5; migrations 199/200): navigation to the
// guest recap card (L2) and the host recap (L3), "Run it again", Home's "This weekend" jump (L5) and the thin RPC
// wrappers those screens use. Pure rules live in Lib/CoreLoops.swift. Web twin: BanBeContext.jsx (openEventRecap,
// openHostRecap, runItAgain, goHomeThisWeekend) + src/screens/EventRecap.jsx, HostRecap.jsx, DigestOptIn.jsx.
extension AppState {
    // MARK: Switches (all dark until an admin sets them, Lib/FeatureFlags.swift)

    var eventRecapEnabled: Bool { FeatureFlags.isOn(featureFlags, "event_recap") }
    var hostRecapEnabled: Bool { FeatureFlags.isOn(featureFlags, "host_recap") }
    var weeklyDigestEnabled: Bool { FeatureFlags.isOn(featureFlags, "weekly_digest") }

    // MARK: Navigation

    func openEventRecap(_ eventID: String, back: Screen) {
        eventRecapID = eventID
        eventRecapBack = back
        screen = .eventRecap
        Task { await loadMissingRealEvents(for: [eventID]) }
    }

    func openHostRecap(_ eventID: String, back: Screen) {
        hostRecapID = eventID
        hostRecapBack = back
        screen = .hostRecap
        if !myOrgEventSummaries.contains(where: { $0.id == eventID }) { Task { await loadMyOrgEventSummaries() } }
    }

    /// L5 weekly digest: Home, scrolled to the "This weekend" rail (HomeView consumes the request once).
    func goHomeThisWeekend() {
        goHome()
        // A remembered Home position would be re-applied over the jump for a moment (ScreenScaffold's restore).
        homeScrollOffsetY = nil
        homeScrollAnchorID = nil
        homeWeekendScrollRequest = UUID()
    }

    /// Where a core-loop notification goes (`CoreLoops.route`, the table shared with web through
    /// tests/fixtures/core-loops.json). A recap opens its card only while that switch is on (otherwise the event / the
    /// dashboard); a host recap only for an event this account organizes.
    func openCoreLoopNotification(_ notification: AppNotification) {
        guard let dest = CoreLoops.route(kind: notification.kind, data: notification.data) else { return }
        switch dest.route {
        case .ticket:
            guard let id = dest.id, let bookingID = UUID(uuidString: id) else { return }
            Task {
                let opened = await openBookingConfirmed(bookingID: bookingID, eventKey: notification.data["event_id"]?.stringValue, back: .notifications)
                if opened == false { reportStaleNotification(notification) }
            }
        case .eventRecap:
            guard let id = dest.id else { return }
            if eventRecapEnabled { openEventRecap(id, back: .notifications) } else { goEvent(id) }
        case .hostRecap:
            guard let id = dest.id, myOrgEventKeys.contains(id) else { return }
            if hostRecapEnabled { openHostRecap(id, back: .notifications) } else { goDashboard(back: .notifications) }
        case .event:
            if let id = dest.id { goEvent(id) }
        case .following:
            notificationsOverlayOpen = false
            screen = .following
        case .thisWeekend:
            goHomeThisWeekend()
        }
    }

    // MARK: L3 "Run it again"

    /// Create Event filled from one of the host's own events: the same fields an edit pre-fills (name, category,
    /// description, intro, included items, the confirmed address, capacity, price in its currency) plus its cover as
    /// the first photo, on the date `CoreLoops.runItAgainDate` picks (one week later, never in the past, at least 2
    /// days out, same time). Shows note 48's "pre-filled from …" notice with Start blank; nothing is created until the
    /// host submits.
    func runItAgain(_ real: RealEventSummary) {
        goCreate()
        guard screen == .create else { return } // signed out: goCreate asked for sign-in first
        // The address first: the form's zone and currency follow it, then the date/time are read in that zone.
        createCountryCode = real.countryCode
        createStateProvince = real.stateProvince
        createNeighborhood = real.neighborhood
        createPlaceTimeZoneID = real.tz
        let hadVerifiedAddress = real.addressVerified == true
        createLoc = hadVerifiedAddress ? "" : (real.area ?? "")
        createLat = real.lat
        createLng = real.lng
        createLocLabel = hadVerifiedAddress
            ? [real.addressLine, real.area, real.city].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            : ""
        createAddressLine = real.addressLine ?? ""
        createDistrict = real.area ?? ""
        createCity = real.city ?? ""
        createPostalCode = real.postalCode ?? ""
        createLocConfirmed = hadVerifiedAddress

        createName = real.name
        createDesc = real.description ?? ""
        createIntro = real.intro ?? ""
        createIncludedItems = real.includedItems ?? []
        createCats = real.catKey.map { [$0] } ?? []

        let next = CoreLoops.runItAgainDate(eventDate: real.eventDate, eventTime: real.eventTime,
                                            today: createFormatter("yyyy-MM-dd").string(from: Date()))
        createEventDate = next.date.flatMap { createFormatter("yyyy-MM-dd").date(from: $0) }
        createEventTime = next.time.flatMap { createFormatter("HH:mm").date(from: $0) }
        // A price is copied only into a form of the same currency (never dong shown as dollars); free stays empty.
        createPrice = real.priceVnd.flatMap { amount -> String? in
            guard amount > 0, real.rowCurrency == createCurrency else { return nil }
            return EventMarket.priceInputText(amount, currency: real.rowCurrency)
        } ?? ""
        createSeats = real.capacity.map(String.init) ?? ""
        if let date = createEventDate, let time = createEventTime {
            createAppliedDefaults = EventDraftDefaults(date: date, time: time, price: createPrice.isEmpty ? nil : createPrice,
                                                       seats: real.capacity ?? 0, categories: createCats, sourceName: real.name)
        } else {
            createAppliedDefaults = nil
        }
        createDefaultsSource = real.name

        createSeedCoverImage = nil
        if let url = real.photoURL {
            Task { [weak self] in
                guard let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) else { return }
                guard let self, self.screen == .create, self.createEditEventId == nil, self.createName == real.name else { return }
                self.createSeedCoverImage = image
            }
        }
    }

    // MARK: RPCs (each owner-only or host-only on the server)

    private struct EventIDParam: Encodable {
        let eventID: String
        enum CodingKeys: String, CodingKey { case eventID = "p_event_id" }
    }

    struct MyFeedback: Equatable { let rating: Int; let note: String }

    /// get_my_event_feedback: nil = never answered (or not reachable). Throws only on a transport failure.
    func fetchMyEventFeedback(eventID: String) async -> MyFeedback? {
        #if DEBUG
        if UITestFixture.isActive { return nil }
        #endif
        struct Reply: Decodable {
            struct FB: Decodable { let rating: Int?; let note: String? }
            let success: Bool?
            let feedback: FB?
        }
        do {
            let r: Reply = try await SupabaseService.client.rpc("get_my_event_feedback", params: EventIDParam(eventID: eventID)).execute().value
            guard r.success == true, let rating = r.feedback?.rating, CoreLoops.ratings.contains(rating) else { return nil }
            return MyFeedback(rating: rating, note: r.feedback?.note ?? "")
        } catch {
            print("get_my_event_feedback failed:", error)
            return nil
        }
    }

    /// submit_event_feedback: nil on success, else the server's error code (NOT_OPEN, NO_TICKET, …) or "NETWORK".
    func submitEventFeedback(eventID: String, rating: Int, note: String) async -> String? {
        struct Params: Encodable {
            let eventID: String
            let rating: Int
            let note: String
            enum CodingKeys: String, CodingKey { case eventID = "p_event_id", rating = "p_rating", note = "p_note" }
        }
        struct Reply: Decodable { let success: Bool?; let error: String? }
        do {
            let r: Reply = try await SupabaseService.client
                .rpc("submit_event_feedback", params: Params(eventID: eventID, rating: rating, note: note)).execute().value
            return r.success == true ? nil : (r.error ?? "NETWORK")
        } catch {
            print("submit_event_feedback failed:", error)
            return "NETWORK"
        }
    }

    /// get_host_event_recap (owner/team only, switch host_recap).
    func fetchHostRecap(eventID: String) async -> CoreLoops.HostRecap {
        do {
            return try await SupabaseService.client.rpc("get_host_event_recap", params: EventIDParam(eventID: eventID)).execute().value
        } catch {
            print("get_host_event_recap failed:", error)
            return CoreLoops.HostRecap(success: false, error: "NETWORK")
        }
    }

    struct NotificationPreferences: Decodable, Equatable {
        var success: Bool?
        var promoPush: Bool?
        var digestOptIn: Bool?
        enum CodingKeys: String, CodingKey { case success, promoPush = "promo_push", digestOptIn = "digest_opt_in" }
    }

    func fetchNotificationPreferences() async -> NotificationPreferences? {
        #if DEBUG
        if UITestFixture.isActive { return NotificationPreferences(success: true, promoPush: false, digestOptIn: false) }
        #endif
        do {
            let r: NotificationPreferences = try await SupabaseService.client.rpc("get_my_notification_preferences").execute().value
            return r.success == true ? r : nil
        } catch {
            print("get_my_notification_preferences failed:", error)
            return nil
        }
    }

    /// set_my_digest_opt_in / set_my_promo_push: nil on success, else the error code (NOT_AVAILABLE when turning the
    /// digest ON while its switch is off; turning anything off always works).
    func setNotificationConsent(_ rpc: String, enabled: Bool) async -> String? {
        #if DEBUG
        if UITestFixture.isActive { return nil }
        #endif
        struct Reply: Decodable { let success: Bool?; let error: String? }
        do {
            let r: Reply = try await SupabaseService.client.rpc(rpc, params: ["p_enabled": enabled]).execute().value
            return r.success == true ? nil : (r.error ?? "NETWORK")
        } catch {
            print("\(rpc) failed:", error)
            return "NETWORK"
        }
    }
}
