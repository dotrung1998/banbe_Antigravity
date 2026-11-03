import XCTest
@testable import BanbeApp

/// Mirrors tests/unit/projectChannels.test.mjs through the shared tests/fixtures/project-channel-links.json.
final class ProjectChannelsTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("tests/fixtures/project-channel-links.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func raw(_ d: [String: Any]) -> (platform: String?, label: String?, url: String?, primary: Bool) {
        (d["platform"] as? String, d["label"] as? String, d["url"] as? String, d["primary"] as? Bool == true)
    }

    func testPlatformDetection() throws {
        for c in try XCTUnwrap(fixture()["detect"] as? [[String: Any]]) {
            let url = c["url"] as? String ?? ""
            XCTAssertEqual(ProjectChannels.detectPlatform(url), c["platform"] as? String, url)
        }
    }

    func testChannels() throws {
        for c in try XCTUnwrap(fixture()["channels"] as? [[String: Any]]) {
            let name = c["case"] as? String ?? "?"
            let r = raw(try XCTUnwrap(c["in"] as? [String: Any]))
            switch ProjectChannels.validate(platform: r.platform, label: r.label, url: r.url, primary: r.primary) {
            case .success(let ch):
                XCTAssertEqual(c["ok"] as? Bool, true, name)
                let out = try XCTUnwrap(c["out"] as? [String: Any], name)
                XCTAssertEqual(ch, ProjectChannels.Channel(platform: out["platform"] as? String ?? "", label: out["label"] as? String ?? "",
                                                           url: out["url"] as? String ?? "", primary: out["primary"] as? Bool ?? false), name)
            case .failure(let f):
                XCTAssertEqual(c["ok"] as? Bool, false, name)
                XCTAssertEqual(f.rawValue, c["error"] as? String, name)
            }
        }
    }

    func testLists() throws {
        for c in try XCTUnwrap(fixture()["lists"] as? [[String: Any]]) {
            let name = c["case"] as? String ?? "?"
            // The JS-only "not a list" vector is a type error Swift's API cannot express.
            guard let list = c["in"] as? [[String: Any]] else { XCTAssertEqual(c["error"] as? String, "list", name); continue }
            switch ProjectChannels.sanitize(list.map(raw)) {
            case .success: XCTAssertEqual(c["ok"] as? Bool, true, name)
            case .failure(let f):
                XCTAssertEqual(c["ok"] as? Bool, false, name)
                XCTAssertEqual(f.error.rawValue, c["error"] as? String, name)
                if let i = c["index"] as? Int { XCTAssertEqual(f.index, i, name) }
            }
        }
    }

    func testEveryNamedPlatformExistsAndOnlyLinkIsUnnamed() {
        let ids = ProjectChannels.platforms.map(\.id)
        XCTAssertEqual(Set(ProjectChannels.names.keys), Set(ids).subtracting(["link"]))
    }

    func testStarredChannelFirst() {
        let a = ProjectChannels.Channel(platform: "link", label: "a", url: "https://a.org", primary: false)
        let b = ProjectChannels.Channel(platform: "link", label: "b", url: "https://b.org", primary: true)
        let c = ProjectChannels.Channel(platform: "link", label: "c", url: "https://c.org", primary: false)
        XCTAssertEqual(ProjectChannels.ordered([a, b, c]).map(\.label), ["b", "a", "c"])
    }
}
