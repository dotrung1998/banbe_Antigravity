import XCTest
@testable import BanbeApp

/// Note 69: Basics and Tickets parts, and which part a "take me there" lands on.
final class CreateSubStepsTests: XCTestCase {
    func testOnlyBasicsAndTicketsHaveParts() {
        XCTAssertEqual(CreateSubSteps.parts(step: 1).map(\.id), ["name", "story", "greeting", "categories", "details"])
        XCTAssertEqual(CreateSubSteps.parts(step: 3).map(\.id), ["price", "seats", "privacy", "criteria"])
        for step in [0, 2, 4] { XCTAssertTrue(CreateSubSteps.parts(step: step).isEmpty) }
    }

    func testEveryBasicsAndTicketsFieldHasAPart() {
        for (field, step) in CreateFieldGuide.fieldStep where step == 1 || step == 3 {
            XCTAssertNotNil(CreateSubSteps.index(of: field, step: step), field)
        }
        XCTAssertEqual(CreateSubSteps.index(of: "intro", step: 1), 1)
        XCTAssertEqual(CreateSubSteps.index(of: "lineup", step: 1), 4, "type facts live in Details")
        XCTAssertEqual(CreateSubSteps.index(of: "alcohol", step: 1), 4)
        XCTAssertEqual(CreateSubSteps.index(of: "seats", step: 3), 1)
        XCTAssertNil(CreateSubSteps.index(of: "location", step: 2))
    }

    func testDoneNeedsNothingMissingAndAVisit() {
        let done = CreateSubSteps.done(step: 1, missing: ["description", "alcohol"], visited: [0, 1, 2])
        XCTAssertEqual(done, [true, false, true, false, false])
        XCTAssertEqual(CreateSubSteps.done(step: 3, missing: [], visited: []), [false, false, false, false])
    }
}
