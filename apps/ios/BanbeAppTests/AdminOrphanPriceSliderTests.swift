import XCTest
@testable import BanbeApp

/// 2026-10-21: orphaned events in Admin > Manage events, and the create-event price slider maths.
/// Mirrors tests/unit/adminEvents.test.mjs and tests/unit/eventRecipe.test.mjs.
final class AdminOrphanPriceSliderTests: XCTestCase {
    func testOrphanRule() {
        func orphan(_ id: String?, found: Bool = true, account: Bool = true, name: String? = "Bếp Nhỏ") -> Bool {
            AdminManagedEvents.isOrphan(organizerId: id, organizerFound: found, organizerHasAccount: account, organizerName: name)
        }
        XCTAssertFalse(orphan("o1"))
        XCTAssertTrue(orphan(nil), "organizer row deleted")
        XCTAssertTrue(orphan("o1", found: false), "organizer missing")
        XCTAssertTrue(orphan("o1", account: false), "no owner and no user")
        XCTAssertTrue(orphan("o1", name: AdminManagedEvents.deletedOrganizerName), "anonymized by the cleanup")
    }

    func testPaging() {
        XCTAssertTrue(AdminManagedEvents.needsAnotherPage(lastPageCount: 500, totalSoFar: 500))
        XCTAssertFalse(AdminManagedEvents.needsAnotherPage(lastPageCount: 499, totalSoFar: 999))
        XCTAssertFalse(AdminManagedEvents.needsAnotherPage(lastPageCount: 500, totalSoFar: 5000), "hard cap")
    }

    func testFixtureOrphansAreFlagged() {
        let orphans = UITestFixture.adminManagedEvents.filter(\.isOrphan).map(\.id)
        XCTAssertEqual(Set(orphans), ["fx-ev-orphan-refund", "fx-ev-orphan-draft"])
    }

    func testPriceSliderMaths() {
        let p = HostBenchmarks.Price(n: 5, p25: 300_000, median: 400_000, p75: 500_000, min: 250_000, max: 600_000, histogram: [1, 2])
        XCTAssertEqual(EventRecipe.priceToFraction(250_000, p), 0)
        XCTAssertEqual(EventRecipe.priceToFraction(600_000, p), 1)
        XCTAssertEqual(EventRecipe.priceToFraction(100_000, p), 0, "below the market pins to the left edge")
        XCTAssertEqual(EventRecipe.fractionToPrice(0.5, p), 430_000)
        XCTAssertEqual(EventRecipe.fractionToPrice(0, p), 250_000)
        XCTAssertEqual(EventRecipe.fractionToPrice(1, p), 600_000)
        XCTAssertEqual(EventRecipe.fractionToPrice(0.123, p) % 10_000, 0)
        let narrow = HostBenchmarks.Price(n: 1, p25: nil, median: nil, p75: nil, min: 251_000, max: 259_000, histogram: nil)
        XCTAssertEqual(EventRecipe.fractionToPrice(0.5, narrow), 255_000)
        let flat = HostBenchmarks.Price(n: 1, p25: nil, median: nil, p75: nil, min: 100_000, max: 100_000, histogram: nil)
        XCTAssertEqual(EventRecipe.priceToFraction(5, flat), 0.5)
    }
}
