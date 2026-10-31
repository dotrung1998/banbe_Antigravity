import XCTest
@testable import BanbeApp

/// Mirrors tests/unit/homeMode.test.mjs through the shared tests/fixtures/home-mode.json (Simple Shell follow-up,
/// plan item 1): Home shows Hosting only when organizer mode is on AND the session picked Hosting.
final class HomeModeTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("tests/fixtures/home-mode.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func view(_ v: Any?) -> HomeViewMode { HomeViewMode(rawValue: v as? String ?? "") ?? .goer }

    func testEffectiveViewMatchesTheSharedCases() throws {
        for c in try XCTUnwrap(fixture()["effective"] as? [[String: Any]]) {
            let on = try XCTUnwrap(c["organizerMode"] as? Bool)
            XCTAssertEqual(HomeMode.effectiveHomeView(organizerMode: on, homeView: c["homeView"] as? String),
                           c["expect"] as? String, "\(c)")
        }
    }

    func testViewAfterSyncMatchesTheSharedCases() throws {
        for c in try XCTUnwrap(fixture()["afterSync"] as? [[String: Any]]) {
            let got = HomeMode.viewAfterSync(prevOrganizerMode: try XCTUnwrap(c["prevOrganizerMode"] as? Bool),
                                             prevHomeView: view(c["prevHomeView"]),
                                             organizerMode: try XCTUnwrap(c["organizerMode"] as? Bool))
            XCTAssertEqual(got.rawValue, c["expect"] as? String, "\(c)")
        }
    }

    func testLockedSegmentAndStartHostingSteps() throws {
        let fx = try fixture()
        for c in try XCTUnwrap(fx["locked"] as? [[String: Any]]) {
            XCTAssertEqual(HomeMode.hostSegmentLocked(organizerMode: try XCTUnwrap(c["organizerMode"] as? Bool)),
                           c["locked"] as? Bool, "\(c)")
        }
        for c in try XCTUnwrap(fx["startHosting"] as? [[String: Any]]) {
            let step = HomeMode.startHostingStep(signedIn: try XCTUnwrap(c["signedIn"] as? Bool),
                                                 organizerMode: try XCTUnwrap(c["organizerMode"] as? Bool))
            XCTAssertEqual(step.rawValue, c["step"] as? String, "\(c)")
        }
    }

    /// VoiceOver reads the label then the hint; together they are the shared locked label (both languages).
    func testLockedLabelAndHintReadAsTheSharedString() throws {
        let labels = try XCTUnwrap(fixture()["lockedLabel"] as? [String: String])
        for (lang, pick) in [("vi", { (vi: String, _: String) in vi }), ("en", { (_: String, en: String) in en })] {
            let hint = HomeMode.lockedHint(pick)
            let spoken = HomeMode.lockedLabel(pick) + ", " + hint.prefix(1).lowercased() + hint.dropFirst()
            XCTAssertEqual(spoken, labels[lang], lang)
        }
    }

    @MainActor
    func testSignOutResetAndRestoredStateNeverShowsHosting() throws {
        let app = AppState()
        // A restored/deep-linked "host" with organizer mode off still renders Going out.
        app.homeView = .host
        app.organizerMode = false
        XCTAssertEqual(app.effectiveHomeView, .goer)
        // Signed out: never Hosting, whatever the stored view.
        app.organizerMode = true
        app.userID = nil
        XCTAssertEqual(app.effectiveHomeView, .goer)
        let signOut = try XCTUnwrap(fixture()["signOut"] as? [String: String])
        XCTAssertEqual(signOut["homeView"], HomeViewMode.goer.rawValue)
    }
}
