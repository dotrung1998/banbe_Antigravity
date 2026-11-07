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

    /// A10 (alcohol and minimum age) is the same text on both, and only while event types are on.
    func testPolicyAlcoholAgeTextMatchesTheWeb() throws {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let web = try String(contentsOf: url.appendingPathComponent("src/screens/Policy.jsx"), encoding: .utf8)
        let ios = try String(contentsOf: url.appendingPathComponent("apps/ios/BanbeApp/Views/PolicyView.swift"), encoding: .utf8)
        let a10 = try XCTUnwrap(web.range(of: "<Section id=\"A10\"")).lowerBound
        let partB = try XCTUnwrap(web.range(of: "<PartHeading vi=\"Phần B.")).lowerBound
        let re = try NSRegularExpression(pattern: "(?:vi|en)=\"([^\"]+)\"")
        let chunk = String(web[a10..<partB])
        let found = re.matches(in: chunk, range: NSRange(chunk.startIndex..., in: chunk)).map { String(chunk[Range($0.range(at: 1), in: chunk)!]) }
        XCTAssertEqual(found.count, 4, "A10 has 2 bilingual passages")
        for t in found { XCTAssertTrue(ios.contains(t), "missing on iOS: \(t.prefix(60))") }
        XCTAssertFalse(ContentFlags.isOn([:], "event_types"))
        XCTAssertTrue(ContentFlags.isOn(["event_type_profiles": true], "event_types"))
    }

    /// The iOS policy shows exactly the web's rewards passages (generated from src/screens/Policy.jsx).
    func testPolicyRewardsTextMatchesTheWeb() throws {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let web = try String(contentsOf: url.appendingPathComponent("src/screens/Policy.jsx"), encoding: .utf8)
        let ios = try String(contentsOf: url.appendingPathComponent("apps/ios/BanbeApp/Views/PolicyView.swift"), encoding: .utf8)
        let a9 = try XCTUnwrap(web.range(of: "<Section id=\"A9\"")).lowerBound
        let partB = try XCTUnwrap(web.range(of: "<Section id=\"A10\"") ?? web.range(of: "<PartHeading vi=\"Phần B.")).lowerBound
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

    // MARK: Event Project Hub (note 76). Mirrors the project cases in tests/unit/contentFlags.test.mjs.
    private let projectKeys = ["event_project_hub", "project_qr_invite", "project_delegate_checkin", "project_delegate_payments", "project_delegate_refunds"]
    private let hub: [String: Bool] = ["event_project_hub": true]
    private var allProject: [String: Bool] { Dictionary(uniqueKeysWithValues: projectKeys.map { ($0, true) }) }

    func testProjectKeysAreDarkUntilSetAndStepsNeedTheHub() {
        for k in projectKeys {
            XCTAssertFalse(ContentFlags.isOn([:], k), "\(k): missing = off")
            XCTAssertFalse(ContentFlags.isOn([k: false], k))
        }
        XCTAssertTrue(ContentFlags.isOn(hub, "event_project_hub"))
        for k in projectKeys.dropFirst() {
            XCTAssertFalse(ContentFlags.isOn([k: true], k), "\(k) without the hub stays hidden")
            XCTAssertFalse(ContentFlags.isOn(hub, k))
            XCTAssertTrue(ContentFlags.isOn(hub.merging([k: true]) { $1 }, k))
        }
    }

    func testProjectsOffRemovesEveryMention() {
        let en = "(event projects?|event team|Projects I'm in|Finance & door|Lane lead|Day-of|Start a team project|Invite by QR)"
        let vi = "(dự án|Tài chính & cổng|Trưởng hạng mục|Ngày G|đội sự kiện)"
        for flags in [[:], allProject.merging(["event_project_hub": false]) { $1 }] {
            for doc in docs {
                let f = ContentFlags.filter(doc, flags)
                XCTAssertFalse(f.sections.contains { $0.id == "projects" }, doc.en)
                XCTAssertNil(text(f, en: true).range(of: en, options: [.regularExpression, .caseInsensitive]), doc.en)
                XCTAssertNil(text(f, en: false).range(of: vi, options: [.regularExpression, .caseInsensitive]), doc.vi)
            }
        }
    }

    func testProjectStepsShowOnlyWithTheirSwitch() {
        let hubOnly = text(ContentFlags.filter(HelpContent.host, hub), en: true)
        XCTAssertTrue(hubOnly.contains("It is not the same as a co-host on your organizer profile"))
        for absent in ["Invite by QR", "door list", "View transfer proof", "Refunds to send", "Finance can refund alone"] {
            XCTAssertFalse(hubOnly.contains(absent), absent)
        }
        let refunds = text(ContentFlags.filter(HelpContent.host, hub.merging(["project_delegate_refunds": true]) { $1 }), en: true)
        XCTAssertTrue(refunds.contains("Finance can refund alone"))
        XCTAssertFalse(refunds.contains("View transfer proof"))
        let all = text(ContentFlags.filter(HelpContent.faq, allProject), en: true)
        XCTAssertTrue(all.contains("Can the team send refunds without me?"))
        XCTAssertTrue(text(ContentFlags.filter(HelpContent.personal, allProject), en: true).contains("Projects I'm in"))
    }

    /// The iOS policy carries exactly the web's project passages (B3 line, B4 and B7 rows), still unbumped.
    func testPolicyProjectTextMatchesTheWeb() throws {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let web = try String(contentsOf: url.appendingPathComponent("src/screens/Policy.jsx"), encoding: .utf8)
        let ios = try String(contentsOf: url.appendingPathComponent("apps/ios/BanbeApp/Views/PolicyView.swift"), encoding: .utf8)
        let rows = try NSRegularExpression(pattern: "\\{ flag: '(?:event_project_hub|project_[a-z_]+)', cells: \\['((?:[^'\\\\]|\\\\.)*)', '((?:[^'\\\\]|\\\\.)*)'\\] \\}")
        let found = rows.matches(in: web, range: NSRange(web.startIndex..., in: web)).flatMap { m in
            [1, 2].map { String(web[Range(m.range(at: $0), in: web)!]).replacingOccurrences(of: "\\'", with: "'") }
        }
        XCTAssertEqual(found.count, 10, "4 B4 rows + 1 B7 row")
        for t in found { XCTAssertTrue(ios.contains(t), "missing on iOS: \(t.prefix(60))") }
        let b3 = try XCTUnwrap(web.range(of: "{on('event_project_hub') && ("))
        let chunk = String(web[b3.upperBound...].prefix(2000))
        let re = try NSRegularExpression(pattern: "(?:vi|en)=\"([^\"]+)\"")
        let b3Texts = re.matches(in: chunk, range: NSRange(chunk.startIndex..., in: chunk)).prefix(2).map { String(chunk[Range($0.range(at: 1), in: chunk)!]) }
        XCTAssertEqual(b3Texts.count, 2)
        for t in b3Texts { XCTAssertTrue(ios.contains(t), "missing on iOS: \(t.prefix(60))") }
        XCTAssertTrue(ios.contains("DRAFT FOR LEGAL REVIEW"))
        XCTAssertTrue(ios.contains("static let version = \"2026-10-06\""), "not bumped before legal review")
    }
}
