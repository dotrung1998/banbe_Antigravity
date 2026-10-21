import XCTest
@testable import BanbeApp

/// Create-event Public preview: the draft must render through the real Event Detail like a published event would.
final class CatalogEventDraftTests: XCTestCase {
    private func draft(price: Int = 100_000, seats: Int? = 10, start: Date? = Date(timeIntervalSince1970: 1_800_000_000)) -> EventDraft {
        EventDraft(name: "Test", catKey: "supper", catLabel: "Supper club", area: "Khánh Hội",
                   lat: 10.76, lng: 106.70, startsAt: start, priceVnd: price, seats: seats,
                   description: "Desc", intro: "", includedItems: [IncludedItem(label: "Tui", detail: ""), IncludedItem(label: "", detail: "x")],
                   inviteOnly: false, organizerName: "Visit Test")
    }

    func testDraftShapesLikeARealEvent() {
        let e = CatalogEvent.fromDraft(draft())
        XCTAssertEqual(e.key, CatalogEvent.draftPreviewKey)
        XCTAssertEqual(e.price, EventLabels.vnd(100_000))
        XCTAssertEqual(e.seatsLong, "10 chỗ trống")
        XCTAssertEqual(e.includedItems, [IncludedItem(label: "Tui", detail: "")], "blank labels dropped")
        XCTAssertNil(e.intro, "empty intro is no intro (no empty About sheet)")
        XCTAssertTrue(e.isOpen)
        XCTAssertFalse(e.soldOut)
        XCTAssertEqual(e.orgName, "Visit Test")
        XCTAssertNotNil(e.mapsURL)
    }

    func testDraftWhereHasNoDistance() {
        let e = CatalogEvent.fromDraft(draft())
        XCTAssertFalse(e.where.contains(" km"), "a draft never shows a distance (was '9665,7 km away')")
        XCTAssertTrue(e.where.hasPrefix("Khánh Hội"))
        XCTAssertFalse(e.when.isEmpty)
    }

    func testFreeAndUnscheduledDraft() {
        let e = CatalogEvent.fromDraft(draft(price: 0, seats: nil, start: nil))
        XCTAssertTrue(e.isFree)
        XCTAssertEqual(e.seatsLong, "")
        XCTAssertEqual(e.when, "")
        XCTAssertEqual(e.where, "Khánh Hội")
    }
}
