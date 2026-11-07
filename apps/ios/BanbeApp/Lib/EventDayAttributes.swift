import ActivityKit
import Foundation

/// L7 day-of card (docs/impl/phase3-extras.md; switch `live_activity`): the event-day Live Activity's data.
/// Compiled into BOTH the app (State/LiveActivityController.swift starts, updates and ends it on the device) and the
/// BanbeLiveActivity widget extension (draws it), so keep this file free of anything app-only.
///
/// No push token is ever requested (pushType nil): every change is made locally by the app. The Lock Screen shows the
/// event's name, start time in the venue's zone and the venue. No countdown timers, no urgency text.
struct EventDayAttributes: ActivityAttributes {
    enum Phase: String, Codable, Hashable { case upcoming, started }

    struct ContentState: Codable, Hashable {
        var phase: Phase
    }

    /// The booking this card belongs to (one activity per confirmed ticket; tapping it opens that ticket).
    var bookingID: String
    var eventName: String
    var venue: String
    var startsAt: Date
    var ticketCode: String
    /// The venue's IANA zone: the start time reads the same for every viewer, wherever they are.
    var timeZoneID: String
    /// "US" reads 7:00 PM, anything else 19:00 (the app's card format).
    var market: String
    /// "vi" | "en": the app's language when the card started (the extension can't read the app's settings).
    var lang: String

    func text(_ vi: String, _ en: String) -> String { lang == "en" ? en : vi }

    /// Start time in the venue's zone.
    var timeText: String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        let c = cal.dateComponents([.hour, .minute], from: startsAt)
        let hour = c.hour ?? 0, minute = c.minute ?? 0
        if market == "US" {
            return String(format: "%d:%02d %@", hour % 12 == 0 ? 12 : hour % 12, minute, hour < 12 ? "AM" : "PM")
        }
        return String(format: "%02d:%02d", hour, minute)
    }

    /// One calm status line: when it starts, or that it has started. Never a countdown.
    func statusText(_ phase: Phase) -> String {
        switch phase {
        case .upcoming: return text("Bắt đầu lúc \(timeText)", "Starts at \(timeText)")
        case .started: return text("Đã bắt đầu lúc \(timeText)", "Started at \(timeText)")
        }
    }

    /// Opens this ticket in the app (AppState.handleDeepLink, host "ticket").
    var ticketURL: URL? { URL(string: "banbe://ticket/\(bookingID)") }
}
