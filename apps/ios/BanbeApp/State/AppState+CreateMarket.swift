import Foundation

// Create-event market (migration 195): the form's event zone and currency. The date/time pickers, the wall-clock
// strings sent to create_event_draft / resubmit_event_for_review, the past-time check, the price field and the
// benchmarks all read these, so a US host's "19:00" is 19:00 at the venue and "$12.50" is 1250 cents.
// Web twin: the create form in src/state/BanBeContext.jsx + src/lib/eventMarket.js.

extension AppState {
    /// The address picked this session decides (MapKit's own zone wins for US); an edit that keeps its address uses
    /// the row's zone; otherwise Vietnam.
    var createEventTimeZoneID: String {
        if let country = createCountryCode {
            return EventMarket.resolveEventTimeZone(countryCode: country, stateProvince: createStateProvince,
                                                    clientTz: createPlaceTimeZoneID) ?? EventMarket.vnTimeZoneID
        }
        return createEditBaseTimeZoneID ?? EventMarket.vnTimeZoneID
    }

    var createEventTimeZone: TimeZone { EventMarket.timeZone(createEventTimeZoneID) }

    /// Currency the price field is typed in. An unsupported country falls back to VND for typing; the server
    /// refuses the event itself (UNSUPPORTED_COUNTRY).
    var createCurrency: String {
        if let country = createCountryCode { return EventMarket.eventCurrency(countryCode: country) ?? "VND" }
        return createEditBaseCurrency ?? "VND"
    }

    /// The price field as minor units of `createCurrency`; nil = not a price ("12.345" in USD). Empty = free (0).
    var createPriceAmount: Int? {
        let trimmed = createPrice.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        return EventMarket.parsePriceInput(trimmed, currency: createCurrency)
    }

    /// `p_tz` for the RPCs: sent ONLY for a US address picked this session, so a VN create keeps calling the
    /// exact function signature a server without migration 195 has. nil = let the server derive it.
    var createTzParam: String? {
        guard (createCountryCode ?? "").trimmingCharacters(in: .whitespaces).uppercased() == "US" else { return nil }
        return EventMarket.resolveEventTimeZone(countryCode: createCountryCode, stateProvince: createStateProvince,
                                                clientTz: createPlaceTimeZoneID)
    }

    /// Keeps the picked wall clock when the event's zone changes (picking a US address after choosing "Sat 19:00"
    /// must still say Sat 19:00, now at the venue). `createEventDate`/`createEventTime` are instants whose
    /// date/time digits in `createZoneApplied` are what the host picked.
    func rezoneCreateDateTime() {
        let next = createEventTimeZoneID
        guard next != createZoneApplied else { return }
        let from = EventMarket.calendar(EventMarket.timeZone(createZoneApplied))
        let to = EventMarket.calendar(EventMarket.timeZone(next))
        createZoneApplied = next
        func move(_ d: Date?) -> Date? {
            guard let d else { return nil }
            return to.date(from: from.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)) ?? d
        }
        if createEventDate != nil { createEventDate = move(createEventDate) }
        if createEventTime != nil { createEventTime = move(createEventTime) }
    }

    /// "yyyy-MM-dd" / "HH:mm:ss" / both, in the create form's zone.
    func createFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = createEventTimeZone
        f.dateFormat = format
        return f
    }

    /// The picked date + time as one real instant at the venue (nil until both are set).
    var createStartsAt: Date? {
        guard let d = createEventDate, let t = createEventTime else { return nil }
        let date = createFormatter("yyyy-MM-dd").string(from: d)
        let time = createFormatter("HH:mm").string(from: t)
        return EventMarket.wallClockDate(date: date, time: time, timeZone: createEventTimeZone)
    }

    /// Migration 195's create/resubmit refusals, in words a host can act on; nil for any other error.
    func createMarketErrorMessage(_ raw: String) -> String? {
        if raw.contains("UNSUPPORTED_COUNTRY") {
            return T("Sự kiện trên banbe có thể ở Việt Nam hoặc Hoa Kỳ.", "banbe events can be in Vietnam or the United States.")
        }
        if raw.contains("TIMEZONE_UNKNOWN") {
            return T("Không xác định được múi giờ của địa chỉ này. Hãy chọn lại địa chỉ.",
                     "Couldn't tell this address's time zone. Pick the address again.")
        }
        return nil
    }
}
