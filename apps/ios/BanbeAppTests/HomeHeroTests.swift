import XCTest
@testable import BanbeApp

/// Mirrors tests/unit/homeHero.test.mjs through the shared tests/fixtures/home-hero.json (note 66).
final class HomeHeroTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("tests/fixtures/home-hero.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testGoerPriority() throws {
        for c in try XCTUnwrap(fixture()["goer"] as? [[String: Any]]) {
            let i = try XCTUnwrap(c["input"] as? [String: Any])
            let got = HomeHero.goer(signedIn: i["signedIn"] as? Bool ?? false, hasNextUp: i["nextUp"] as? Bool ?? false,
                                    actionCount: i["actionCount"] as? Int ?? 0, checklistVisible: i["checklistVisible"] as? Bool ?? false)
            XCTAssertEqual(got.rawValue, c["expect"] as? String, "\(c["case"] ?? "")")
        }
    }

    func testHostNextEvent() throws {
        let fx = try fixture()
        let now = Date(timeIntervalSince1970: (fx["now"] as! Double) / 1000)
        for c in try XCTUnwrap(fx["host"] as? [[String: Any]]) {
            let events = (c["events"] as? [[String: Any]] ?? []).map { e in
                HomeHero.HostedEvent(key: e["key"] as! String,
                                     startsAt: Date(timeIntervalSince1970: (e["startsAt"] as! Double) / 1000),
                                     endsAt: (e["endsAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) },
                                     status: e["status"] as? String ?? "live")
            }
            XCTAssertEqual(HomeHero.host(events, now: now)?.key, c["expect"] as? String, "\(c["case"] ?? "")")
        }
    }
}
