import XCTest
import SwiftUI
@testable import BanbeApp

/// Mirrors tests/unit/profileCard.test.mjs through the shared tests/fixtures/profile-card.json (note 68) — change both
/// together.
final class ProfileCardTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("tests/fixtures/profile-card.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func hex(_ c: Color) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    func testPalettesAndSurfaceMatchFixture() throws {
        let fx = try fixture()
        let palettes = try XCTUnwrap(fx["palettes"] as? [String: String])
        for p in ProfilePalette.all { XCTAssertEqual(hex(p.color), palettes[p.key], p.key) }
        XCTAssertEqual(ProfileCard.tint, fx["tint"] as? Double)
        XCTAssertEqual(ProfileCard.glow, fx["glow"] as? Double)
    }

    func testRoleLabel() throws {
        for c in try XCTUnwrap(fixture()["roleLabel"] as? [[String: Any]]) {
            let i = try XCTUnwrap(c["in"] as? [String: Any])
            let name = i["organizerName"] as? String, mode = i["organizerMode"] as? Bool ?? false
            XCTAssertEqual(ProfileCard.roleLabel(organizerName: name, organizerMode: mode, vi: false), c["en"] as? String)
            XCTAssertEqual(ProfileCard.roleLabel(organizerName: name, organizerMode: mode, vi: true), c["vi"] as? String)
        }
    }

    func testDedupeChips() throws {
        for c in try XCTUnwrap(fixture()["dedupeChips"] as? [[String: Any]]) {
            let out = ProfileCard.dedupeChips(c["chips"] as? [String] ?? [], alreadyShown: c["shown"] as? [String] ?? [])
            XCTAssertEqual(out, c["out"] as? [String], c["name"] as? String ?? "")
        }
    }

    func testStats() throws {
        for c in try XCTUnwrap(fixture()["profileStats"] as? [[String: Any]]) {
            let i = try XCTUnwrap(c["in"] as? [String: Any])
            let org = i["organizer"] as? [String: Any]
            let isHost = org != nil && (i["organizerMode"] as? Bool ?? false)
            let out = ProfileCard.stats(eventCount: org?["event_count"] as? Int, followerCount: org?["follower_count"] as? Int,
                                        hostingSinceYear: org?["hosting_since_year"] as? Int, isHost: isHost,
                                        isOwner: i["isOwner"] as? Bool ?? false, rewardsOn: i["rewardsOn"] as? Bool ?? false,
                                        badgeCount: i["badgeCount"] as? Int, upcomingCount: i["upcomingCount"] as? Int)
            let want = try XCTUnwrap(c["out"] as? [[Any]]).map { ProfileCard.Stat(id: $0[0] as? String ?? "", value: $0[1] as? Int ?? -1) }
            XCTAssertEqual(out, want, c["name"] as? String ?? "")
        }
    }

    func testUpcoming() throws {
        let up = try XCTUnwrap(fixture()["upcoming"] as? [String: Any])
        let events = try XCTUnwrap(up["events"] as? [[String: Any]]).map {
            ProfileCard.UpcomingInput(key: $0["key"] as? String ?? "", name: $0["name"] as? String ?? "", organizerId: $0["organizerId"] as? String,
                                      start: ($0["start"] as? NSNumber)?.doubleValue, ended: $0["ended"] as? Bool ?? false, cancelled: $0["cancelled"] as? Bool ?? false)
        }
        for c in try XCTUnwrap(up["cases"] as? [[String: Any]]) {
            let i = try XCTUnwrap(c["in"] as? [String: Any])
            let out = ProfileCard.upcoming(events, organizerId: i["organizerId"] as? String, organizerMode: i["organizerMode"] as? Bool ?? false,
                                           isOwner: i["isOwner"] as? Bool ?? false, goingKeys: i["goingKeys"] as? [String] ?? [])
            let want = try XCTUnwrap(c["out"] as? [[String]])
            XCTAssertEqual(out.map { [$0.event.key, $0.role] }, want, c["name"] as? String ?? "")
        }
    }
}
