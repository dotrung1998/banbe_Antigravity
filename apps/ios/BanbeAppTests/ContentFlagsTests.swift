import XCTest
@testable import BanbeApp

/// Feature-switched content (note 59). Mirrors tests/unit/contentFlags.test.mjs.
final class ContentFlagsTests: XCTestCase {
    private let off: [String: Bool] = ["rewards": false]
    private let on: [String: Bool] = ["rewards": true]
    private let onV2: [String: Bool] = ["rewards": true, "rewards_v2": true]
    private var docs: [HelpDoc] { [HelpContent.personal, HelpContent.host, HelpContent.admin, HelpContent.faq] }

    /// Everything a reader can see or search: section titles (table of contents) and every block, in one language.
    private func text(_ doc: HelpDoc, en: Bool) -> String {
        func block(_ b: HelpBlock) -> String {
            switch b {
            case .p(let vi, let e), .h(let vi, let e), .tip(let vi, let e): return en ? e : vi
            case .ul(let items), .ol(let items): return items.map { en ? $0[1] : $0[0] }.joined(separator: " ")
            case .q(let qv, let qe, let av, let ae): return en ? "\(qe) \(ae)" : "\(qv) \(av)"
            case .flagged(_, let inner): return block(inner)
            }
        }
        return doc.sections.map { ([en ? $0.en : $0.vi] + $0.blocks.map(block)).joined(separator: " ") }.joined(separator: " ")
    }

    func testContentKeysFollowThePlatformSwitches() {
        XCTAssertFalse(ContentFlags.isOn(off, "rewards"))
        XCTAssertTrue(ContentFlags.isOn(on, "rewards"))
        XCTAssertTrue(ContentFlags.isOn([:], "rewards"), "missing rewards key = on, like the app")
        XCTAssertTrue(ContentFlags.isOn(on, "rewards_daily"))
        XCTAssertFalse(ContentFlags.isOn(on, "rewards_v2"))
        XCTAssertTrue(ContentFlags.isOn(onV2, "rewards_v2"))
        XCTAssertFalse(ContentFlags.isOn(["rewards": false, "rewards_v2": true], "rewards_v2"))
        XCTAssertFalse(ContentFlags.isOn(on, "nope"))
        XCTAssertTrue(ContentFlags.isOn(off, nil))
    }

    func testRewardsOffRemovesEveryMentionFromGuidesTocAndQA() {
        let enPattern = "\\b(rewards?|coins?|streaks?|grace weeks?|monthly goal)\\b"
        let viPattern = "(phần thưởng|(?<!\\p{L})xu(?!\\p{L}| hướng)|chuỗi (ngày|tuần)|tuần nghỉ|mục tiêu tháng)"
        for doc in docs {
            let f = ContentFlags.filter(doc, off)
            XCTAssertFalse(f.sections.contains { $0.id == "rewards" }, doc.en)
            XCTAssertNil(text(f, en: true).range(of: enPattern, options: [.regularExpression, .caseInsensitive]), doc.en)
            XCTAssertNil(text(f, en: false).range(of: viPattern, options: [.regularExpression, .caseInsensitive]), doc.vi)
            for s in f.sections { for b in s.blocks { if case .flagged = b { XCTFail("flagged block left in \(doc.en)") } } }
        }
    }

    func testRewardsOnOrMissingShowsTheSectionsInBothLanguages() {
        for flags in [on, [:]] {
            let personal = ContentFlags.filter(HelpContent.personal, flags)
            XCTAssertTrue(personal.sections.contains { $0.id == "rewards" })
            XCTAssertTrue(text(personal, en: true).contains("A few extra locked designs can be unlocked with coins"))
            XCTAssertTrue(text(personal, en: false).contains("mở bằng xu"))
            let faq = ContentFlags.filter(HelpContent.faq, flags)
            XCTAssertTrue(text(faq, en: true).contains("Do coins expire?"))
            XCTAssertTrue(text(faq, en: false).contains("Xu có hết hạn không?"))
        }
    }

    func testDailyOrWeeklyStreakTextFollowsRewardsV2() {
        let daily = text(ContentFlags.filter(HelpContent.personal, on), en: true)
        XCTAssertTrue(daily.contains("Miss a day and the streak starts again from 0"))
        XCTAssertFalse(daily.contains("grace week"))
        let weekly = text(ContentFlags.filter(HelpContent.personal, onV2), en: true)
        XCTAssertTrue(weekly.contains("Monday to Sunday"))
        XCTAssertTrue(weekly.contains("Badges have tiers"))
        XCTAssertFalse(weekly.contains("Miss a day"))
    }

    /// The iOS policy shows exactly the web's rewards passages (generated from src/screens/Policy.jsx).
    func testPolicyRewardsTextMatchesTheWeb() throws {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let web = try String(contentsOf: url.appendingPathComponent("src/screens/Policy.jsx"), encoding: .utf8)
        let ios = try String(contentsOf: url.appendingPathComponent("apps/ios/BanbeApp/Views/PolicyView.swift"), encoding: .utf8)
        let a9 = try XCTUnwrap(web.range(of: "<Section id=\"A9\"")).lowerBound
        let partB = try XCTUnwrap(web.range(of: "<PartHeading vi=\"Phần B.")).lowerBound
        let re = try NSRegularExpression(pattern: "(?:vi|en)=\"([^\"]+)\"")
        let chunk = String(web[a9..<partB])
        let found = re.matches(in: chunk, range: NSRange(chunk.startIndex..., in: chunk)).map { String(chunk[Range($0.range(at: 1), in: chunk)!]) }
        XCTAssertEqual(found.count, 12, "A9 has 6 bilingual passages")
        for t in found { XCTAssertTrue(ios.contains(t), "missing on iOS: \(t.prefix(60))") }
        for marker in ["Coin ledger (awards, reversals, redemptions)", "Anonymous aggregate counts", "any group smaller than 20 people is hidden",
                       "remembers which badges and milestones have already been celebrated"] {
            XCTAssertTrue(web.contains(marker) && ios.contains(marker), marker)
        }
        XCTAssertTrue(ios.contains("static let version = \"2026-10-06\""), "policy version unchanged (no re-consent)")
    }
}
