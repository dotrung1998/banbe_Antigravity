import XCTest
@testable import BanbeApp

/// Mirrors tests/unit/rosLayout.test.mjs through the shared tests/fixtures/ros-layout.json.
final class RosLayoutTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("tests/fixtures/ros-layout.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func ms(_ iso: Any?) throws -> Int {
        let f = ISO8601DateFormatter()
        let d = try XCTUnwrap(f.date(from: try XCTUnwrap(iso as? String)), "\(iso ?? "nil")")
        return Int((d.timeIntervalSince1970 * 1000).rounded())
    }

    private func input(_ c: [String: Any], base: [[String: Any]]) throws -> [RosLayout.Item] {
        var rows = (c["items"] as? [[String: Any]]) ?? base
        if let order = c["shuffle"] as? [String] { rows = order.compactMap { id in rows.first { $0["id"] as? String == id } } }
        let done = c["done"] as? [String: String] ?? [:]
        return try rows.map { r in
            let id = try XCTUnwrap(r["id"] as? String)
            let doneISO = done[id] ?? r["doneAt"] as? String
            return RosLayout.Item(id: id, startsAt: try ms(r["startsAt"]), endsAt: try ms(r["endsAt"]),
                                  doneAt: try doneISO.map { try ms($0) })
        }
    }

    func testSharedVectors() throws {
        let fx = try fixture()
        let base = try XCTUnwrap(fx["base"] as? [[String: Any]])
        for c in try XCTUnwrap(fx["cases"] as? [[String: Any]]) {
            let name = c["case"] as? String ?? "?"
            let r = RosLayout.layout(try input(c, base: base), now: try ms(c["now"]))
            let e = try XCTUnwrap(c["expect"] as? [String: Any])
            let items = try XCTUnwrap(e["items"] as? [[String: Any]])
            XCTAssertEqual(r.items.count, items.count, name)
            for (got, want) in zip(r.items, items) {
                XCTAssertEqual(got.id, want["id"] as? String, name)
                XCTAssertEqual(got.start, try ms(want["start"]), "\(name) \(got.id) start")
                XCTAssertEqual(got.end, try ms(want["end"]), "\(name) \(got.id) end")
                XCTAssertEqual(got.overrunMin, want["overrunMin"] as? Int, "\(name) \(got.id) overrun")
                XCTAssertEqual(got.squeezedMin, want["squeezedMin"] as? Int, "\(name) \(got.id) squeezed")
                XCTAssertEqual(got.overlap, want["overlap"] as? Bool, "\(name) \(got.id) overlap")
                XCTAssertEqual(got.active, want["active"] as? Bool, "\(name) \(got.id) active")
            }
            let chips = try XCTUnwrap(e["chips"] as? [[String: Any]])
            XCTAssertEqual(r.chips.map { "\($0.id):\($0.kind.rawValue):\($0.minutes)" },
                           chips.map { "\($0["id"] ?? ""):\($0["kind"] ?? ""):\($0["minutes"] ?? "")" }, name)
            if let axis = e["axis"] as? [String: Any] {
                XCTAssertEqual(r.axis, RosLayout.Axis(start: try ms(axis["start"]), end: try ms(axis["end"])), name)
            } else {
                XCTAssertNil(r.axis, name)
            }
        }
    }

    func testDerivedFlagsFollowThePrototype() throws {
        let fx = try fixture()
        let base = try XCTUnwrap(fx["base"] as? [[String: Any]])
        for c in try XCTUnwrap(fx["cases"] as? [[String: Any]]) {
            for l in RosLayout.layout(try input(c, base: base), now: try ms(c["now"])).items {
                XCTAssertEqual(l.overrun, !l.done && l.overrunMin > 0)
                XCTAssertEqual(l.squeezed, l.squeezedMin > 0 && !l.overlap)
                XCTAssertGreaterThanOrEqual(l.end - l.start, 10 * 60_000)
                XCTAssertGreaterThanOrEqual(l.squeezedMin, 0)
            }
        }
    }
}
