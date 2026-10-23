import Foundation

/// Phase 2-3 core loops (docs/impl/phase2-core-loops.md, phase3-extras.md L5): the pure rules behind notification
/// routing, the guest's private feedback, the host recap and "Run it again". Mirrors src/lib/coreLoops.js; shared
/// vectors in tests/fixtures/core-loops.json (BanbeAppTests/CoreLoopsTests.swift and tests/unit/coreLoops.test.mjs) —
/// change all three together.
///
/// The server (migrations 199/200) owns every decision that matters: who may answer, for how long, when the host may
/// see anything. These helpers only shape what the screen says, never a public rating, never a countdown.
enum CoreLoops {
    // MARK: Notification routing

    enum Route: String { case ticket, eventRecap, hostRecap, event, following, thisWeekend }

    struct Destination: Equatable {
        let route: Route
        /// Booking id for `.ticket`, event id for `.eventRecap`/`.hostRecap`/`.event`, nil otherwise.
        let id: String?
    }

    /// Kinds this file routes (the notification list gives them their own icons).
    static let kinds: Set<String> = ["event_reminder_day", "event_reminder_soon", "event_recap", "host_event_recap",
                                     "follow_alert", "weekly_digest"]

    /// Where a tapped notification goes, or nil for a kind this file doesn't own.
    static func route(kind: String, data: [String: AnyCodableValue]) -> Destination? {
        func str(_ key: String) -> String? {
            switch data[key] {
            case .string(let s)?: return s.isEmpty ? nil : s
            case .int(let n)?: return String(n)
            default: return nil
            }
        }
        switch kind {
        case "event_reminder_day", "event_reminder_soon":
            return str("booking_id").map { Destination(route: .ticket, id: $0) }
        case "event_recap":
            return str("event_id").map { Destination(route: .eventRecap, id: $0) }
        case "host_event_recap":
            return str("event_id").map { Destination(route: .hostRecap, id: $0) }
        case "follow_alert":
            // One new event opens it; a bundle of several opens the list of hosts you follow.
            let count: Double
            switch data["count"] {
            case .int(let n)?: count = Double(n)
            case .double(let d)?: count = d
            case .string(let s)?: count = Double(s) ?? 1
            default: count = 1
            }
            if count > 1 { return Destination(route: .following, id: nil) }
            return str("event_id").map { Destination(route: .event, id: $0) } ?? Destination(route: .following, id: nil)
        case "weekly_digest":
            return Destination(route: .thisWeekend, id: nil)
        default:
            return nil
        }
    }

    // MARK: Run it again

    /// Same rule as smart defaults (note 48): a new date is at least this many days out, so there is time to promote.
    static let runAgainMinDaysAhead = 2

    private static let utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.calendar = utcCalendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func day(_ s: String?) -> Date? {
        guard let s, s.count == 10 else { return nil }
        return isoDay.date(from: s)
    }

    /// "Run it again": the new event's date and time. One week after the original; when that is already too close or in
    /// the past, the first same weekday at least 2 days after `today`. Time is kept ("HH:mm"). All dates are
    /// "yyyy-MM-dd" in the event's own zone (`today` too), so the rule never depends on the device clock's zone.
    static func runItAgainDate(eventDate: String?, eventTime: String?, today: String) -> (date: String?, time: String?) {
        let time = eventTime.flatMap { $0.isEmpty ? nil : String($0.prefix(5)) }
        guard let t = day(today) else { return (nil, time) }
        let earliest = utcCalendar.date(byAdding: .day, value: runAgainMinDaysAhead, to: t)!
        guard let original = day(eventDate) else { return (isoDay.string(from: earliest), time) }
        let weekLater = utcCalendar.date(byAdding: .day, value: 7, to: original)!
        if weekLater >= earliest { return (isoDay.string(from: weekLater), time) }
        let delta = (utcCalendar.component(.weekday, from: original) - utcCalendar.component(.weekday, from: earliest) + 7) % 7
        return (isoDay.string(from: utcCalendar.date(byAdding: .day, value: delta, to: earliest)!), time)
    }

    // MARK: Feedback (L2, private to the host)

    static let noteMax = 500
    static let ratings = [1, -1]
    static let openDays = 14
    static let hostMinResponses = 3

    /// Characters as Postgres length() counts them (code points), so the counter and the server agree.
    static func noteLength(_ note: String) -> Int { note.unicodeScalars.count }

    /// Cuts a note to the limit, by code point.
    static func clampNote(_ note: String) -> String {
        guard note.unicodeScalars.count > noteMax else { return note }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: note.unicodeScalars.prefix(noteMax))
        return String(view)
    }

    static func canSaveFeedback(rating: Int?, note: String) -> Bool {
        guard let rating, ratings.contains(rating) else { return false }
        return noteLength(note) <= noteMax
    }

    /// The answer window the server applies (14 days after the start). The server still decides; this only avoids
    /// offering a form that can't be saved. Unknown start = open (let the server say).
    static func feedbackWindowOpen(startsAt: Date?, now: Date = Date()) -> Bool {
        guard let startsAt else { return true }
        return now.timeIntervalSince(startsAt) <= Double(openDays) * 86_400
    }

    static let privacyLine = (vi: "Chỉ host thấy, dưới dạng số đếm và ghi chú không kèm tên, khi có từ 3 người trả lời.",
                              en: "Only the host sees this, as counts and unnamed notes, once 3 or more guests have answered.")

    /// submit_event_feedback's error codes -> what the guest reads.
    static func feedbackErrorText(_ code: String?) -> (vi: String, en: String) {
        switch code {
        case "NOT_OPEN": return ("Đã đóng phần cảm nhận cho sự kiện này.", "Feedback for this event is closed.")
        case "NO_TICKET": return ("Chỉ khách có vé mới gửi được cảm nhận.", "Only guests with a ticket can send feedback.")
        case "INVALID_VALUE": return ("Chọn 👍 hoặc 👎, ghi chú tối đa 500 ký tự.", "Pick 👍 or 👎, and keep the note to 500 characters.")
        case "NOT_AVAILABLE": return ("Tính năng này đang tạm tắt.", "This is turned off for now.")
        case "AUTH_REQUIRED": return ("Hãy đăng nhập lại.", "Please sign in again.")
        default: return ("Không lưu được. Thử lại nhé.", "Couldn't save. Try again.")
        }
    }

    // MARK: Host recap (L3)

    /// get_event_feedback_summary / get_host_event_recap.feedback, as decoded.
    struct FeedbackSummary: Decodable, Equatable {
        var responses: Int?
        var hidden: Bool?
        var up: Int?
        var down: Int?
        var notes: [String]?
    }

    struct FeedbackView: Equatable {
        let hidden: Bool
        let responses: Int
        var up = 0
        var down = 0
        var notes: [String] = []
    }

    /// Hidden below 3 answers, otherwise counts and notes without names. Anything malformed reads as hidden.
    static func hostFeedbackView(_ fb: FeedbackSummary?) -> FeedbackView {
        let responses = fb?.responses ?? 0
        guard let fb, fb.hidden == false, responses >= hostMinResponses else { return FeedbackView(hidden: true, responses: responses) }
        let notes = (fb.notes ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return FeedbackView(hidden: false, responses: responses, up: fb.up ?? 0, down: fb.down ?? 0, notes: notes)
    }

    static let hostFeedbackHidden = (vi: "Cảm nhận hiện khi có từ 3 khách trả lời.", en: "Feedback appears once 3 guests have answered.")

    /// get_host_event_recap's reply. Missing numbers read as 0; capacity may be unknown.
    struct HostRecap: Decodable, Equatable {
        var success: Bool?
        var error: String?
        var confirmedSeats: Int?
        var capacity: Int?
        var checkedIn: Int?
        var newFollowers: Int?
        var repeatGuests: Int?
        var photos: Int?
        var feedback: FeedbackSummary?
        enum CodingKeys: String, CodingKey {
            case success, error, capacity, photos, feedback
            case confirmedSeats = "confirmed_seats", checkedIn = "checked_in", newFollowers = "new_followers", repeatGuests = "repeat_guests"
        }
    }
}
