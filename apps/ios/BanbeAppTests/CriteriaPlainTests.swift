import XCTest
@testable import BanbeApp

/// Mirrors tests/unit/criteriaPlain.test.mjs through the shared tests/fixtures/criteria-plain.json (note 70) — change
/// both together.
final class CriteriaPlainTests: XCTestCase {
    func testPlainMatchesFixture() throws {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("tests/fixtures/criteria-plain.json"))
        let fx = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for c in try XCTUnwrap(fx["cases"] as? [[String: Any]]) {
            let name = c["name"] as? String ?? ""
            let raw = try JSONSerialization.data(withJSONObject: try XCTUnwrap(c["criteria"]))
            let criteria = try JSONDecoder().decode(ReservationCriteria.self, from: raw)
            XCTAssertEqual(criteria.plain(vi: false), c["en"] as? String, name)
            XCTAssertEqual(criteria.plain(vi: true), c["vi"] as? String, name)
            for out in [criteria.plain(vi: false), criteria.plain(vi: true)].compactMap({ $0 }) {
                XCTAssertNil(out.range(of: "Any of|All of|Interests:|Một trong|▪", options: .regularExpression), name)
            }
        }
    }
}
