import XCTest
@testable import BanbeApp

/// Mirrors tests/unit/createFieldGuide.test.mjs (note 53) — change both together.
final class CreateFieldGuideTests: XCTestCase {
    typealias G = CreateFieldGuide

    func testEveryRecipeIngredientPointsAtAKnownFieldOnItsStep() {
        let checks = EventRecipe.checks(EventRecipe.Draft(), benchmarks: nil, goal: nil, now: Date())
        XCTAssertGreaterThanOrEqual(checks.count, 9)
        for c in checks {
            XCTAssertNotNil(G.step(of: c.fix.field), "\(c.id) -> \(c.fix.field) has no anchor")
            XCTAssertEqual(G.step(of: c.fix.field), c.fix.step, "\(c.id): field \(c.fix.field) is on another step")
        }
    }

    func testSteps() {
        XCTAssertEqual(G.step(of: "hostName"), 0)
        XCTAssertEqual(G.step(of: "intro"), 1)
        XCTAssertEqual(G.step(of: "location"), 2)
        XCTAssertEqual(G.step(of: "seats"), 3)
        XCTAssertEqual(G.step(of: "photos"), 4)
        XCTAssertNil(G.step(of: "nope"))
    }

    func testOnlyTypingFieldsGetFocus() {
        for f in ["hostName", "name", "description", "intro", "greeting", "keywords", "location", "price"] { XCTAssertTrue(G.isTextField(f), f) }
        for f in ["categories", "included", "date", "seats", "photos"] { XCTAssertFalse(G.isTextField(f), f) }
    }

    func testFirstMissingFollowsOnScreenOrder() {
        XCTAssertNil(G.firstMissing([:]))
        XCTAssertEqual(G.firstMissing(["photos": true, "name": true]), "name")
        XCTAssertEqual(G.firstMissing(["seats": true, "location": true]), "location")
        XCTAssertEqual(G.firstMissing(["hostName": true, "description": true]), "hostName")
        XCTAssertEqual(G.firstMissing(["included": false, "date": true]), "date")
        // Same order as the ring: price and the type facts count too (was a stale list without them).
        XCTAssertEqual(G.firstMissing(["price": true, "seats": true]), "price")
        XCTAssertEqual(G.firstMissing(["alcohol": true, "location": true]), "alcohol")
    }

    func testAnchor() {
        XCTAssertEqual(G.anchor("intro"), "create.field.intro")
    }
}
