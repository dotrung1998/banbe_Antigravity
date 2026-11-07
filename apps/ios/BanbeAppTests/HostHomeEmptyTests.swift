import XCTest
@testable import BanbeApp

/// Mirrors tests/unit/hostHomeEmpty.test.mjs through the shared tests/fixtures/host-home-empty.json (Calm Pass pilot):
/// Hosting Home never ends in blank space, and the numbers heading names the real range.
final class HostHomeEmptyTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("tests/fixtures/host-home-empty.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testComingUpMatchesTheSharedCases() throws {
        for c in try XCTUnwrap(fixture()["comingUp"] as? [[String: Any]]) {
            let i = try XCTUnwrap(c["in"] as? [String: Any])
            let got = HostHomeEmpty.comingUp(upcoming: try XCTUnwrap(i["upcoming"] as? Int),
                                             hasHero: try XCTUnwrap(i["hasHero"] as? Bool),
                                             pending: try XCTUnwrap(i["pending"] as? Int),
                                             needsFix: try XCTUnwrap(i["needsFix"] as? Int))
            XCTAssertEqual(got?.rawValue, c["expect"] as? String, "\(c["name"] ?? "")")
        }
    }

    func testKpiStateMatchesTheSharedCases() throws {
        for c in try XCTUnwrap(fixture()["kpis"] as? [[String: Any]]) {
            let i = try XCTUnwrap(c["in"] as? [String: Any])
            let got = HostHomeEmpty.kpiState(hasOrganizer: try XCTUnwrap(i["hasOrganizer"] as? Bool),
                                             loading: try XCTUnwrap(i["loading"] as? Bool),
                                             error: try XCTUnwrap(i["error"] as? Bool),
                                             tiles: try XCTUnwrap(i["tiles"] as? Int),
                                             hasReport: try XCTUnwrap(i["hasReport"] as? Bool))
            XCTAssertEqual(got.rawValue, c["expect"] as? String, "\(c["name"] ?? "")")
        }
    }

    func testRangeHeadingMatchesTheSharedCases() throws {
        let ranges: [String: ReportsRangeDays] = ["7": .days7, "30": .days30, "90": .days90, "custom": .custom]
        for c in try XCTUnwrap(fixture()["rangeHeading"] as? [[String: Any]]) {
            let r = try XCTUnwrap(ranges[try XCTUnwrap(c["range"] as? String)])
            XCTAssertEqual(HostHomeEmpty.rangeHeading(r) { _, en in en }, c["en"] as? String)
            XCTAssertEqual(HostHomeEmpty.rangeHeading(r) { vi, _ in vi }, c["vi"] as? String)
        }
    }

    // MARK: Phase 0 regression: Hosting Home's numbers were thrown away (scope "host" vs reportsScope "personal") and
    // `reportsLoading` stayed true, so "This month" never loaded on iOS.

    func testScopeMismatchIsNotTreatedAsSupersededSoLoadingClears() {
        XCTAssertEqual(AppState.kpiResultDisposition(requestID: 3, currentSeq: 3, scope: "host", currentScope: "personal"), .scopeChanged)
        XCTAssertEqual(AppState.kpiResultDisposition(requestID: 2, currentSeq: 3, scope: "host", currentScope: "host"), .superseded)
        XCTAssertEqual(AppState.kpiResultDisposition(requestID: 3, currentSeq: 3, scope: "host", currentScope: "host"), .apply)
    }

    @MainActor
    func testHostHomeCommitsTheHostScopeBeforeFetching() {
        let app = AppState()
        XCTAssertEqual(app.reportsScope, "personal")
        app.prepareHostHomeKpis(organizerID: "org-1")
        XCTAssertEqual(app.reportsScope, "host")
        XCTAssertEqual(app.reportsOrganizerId, "org-1")
        XCTAssertEqual(AppState.kpiResultDisposition(requestID: 1, currentSeq: 1, scope: "host", currentScope: app.reportsScope), .apply)
    }
}
