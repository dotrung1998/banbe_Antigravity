import XCTest
@testable import BanbeApp

/// Event Project Hub phase 4 (note 76): the Team tab's "Who can do what" table never promises more (or less) than the
/// permission rules, and invite links, typed codes and project notifications land where they should.
@MainActor
final class ProjectTeamTopicsTests: XCTestCase {
    private let host = "00000000-0000-4000-8000-0000000000a1"
    private let me = "00000000-0000-4000-8000-0000000000b2"
    private let ownLane = "lane-own"
    private let otherLane = "lane-other"

    private func context(_ column: String, caps: Bool = false, flags: [String: Bool] = [:], target: ProjectPermissions.Target) -> ProjectPermissions.Context {
        let all = ["event_project_hub": true].merging(flags) { $1 }
        if column == "host" {
            return .init(userId: host, organizer: .init(ownerId: host, userId: nil), flags: all, target: target)
        }
        let member = ProjectPermissions.Member(role: column, laneId: column == "lane_lead" ? ownLane : nil, capMoney: caps, capCheckin: caps)
        return .init(userId: me, member: member, organizer: .init(ownerId: host, userId: nil), flags: all, target: target)
    }

    private func target(_ probe: ProjectRoleMatrix.Probe, lane: String?, column: String) -> ProjectPermissions.Target {
        let uid = column == "host" ? host : me
        switch probe {
        case .plain: return .init()
        case .laneScoped: return .init(laneId: lane)
        case .ownTask: return .init(laneId: lane, assigneeId: uid)
        case .ownQuietPost: return .init(laneId: lane, authorId: uid, type: "question", state: "open", quiet: true)
        case .roleHelper: return .init(role: "helper")
        }
    }

    func testEveryMatrixCellMatchesThePermissionRules() {
        let delegation = ["project_delegate_checkin": true, "project_delegate_payments": true, "project_delegate_refunds": true]
        for row in ProjectRoleMatrix.rows {
            XCTAssertEqual(row.cells.count, ProjectRoleMatrix.columns.count, row.id)
            guard let action = row.action else { continue }
            for (column, cell) in zip(ProjectRoleMatrix.columns, row.cells) {
                let name = "\(row.id) / \(column)"
                func can(lane: String?, caps: Bool = false, flags: [String: Bool] = [:]) -> Bool {
                    ProjectPermissions.can(action, context(column, caps: caps, flags: flags, target: target(row.probe, lane: lane, column: column)))
                }
                switch cell {
                case .yes:
                    // Money and door cells read "once banbe turns delegation on" (the table's footnote; see the next test).
                    XCTAssertTrue(can(lane: ownLane, flags: delegation), name); XCTAssertTrue(can(lane: otherLane, flags: delegation), name)
                case .no:
                    XCTAssertFalse(can(lane: ownLane, flags: delegation), name); XCTAssertFalse(can(lane: otherLane, flags: delegation), name)
                case .lane:
                    XCTAssertTrue(can(lane: ownLane), name); XCTAssertFalse(can(lane: otherLane), name)
                case .grant:
                    XCTAssertFalse(can(lane: nil, flags: delegation), "\(name) without the access")
                    XCTAssertTrue(can(lane: nil, caps: true, flags: delegation), "\(name) once the Host grants it")
                case .propose:
                    XCTAssertFalse(can(lane: nil), name)
                    XCTAssertTrue(ProjectPermissions.can("change.propose", context(column, target: .init())), "\(name) proposes")
                }
            }
        }
    }

    func testFinanceMoneyCellsNeedTheDelegationSwitches() {
        // The table shows Finance with money and check-in; the rules only allow it once banbe turns delegation on.
        for action in ["money.confirm", "checkin"] {
            XCTAssertFalse(ProjectPermissions.can(action, context("finance", target: .init())), "\(action) with the switches off")
        }
    }

    func testInviteLinksAndCodesOpenTheJoinScreen() {
        let app = AppState()
        defer { UserDefaults.standard.removeObject(forKey: AppState.pendingProjectInviteKey) }
        app.screen = .home
        app.handleDeepLink(URL(string: "banbe://join/BB-7K2Q")!)
        XCTAssertEqual(app.screen, .projectJoin)
        XCTAssertEqual(app.projectJoinCode, "BB-7K2Q")
        XCTAssertEqual(app.projectJoinBack, .home)

        app.screen = .profile
        app.handleUniversalLink(URL(string: "https://www.banbe.app/join/Fx7kQ2mN9pR4sT6vW8yZ1a")!)
        XCTAssertEqual(app.screen, .projectJoin)
        XCTAssertEqual(app.projectJoinCode, "Fx7kQ2mN9pR4sT6vW8yZ1a", "the token is kept as-is")

        app.openProjectJoin("bb h3qd", back: .myProjects)
        XCTAssertEqual(app.projectJoinCode, "BB-H3QD", "a typed code is normalised")
        app.goBack()
        XCTAssertEqual(app.screen, .myProjects)
    }

    func testAPastedOrScannedLinkBecomesTheBareValueTheServerTakes() {
        XCTAssertEqual(AppState.projectInviteValue("https://www.banbe.app/join/bb-h3qd?src=qr"), "BB-H3QD")
        XCTAssertEqual(AppState.projectInviteValue("banbe://join/Fx7kQ2mN9pR4sT6vW8yZ1a"), "Fx7kQ2mN9pR4sT6vW8yZ1a")
        XCTAssertEqual(AppState.projectInviteValue(" bb h3qd "), "BB-H3QD")
        XCTAssertNil(AppState.projectInviteValue("https://evil.example/join/BB-H3QD"))
    }

    func testSignedOutJoinParksTheCodeUntilSignIn() {
        let app = AppState()
        UserDefaults.standard.removeObject(forKey: AppState.pendingProjectInviteKey)
        defer { UserDefaults.standard.removeObject(forKey: AppState.pendingProjectInviteKey) }
        app.userID = nil
        app.openProjectJoin("https://banbe.app/join/BB-7K2Q", back: .home)
        XCTAssertEqual(UserDefaults.standard.string(forKey: AppState.pendingProjectInviteKey), "BB-7K2Q")
        XCTAssertTrue(AppState.guestAllowedScreens.contains(.projectJoin), "a guest sees the join screen, not a bounce to Login")
        XCTAssertNil(app.projectJoinPeek, "nothing is looked up without an account")
    }

    func testProjectNotificationForAProjectImNotInStaysOnTheBell() async {
        let app = AppState()
        app.screen = .notifications
        let n = AppNotification(id: UUID(), recipientId: UUID(), kind: "project_blocked", title: "", body: "",
                                data: ["screen": .string("event_project"), "event_id": .string("not-mine")], readAt: nil, createdAt: Date())
        app.openProjectFromNotification(n)
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(app.screen, .notifications)
    }
}
