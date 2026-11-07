import XCTest
@testable import BanbeApp

/// Mirrors tests/unit/projectPermissions.test.mjs through the shared tests/fixtures/project-permissions.json: every row,
/// every actor, under BOTH Host definitions.
final class ProjectPermissionsTests: XCTestCase {
    private let iso = ISO8601DateFormatter()

    private func fixture() throws -> [String: Any] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("tests/fixtures/project-permissions.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func date(_ v: Any?) throws -> Date { try XCTUnwrap(iso.date(from: try XCTUnwrap(v as? String)), "\(v ?? "nil")") }

    func testSharedVectorsUnderBothHostDefinitions() throws {
        let fx = try fixture()
        let actors = try XCTUnwrap(fx["actors"] as? [String: [String: Any]])
        let orgJ = try XCTUnwrap(fx["organizer"] as? [String: String])
        let organizer = ProjectPermissions.Organizer(ownerId: orgJ["ownerId"], userId: orgJ["userId"])
        let defaults = try XCTUnwrap(fx["defaults"] as? [String: Any])
        let hosts = ["owner_account", "second_account"]
        let all = hosts + actors.keys.filter { (actors[$0]?["member"] as? [String: Any])?["status"] as? String == "active" }
        func expand(_ list: [String]) -> Set<String> {
            Set(list.flatMap { $0 == "@hosts" ? hosts : $0 == "@all" ? all : [$0] })
        }

        for def in [ProjectPermissions.HostDefinition.either, .ownerOnly] {
            for row in try XCTUnwrap(fx["rows"] as? [[String: Any]]) {
                let name = "[\(def.rawValue)] \(row["case"] ?? "?")"
                let action = try XCTUnwrap(row["action"] as? String)
                let allow = expand(row["allow"] as? [String] ?? [])
                let allowed: Set<String> = def == .either ? allow
                    : (row["allowOwnerOnly"] as? [String]).map(expand) ?? allow.subtracting(["second_account"])
                let flags = (row["flags"] ?? defaults["flags"]) as? [String: Bool] ?? [:]
                let project = (row["project"] ?? defaults["project"]) as? [String: Any] ?? [:]
                let t = row["target"] as? [String: Any] ?? [:]
                let target = ProjectPermissions.Target(
                    laneId: t["laneId"] as? String, assigneeId: t["assigneeId"] as? String, authorId: t["authorId"] as? String,
                    addresseeId: t["addresseeId"] as? String, createdBy: t["createdBy"] as? String, type: t["type"] as? String,
                    state: t["state"] as? String, quiet: t["quiet"] as? Bool, role: t["role"] as? String,
                    awaitingVerification: t["awaitingVerification"] as? Bool, refundClaimId: t["refundClaimId"] as? String)
                let grants = try (row["disputeGrants"] as? [[String: Any]] ?? []).map {
                    ProjectPermissions.DisputeGrant(userId: $0["userId"] as? String ?? "", refundClaimId: $0["refundClaimId"] as? String ?? "",
                                                    until: try date($0["until"]), disputeOpen: $0["disputeOpen"] as? Bool ?? false)
                }
                for (key, a) in actors {
                    var member: ProjectPermissions.Member?
                    if let m = a["member"] as? [String: Any] {
                        let caps = m["caps"] as? [String: Bool] ?? [:]
                        member = ProjectPermissions.Member(role: m["role"] as? String ?? "", laneId: m["laneId"] as? String,
                                                           capMoney: caps["money"] ?? false, capCheckin: caps["checkin"] ?? false,
                                                           status: m["status"] as? String ?? "", grantExpiresAt: try date(defaults["grantExpiresAt"]))
                    }
                    let ctx = ProjectPermissions.Context(
                        userId: a["userId"] as? String, member: member, organizer: organizer, hostDefinition: def, flags: flags,
                        now: try date(row["now"] ?? defaults["now"]), readOnlyAt: try project["readOnlyAt"].map { try date($0) },
                        refundApproval: project["refundApproval"] as? String ?? "host", target: target, disputeGrants: grants)
                    XCTAssertEqual(ProjectPermissions.can(action, ctx), allowed.contains(key), "\(name): \(key) → \(action)")
                }
            }
        }
    }

    func testEveryActionIsCovered() throws {
        let covered = Set(try XCTUnwrap(fixture()["rows"] as? [[String: Any]]).compactMap { $0["action"] as? String })
        for a in ProjectPermissions.actions { XCTAssertTrue(covered.contains(a), a) }
    }

    func testActionListMatchesWeb() throws {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let js = try String(contentsOf: url.appendingPathComponent("src/lib/projectPermissions.js"), encoding: .utf8)
        let block = try XCTUnwrap(js.range(of: "export const PROJECT_ACTIONS = [").flatMap { start in
            js.range(of: "];", range: start.upperBound..<js.endIndex).map { js[start.upperBound..<$0.lowerBound] }
        })
        let webActions = block.split(separator: "'").enumerated().filter { $0.offset % 2 == 1 }.map { String($0.element) }
        XCTAssertEqual(webActions, ProjectPermissions.actions)
    }

    func testHostDefinitions() {
        let org = ProjectPermissions.Organizer(ownerId: "u_owner", userId: "u_second")
        XCTAssertTrue(ProjectPermissions.projectIsHost("u_second", org))
        XCTAssertFalse(ProjectPermissions.projectIsHost("u_second", org, .ownerOnly))
        XCTAssertTrue(ProjectPermissions.projectIsHost("u_owner", org, .ownerOnly))
        XCTAssertFalse(ProjectPermissions.projectIsHost(nil, org))
        // The money/door check is the existing RPCs' and does not follow the Host definition.
        XCTAssertTrue(ProjectPermissions.organizerAccount("u_second", org))
    }

    func testFinanceAlwaysHoldsBothCapabilities() {
        XCTAssertTrue(ProjectPermissions.caps(.init(role: "finance")) == (true, true))
        XCTAssertTrue(ProjectPermissions.caps(.init(role: "helper", capCheckin: true)) == (false, true))
        XCTAssertTrue(ProjectPermissions.caps(nil) == (false, false))
    }
}
