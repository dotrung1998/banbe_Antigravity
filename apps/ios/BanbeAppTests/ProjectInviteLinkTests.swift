import XCTest
@testable import BanbeApp

/// Mirrors tests/unit/projectInviteLink.test.mjs through the shared tests/fixtures/project-invite-links.json.
final class ProjectInviteLinkTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("tests/fixtures/project-invite-links.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testParse() throws {
        for c in try XCTUnwrap(fixture()["parse"] as? [[String: Any]]) {
            let input = c["in"] as? String ?? ""
            var want: ProjectInviteLink.Invite?
            if let e = c["expect"] as? [String: Any] {
                want = e["kind"] as? String == "token" ? .token(e["token"] as? String ?? "") : .code(e["code"] as? String ?? "")
            }
            XCTAssertEqual(ProjectInviteLink.parse(input), want, input)
        }
    }

    func testAlphabet() {
        let a = ProjectInviteLink.codeAlphabet
        XCTAssertEqual(a.count, 31)
        XCTAssertEqual(Set(a).count, 31)
        for ch in "0O1IL" { XCTAssertFalse(a.contains(ch), String(ch)) }
    }

    func testJoinURL() throws {
        let j = try XCTUnwrap(fixture()["joinUrl"] as? [String: String])
        let token = try XCTUnwrap(j["token"])
        XCTAssertEqual(ProjectInviteLink.joinURL(token: token), j["url"])
        XCTAssertEqual(ProjectInviteLink.parse(try XCTUnwrap(ProjectInviteLink.joinURL(token: token))), .token(token))
        XCTAssertNil(ProjectInviteLink.joinURL(token: "BB-H3QD"))
    }
}
