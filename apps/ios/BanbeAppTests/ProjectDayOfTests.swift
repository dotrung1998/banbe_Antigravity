import XCTest
@testable import BanbeApp

/// Event Project Hub phase 5 (note 76): when live sync runs, and how the demo run-of-show lays out on the event day.
@MainActor
final class ProjectDayOfTests: XCTestCase {
    private func snapshot() throws -> ProjectSnapshot {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("tests/fixtures/project-snapshot.json"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let snap = try JSONSerialization.data(withJSONObject: try XCTUnwrap(root["snapshot"]))
        return try JSONDecoder().decode(ProjectSnapshot.self, from: snap)
    }

    private let iso = ISO8601DateFormatter()

    func testLiveSyncOnlyOnTheEventDayOnDayOfWithTheAppInFront() throws {
        let app = AppState()
        app.projectSnapshot = try snapshot()
        app.screen = .eventProject
        app.projectTab = "dayof"
        // projectNow is the real clock in unit tests, so the event-day check is asserted through the presentation rule.
        let eventDay = try XCTUnwrap(iso.date(from: "2026-11-14T08:00:00+07:00"))
        let dayBefore = try XCTUnwrap(iso.date(from: "2026-11-13T23:59:00+07:00"))
        let event = try XCTUnwrap(app.projectSnapshot?.event)
        XCTAssertEqual(ProjectPresentation.daysToGo(event, now: eventDay), 0)
        XCTAssertEqual(ProjectPresentation.daysToGo(event, now: dayBefore), 1, "the day is counted in the event's zone")
        XCTAssertFalse(app.projectLiveSyncOn(scenePhaseActive: false), "never in the background")
        app.projectTab = "tasks"
        XCTAssertFalse(app.projectLiveSyncOn(scenePhaseActive: true), "only on Day-of")
        app.projectTab = "dayof"
        app.screen = .home
        XCTAssertFalse(app.projectLiveSyncOn(scenePhaseActive: true), "only while the hub is open")
    }

    func testTheDemoDayStretchesTheFirstItemAndSqueezesTheNext() throws {
        let ros = try XCTUnwrap(snapshot().ros)
        let now = try XCTUnwrap(iso.date(from: "2026-11-14T18:10:00+07:00"))   // 11:10Z; item 501 was planned to end 10:30Z
        let placed = ProjectRosGrid.placed(ros, now: now)
        let first = try XCTUnwrap(placed["00000000-0000-4000-8000-000000000501"])
        XCTAssertTrue(first.overrun)
        XCTAssertEqual(first.overrunMin, 40)
        let second = try XCTUnwrap(placed["00000000-0000-4000-8000-000000000502"])
        XCTAssertTrue(second.squeezed)
        XCTAssertEqual(second.squeezedMin, 40)
        let third = try XCTUnwrap(placed["00000000-0000-4000-8000-000000000503"])
        XCTAssertEqual(third.squeezedMin, 0, "later items keep their planned times")
    }
}
