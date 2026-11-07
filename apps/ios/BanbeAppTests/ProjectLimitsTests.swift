import XCTest
@testable import BanbeApp

/// The bundled src/data/projectLimits.json is the repo file (one source for web, iOS and the server's numbers).
final class ProjectLimitsTests: XCTestCase {
    func testBundledLimitsMatchTheRepoFileAndTheFallback() throws {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("src/data/projectLimits.json"))
        let repo = try JSONDecoder().decode(ProjectLimits.self, from: data)
        XCTAssertNotNil(Bundle.main.url(forResource: "projectLimits", withExtension: "json"), "run xcodegen generate")
        XCTAssertEqual(ProjectLimits.shared, repo)
        XCTAssertEqual(ProjectLimits.fallback, repo)
    }
}
