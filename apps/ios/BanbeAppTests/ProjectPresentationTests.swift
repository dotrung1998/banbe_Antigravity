import XCTest
@testable import BanbeApp

/// tests/fixtures/project-presentation.json over tests/fixtures/project-snapshot.json (the web twin reads the same
/// files in phase 8). Also proves the snapshot fixture decodes with the app's models.
final class ProjectPresentationTests: XCTestCase {
    private func repo(_ path: String) throws -> Data {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        return try Data(contentsOf: url.appendingPathComponent(path))
    }

    private func snapshot() throws -> ProjectSnapshot {
        struct File: Decodable { let snapshot: ProjectSnapshot }
        return try JSONDecoder().decode(File.self, from: repo("tests/fixtures/project-snapshot.json")).snapshot
    }

    private func id(_ suffix: Any) -> String {
        let s = "\(suffix)"
        if s.hasPrefix("post:") { return String(format: "00000000-0000-4000-8000-0000000004%02d", Int(s.dropFirst(5)) ?? 0) }
        if s.count > 4 { return s }
        return String(format: "00000000-0000-4000-8000-0000000003%02d", Int(s) ?? 0)
    }

    func testSnapshotDecodes() throws {
        let s = try snapshot()
        XCTAssertTrue(s.success)
        XCTAssertEqual(s.lanes?.count, 6)
        XCTAssertEqual(s.tasks?.count, 12)
        XCTAssertEqual(s.members?.count, 5)
        XCTAssertEqual(s.project?.channels.first?.platform, "zalo")
        XCTAssertEqual(s.posts?.first(where: { $0.type == "proposal" })?.options, ["Cá kho", "Nấm kho"])
        XCTAssertEqual(s.changeRequests?.first?.payload.name, "Truyền thông")
        XCTAssertNotNil(ProjectDates.parse(s.project?.readOnlyAt))
        XCTAssertNotNil(ProjectDates.parse("2026-11-03T23:15:54.031691+00:00"), "fractional seconds from Postgres")
    }

    func testSharedVectors() throws {
        let snap = try snapshot()
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: repo("tests/fixtures/project-presentation.json")) as? [String: Any])
        let iso = ISO8601DateFormatter()
        let tasks = snap.tasks ?? []
        let tz = try XCTUnwrap(snap.event).timeZone
        for c in try XCTUnwrap(root["cases"] as? [[String: Any]]) {
            let name = c["case"] as? String ?? "?"
            let now = try XCTUnwrap(iso.date(from: (c["now"] ?? root["now"]) as? String ?? ""))
            let me = c["me"] as? String
            var s = snap
            s.isHost = c["isHost"] as? Bool
            let e = try XCTUnwrap(c["expect"] as? [String: Any])

            let r = try XCTUnwrap(e["readiness"] as? [String: Int])
            XCTAssertEqual(ProjectPresentation.readiness(tasks), .init(done: r["done"]!, total: r["total"]!, percent: r["percent"]!), name)
            XCTAssertEqual(ProjectPresentation.laneProgress(snap.lanes ?? [], tasks).map { [$0.done, $0.total] }, e["lanes"] as? [[Int]], name)
            XCTAssertEqual(ProjectPresentation.myOpenTasks(tasks, me: me).map(\.id), (e["myOpenTasks"] as? [Int] ?? []).map(id), name)
            XCTAssertEqual(ProjectPresentation.attention(tasks, now: now, tz: tz).map(\.id), (e["attention"] as? [Int] ?? []).map(id), name)
            XCTAssertEqual(ProjectPresentation.comingUp(tasks).map(\.id), (e["comingUp"] as? [Int] ?? []).map(id), name)
            XCTAssertEqual(ProjectPresentation.awaiting(s, me: me).map { "\($0.kind.rawValue)|\($0.id)" },
                           (e["awaiting"] as? [[String]] ?? []).map { "\($0[0])|\(id($0[1]))" }, name)
            XCTAssertEqual(ProjectPresentation.decisions(snap.posts ?? []).map(\.id), (e["decisions"] as? [Int] ?? []).map { id("post:\($0)") }, name)
            XCTAssertEqual(ProjectPresentation.daysToGo(snap.event, now: now), e["daysToGo"] as? Int, name)
            for (t, n) in e["dayDeltas"] as? [String: Int] ?? [:] {
                let task = try XCTUnwrap(tasks.first { $0.id == id(t) })
                XCTAssertEqual(ProjectPresentation.dayDelta(task.dueDate, now: now, tz: tz), n, "\(name) task \(t)")
            }
            for (t, label) in e["dueLabels"] as? [String: String] ?? [:] {
                let task = try XCTUnwrap(tasks.first { $0.id == id(t) })
                let want: ProjectPresentation.DueLabel = label == "today" ? .today : label == "tomorrow" ? .tomorrow
                    : label.hasPrefix("late:") ? .late(Int(label.dropFirst(5)) ?? 0) : .date(String(label.dropFirst(5)))
                XCTAssertEqual(ProjectPresentation.dueLabel(task.dueDate, now: now, tz: tz), want, "\(name) task \(t)")
            }
        }
    }
}

extension ProjectPresentationTests {
    /// The DEBUG UI fixture (shell.project) must load the same snapshot, for the Host and re-cast as a member.
    func testUIFixtureSnapshotLoads() throws {
        let host = try XCTUnwrap(UITestFixture.projectSnapshot(), "fixture snapshot")
        XCTAssertEqual(host.isHost, true)
        XCTAssertEqual(host.tasks?.count, 12)
    }
}
