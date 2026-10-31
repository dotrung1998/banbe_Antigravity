import XCTest
@testable import BanbeApp

/// Simple Shell dock order (note 66): OFF must stay exactly today's dock.
final class DockLayoutTests: XCTestCase {
    func testOffIsTodaysFiveTabs() {
        XCTAssertEqual(DockLayout.dockOrder(simpleShell: false), [.home, .mapExplore, .schedule, .inbox, .profile])
        XCTAssertEqual(DockLayout.dockOrder(simpleShell: false), BottomTabBar.dockOrder)
        XCTAssertEqual(DockLayout.slots(simpleShell: false), ["home", "map", "schedule", "inbox", "profile"])
        XCTAssertFalse(DockLayout.slots(simpleShell: false).contains(DockLayout.createSlot))
    }

    func testOnDropsMapAndPutsCreateInTheCentre() {
        XCTAssertEqual(DockLayout.dockOrder(simpleShell: true), [.home, .schedule, .inbox, .profile])
        let slots = DockLayout.slots(simpleShell: true)
        XCTAssertEqual(slots, ["home", "schedule", "create", "inbox", "profile"])
        XCTAssertEqual(slots[slots.count / 2], DockLayout.createSlot)
        XCTAssertFalse(slots.contains("map"))
    }

    func testMapHighlightsHomeOnlyWhenOn() {
        XCTAssertEqual(DockLayout.highlight(for: .mapExplore, simpleShell: true), "home")
        XCTAssertEqual(DockLayout.highlight(for: .mapExplore, simpleShell: false), "map")
        for on in [false, true] {
            XCTAssertEqual(DockLayout.highlight(for: .home, simpleShell: on), "home")
            XCTAssertEqual(DockLayout.highlight(for: .schedule, simpleShell: on), "schedule")
            XCTAssertEqual(DockLayout.highlight(for: .inbox, simpleShell: on), "inbox")
            XCTAssertEqual(DockLayout.highlight(for: .profile, simpleShell: on), "profile")
            XCTAssertNil(DockLayout.highlight(for: .event, simpleShell: on))
        }
    }

    private func scrubFixture() throws -> [String: Any] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("tests/fixtures/dock-scrub.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// The fixture names tabs by screen (web); the iOS slot id for Map is "map".
    private func expected(_ e: [String: Any]) -> DockLayout.ScrubTarget? {
        switch e["kind"] as? String {
        case "create": return .create
        case "tab":
            let id = e["id"] as? String ?? ""
            return .tab(id == "mapExplore" ? "map" : id)
        default: return nil
        }
    }

    /// Plan item 3, shared with tests/unit/dockLayout.test.mjs: every slot boundary and the centre slot.
    func testScrubTargetMatchesTheSharedFixture() throws {
        let fx = try scrubFixture()
        for (key, on) in [("simpleShell", true), ("legacy", false)] {
            for c in try XCTUnwrap(fx[key] as? [[String: Any]]) {
                let f = try XCTUnwrap(c["fraction"] as? Double)
                XCTAssertEqual(DockLayout.scrubTarget(fraction: f, simpleShell: on),
                               expected(try XCTUnwrap(c["expect"] as? [String: Any])), "\(key) \(f)")
            }
        }
        // A drag's result is where it is released; crossing the "+" on the way never matters.
        for d in try XCTUnwrap(fx["drags"] as? [[String: Any]]) {
            let path = try XCTUnwrap(d["path"] as? [Double])
            let on = d["simpleShell"] as? Bool ?? true
            XCTAssertEqual(DockLayout.scrubTarget(fraction: try XCTUnwrap(path.last), simpleShell: on),
                           expected(try XCTUnwrap(d["release"] as? [String: Any])), "\(path)")
        }
    }

    func testScrubTargetOverTheCentreIsCreateOnlyWhenOn() {
        XCTAssertEqual(DockLayout.scrubTarget(fraction: 0.5, simpleShell: true), .create)
        XCTAssertEqual(DockLayout.scrubTarget(fraction: 0.5, simpleShell: false), .tab("schedule"))
        XCTAssertEqual(DockLayout.scrubTarget(fraction: .nan, simpleShell: true), .tab("home"))
    }

    /// The "+" is never a selected tab (a release over it opens its menu instead, see scrubTarget).
    func testCreateSlotIsNeverATab() {
        XCTAssertNil(DockLayout.tab(atSlot: 2, simpleShell: true))
        XCTAssertEqual(DockLayout.tab(atSlot: 1, simpleShell: true), "schedule")
        XCTAssertEqual(DockLayout.tab(atSlot: 3, simpleShell: true), "inbox")
        XCTAssertEqual(DockLayout.tab(atSlot: 2, simpleShell: false), "schedule")
        XCTAssertNil(DockLayout.tab(atSlot: 5, simpleShell: true))
        XCTAssertNil(DockLayout.tab(atSlot: -1, simpleShell: false))
    }
}
