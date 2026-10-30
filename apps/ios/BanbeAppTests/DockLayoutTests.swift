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

    func testScrubSkipsTheCreateSlot() {
        XCTAssertNil(DockLayout.tab(atSlot: 2, simpleShell: true))
        XCTAssertEqual(DockLayout.tab(atSlot: 1, simpleShell: true), "schedule")
        XCTAssertEqual(DockLayout.tab(atSlot: 3, simpleShell: true), "inbox")
        XCTAssertEqual(DockLayout.tab(atSlot: 2, simpleShell: false), "schedule")
        XCTAssertNil(DockLayout.tab(atSlot: 5, simpleShell: true))
        XCTAssertNil(DockLayout.tab(atSlot: -1, simpleShell: false))
    }
}
