import XCTest
@testable import BanbeApp

/// Phase 3 extras L6-L8 (docs/impl/phase3-extras.md). The `intentTitles`, `shareText` and `liveActivity` vectors in
/// tests/fixtures/core-loops.json are shared with tests/unit/coreLoops.test.mjs (web) — change both together.
final class Phase3ExtrasTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("tests/fixtures/core-loops.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func zone(_ id: String) -> TimeZone { TimeZone(identifier: id)! }
    private func at(_ date: String, _ time: String, _ tz: String) -> Date {
        EventMarket.wallClockDate(date: date, time: time, timeZone: zone(tz))!
    }

    // MARK: L6 intent For You

    func testIntentTitlesMatchTheContract() throws {
        let vs = try XCTUnwrap(fixture()["intentTitles"] as? [[String: Any]])
        XCTAssertEqual(vs.count, 5)
        for v in vs {
            let goal = v["goal"] as? String
            let t = CoreLoops.intentTitle(goals: goal.map { [$0] } ?? [])
            XCTAssertEqual(t.goal, goal)
            XCTAssertEqual(t.vi, v["vi"] as? String, "\(v)")
            XCTAssertEqual(t.en, v["en"] as? String, "\(v)")
            XCTAssertEqual(t.whyVi, v["whyVi"] as? String, "\(v)")
            XCTAssertEqual(t.whyEn, v["whyEn"] as? String, "\(v)")
        }
        // Every onboarding goal has a title (none silently falls back).
        XCTAssertEqual(Set(CoreLoops.intentTitles.keys), Set(EventPrefTaxonomy.goals.map(\.id)))
        XCTAssertEqual(Set(CoreLoops.intentTitles.keys), Set(vs.compactMap { $0["goal"] as? String }))
    }

    func testIntentTitleUsesTheFirstStatedGoal() {
        XCTAssertEqual(CoreLoops.intentTitle(goals: ["networking", "meet_people"]).goal, "networking")
        var p = EventPreferences()
        p.goals = ["learn", "experiences"]
        XCTAssertEqual(CoreLoops.intentTitle(goals: p.declaredGoals).en, "Learn something new")
        for goals in [nil, [], [EventPrefTaxonomy.noPreference]] as [[String]?] {
            var q = EventPreferences()
            q.goals = goals
            let t = CoreLoops.intentTitle(goals: q.declaredGoals)
            XCTAssertNil(t.goal)
            XCTAssertEqual(t.en, "For You")
            XCTAssertNil(t.whyEn)
        }
        XCTAssertEqual(CoreLoops.intentTitle(goals: ["someday_new_goal", "learn"]).goal, "learn")
        XCTAssertNil(CoreLoops.intentTitle(goals: ["someday_new_goal"]).goal)
    }

    // MARK: L7 Live Activity timing

    func testLiveActivityTimingMatchesTheContract() throws {
        let la = try XCTUnwrap(fixture()["liveActivity"] as? [String: Any])
        let before = try XCTUnwrap(la["startHoursBefore"] as? Int)
        let after = try XCTUnwrap(la["endHoursAfterStart"] as? Int)
        XCTAssertEqual(CoreLoops.liveActivityStartHoursBefore, before)
        XCTAssertEqual(CoreLoops.liveActivityEndHoursAfterStart, after)

        let start = at("2027-03-06", "19:00", "Asia/Ho_Chi_Minh")
        let h = { (n: Double) in start.addingTimeInterval(n * 3600) }
        XCTAssertNil(CoreLoops.liveActivityPhase(startsAt: start, now: h(-Double(before)).addingTimeInterval(-1)))
        XCTAssertEqual(CoreLoops.liveActivityPhase(startsAt: start, now: h(-Double(before))), .upcoming)
        XCTAssertEqual(CoreLoops.liveActivityPhase(startsAt: start, now: start.addingTimeInterval(-1)), .upcoming)
        XCTAssertEqual(CoreLoops.liveActivityPhase(startsAt: start, now: start), .started)
        XCTAssertEqual(CoreLoops.liveActivityPhase(startsAt: start, now: h(Double(after)).addingTimeInterval(-1)), .started)
        XCTAssertNil(CoreLoops.liveActivityPhase(startsAt: start, now: h(Double(after))))
        XCTAssertEqual(CoreLoops.liveActivityEnd(startsAt: start), h(Double(after)))
        // The app re-checks at the next phase change while running.
        XCTAssertEqual(CoreLoops.liveActivityNextChange(startsAt: start, now: h(-10)), h(-Double(before)))
        XCTAssertEqual(CoreLoops.liveActivityNextChange(startsAt: start, now: h(-1)), start)
        XCTAssertEqual(CoreLoops.liveActivityNextChange(startsAt: start, now: h(1)), h(Double(after)))
        XCTAssertNil(CoreLoops.liveActivityNextChange(startsAt: start, now: h(Double(after))))
    }

    func testLiveActivityShowsTheVenueTimeWithoutACountdown() {
        let start = at("2027-03-06", "19:00", "America/New_York")
        let us = EventDayAttributes(bookingID: "b1", eventName: "Jazz Night", venue: "Brooklyn", startsAt: start,
                                    ticketCode: "BB-1", timeZoneID: "America/New_York", market: "US", lang: "en")
        XCTAssertEqual(us.timeText, "7:00 PM")
        XCTAssertEqual(us.statusText(.upcoming), "Starts at 7:00 PM")
        XCTAssertEqual(us.statusText(.started), "Started at 7:00 PM")
        XCTAssertEqual(us.ticketURL?.absoluteString, "banbe://ticket/b1")
        let vn = EventDayAttributes(bookingID: "b2", eventName: "Đêm nhạc Jazz", venue: "Quận 1",
                                    startsAt: at("2027-03-06", "19:00", "Asia/Ho_Chi_Minh"), ticketCode: "BB-2",
                                    timeZoneID: "Asia/Ho_Chi_Minh", market: "VN", lang: "vi")
        XCTAssertEqual(vn.timeText, "19:00")
        XCTAssertEqual(vn.statusText(.upcoming), "Bắt đầu lúc 19:00")
    }

    // MARK: L8 market sharing

    func testShareTextMatchesTheContract() throws {
        let vs = try XCTUnwrap(fixture()["shareText"] as? [[String: Any]])
        let zones = ["VN": "Asia/Ho_Chi_Minh", "US": "America/New_York"]
        XCTAssertEqual(vs.count, 2)
        for v in vs {
            let market = try XCTUnwrap(v["market"] as? String)
            XCTAssertEqual(CoreLoops.shareMarket(market.lowercased()), market)
            let tz = try XCTUnwrap(zones[market])
            // 2027-03-06 19:00 in the venue's zone (a Saturday).
            XCTAssertEqual(CoreLoops.shareWhen(startsAt: at("2027-03-06", "19:00", tz), timeZone: zone(tz), market: market),
                           v["when"] as? String, market)
            let text = CoreLoops.shareInviteText(name: try XCTUnwrap(v["name"] as? String), when: try XCTUnwrap(v["when"] as? String),
                                                 url: try XCTUnwrap(v["url"] as? String))
            XCTAssertEqual(text, v["text"] as? String, market)
            if let sms = v["sms"] as? String {
                XCTAssertEqual(CoreLoops.smsInviteLink(text), sms)
                XCTAssertNotNil(URL(string: sms))
            }
        }
    }

    func testShareMarketAndFormats() {
        XCTAssertNil(CoreLoops.shareMarket(nil))
        XCTAssertNil(CoreLoops.shareMarket(""))
        XCTAssertNil(CoreLoops.shareMarket("FR"))
        let ny = "America/New_York"
        XCTAssertEqual(CoreLoops.shareWhen(startsAt: at("2027-03-07", "00:05", ny), timeZone: zone(ny), market: "US"), "Sun, Mar 7 ▪︎ 12:05 AM")
        XCTAssertEqual(CoreLoops.shareWhen(startsAt: at("2027-03-07", "12:30", ny), timeZone: zone(ny), market: "US"), "Sun, Mar 7 ▪︎ 12:30 PM")
        let vn = "Asia/Ho_Chi_Minh"
        XCTAssertEqual(CoreLoops.shareWhen(startsAt: at("2027-12-28", "09:00", vn), timeZone: zone(vn), market: "VN"), "Th 3, 28.12 ▪︎ 09:00")
        XCTAssertEqual(CoreLoops.shareInviteText(name: "Jazz", when: "", url: "https://x"), "Jazz\nhttps://x")
        XCTAssertEqual(CoreLoops.zaloCopied.vi, "Đã chép. Dán vào Zalo nhé.")
        XCTAssertEqual(CoreLoops.zaloCopied.en, "Copied. Paste it in Zalo.")
    }
}
