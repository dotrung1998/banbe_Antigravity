import XCTest
@testable import BanbeApp

final class EventPreferencesTests: XCTestCase {
    func testNormalizedForSaveEmptyArraysBecomeNil() {
        let p = EventPreferences(interests: [], goals: [], availability: [], budget: nil, languages: []).normalizedForSave()
        XCTAssertNil(p.interests); XCTAssertNil(p.goals); XCTAssertNil(p.availability); XCTAssertNil(p.languages)
        XCTAssertTrue(p.isEmpty)
    }

    func testNoPreferenceIsExclusive() {
        let p = EventPreferences(interests: ["music", "no_preference", "gallery"]).normalizedForSave()
        XCTAssertEqual(p.interests, ["no_preference"])
        XCTAssertTrue(p.declaredInterests.isEmpty)
    }

    func testFreeBudgetDropsCurrency() {
        let p = EventPreferences(budget: BudgetPref(tier: "free", currency: "VND")).normalizedForSave()
        XCTAssertEqual(p.budget, BudgetPref(tier: "free", currency: nil))
        let q = EventPreferences(budget: BudgetPref(tier: "low", currency: "VND")).normalizedForSave()
        XCTAssertEqual(q.budget?.currency, "VND")
    }

    func testReservationCriteriaNormalization() {
        let empty = ReservationCriteria(mode: "declared", interests: CriteriaGroup(rule: "any", values: []),
                                        goals: CriteriaGroup(rule: "all", values: []))
        XCTAssertEqual(empty.normalizedForSave(), .everyone)
        XCTAssertEqual(ReservationCriteria(mode: "declared").normalizedForSave(), .everyone)
        let ok = ReservationCriteria(mode: "declared", interests: CriteriaGroup(rule: "any", values: ["music"]),
                                     goals: CriteriaGroup(rule: "all", values: []))
        let n = ok.normalizedForSave()
        XCTAssertEqual(n.mode, "declared"); XCTAssertNil(n.goals); XCTAssertEqual(n.interests?.values, ["music"])
        let ev = ReservationCriteria(mode: "everyone", interests: CriteriaGroup(rule: "any", values: ["music"]))
        XCTAssertEqual(ev.normalizedForSave(), .everyone)
    }

    func testEligibilityGuidance() throws {
        let json = """
        {"success":true,"eligible":false,"mode":"declared","interest_rule":"any","goal_rule":"all",
         "missing_interests":["music","gallery"],"missing_goals":["learn"]}
        """
        let e = try JSONDecoder().decode(ReservationEligibility.self, from: Data(json.utf8))
        let g = e.guidance(vi: false)
        XCTAssertEqual(g.count, 2)
        XCTAssertTrue(g[0].contains("Pick at least one"))
        XCTAssertTrue(g[0].contains("Music") && g[0].contains("Gallery"))
        XCTAssertTrue(g[1].contains("Add"))
        XCTAssertTrue(g[1].contains("Learn something"))
    }

    private func object(_ v: some Encodable) throws -> [String: Any] {
        let d = try JSONEncoder().encode(v)
        return try JSONSerialization.jsonObject(with: d) as! [String: Any]
    }

    func testEventPreferencesJSONShape() throws {
        let p = EventPreferences(interests: ["music"], goals: ["learn"], availability: ["weekends"],
                                 budget: BudgetPref(tier: "low", currency: "VND"), languages: ["vi"])
        let o = try object(p)
        XCTAssertEqual(o["version"] as? Int, 1)
        XCTAssertEqual(o["interests"] as? [String], ["music"])
        XCTAssertEqual(o["goals"] as? [String], ["learn"])
        XCTAssertEqual(o["availability"] as? [String], ["weekends"])
        XCTAssertEqual(o["languages"] as? [String], ["vi"])
        let b = o["budget"] as? [String: Any]
        XCTAssertEqual(b?["tier"] as? String, "low"); XCTAssertEqual(b?["currency"] as? String, "VND")
        let back = try JSONDecoder().decode(EventPreferences.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back, p)
        // Skipped questions are omitted, not null.
        let sparse = try object(EventPreferences(interests: ["music"]))
        XCTAssertNil(sparse["goals"]); XCTAssertNil(sparse["budget"])
    }

    func testReservationCriteriaJSONShape() throws {
        let c = ReservationCriteria(mode: "declared", interests: CriteriaGroup(rule: "any", values: ["music", "gallery"]))
        let o = try object(c)
        XCTAssertEqual(o["version"] as? Int, 1)
        XCTAssertEqual(o["mode"] as? String, "declared")
        let i = o["interests"] as? [String: Any]
        XCTAssertEqual(i?["rule"] as? String, "any")
        XCTAssertEqual(i?["values"] as? [String], ["music", "gallery"])
        XCTAssertNil(o["goals"])
        XCTAssertEqual(try JSONDecoder().decode(ReservationCriteria.self, from: JSONEncoder().encode(c)), c)
    }
}
