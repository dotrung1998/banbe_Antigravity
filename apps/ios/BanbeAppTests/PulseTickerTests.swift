import XCTest
@testable import BanbeApp

/// Mirrors tests/unit/pulseTicker.test.mjs — change both together.
final class PulseTickerTests: XCTestCase {
    private func row(_ id: String, _ name: String) -> PulseItem {
        let json = """
        {"event_id":"\(id)","event_name":"\(name)","organizer_id":"o","organizer_name":"Host","organizer_verified":false,"score":1}
        """
        return try! JSONDecoder().decode(PulseItem.self, from: Data(json.utf8))
    }

    func testKeepsServerOrderNumbersFromOneAndCaps() {
        let items = PulseTicker.items(from: (0..<8).map { row("e\($0)", "Event \($0)") })
        XCTAssertEqual(items.count, PulseTicker.maxItems)
        XCTAssertEqual(items.map(\.rank), [1, 2, 3, 4, 5])
        XCTAssertEqual(items.map(\.name), ["Event 0", "Event 1", "Event 2", "Event 3", "Event 4"])
    }

    func testSkipsBlankNamesAndTrims() {
        let items = PulseTicker.items(from: [row("a", "  Supper club  "), row("b", ""), row("c", "   "), row("e", "Jazz")])
        XCTAssertEqual(items.map(\.id), ["a", "e"])
        XCTAssertEqual(items.map(\.rank), [1, 2])
        XCTAssertEqual(items.map(\.name), ["Supper club", "Jazz"])
    }

    func testEmptyInputGivesNoItems() {
        XCTAssertEqual(PulseTicker.items(from: []), [])
    }

    func testSpeedIsProportionalWithAFloor() {
        let short = PulseTicker.items(from: [row("a", "Jazz")])
        XCTAssertEqual(PulseTicker.seconds(for: short), 14)
        let long = PulseTicker.items(from: (0..<5).map { row("e\($0)", String(repeating: "x", count: 40)) })
        // 5 * (40 + 4) = 220 chars * 0.26 = 57.2 -> 57
        XCTAssertEqual(PulseTicker.seconds(for: long), 57)
        XCTAssertGreaterThan(PulseTicker.seconds(for: long), PulseTicker.seconds(for: short))
        XCTAssertEqual(PulseTicker.seconds(for: []), 14)
    }
}
