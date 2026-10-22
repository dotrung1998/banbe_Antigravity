import XCTest
@testable import BanbeApp

/// Rewards v2 (migration 192). The vectors in tests/fixtures/rewards-v2-week-streak.json are shared with
/// tests/unit/rewardsV2.test.mjs, so web and iOS must produce the same English strings.
@MainActor
final class RewardsV2Tests: XCTestCase {
    private let T: (String, String) -> String = { _, en in en }

    private func fixture() throws -> [String: Any] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("tests/fixtures/rewards-v2-week-streak.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func decode<D: Decodable>(_ type: D.Type, _ obj: Any) throws -> D {
        try JSONDecoder().decode(D.self, from: JSONSerialization.data(withJSONObject: obj))
    }

    func testWeekStreakVectorsMatchWeb() throws {
        let vectors = try XCTUnwrap(fixture()["week_streak"] as? [[String: Any]])
        XCTAssertEqual(vectors.count, 5)
        for v in vectors {
            let ws = try decode(RewardsPayload.WeekStreak.self, v["raw"]!)
            let expect = try XCTUnwrap(v["expect"] as? [String: String])
            XCTAssertEqual(RewardsLogic.weekStreakHint(ws, en: true, T: T).status, expect["status"], v["name"] as? String ?? "")
            XCTAssertEqual(RewardsLogic.graceLine(ws, T: T), expect["grace"], v["name"] as? String ?? "")
        }
    }

    func testNextBadgeAndGoalVectorsMatchWeb() throws {
        for v in try XCTUnwrap(fixture()["next_badge"] as? [[String: Any]]) {
            let nb = try decode(RewardsPayload.NextBadge.self, v["nb"]!)
            XCTAssertEqual(RewardsLogic.nextBadgeLine(nb, en: true, T: T), v["expect"] as? String)
        }
        for v in try XCTUnwrap(fixture()["goal"] as? [[String: Any]]) {
            let g = try decode(RewardsPayload.Goal.self, v["raw"]!)
            XCTAssertEqual(RewardsLogic.goalLine(g, T: T), v["expect"] as? String)
        }
    }

    func testRepairCopyNamesTheRealDateAndNoLossWords() throws {
        let vectors = try XCTUnwrap(fixture()["week_streak"] as? [[String: Any]])
        let repair = try decode(RewardsPayload.WeekStreak.self, vectors[2]["raw"]!)
        XCTAssertTrue(RewardsLogic.weekStreakHint(repair, en: true, T: T).how.contains("Oct 25"))
        XCTAssertEqual(RewardsLogic.shortDate("2026-10-25", en: false), "25 thg 10")
        for v in vectors {
            let h = RewardsLogic.weekStreakHint(try decode(RewardsPayload.WeekStreak.self, v["raw"]!), en: true, T: T)
            XCTAssertNil("\(h.status) \(h.how)".range(of: "lose|lost|hurry|last chance|don't break", options: [.regularExpression, .caseInsensitive]))
        }
    }

    func testOldPayloadStillDecodesAndV2KeysAreOptional() throws {
        let old = """
        {"success":true,"balance":20,"rules":{"version":1},"streak":{"current":2,"longest":3},
         "badges":[{"code":"regular","title_vi":"a","title_en":"b","desc_vi":"c","desc_en":"d","target":5,"progress":2,"earned":false}],
         "history":[],"catalog":[]}
        """
        let p = try JSONDecoder().decode(RewardsPayload.self, from: Data(old.utf8))
        XCTAssertNil(p.weekStreak); XCTAssertNil(p.nextBadge); XCTAssertNil(p.goal)
        XCTAssertNil(p.badges[0].family)
        // A malformed v2 value is dropped, never a failed screen.
        let bad = old.replacingOccurrences(of: "\"catalog\":[]", with: "\"catalog\":[],\"week_streak\":{\"unit\":\"day\"},\"goal\":\"x\"")
        let q = try JSONDecoder().decode(RewardsPayload.self, from: Data(bad.utf8))
        XCTAssertNil(q.weekStreak); XCTAssertNil(q.goal)
        // A goal outside 1/2/4 reads as "no goal".
        XCTAssertNil(try decode(RewardsPayload.Goal.self, ["target": 3, "progress": 0]).target)
    }

    func testBadgesGroupByFamilyInTierOrder() throws {
        let raw: [[String: Any]] = [
            ["code": "regular", "family": "outings", "tier": 2, "title_vi": "", "title_en": "", "desc_vi": "", "desc_en": "", "target": 5, "progress": 4, "earned": false],
            ["code": "first_outing", "family": "outings", "tier": 1, "title_vi": "", "title_en": "", "desc_vi": "", "desc_en": "", "target": 1, "progress": 1, "earned": true],
            ["code": "explorer", "family": "explorer", "tier": 1, "title_vi": "", "title_en": "", "desc_vi": "", "desc_en": "", "target": 3, "progress": 1, "earned": false],
        ]
        let groups = RewardsLogic.groupBadgesByFamily(try decode([RewardsPayload.Badge].self, raw))
        XCTAssertEqual(groups.map(\.family), ["outings", "explorer"])
        XCTAssertEqual(groups[0].badges.map(\.code), ["first_outing", "regular"])
        XCTAssertEqual(groups[0].top?.code, "first_outing")
        XCTAssertEqual(groups[0].next?.code, "regular")
    }

    func testCelebrationsOncePerDeviceAndSameKeysAsWeb() throws {
        let earned: [[String: Any]] = [["code": "first_outing", "title_vi": "", "title_en": "", "desc_vi": "", "desc_en": "",
                                        "target": 1, "progress": 1, "earned": true, "earned_at": "2026-10-01T10:00:00Z"]]
        let badges = try decode([RewardsPayload.Badge].self, earned)
        let first = RewardsLogic.celebrationDiff(badges: badges, week: nil, celebrated: nil)
        XCTAssertTrue(first.show.isEmpty)
        XCTAssertEqual(first.keys, ["b:first_outing:2026-10-01T10:00:00Z"])
        XCTAssertTrue(RewardsLogic.celebrationDiff(badges: badges, week: nil, celebrated: first.keys).show.isEmpty)
        let ws = RewardsPayload.WeekStreak(current: 4, weekStart: "2026-10-19")
        let d = RewardsLogic.celebrationDiff(badges: [], week: ws, celebrated: [])
        XCTAssertEqual(d.show, [.weeks(4)])
        XCTAssertEqual(d.keys, ["w:4:2026-09-28"]) // same key as the web unit test
        XCTAssertTrue(RewardsLogic.celebrationDiff(badges: [], week: ws, celebrated: d.keys).show.isEmpty)
    }

    func testCapsuleCountsWeeksOnlyUnderV2WithAServerValue() {
        let old = RewardSummary(balance: 5, streak: 2, activeToday: true)
        XCTAssertEqual(RewardsLogic.capsuleStreak(old, weekly: true).value, 2)
        let v2 = RewardSummary(balance: 5, streak: 2, activeToday: true, weekStreak: 7, weekActive: false)
        XCTAssertEqual(RewardsLogic.capsuleStreak(v2, weekly: false).value, 2)
        XCTAssertEqual(RewardsLogic.capsuleStreak(v2, weekly: true).value, 7)
        XCTAssertTrue(RewardsLogic.capsuleStreak(v2, weekly: true).weekly)
    }

    func testRulesV2WindowLineAndWeeklyTerms() {
        var r = RewardsPayload.Rules(onboardingCoins: 10, attendanceCoins: 20, attendanceCoinCapPerMonth: 10, version: 3, timezone: nil)
        XCTAssertEqual(RewardsLogic.ruleLines(r, T: T).count, 3)
        r.attendanceWindowBeforeHours = 3; r.attendanceWindowAfterHours = 24
        XCTAssertTrue(RewardsLogic.ruleLines(r, T: T)[3].contains("between 3 hours before and 24 hours after the start"))
        XCTAssertTrue(RewardsLogic.termsLines(weekly: true, T: T).last!.contains("missing a week never costs coins"))
        XCTAssertTrue(RewardsLogic.historyLabel(reason: "off_window", eventName: nil, T: T).contains("outside the event time"))
        XCTAssertEqual(RewardsLogic.redeemErrorMessage("NOT_AVAILABLE", T: T), "Redeeming is switched off right now. No coins were spent.")
    }

    func testRewardsV2FlagIsOffUnlessSet() {
        XCTAssertFalse(FeatureFlags.isOn([:], "rewards_v2"))
        XCTAssertFalse(FeatureFlags.isOn(["rewards_v2": false], "rewards_v2"))
        XCTAssertTrue(FeatureFlags.isOn(["rewards_v2": true], "rewards_v2"))
        XCTAssertEqual(FeatureFlags.normalize(["rewards_v2": true]), ["rewards_v2": true])
    }
}
