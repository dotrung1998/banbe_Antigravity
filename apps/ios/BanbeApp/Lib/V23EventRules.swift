import Foundation

// v2.3 Event Detail, Next up and end-time rules (notes 81, 82). Line-for-line ports of
//   ReserveBarV23 <- src/lib/reserveBarV23.js     EventDetailV23 <- src/lib/eventDetailV23.js
//   NextUp        <- src/lib/nextUp.js            EventEnd       <- src/lib/eventEnd.js
// Tests: BanbeAppTests/V23EventRulesTests.swift (the web unit cases). Change both together.

// MARK: - Reserve bar v2.3 (compact/full, 1·2·3·4+, stamps, adding after a hold)

enum ReserveBarV23 {
    static let growAt: CGFloat = 40
    static let compactAt: CGFloat = 24
    static let moreAt = 4

    /// Compact on arrival, full past 40 pt, compact again at ≤ 24 pt (hysteresis, no flicker).
    static func nextCompact(_ offset: CGFloat, _ compact: Bool) -> Bool {
        let t = max(0, offset)
        return compact ? t <= growAt : t <= compactAt
    }

    struct Control: Equatable { var max: Int; var stepper: Bool; var moreEnabled: Bool; var canMinus: Bool; var canPlus: Bool }

    static func control(_ qty: Int, remaining: Int?) -> Control {
        let m = ReserveBar.qtyCeiling(remaining: remaining)
        return Control(max: m, stepper: qty >= moreAt, moreEnabled: m >= moreAt, canMinus: qty > 1, canPlus: qty < m)
    }

    enum Dot: String { case me, guest, empty }
    static func seatDots(_ qty: Int) -> [Dot] { (0..<ReserveBar.maxQty).map { $0 == 0 ? .me : $0 < qty ? .guest : .empty } }

    static func guestLine(_ qty: Int, remaining: Int?) -> ViEn {
        let m = ReserveBar.qtyCeiling(remaining: remaining)
        let g = max(0, qty - 1)
        let who = g == 0 ? ViEn("Chỉ mình bạn", "Just you") : ViEn("Bạn + \(g) khách", "You + \(g) \(g == 1 ? "guest" : "guests")")
        let cap: ViEn
        if qty < m { cap = ViEn("tối đa \(m)", "up to \(m)") }
        else if m < ReserveBar.maxQty { cap = ViEn("chỉ còn \(m) chỗ", "only \(m) left") }
        else { cap = ViEn("tối đa \(ReserveBar.maxQty) vé mỗi người", "\(ReserveBar.maxQty) is the most per person") }
        return ViEn("\(who.vi) · \(cap.vi)", "\(who.en) · \(cap.en)")
    }

    static func moreRefusal(_ remaining: Int) -> ViEn {
        let n = max(0, remaining)
        return n == 1 ? ViEn("Sự kiện này chỉ còn 1 vé", "Only 1 ticket left for this one") : ViEn("Sự kiện này chỉ còn \(n) vé", "Only \(n) tickets left for this one")
    }

    static func totalSub(_ qty: Int, unitText: String, free: Bool) -> ViEn {
        if free { return ViEn("không mất phí", "no charge") }
        if qty <= 1 { return ViEn("mỗi vé", "per ticket") }
        return ViEn("Tổng · \(qty) × \(unitText)", "Total · \(qty) × \(unitText)")
    }

    // ---- Phase e: stamps and adding after a hold ----

    /// The parts of a booking these rules read (a Booking or a PayableBooking maps onto it).
    struct SeatBooking: Equatable {
        var id: String
        var qty: Int
        var status: String
        var paymentState: String?
        var holdExpiresAt: Date?
        var verifyDueAt: Date?
        var createdAt: Date?
    }

    /// booking_holds_seat(): attended/no-show always, cancelled/expired never, confirmed / pending verification /
    /// disputed yes, holding only until hold_expires_at.
    static func holdsSeat(_ b: SeatBooking, now: Date = Date()) -> Bool {
        if b.status == "attended" || b.status == "no_show" { return true }
        if b.status == "cancelled" || b.status == "expired" { return false }
        switch b.paymentState {
        case "confirmed", "pending_verification", "disputed": return true
        case "holding": return b.holdExpiresAt.map { $0 > now } ?? true
        default: return false
        }
    }

    static func isTicket(_ b: SeatBooking) -> Bool { b.status == "attended" || (b.status == "confirmed" && b.paymentState == "confirmed") }

    static func bookedQty(_ bookings: [SeatBooking], now: Date = Date()) -> Int {
        bookings.filter { holdsSeat($0, now: now) }.reduce(0) { $0 + $1.qty }
    }

    struct Stamp: Equatable { enum Kind: String { case held, confirmed }; var kind: Kind; var until: Date?; var phase: String? }

    static func stampState(_ bookings: [SeatBooking], now: Date = Date()) -> Stamp? {
        let seat = bookings.filter { holdsSeat($0, now: now) }
        guard !seat.isEmpty else { return nil }
        let open = seat.filter { !isTicket($0) }
        guard !open.isEmpty else { return Stamp(kind: .confirmed, until: nil, phase: nil) }
        func deadline(_ b: SeatBooking) -> Date? { b.paymentState == "holding" ? b.holdExpiresAt : b.paymentState == "pending_verification" ? b.verifyDueAt : nil }
        let first = open.map { ($0, deadline($0)) }.sorted { ($0.1 ?? .distantFuture) < ($1.1 ?? .distantFuture) }[0]
        return Stamp(kind: .held, until: first.1, phase: first.0.paymentState == "holding" ? "hold" : "verify")
    }

    static func stampText(_ s: Stamp?, now: Date = Date()) -> ViEn? {
        guard let s else { return nil }
        if s.kind == .confirmed { return ViEn("Đã xác nhận", "Confirmed") }
        guard let until = s.until else { return ViEn("Đã giữ", "Held") }
        let mins = Int(ceil(until.timeIntervalSince(now) / 60))
        if mins <= 0 { return ViEn("Đã giữ", "Held") }
        if mins >= 60 { let h = Int(ceil(Double(mins) / 60)); return ViEn("Đã giữ · \(h) giờ", "Held · \(h) h") }
        return ViEn("Đã giữ · \(mins) phút", "Held · \(mins) min")
    }

    struct AddControl: Equatable { var qty, min, max, extra: Int; var adding, stepper, moreEnabled, canMinus, canPlus: Bool }

    /// Once the viewer holds `booked` seats: never below that, up to 6 per person or held + seats free.
    static func addControl(_ qty: Int, remaining: Int?, booked: Int) -> AddControl {
        let mx = min(ReserveBar.maxQty, booked + (remaining.map { max(0, $0) } ?? ReserveBar.maxQty))
        let mn = max(1, booked)
        let q = min(mx, max(mn, qty))
        return AddControl(qty: q, min: mn, max: mx, extra: max(0, q - booked), adding: q > booked, stepper: q >= moreAt,
                          moreEnabled: mx >= moreAt && booked < mx, canMinus: q > mn, canPlus: q < mx)
    }

    struct HeldCopy: Equatable { var button: ViEn; var sub: ViEn; var trust: ViEn }

    static func heldCopy(booked: Int, extra: Int, confirmed: Bool, phase: String?) -> HeldCopy {
        if extra > 0 {
            return HeldCopy(button: ViEn("Thêm \(extra) vé", "Add \(extra) \(extra == 1 ? "ticket" : "tickets")"),
                            sub: ViEn("thêm \(extra) · tổng \(booked + extra) vé", "\(extra) more · \(booked + extra) in all"),
                            trust: ViEn("Lượt đặt mới · chủ nhà cũng xác nhận", "A new booking · the host confirms it too"))
        }
        return HeldCopy(
            button: confirmed ? ViEn("Xem vé của bạn", "View your ticket") : ViEn("Đã giữ chỗ", "Seats held"),
            sub: ViEn("\(booked) vé của bạn", "\(booked) \(booked == 1 ? "ticket" : "tickets") yours"),
            trust: confirmed ? ViEn("Chủ nhà đã xác nhận · mã QR đã sẵn sàng", "Confirmed by the host · your QR is ready")
                : phase == "verify" ? ViEn("Chủ nhà có 1 giờ để xác nhận · banbe sẽ nhắc", "The host has 1 hour to confirm · banbe reminds them")
                : ViEn("Chỗ được giữ trong lúc bạn chuyển khoản", "Your seats are held while you pay"))
    }

    static func addGuestLine(_ qty: Int, booked: Int, max m: Int) -> ViEn? {
        guard booked > 0, qty > booked else { return nil }
        let cap: ViEn = qty >= m
            ? (m < ReserveBar.maxQty ? ViEn("chỉ còn \(m - booked) chỗ", "only \(m - booked) more free") : ViEn("tối đa \(ReserveBar.maxQty) vé mỗi người", "\(ReserveBar.maxQty) is the most per person"))
            : ViEn("tối đa \(m)", "up to \(m)")
        return ViEn("\(booked) đã giữ · thêm \(qty - booked) · \(cap.vi)", "\(booked) held · adding \(qty - booked) · \(cap.en)")
    }
}

// MARK: - Event Detail v2.3 presentation

enum EventDetailV23 {
    static let navAt: CGFloat = 140

    struct KnowRow: Equatable { let key: String; let label: ViEn; let text: String }

    /// One need-to-know row from the existing rules (EventDetailPresentation): id, key, title, sub, icon.
    struct NeedRow: Equatable { let id: String; let key: String; let icon: String; let title: String; let sub: String? }

    /// "Good to know" as label / value: alcohol, every dietary choice in ONE row, age, facts, refund last.
    static func knowRows(_ need: [NeedRow], refund: String?) -> [KnowRow] {
        func join(_ parts: [String?]) -> String {
            parts.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " · ")
        }
        let dietary = need.filter { $0.id == "dietary" }
        var out: [KnowRow] = []
        for r in need {
            if r.id == "dietary" {
                guard r == dietary.first else { continue }
                out.append(KnowRow(key: "dietary", label: ViEn("Ăn uống", "Dietary"),
                                   text: join([dietary.map(\.title).joined(separator: ", ")] + dietary.map(\.sub))))
            } else if r.id == "alcohol" {
                out.append(KnowRow(key: r.key, label: ViEn("Đồ uống", "Alcohol"), text: join([r.title, r.sub])))
            } else if r.icon == "age" {
                out.append(KnowRow(key: r.key, label: ViEn("Độ tuổi", "Age"), text: join([r.title, r.sub])))
            } else if let sub = r.sub, !sub.isEmpty {
                out.append(KnowRow(key: r.key, label: ViEn(r.title, r.title), text: sub))
            }
        }
        if let refund, !refund.isEmpty { out.append(KnowRow(key: "refund", label: ViEn("Hoàn tiền", "Refund"), text: refund)) }
        return out.filter { !$0.text.isEmpty }
    }

    static func listNo(_ i: Int) -> String { String(format: "%02d", i + 1) }

    /// Parallax for the 140 % tall hero art, and how far the title has sunk (0…1).
    static func heroMotion(_ y: CGFloat) -> (offset: CGFloat, scale: CGFloat, dp: CGFloat) {
        let t = max(0, y)
        return (t * 0.2, 1 + t / 4000, min(1, t / 300))
    }

    static func navOn(_ y: CGFloat) -> Bool { y > navAt }

    static func readProgress(_ y: CGFloat, contentHeight: CGFloat, viewHeight: CGFloat) -> CGFloat {
        let m = contentHeight - viewHeight
        return m > 0 ? min(1, max(0, y / m)) : 0
    }
}

// MARK: - Next up (Home ticket cards)

enum NextUp {
    struct EventInfo: Equatable { var startMs: Double; var endMs: Double?; var cancelled = false }

    struct Group: Equatable, Identifiable {
        var eventId: String
        var bookings: [ReserveBarV23.SeatBooking]
        var seats, ready, open: Int
        var state: String   // ready | pay | waiting
        var mixed: Bool
        var holdUntil: Date?
        var primaryId: String
        var live: Bool
        var startMs: Double
        var id: String { eventId }
    }

    /// One card per event, soonest first; gifted (`giftedIds`), lapsed and over events left out.
    static func groups(_ bookings: [(eventId: String, booking: ReserveBarV23.SeatBooking, gifted: Bool)], events: [String: EventInfo], now: Date = Date()) -> [Group] {
        var order: [String] = []
        var by: [String: [ReserveBarV23.SeatBooking]] = [:]
        for row in bookings where !row.gifted && ReserveBarV23.holdsSeat(row.booking, now: now) && !row.eventId.isEmpty {
            if by[row.eventId] == nil { order.append(row.eventId) }
            by[row.eventId, default: []].append(row.booking)
        }
        let nowMs = now.timeIntervalSince1970 * 1000
        var out: [Group] = []
        for id in order {
            guard let ev = events[id], !ev.cancelled, let list = by[id] else { continue }
            let over = ev.endMs ?? (ev.startMs + 12 * 3_600_000)
            if nowMs > over { continue }
            let readyB = list.filter(ReserveBarV23.isTicket)
            let openB = list.filter { !ReserveBarV23.isTicket($0) }
            let holding = openB.filter { $0.paymentState == "holding" }
            let seats = list.reduce(0) { $0 + $1.qty }
            let ready = readyB.reduce(0) { $0 + $1.qty }
            let state = openB.isEmpty ? "ready" : !holding.isEmpty ? "pay" : "waiting"
            let holdUntil = holding.compactMap(\.holdExpiresAt).min()
            let primary = state == "pay" ? holding.first : state == "waiting" ? openB.first
                : readyB.max { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
            out.append(Group(eventId: id, bookings: list, seats: seats, ready: ready, open: seats - ready, state: state,
                             mixed: ready > 0 && !openB.isEmpty, holdUntil: holdUntil, primaryId: primary?.id ?? list[0].id,
                             live: nowMs >= ev.startMs, startMs: ev.startMs))
        }
        return out.sorted { $0.startMs < $1.startMs }
    }

    /// Calendar days from today to the event's day in the venue's zone.
    static func dayDiff(_ startMs: Double, now: Date, tz: String) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: tz) ?? TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        let a = cal.startOfDay(for: now)
        let b = cal.startOfDay(for: Date(timeIntervalSince1970: startMs / 1000))
        return cal.dateComponents([.day], from: a, to: b).day ?? 0
    }

    static func chip(_ g: Group, now: Date, tz: String) -> ViEn {
        if g.live { return ViEn("Đang diễn ra", "Happening now") }
        let d = dayDiff(g.startMs, now: now, tz: tz)
        if d <= 0 {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: tz) ?? TimeZone(identifier: "Asia/Ho_Chi_Minh")!
            let hour = cal.component(.hour, from: Date(timeIntervalSince1970: g.startMs / 1000))
            return hour >= 17 ? ViEn("Tối nay", "Tonight") : ViEn("Hôm nay", "Today")
        }
        if d == 1 { return ViEn("Ngày mai", "Tomorrow") }
        return ViEn("Còn \(d) ngày", "In \(d) days")
    }

    static func people(_ g: Group) -> (main: ViEn, note: ViEn?) {
        let n = g.seats, k = g.bookings.count
        return (ViEn("\(n) người", n == 1 ? "1 person" : "\(n) people"), k > 1 ? ViEn("\(k) lượt đặt", "\(k) bookings") : nil)
    }

    struct Status: Equatable { var text: ViEn; var note: ViEn?; var tone: String; var icon: String; var action: String; var button: ViEn }

    static func status(_ g: Group, now: Date) -> Status {
        if g.state == "ready" {
            return Status(text: ViEn("Sẵn sàng", "Ready"), note: nil, tone: "moss", icon: "check", action: "ticket", button: ViEn("Hiện vé", "Show ticket"))
        }
        let mins: Int? = g.state == "pay" ? g.holdUntil.map { max(0, Int(ceil($0.timeIntervalSince(now) / 60))) } : nil
        let (action, button) = g.state == "pay" ? ("pay", ViEn("Thanh toán", "Pay now")) : ("status", ViEn("Xem trạng thái", "View status"))
        if g.mixed {
            return Status(text: ViEn("\(g.ready) sẵn sàng", "\(g.ready) ready"), note: ViEn("\(g.open) đang chờ", "\(g.open) waiting"), tone: "honey", icon: "clock", action: action, button: button)
        }
        if g.state == "pay" {
            return Status(text: ViEn("Chờ thanh toán", "Payment due"), note: mins.map { ViEn("còn \($0) phút", "\($0) min left") }, tone: "honey", icon: "clock", action: action, button: button)
        }
        return Status(text: ViEn("Chờ chủ nhà", "Host confirming"), note: nil, tone: "honey", icon: "clock", action: action, button: button)
    }

    /// Date badge in the venue's zone: SUN / 22 / NOV (VI: CN / 22 / TH 11).
    static func dateBadge(_ startMs: Double, tz: String, english: Bool) -> (weekday: String, day: String, month: String) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: tz) ?? TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        let d = Date(timeIntervalSince1970: startMs / 1000)
        let wd = cal.component(.weekday, from: d) - 1
        let day = cal.component(.day, from: d), month = cal.component(.month, from: d)
        let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
        return english
            ? (["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"][wd], "\(day)", months[month - 1])
            : (["CN", "T2", "T3", "T4", "T5", "T6", "T7"][wd], "\(day)", "TH \(month)")
    }
}

// MARK: - Event end time (note 82)

enum EventEnd {
    private static func hm(_ t: String?) -> Int? {
        guard let t, t.count >= 4 else { return nil }
        let parts = t.split(separator: ":")
        guard parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1].prefix(2)) else { return nil }
        return h * 60 + m
    }
    private static func fmt(_ mins: Int) -> String { String(format: "%02d:%02d", (mins / 60) % 24, mins % 60) }

    enum Mode: String { case time, open }

    static func mode(endTime: String?, endOpen: Bool) -> Mode? {
        if endOpen { return .open }
        return hm(endTime) != nil ? .time : nil
    }

    static func endsNextDay(_ start: String?, _ end: String?) -> Bool {
        guard let s = hm(start), let e = hm(end) else { return false }
        return e <= s
    }

    /// The end as a moment: the start's day at `endTime` on the venue's clock, the next day when it ends past midnight.
    static func endDate(start: Date, startTime: String, endTime: String) -> Date? {
        guard let s = hm(startTime), let e = hm(endTime) else { return nil }
        let minutes = e - s + (e <= s ? 1440 : 0)
        return start.addingTimeInterval(Double(minutes) * 60)
    }

    static func defaultEnd(_ start: String?) -> String { hm(start).map { fmt($0 + 180) } ?? "" }

    /// The note 38 window used when an event states no end: 12 hours after its start.
    static let overFallback: TimeInterval = 12 * 3600

    /// The moment an event is over (web twin `eventEndsAt`, src/lib/eventEnd.js), ONE rule for every surface: the
    /// host's end time on the venue's clock (at or before the start = the next day), else 12 h after the start when
    /// it is open-ended or not stated. Nil when the start is unknown (then nothing claims it is over).
    static func endsAt(start: Date?, timeZone: TimeZone?, endTime: String?, endOpen: Bool) -> Date? {
        guard let start else { return nil }
        if mode(endTime: endTime, endOpen: endOpen) == .time, let endTime {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = timeZone ?? TimeZone(identifier: "Asia/Ho_Chi_Minh") ?? .current
            let c = cal.dateComponents([.hour, .minute], from: start)
            let startTime = fmt((c.hour ?? 0) * 60 + (c.minute ?? 0))
            return endDate(start: start, startTime: startTime, endTime: endTime) ?? start.addingTimeInterval(overFallback)
        }
        return start.addingTimeInterval(overFallback)
    }

    /// True once the event is past its end (web twin `isEventOver`, without the status: callers drop 'ended' rows).
    static func isOver(start: Date?, timeZone: TimeZone?, endTime: String?, endOpen: Bool, now: Date) -> Bool {
        guard let end = endsAt(start: start, timeZone: timeZone, endTime: endTime, endOpen: endOpen) else { return false }
        return now >= end
    }

    static func error(mode: Mode?, start: String?, end: String?) -> String? {
        if mode == .open { return nil }
        guard mode == .time, let e = hm(end) else { return "missing" }
        if let s = hm(start), s == e { return "same" }
        return nil
    }

    /// "16:00 – 22:00", "22:00 – 02:00 (next day)", "16:00 · open-ended", or the start alone.
    static func timeRange(_ start: String?, endTime: String?, endOpen: Bool) -> ViEn? {
        guard let start, start.count >= 4 else { return nil }
        let s = String(start.prefix(5))
        switch mode(endTime: endTime, endOpen: endOpen) {
        case .open: return ViEn("\(s) · chưa có giờ kết thúc", "\(s) · open-ended")
        case .time:
            let e = String((endTime ?? "").prefix(5))
            let next = endsNextDay(s, e)
            return ViEn("\(s) – \(e)\(next ? " (hôm sau)" : "")", "\(s) – \(e)\(next ? " (next day)" : "")")
        case nil: return ViEn(s, s)
        }
    }

    static func duration(_ start: String?, _ end: String?) -> Int? {
        guard let s = hm(start), let e = hm(end) else { return nil }
        return e > s ? e - s : e + 1440 - s
    }
}
