import XCTest
@testable import BanbeApp

/// Migration 216: the admin "Project hub demo" (Lib/ProjectDemo.swift). The gate, the bundled sample, and that the demo
/// keeps everything in memory (no fixture is active here, so `projectOffline` comes from the demo alone).
@MainActor
final class ProjectDemoTests: XCTestCase {

    // MARK: gate

    func testGateNeedsAnAdminAndTheSwitch() {
        XCTAssertTrue(ProjectDemo.available(isAdmin: true, flags: ["project_hub_demo": true]))
        XCTAssertFalse(ProjectDemo.available(isAdmin: true, flags: ["project_hub_demo": false]))
        XCTAssertFalse(ProjectDemo.available(isAdmin: true, flags: [:]), "a missing switch is off")
        XCTAssertFalse(ProjectDemo.available(isAdmin: false, flags: ["project_hub_demo": true]), "admins only")
    }

    func testSwitchIsKnownOffUnlessSetAndGroupedWithTheProjectSwitches() {
        XCTAssertTrue(FeatureFlags.keys.contains("project_hub_demo"))
        XCTAssertTrue(FeatureFlags.offUnlessSet.contains("project_hub_demo"))
        XCTAssertEqual(FeatureFlags.normalize(["project_hub_demo": true]), ["project_hub_demo": true])
        let projects = FeatureFlagCategories.all.first { $0.key == "projects" }
        XCTAssertEqual(projects?.flags.last, "project_hub_demo")
    }

    func testAppStateGateFollowsAccountTypeAndSwitch() {
        let app = AppState()
        app.featureFlags = app.featureFlags.merging(["project_hub_demo": true]) { $1 }
        app.accountType = "participant"
        XCTAssertFalse(app.projectDemoAvailable)
        app.startProjectDemo(as: .host, eventDay: false)
        XCTAssertNil(app.projectDemo, "a non-admin can't open it")
        app.accountType = "admin"
        XCTAssertTrue(app.projectDemoAvailable)
        app.featureFlags = app.featureFlags.merging(["project_hub_demo": false]) { $1 }
        XCTAssertFalse(app.projectDemoAvailable)
    }

    // MARK: sample

    func testBundledSampleCastsTheViewerAsHostOrMember() throws {
        let me = UUID().uuidString
        let host = try XCTUnwrap(ProjectDemo.snapshot(as: nil, me: me))
        XCTAssertEqual(host.isHost, true)
        XCTAssertEqual(host.event?.id, "fx_project")
        XCTAssertFalse((host.tasks ?? []).isEmpty)

        let finance = try XCTUnwrap(ProjectDemo.snapshot(as: "finance", me: me))
        XCTAssertEqual(finance.isHost, false)
        XCTAssertEqual(finance.me?.role, "finance")
        XCTAssertTrue((finance.members ?? []).contains { $0.userId == me.lowercased() })
    }

    // MARK: session

    private func adminInDemo(_ role: ProjectDemo.Role = .host, eventDay: Bool = false) -> AppState {
        let app = AppState()
        // Flags first and without a user, so no switch change starts a load; the project switches are off for real.
        var flags = app.featureFlags
        for key in ProjectDemo.projectFlags { flags[key] = false }
        flags["project_hub_demo"] = true
        app.featureFlags = flags
        app.userID = UUID()
        app.accountType = "admin"
        app.screen = .accountGroup
        app.startProjectDemo(as: role, eventDay: eventDay)
        return app
    }

    func testOpeningTheDemoTurnsTheProjectSwitchesOnInsideOnly() {
        let app = adminInDemo()
        XCTAssertEqual(app.screen, .eventProject)
        XCTAssertNotNil(app.projectSnapshot)
        XCTAssertTrue(app.projectOffline)
        for key in ProjectDemo.projectFlags {
            XCTAssertTrue(FeatureFlags.isOn(app.projectFlags, key), key)
            XCTAssertFalse(FeatureFlags.isOn(app.featureFlags, key), "the real switch stays off: \(key)")
        }
        XCTAssertFalse(app.projectHubEnabled, "outside the hub nothing changes")
    }

    func testEventDayPinsTheClock() {
        XCTAssertEqual(adminInDemo(eventDay: true).projectNow, ProjectDemo.eventDayNow)
        XCTAssertEqual(adminInDemo(eventDay: true).projectTab, "dayof")
        XCTAssertEqual(adminInDemo(eventDay: false).projectNow, ProjectDemo.defaultNow)
    }

    func testWritesChangeOnlyTheSnapshotAndExitForgetsThem() async {
        let app = adminInDemo()
        let lane = app.projectSnapshot?.lanes?.first?.id ?? ""
        let before = app.projectSnapshot?.tasks?.count ?? 0
        let ok = await app.saveProjectTask(taskID: nil, laneID: lane, title: "Demo task", assigneeID: nil, dueDate: nil, status: nil)
        XCTAssertTrue(ok)
        XCTAssertEqual(app.projectSnapshot?.tasks?.count, before + 1)
        // Writes without their own sample path still never leave the device.
        let renamed = await app.renameProjectLane(lane, "Renamed")
        XCTAssertTrue(renamed)
        XCTAssertEqual(app.projectSnapshot?.lanes?.first?.name, "Renamed")
        _ = await app.createProjectInvite(role: "helper", laneID: nil)
        XCTAssertEqual(ProjectDemo.inviteCount, 1)

        app.endProjectDemo()
        XCTAssertNil(app.projectDemo)
        XCTAssertNil(app.projectSnapshot)
        XCTAssertTrue(app.projectInvites.isEmpty)
        XCTAssertEqual(ProjectDemo.inviteCount, 0)
        XCTAssertEqual(app.screen, .accountGroup, "Exit returns where the demo was opened")
        XCTAssertFalse(app.projectOffline)
    }

    func testLinksOutAreBlockedOnlyInTheDemo() {
        let app = adminInDemo(.finance)
        XCTAssertTrue(app.projectDemoBlocksLink())
        XCTAssertFalse(app.projectNotice.isEmpty)
        app.endProjectDemo()
        XCTAssertFalse(app.projectDemoBlocksLink())
    }

    func testLeavingTheHubAnyWayEndsTheDemo() {
        let app = adminInDemo(.helper)
        app.screen = .home
        XCTAssertNil(app.projectDemo)
        XCTAssertNil(app.projectSnapshot)

        let back = adminInDemo()
        back.backFromProject()
        XCTAssertNil(back.projectDemo)
        XCTAssertEqual(back.screen, .accountGroup)
    }
}
