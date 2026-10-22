import XCTest
@testable import BanbeApp

@MainActor
final class RewardsTests: XCTestCase {
    private let en: (String, String) -> String = { _, e in e }

    func testCompactCoinsKeepsTheHeaderNarrow() {
        XCTAssertEqual(RewardsLogic.compactCoins(0), "0")
        XCTAssertEqual(RewardsLogic.compactCoins(9999), "9999")
        XCTAssertEqual(RewardsLogic.compactCoins(10_000), "10k")
        XCTAssertEqual(RewardsLogic.compactCoins(12_500), "12.5k")
        XCTAssertEqual(RewardsLogic.compactCoins(-40), "-40") // a balance can go negative after a reversal
    }

    func testShortfallIsExactAndNeverNegative() {
        XCTAssertEqual(RewardsLogic.shortfall(balance: 60, price: 80), 20)
        XCTAssertEqual(RewardsLogic.shortfall(balance: 100, price: 80), 0)
        XCTAssertEqual(RewardsLogic.shortfall(balance: -40, price: 40), 80)
    }

    func testPayloadDecodesTheServerShape() throws {
        let json = """
        {"success":true,"balance":60,"rules":{"onboarding_coins":10,"attendance_coins":20,"attendance_coin_cap_per_month":10,"version":1,"timezone":"Asia/Ho_Chi_Minh"},
         "streak":{"current":3,"longest":5,"active_today":true,"timezone":"Asia/Ho_Chi_Minh","last_active_date":"2026-10-07"},
         "badges":[{"code":"first_outing","title_vi":"Buổi đầu tiên","title_en":"First outing","desc_vi":"x","desc_en":"y","target":1,"progress":1,"earned":true,"earned_at":"2026-10-07T01:00:00Z"}],
         "history":[{"id":"a","type":"award","amount":20,"reason":"attendance","created_at":"2026-10-07T01:00:00.123456+00:00","event_name":"Jazz","item_code":null}],
         "catalog":[{"code":"rwd-comet","kind":"keychain_design","design_id":"rwd-comet","price":40,"unlocked":false}],
         "attendance_paid_this_month":1}
        """
        let p = try JSONDecoder().decode(RewardsPayload.self, from: Data(json.utf8))
        XCTAssertEqual(p.balance, 60)
        XCTAssertEqual(p.rules.attendanceCoinCapPerMonth, 10)
        XCTAssertEqual(p.streak.current, 3)
        XCTAssertTrue(p.badges[0].earned)
        XCTAssertEqual(p.history[0].eventName, "Jazz")
        XCTAssertEqual(p.catalog[0].price, 40)
        XCTAssertFalse(p.catalog[0].unlocked)
    }

    func testEarningRulesComeFromServerValuesAndStateTheCap() {
        let r = RewardsPayload.Rules(onboardingCoins: 10, attendanceCoins: 20, attendanceCoinCapPerMonth: 10, version: 1, timezone: nil)
        let lines = RewardsLogic.ruleLines(r, T: en)
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].contains("+10 coins"))
        XCTAssertTrue(lines[1].contains("+20 coins"))
        XCTAssertTrue(lines[2].contains("10 events pay coins per month (200 coins)"))
        XCTAssertEqual(RewardsLogic.ruleLines(.init(onboardingCoins: 5, attendanceCoins: 7), T: en).count, 2)
    }

    func testTermsStateTheNonNegotiables() {
        let all = (RewardsLogic.termsLines(T: en) + RewardsLogic.noCoinLines(T: en)).joined(separator: " ")
        for must in ["cannot be bought, transferred or cashed out", "no random prizes", "never affect booking, priority or eligibility",
                     "free charms always stay available", "negative", "never costs coins", "claimed the ticket"] {
            XCTAssertTrue(all.localizedCaseInsensitiveContains(must), must)
        }
    }

    func testHistoryLabelsNeverExposeRawCodes() {
        XCTAssertEqual(RewardsLogic.historyLabel(reason: "attendance", eventName: "Jazz", T: en), "Attended an event ▪︎ Jazz")
        XCTAssertTrue(RewardsLogic.historyLabel(reason: "attendance_reversed", eventName: nil, T: en).contains("undone"))
        XCTAssertEqual(RewardsLogic.historyLabel(reason: "something_new", eventName: nil, T: en), "Activity")
    }

    func testRedeemErrorsAreHumanReadable() {
        XCTAssertTrue(RewardsLogic.redeemErrorMessage("INSUFFICIENT_BALANCE", T: en).contains("enough coins"))
        XCTAssertTrue(RewardsLogic.redeemErrorMessage("NETWORK", T: en).contains("No coins were spent"))
        XCTAssertEqual(RewardsLogic.redeemErrorMessage(nil, T: en), "Please try again.")
    }

    func testAccountSwitchClearsRewardsImmediately() {
        let app = AppState()
        app.rewardsSummary = RewardSummary(balance: 120, streak: 4, activeToday: true)
        app.rewardsSummaryStatus = .loaded
        app.rewardsUnlocked = ["rwd-comet"]
        app.rewardsOwnerID = UUID()
        app.resetRewardsState()
        XCTAssertNil(app.rewardsSummary)
        XCTAssertEqual(app.rewardsSummaryStatus, .idle)
        XCTAssertTrue(app.rewardsUnlocked.isEmpty)
        XCTAssertNil(app.rewardsOwnerID)
    }

    func testNothingIsRequestedWithoutAnAccount() async {
        let app = AppState()
        app.userID = nil
        await app.loadRewardsSummary()
        await app.loadRewards()
        let r = await app.redeemReward("rwd-comet")
        XCTAssertNil(r)
        XCTAssertEqual(app.rewardsSummaryStatus, .idle)
        XCTAssertNil(app.rewards)
    }

    func testRewardDesignsMatchTheServerCatalog() throws {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let sql = try String(contentsOf: url.appendingPathComponent("supabase/migrations/20261212000165_165_rewards_badges_streaks.sql"), encoding: .utf8)
        for (id, price) in [("rwd-comet", 40), ("rwd-lantern", 80), ("rwd-crown", 120)] {
            let pattern = "\\('\(id)',\\s*'keychain_design',\\s*'\(id)',\\s*\(price),"
            XCTAssertNotNil(sql.range(of: pattern, options: .regularExpression), "\(id) @ \(price)")
        }
    }

    func testOlderServerPayloadWithoutTimezoneSettingsStillDecodes() throws {
        let json = """
        {"success":true,"balance":0,"rules":{"version":1},"streak":{"current":0,"longest":0},"badges":[],"history":[],"catalog":[]}
        """
        let p = try JSONDecoder().decode(RewardsPayload.self, from: Data(json.utf8))
        XCTAssertNil(p.timezoneSettings)
    }

    func testNewPayloadDecodesTimezoneSettingsAndToleratesUnknownKeys() throws {
        let json = """
        {"success":true,"balance":0,"rules":{"version":1},"streak":{"current":0,"longest":0,"timezone":"America/New_York"},"badges":[],"history":[],"catalog":[],
         "some_future_key":{"x":1},
         "timezone_settings":{"effective_tz":"America/New_York","chosen":true,"default_tz":"Asia/Ho_Chi_Minh","pending_tz":null,"pending_from":null,"changes_left":1,"next_change_at":null}}
        """
        let p = try JSONDecoder().decode(RewardsPayload.self, from: Data(json.utf8))
        XCTAssertEqual(p.timezoneSettings?.effectiveTz, "America/New_York")
        XCTAssertEqual(p.timezoneSettings?.changesLeft, 1)
        XCTAssertNil(p.timezoneSettings?.pendingTz)
    }

    func testTimezoneSuggestionsNeverAutoAssign() {
        XCTAssertEqual(RewardsLogic.suggestedTimezones.first?.id, "Asia/Ho_Chi_Minh")
        XCTAssertEqual(RewardsLogic.deviceTimezoneHint("America/Chicago"), "America/Chicago")
        XCTAssertNil(RewardsLogic.deviceTimezoneHint("Europe/Paris"))
        XCTAssertTrue(RewardsLogic.streakLines(tz: nil, T: en)[1].contains("Asia/Ho_Chi_Minh"))
        XCTAssertFalse(RewardsLogic.streakLines(tz: "America/New_York", T: en)[1].contains("fixed"))
        XCTAssertEqual(RewardsLogic.timezoneErrorMessage("TZ_CHANGE_LIMIT", T: en).prefix(11), "You changed")
    }

    // MARK: get_my_rewards in the three shapes a device can meet (pre-177 server, 177, 179)

    private static let pre177 = """
    {"success":true,"balance":60,"rules":{"onboarding_coins":10,"attendance_coins":20,"attendance_coin_cap_per_month":10,"version":1,"timezone":"Asia/Ho_Chi_Minh"},
     "streak":{"current":3,"longest":5,"active_today":true,"timezone":"Asia/Ho_Chi_Minh","last_active_date":"2026-10-07"},
     "badges":[{"code":"first_outing","title_vi":"a","title_en":"b","desc_vi":"x","desc_en":"y","target":1,"progress":1,"earned":true,"earned_at":"2026-10-07T01:00:00Z"}],
     "history":[{"id":"a","type":"award","amount":20,"reason":"attendance","created_at":"2026-10-07T01:00:00.123456+00:00","event_name":"Jazz","item_code":null}],
     "catalog":[{"code":"rwd-comet","kind":"keychain_design","design_id":"rwd-comet","price":40,"unlocked":false},
                {"code":"rwd-lantern","kind":"keychain_design","design_id":"rwd-lantern","price":80,"unlocked":true}],
     "attendance_paid_this_month":1}
    """
    private static let v177 = """
    {"success":true,"balance":60,"rules":{"version":1,"timezone":"Asia/Ho_Chi_Minh"},"streak":{"current":0,"longest":0,"timezone":"America/Chicago"},
     "badges":[],"history":[],"catalog":[{"code":"rwd-comet","kind":"keychain_design","design_id":"rwd-comet","price":40,"unlocked":false}],
     "attendance_paid_this_month":0,
     "timezone_settings":{"effective_tz":"America/Chicago","chosen":true,"default_tz":"Asia/Ho_Chi_Minh","pending_tz":null,"pending_from":null,"changes_left":1,"next_change_at":null}}
    """
    private static let v179 = """
    {"success":true,"balance":60,"rules":{"version":1,"timezone":"Asia/Ho_Chi_Minh"},"streak":{"current":1,"longest":1,"timezone":"Asia/Ho_Chi_Minh"},
     "badges":[],"history":[],
     "catalog":[{"code":"rwd-comet","kind":"keychain_design","design_id":"rwd-comet","price":40,"unlocked":false,"title_vi":null,"title_en":null,"desc_vi":null,"desc_en":null,"status":"available"}],
     "offers":[{"code":"offer-x","kind":"partner_offer","price":50,"title_vi":"Ưu đãi X","title_en":"Offer X","desc_vi":"mô tả","desc_en":"description","status":"unavailable"}],
     "attendance_paid_this_month":0,
     "timezone_settings":{"effective_tz":"Asia/Ho_Chi_Minh","chosen":false,"default_tz":"Asia/Ho_Chi_Minh","pending_tz":null,"pending_from":null,"changes_left":2,"next_change_at":null}}
    """

    func testAllThreeServerShapesDecode() throws {
        let d = JSONDecoder()
        let a = try d.decode(RewardsPayload.self, from: Data(Self.pre177.utf8))
        XCTAssertEqual(a.catalog.count, 2); XCTAssertNil(a.timezoneSettings); XCTAssertTrue(a.offers.isEmpty)
        XCTAssertFalse(RewardsLogic.showsOffersSection(a))
        let b = try d.decode(RewardsPayload.self, from: Data(Self.v177.utf8))
        XCTAssertEqual(b.timezoneSettings?.effectiveTz, "America/Chicago"); XCTAssertTrue(b.offers.isEmpty)
        XCTAssertFalse(RewardsLogic.showsOffersSection(b))
        let c = try d.decode(RewardsPayload.self, from: Data(Self.v179.utf8))
        XCTAssertEqual(c.catalog.count, 1); XCTAssertEqual(c.catalog[0].status, "available")
        XCTAssertEqual(c.offers.map(\.code), ["offer-x"]); XCTAssertEqual(c.offers[0].titleEn, "Offer X")
        XCTAssertTrue(RewardsLogic.showsOffersSection(c))
    }

    func testOffersEmptyOrFlagOffHidesTheSection() throws {
        let flagOff = Self.v179.replacingOccurrences(of: #""offers":[{"code":"offer-x","kind":"partner_offer","price":50,"title_vi":"Ưu đãi X","title_en":"Offer X","desc_vi":"mô tả","desc_en":"description","status":"unavailable"}],"#, with: #""offers":[],"#)
        XCTAssertTrue(flagOff.contains(#""offers":[]"#))
        XCTAssertFalse(RewardsLogic.showsOffersSection(try JSONDecoder().decode(RewardsPayload.self, from: Data(flagOff.utf8))))
    }

    func testAnOfferThatLeaksIntoCatalogIsDroppedNotFatal() throws {
        let leaky = Self.v179.replacingOccurrences(of: #""catalog":["#, with: #""catalog":[{"code":"offer-x","kind":"partner_offer","price":50,"unlocked":false,"status":"unavailable"},"#)
        let p = try JSONDecoder().decode(RewardsPayload.self, from: Data(leaky.utf8))
        XCTAssertEqual(p.catalog.map(\.code), ["rwd-comet"])   // keychain list never contains the offer, and the payload still decodes
        XCTAssertEqual(p.offers.map(\.code), ["offer-x"])
    }

    func testMalformedOfferRowsAreSkipped() throws {
        let bad = Self.v179.replacingOccurrences(of: #""offers":["#, with: #""offers":[{"nope":1},"#)
        let p = try JSONDecoder().decode(RewardsPayload.self, from: Data(bad.utf8))
        XCTAssertEqual(p.offers.map(\.code), ["offer-x"])
    }
}
