import XCTest
@testable import BanbeApp

/// Mirrors tests/unit/createProgress.test.mjs through the shared tests/fixtures/create-progress.json.
final class CreateProgressTests: XCTestCase {
    private func cases() throws -> [[String: Any]] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("tests/fixtures/create-progress.json"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(root["cases"] as? [[String: Any]])
    }

    func testSharedVectors() throws {
        for c in try cases() {
            let name = c["case"] as? String ?? "?"
            let missing = Dictionary(uniqueKeysWithValues: (c["missing"] as? [String] ?? []).map { ($0, true) })
            let p = CreateProgress.compute(missing: missing, required: c["required"] as? [String] ?? CreateProgress.defaultRequired)
            let e = try XCTUnwrap(c["expect"] as? [String: Any])
            XCTAssertEqual(p.steps.map(\.done), e["done"] as? [Bool], name)
            XCTAssertEqual(p.percent, e["percent"] as? Int, name)
            XCTAssertEqual(p.stepsLeft, e["stepsLeft"] as? Int, name)
            XCTAssertEqual(p.firstMissing, e["firstMissing"] as? String, name)
            XCTAssertEqual(p.missing, e["missing"] as? [String], name)
            // Ring, steps left and Still needed come from one result.
            XCTAssertEqual(p.stepsLeft, p.steps.filter { !$0.done }.count, name)
            XCTAssertEqual(p.steps.flatMap(\.missing), p.missing, name)
        }
    }

    func testEveryFieldHasAStepAndALabel() {
        for id in CreateProgress.fieldOrder {
            XCTAssertNotNil(CreateFieldGuide.step(of: id), id)
            XCTAssertNotEqual(CreateProgress.label(id, minPhotos: 4) { vi, _ in vi }, id, id)
        }
    }
}
