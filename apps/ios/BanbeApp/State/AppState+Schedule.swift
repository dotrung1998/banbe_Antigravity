import Foundation

// Schedule tab state + real data sources (note 44). The mapping itself lives
// in Lib/SchedulePresentation.swift; this file only adapts AppState's
// existing data (paymentBookings, myOrgEvents, discoveryEvents, the resolved
// event caches) and the device-local InAppCalendarStore to it.

extension AppState {

    func goSchedule() {
        screen = .schedule
        Analytics.track(.scheduleOpened)
    }

    func resetScheduleState() {
        scheduleCache = nil
        scheduleLoadedAt = nil
        scheduleAddedKeys = []
        scheduleMode = .mine
        scheduleSelectedDate = Date()
    }

    /// Reads this account's own device-local additions (none when signed out).
    func refreshScheduleAdded() {
        guard let uid = userID else { scheduleAddedKeys = []; return }
        scheduleAddedKeys = InAppCalendarStore().keys(uid: uid)
    }

    // MARK: event → schedule info

    func scheduleInfo(for e: CatalogEvent) -> ScheduleEventInfo {
        let loc = eventLocation(e)
        return ScheduleEventInfo(
            key: e.key, title: e.name, start: e.startDate, end: nil,
            timeZone: e.eventTimeZone ?? ForYou.timeZone(countryCode: loc.countryCode, stateProvince: loc.stateProvince),
            location: e.locationLabel ?? "",
            cancelled: e.cancelled, ended: e.endedHoursAgo != nil,
            inviteOnly: e.inviteOnly, soldOut: e.soldOut)
    }

    /// Every event this account's schedule could reference, keyed by id.
    private var scheduleEventIndex: [String: ScheduleEventInfo] {
        var index: [String: ScheduleEventInfo] = [:]
        let keys = Set(paymentBookings.map(\.eventKey) + scheduleAddedKeys + myOrgEvents.map(\.key))
        for e in myOrgEvents { index[e.key] = scheduleInfo(for: e) }
        for key in keys where index[key] == nil {
            if let e = resolvedEvent(for: key) { index[key] = scheduleInfo(for: withLive(e)) }
        }
        return index
    }

    var scheduleBookingInputs: [ScheduleBookingInput] {
        paymentBookings.map {
            ScheduleBookingInput(eventKey: $0.eventKey, status: $0.status,
                                 paymentState: $0.paymentState.rawValue, holdExpiresAt: $0.holdExpiresAt,
                                 giftedAway: $0.giftedAt != nil && $0.claimedByUserId != userID)
        }
    }

    /// Hosted = the account's own organizer's LIVE events (drafts, reviews and
    /// cancelled events are not plans).
    var scheduleHostedKeys: [String] {
        myOrgEvents.filter { !$0.cancelled }.map(\.key)
    }

    /// Everything the Schedule screen derives, computed ONCE per input change.
    /// The view used to recompute this ~15 times per body pass (every card, every
    /// strip dot), and a pass ran every second; now a pass is one hash + a cache hit.
    var scheduleSnapshot: ScheduleSnapshot {
        let key = scheduleInputsKey()
        if let c = scheduleCache, c.key == key { return c.value }
        let now = Date()
        let mine = SchedulePresentation.mySchedule(bookings: scheduleBookingInputs, hostedKeys: scheduleHostedKeys,
                                                   addedKeys: scheduleAddedKeys, events: scheduleEventIndex, now: now)
        let discover = SchedulePresentation.discover(events: discoveryEvents.map { scheduleInfo(for: withLive($0)) },
                                                     excluding: Set(mine.items.map(\.id)), now: now)
        let snapshot = ScheduleSnapshot(mine: mine, discover: discover)
        scheduleCache = (key, snapshot)
        return snapshot
    }

    /// Cheap signature of every input the snapshot depends on, plus a 30s time
    /// bucket so holds expire and "upcoming" stays honest without per-second work.
    func scheduleInputsKey() -> Int {
        var h = Hasher()
        h.combine(userID)
        for b in paymentBookings {
            h.combine(b.id); h.combine(b.eventKey); h.combine(b.status)
            h.combine(b.paymentState.rawValue); h.combine(b.holdExpiresAt)
            h.combine(b.giftedAt != nil); h.combine(b.claimedByUserId)
        }
        h.combine(myOrganizerID)
        h.combine(myOrgEventKeys)
        for e in myOrgEventSummaries { h.combine(e.id); h.combine(e.status); h.combine(e.startsAt) }
        h.combine(scheduleAddedKeys)
        for e in discoveryEvents {
            h.combine(e.key); h.combine(e.cancelled); h.combine(e.endedHoursAgo); h.combine(e.soldOut); h.combine(e.startDate)
        }
        h.combine(realEventsByID.count)
        h.combine(homeLiveEvents.count)
        h.combine(Int(Date().timeIntervalSince1970 / 30))
        return h.finalize()
    }

    var mySchedule: SchedulePresentation.MyScheduleResult { scheduleSnapshot.mine }
    var scheduleDiscover: [ScheduleEventInfo] { scheduleSnapshot.discover }

    /// Is this event already on My schedule, from ANY source?
    func isInMySchedule(_ key: String) -> Bool { mySchedule.items.contains { $0.id == key } }

    /// The strongest source keeping an event on My schedule, if any.
    func scheduleSource(for key: String) -> ScheduleSource? { mySchedule.items.first { $0.id == key }?.source }

    // MARK: add / remove (device-local)

    enum ScheduleAddOutcome: Equatable { case added, alreadyThere, needsSignIn, ineligible }

    /// "Add to banbe Schedule" — not a reservation, not an export.
    @discardableResult
    func addToBanbeSchedule(_ e: CatalogEvent) -> ScheduleAddOutcome {
        Analytics.track(.banbeScheduleAdd)
        guard let uid = userID else {
            requireAuth(returnTo: screen, backTo: screen)
            return .needsSignIn
        }
        if isInMySchedule(e.key) {
            Analytics.track(.banbeScheduleResult(result: "alreadyAdded"))
            return .alreadyThere
        }
        guard SchedulePresentation.canAdd(scheduleInfo(for: withLive(e)), now: Date()) else {
            Analytics.track(.banbeScheduleResult(result: "ineligible"))
            return .ineligible
        }
        let r = InAppCalendarStore().add(e.key, uid: uid)
        refreshScheduleAdded()
        Haptics.success()
        Analytics.track(.banbeScheduleResult(result: r.rawValue))
        return .added
    }

    /// Only removes a manual addition; bookings/hosting are not touched here.
    func removeFromBanbeSchedule(_ key: String) {
        Analytics.track(.banbeScheduleRemove)
        guard let uid = userID else { return }
        let r = InAppCalendarStore().remove(key, uid: uid)
        refreshScheduleAdded()
        Analytics.track(.banbeScheduleResult(result: r.rawValue))
    }

    /// Loads what the agenda reads, reusing the existing loaders. Throttled: the
    /// tab remounts on every visit (and as a swipe neighbor), and each load
    /// republishes app-wide state, so a recent load is reused unless `force`
    /// (pull to refresh).
    func loadScheduleData(force: Bool = false) async {
        guard userID != nil else { return }
        #if DEBUG
        if UITestFixture.isActive { return }
        #endif
        if !force, let at = scheduleLoadedAt, Date().timeIntervalSince(at) < 45 { return }
        scheduleLoadedAt = Date()
        await loadPaymentBookings()
        await loadMissingRealEvents(for: paymentBookings.map(\.eventKey) + scheduleAddedKeys)
        if discoveryEvents.isEmpty && !discoveryEventsLoading { await loadDiscoveryEvents() }
    }
}

/// What Schedule renders, derived in one pass (see `scheduleSnapshot`).
struct ScheduleSnapshot {
    let mine: SchedulePresentation.MyScheduleResult
    let discover: [ScheduleEventInfo]
}
