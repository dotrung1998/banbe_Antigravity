import XCTest
@testable import BanbeApp

/// Mirrors tests/unit/pager.test.mjs, browse.test.mjs, liveLine.test.mjs, reserveBarV23.test.mjs, eventDetailV23.test.mjs,
/// nextUp.test.mjs and eventEnd.test.mjs (note 81/82). The pager cases come from the shared tests/fixtures/pager.json.
final class V23RulesTests: XCTestCase {
    private func fixture(_ name: String) throws -> [String: Any] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("tests/fixtures/\(name)"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: Pager (shared fixture)

    func testPagerSharedFixture() throws {
        let root = try fixture("pager.json")
        for c in try XCTUnwrap(root["pages"] as? [[String: Any]]) {
            let n = c["n"] as? Int ?? 0
            XCTAssertEqual(Pager.paginate(Array(0..<n)).map(\.count), c["sizes"] as? [Int], "n \(n)")
        }
        for c in try XCTUnwrap(root["ranges"] as? [[String: Any]]) {
            let n = c["n"] as? Int ?? 0, page = c["page"] as? Int ?? 0
            let sizes = Pager.paginate(Array(0..<n)).map(\.count)
            XCTAssertEqual(Pager.rangeText(sizes: sizes, page: page, english: true), c["en"] as? String)
            XCTAssertEqual(Pager.rangeText(sizes: sizes, page: page, english: false), c["vi"] as? String)
        }
        for c in try XCTUnwrap(root["endCard"] as? [[String: Any]]) {
            let n = c["n"] as? Int ?? 0
            let r = Pager.endCardRoom(sizes: Pager.paginate(Array(0..<n)).map(\.count))
            XCTAssertEqual(r.room, c["room"] as? Int, "n \(n)")
            XCTAssertEqual(r.variant?.rawValue, c["variant"] as? String, "n \(n)")
        }
    }

    func testPageWindowAndNav() {
        XCTAssertEqual(Pager.pageWindow(0, 3), [0, 1, 2])
        XCTAssertEqual(Pager.pageWindow(0, 8), [0, 1, 2, 3, 4])
        XCTAssertEqual(Pager.pageWindow(7, 8), [3, 4, 5, 6, 7])
        XCTAssertEqual(Pager.pageWindow(4, 8), [2, 3, 4, 5, 6])
        XCTAssertFalse(Pager.showNav(pageCount: 1))
        XCTAssertEqual(Pager.pageAt(offset: 390 * 1.6, pageWidth: 390, pageCount: 3), 2)
    }

    // MARK: End cards

    func testShortlistAndBrowseEndCards() {
        let f = ListEnd.shortlistEnd(tab: "foryou", tabLabel: ViEn("Dành cho bạn", "For You"), total: 9, shown: 6, filtersOn: true)
        XCTAssertEqual(f.kind, "filters")
        XCTAssertEqual(f.title.en, "3 more are just outside your filters.")
        XCTAssertEqual(f.slimmed.actions.map(\.act), ["clear-filters"])
        XCTAssertNil(f.slimmed.body)
        let t = ListEnd.shortlistEnd(tab: "tonight", tabLabel: ViEn("Tối nay", "Tonight"), total: 3, shown: 3, filtersOn: false)
        XCTAssertEqual(t.title.en, "That’s tonight. The good seats go first.")
        let ty = ListEnd.browseEnd(type: "gallery", typeName: ViEn("Phòng tranh", "Gallery"), count: 9, hidden: 0, query: "",
                                   others: [.init(key: "fashion", name: ViEn("Thời trang", "Fashion"), count: 8)])
        XCTAssertEqual(ty.title.vi, "Vẫn tò mò? Thời trang có 8 sự kiện.")
        XCTAssertEqual(ty.actions.map(\.act), ["type:fashion", "type:all"])
        let s = ListEnd.browseEnd(type: "all", typeName: nil, count: 1, hidden: 0, query: "bep", others: [])
        XCTAssertEqual(s.eyebrow?.en, "1 match for “bep”")
        for c in [f, t, ty, s] { for p in [c.title, c.body].compactMap({ $0 }) { XCTAssertFalse("\(p.vi) \(p.en)".contains("—")) } }
    }

    // MARK: Browse

    private func entry(_ key: String, _ cats: [String], name: String, host: String?, hostName: String = "") -> BrowseRules.Entry {
        BrowseRules.Entry(item: HomeDiscovery.Item(key: key, startsAt: nil, priceVnd: 100_000, catKeys: cats), name: name, area: "Quận 1",
                          catDisplay: "", organizerId: host, organizerName: hostName, avatarURL: nil)
    }

    func testBrowseTypesSearchHosts() {
        let list = [entry("a", ["supper"], name: "Bếp Nhỏ №12", host: "o1", hostName: "Bếp Nhỏ"),
                    entry("b", ["music", "supper"], name: "Jazz Ở Gác", host: "o2", hostName: "Gác"),
                    entry("c", ["music"], name: "Đêm Bass", host: "o2", hostName: "Gác"),
                    entry("d", ["gallery"], name: "Demo", host: nil)]
        XCTAssertEqual(BrowseRules.ofType(list, "supper").map(\.key), ["a", "b"])
        XCTAssertEqual(BrowseRules.typeCounts(list)["music"], 2)
        XCTAssertTrue(BrowseRules.matches(list[0], "bep nho"))
        XCTAssertFalse(BrowseRules.matches(list[0], "jazz"))
        let hosts = BrowseRules.hosts(list)
        XCTAssertEqual(hosts.map(\.id), ["o2", "o1"], "busiest first, demo rows have no host")
        XCTAssertEqual(BrowseRules.deckLine(hosts).names.en, "Gác, Bếp Nhỏ")
        XCTAssertEqual(BrowseRules.deckLine([hosts[0]]).more.en, "hosts every event here")
        XCTAssertEqual(BrowseRules.rotate(hosts).map(\.id), ["o1", "o2"])
        XCTAssertEqual(BrowseRules.filterHosts(hosts, "bep").map(\.id), ["o1"])
        var f = HomeDiscovery.Filters.default
        f.date = "weekend"; f.free = true; f.cats = ["music"]
        XCTAssertEqual(BrowseRules.filterCount(f), 2, "category is the chips' job, not a filter")
    }

    // MARK: Live line

    func testLiveLine() {
        let pulse = [LiveLine.PulseItem(eventId: "e1", eventName: "Bếp Nhỏ", organizerName: "Minh", bookingCount: 0),
                     LiveLine.PulseItem(eventId: "e2", eventName: "Băng Cối", organizerName: "Băng Cối", bookingCount: 0),
                     LiveLine.PulseItem(eventId: "e3", eventName: "Jazz", organizerName: "Gác", bookingCount: 4),
                     LiveLine.PulseItem(eventId: "gone", eventName: "Old", organizerName: "", bookingCount: 9)]
        let facts: [String: LiveLine.Facts] = ["e1": .init(seatsLeft: 3, when: "T7"), "e2": .init(seatsLeft: 20, when: ""), "e3": .init(seatsLeft: nil, when: "")]
        let u = LiveLine.updates(pulse: pulse, lookup: { facts[$0] }, tonight: 2, weekend: 5)
        XCTAssertEqual(u.map(\.kind), ["summary", "seats", "trending", "booked"])
        XCTAssertEqual(u[0].text.en, "2 events on tonight")
        XCTAssertEqual(u[1].text.en, "Only 3 seats left at Bếp Nhỏ")
        XCTAssertEqual(u[2].text.en, "Băng Cối is getting attention", "a host named like the event is left out")
        XCTAssertEqual(u[3].text.en, "4 bookings for Jazz today")
        XCTAssertEqual(LiveLine.step(0, -1, 3), 0)
        XCTAssertEqual(LiveLine.step(2, 1, 3), 2)
        XCTAssertGreaterThanOrEqual(LiveLine.seconds(["a"]), 16)
    }
}

final class V23EventRulesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_794_632_400) // 2026-11-14 05:00Z, Saturday noon in Saigon
    private func at(_ m: Double) -> Date { now.addingTimeInterval(m * 60) }
    private func bk(_ id: String = "b1", qty: Int = 1, status: String = "pending", pay: String = "holding", hold: Double? = 25,
                    verify: Double? = nil, created: Double = -60) -> ReserveBarV23.SeatBooking {
        .init(id: id, qty: qty, status: status, paymentState: pay, holdExpiresAt: hold.map(at), verifyDueAt: verify.map(at), createdAt: at(created))
    }

    func testCompactAndQuantity() {
        XCTAssertTrue(ReserveBarV23.nextCompact(0, true))
        XCTAssertTrue(ReserveBarV23.nextCompact(40, true))
        XCTAssertFalse(ReserveBarV23.nextCompact(41, true))
        XCTAssertFalse(ReserveBarV23.nextCompact(30, false), "between the thresholds it keeps its state")
        XCTAssertTrue(ReserveBarV23.nextCompact(-20, false))
        XCTAssertEqual(ReserveBarV23.control(1, remaining: nil), .init(max: 6, stepper: false, moreEnabled: true, canMinus: false, canPlus: true))
        XCTAssertFalse(ReserveBarV23.control(2, remaining: 3).moreEnabled)
        XCTAssertEqual(ReserveBarV23.seatDots(4), [.me, .guest, .guest, .guest, .empty, .empty])
        XCTAssertEqual(ReserveBarV23.guestLine(4, remaining: nil).en, "You + 3 guests · up to 6")
        XCTAssertEqual(ReserveBarV23.guestLine(6, remaining: nil).en, "You + 5 guests · 6 is the most per person")
        XCTAssertEqual(ReserveBarV23.guestLine(4, remaining: 4).en, "You + 3 guests · only 4 left")
        XCTAssertEqual(ReserveBarV23.moreRefusal(3).en, "Only 3 tickets left for this one")
        XCTAssertEqual(ReserveBarV23.totalSub(2, unitText: "850.000₫", free: false).en, "Total · 2 × 850.000₫")
    }

    func testStampsAndAdding() {
        XCTAssertTrue(ReserveBarV23.holdsSeat(bk(), now: now))
        XCTAssertFalse(ReserveBarV23.holdsSeat(bk(hold: -1), now: now))
        XCTAssertTrue(ReserveBarV23.holdsSeat(bk(pay: "pending_verification", hold: -90), now: now))
        XCTAssertEqual(ReserveBarV23.bookedQty([bk(qty: 2), bk(qty: 3, status: "cancelled"), bk(qty: 1, status: "confirmed", pay: "confirmed")], now: now), 3)
        XCTAssertNil(ReserveBarV23.stampState([], now: now))
        XCTAssertEqual(ReserveBarV23.stampText(ReserveBarV23.stampState([bk()], now: now), now: now)?.en, "Held · 25 min")
        XCTAssertEqual(ReserveBarV23.stampState([bk(status: "confirmed", pay: "confirmed")], now: now)?.kind, .confirmed)
        XCTAssertEqual(ReserveBarV23.stampState([bk(status: "confirmed", pay: "confirmed"), bk("b2")], now: now)?.kind, .held)
        XCTAssertEqual(ReserveBarV23.stampText(.init(kind: .held, until: at(61), phase: "hold"), now: now)?.vi, "Đã giữ · 2 giờ")
        XCTAssertEqual(ReserveBarV23.addControl(1, remaining: 10, booked: 2).qty, 2)
        XCTAssertEqual(ReserveBarV23.addControl(5, remaining: 10, booked: 4).extra, 1)
        XCTAssertEqual(ReserveBarV23.addControl(6, remaining: 1, booked: 4).max, 5)
        XCTAssertFalse(ReserveBarV23.addControl(6, remaining: 0, booked: 6).moreEnabled)
        let c = ReserveBarV23.heldCopy(booked: 4, extra: 1, confirmed: false, phase: nil)
        XCTAssertEqual(c.button.en, "Add 1 ticket")
        XCTAssertEqual(c.sub.en, "1 more · 5 in all")
        XCTAssertEqual(ReserveBarV23.addGuestLine(5, booked: 4, max: 6)?.en, "4 held · adding 1 · up to 6")
        XCTAssertNil(ReserveBarV23.addGuestLine(4, booked: 4, max: 6))
    }

    func testKnowRowsAndMotion() {
        let need = [EventDetailV23.NeedRow(id: "alcohol", key: "alcohol", icon: "alcohol", title: "Included", sub: "Rice wine all night"),
                    .init(id: "dietary", key: "dietary", icon: "dietary", title: "Vegetarian", sub: "Tell us 24 h ahead"),
                    .init(id: "dietary", key: "dietary-2", icon: "dietary", title: "No pork", sub: nil),
                    .init(id: "min_age", key: "min_age-row", icon: "age", title: "Ages 18 and up", sub: nil),
                    .init(id: "dress", key: "dress", icon: "fact", title: "Dress code", sub: "Smart casual"),
                    .init(id: "empty", key: "empty", icon: "fact", title: "Nothing", sub: nil)]
        let k = EventDetailV23.knowRows(need, refund: "Automatic full refund if the event is cancelled")
        XCTAssertEqual(k.map(\.key), ["alcohol", "dietary", "min_age-row", "dress", "refund"])
        XCTAssertEqual(k[1].text, "Vegetarian, No pork · Tell us 24 h ahead")
        XCTAssertEqual(EventDetailV23.listNo(0), "01")
        XCTAssertEqual(EventDetailV23.heroMotion(100).offset, 20)
        XCTAssertFalse(EventDetailV23.navOn(140))
        XCTAssertTrue(EventDetailV23.navOn(141))
        XCTAssertEqual(EventDetailV23.readProgress(50, contentHeight: 1100, viewHeight: 1000), 0.5)
    }

    func testNextUp() {
        let H = 3_600_000.0, nowMs = now.timeIntervalSince1970 * 1000
        let events: [String: NextUp.EventInfo] = ["e1": .init(startMs: nowMs + 15 * 24 * H), "e2": .init(startMs: nowMs + 2 * 24 * H),
                                                  "e3": .init(startMs: nowMs - 2 * H, endMs: nowMs + H), "old": .init(startMs: nowMs - 20 * H)]
        let rows: [(eventId: String, booking: ReserveBarV23.SeatBooking, gifted: Bool)] = [
            ("e1", bk("b1", qty: 2, status: "confirmed", pay: "confirmed"), false),
            ("e1", bk("b2", qty: 1, hold: 20), false),
            ("e2", bk("b3", qty: 1, status: "confirmed", pay: "confirmed"), false),
            ("old", bk("b4", status: "confirmed", pay: "confirmed"), false),
            ("e2", bk("b5", status: "confirmed", pay: "confirmed"), true),
            ("e3", bk("b6", pay: "pending_verification", hold: nil), false),
        ]
        let g = NextUp.groups(rows, events: events, now: now)
        XCTAssertEqual(g.map(\.eventId), ["e3", "e2", "e1"])
        let e1 = g[2]
        XCTAssertEqual(e1.seats, 3)
        XCTAssertEqual(e1.state, "pay")
        XCTAssertTrue(e1.mixed)
        XCTAssertEqual(e1.primaryId, "b2")
        XCTAssertTrue(g[0].live)
        XCTAssertEqual(NextUp.status(e1, now: now).text.en, "2 ready")
        XCTAssertEqual(NextUp.status(e1, now: now).note?.en, "1 waiting")
        XCTAssertEqual(NextUp.people(e1).note?.en, "2 bookings")
        XCTAssertEqual(NextUp.status(g[1], now: now).button.en, "Show ticket")
        XCTAssertEqual(NextUp.chip(e1, now: now, tz: "Asia/Ho_Chi_Minh").en, "In 15 days")
        XCTAssertEqual(NextUp.chip(g[0], now: now, tz: "Asia/Ho_Chi_Minh").en, "Happening now")
        let badge = NextUp.dateBadge(Date(timeIntervalSince1970: 1_795_350_600).timeIntervalSince1970 * 1000, tz: "Asia/Ho_Chi_Minh", english: true)
        XCTAssertEqual(badge.day.count > 0, true)
    }

    func testEventEnd() {
        XCTAssertEqual(EventEnd.mode(endTime: "22:00:00", endOpen: false), .time)
        XCTAssertEqual(EventEnd.mode(endTime: nil, endOpen: true), .open)
        XCTAssertNil(EventEnd.mode(endTime: nil, endOpen: false))
        XCTAssertEqual(EventEnd.timeRange("16:00:00", endTime: "22:00:00", endOpen: false)?.en, "16:00 – 22:00")
        XCTAssertEqual(EventEnd.timeRange("22:00", endTime: "02:00", endOpen: false)?.en, "22:00 – 02:00 (next day)")
        XCTAssertEqual(EventEnd.timeRange("22:00", endTime: "02:00", endOpen: false)?.vi, "22:00 – 02:00 (hôm sau)")
        XCTAssertEqual(EventEnd.timeRange("16:00", endTime: nil, endOpen: true)?.en, "16:00 · open-ended")
        XCTAssertEqual(EventEnd.timeRange("16:00", endTime: nil, endOpen: false)?.en, "16:00")
        XCTAssertEqual(EventEnd.defaultEnd("22:30"), "01:30")
        XCTAssertEqual(EventEnd.error(mode: .time, start: "19:00", end: "19:00"), "same")
        XCTAssertNil(EventEnd.error(mode: .open, start: "19:00", end: nil))
        XCTAssertEqual(EventEnd.duration("22:00", "02:00"), 240)
    }
}
