import XCTest
@testable import BanbeApp

/// Regression test for the refund-discoverability investigation (point 3):
/// `RefundClaim`'s custom `init(from:)` used to hardcode `eventName = ""`/
/// `eventKey = nil` unconditionally instead of decoding
/// get_host_refund_claims()'s own `event_name`/`event_id` fields — every
/// host-queue/Refund-Center row showed a blank event name regardless of
/// what the RPC actually returned. Covers both a populated payload and one
/// with `event_name`/`event_id`/`guest_name` null (the defensive-null
/// handling this struct exists for in the first place, per its own
/// 2026-10-01 doc comment).
final class RefundClaimDecodeTests: XCTestCase {
    private func decodeClaim(_ json: String) throws -> RefundClaim {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RefundClaim.self, from: Data(json.utf8))
    }

    func testDecodesEventNameAndKeyWhenPresent() throws {
        let claim = try decodeClaim("""
        {
          "id": "28b7e32f-9fc5-4d9e-bf2f-7457c219817b",
          "amount_vnd": 900000,
          "reason": "guest_cancelled",
          "status": "owed",
          "guest_name": "Test Admin",
          "event_name": "Test sự kiện",
          "event_id": "test-s-ki-n-8444c8"
        }
        """)
        XCTAssertEqual(claim.eventName, "Test sự kiện")
        XCTAssertEqual(claim.eventKey, "test-s-ki-n-8444c8")
        XCTAssertEqual(claim.guestName, "Test Admin")
        XCTAssertEqual(claim.amountVnd, 900000)
    }

    func testDefensiveNullsNeverThrowAndFallBackSafely() throws {
        let claim = try decodeClaim("""
        {
          "id": "4a520684-2fcd-496d-abcd-dd3247a840a7",
          "amount_vnd": 80000,
          "reason": "guest_cancelled",
          "status": "owed",
          "guest_name": null,
          "event_name": null,
          "event_id": null
        }
        """)
        XCTAssertEqual(claim.eventName, "")
        XCTAssertNil(claim.eventKey)
        XCTAssertEqual(claim.guestName, "")
    }

    func testMissingFieldsEntirelyAlsoDecodeSafely() throws {
        // A row shape with none of event_name/event_id/guest_name present
        // at all (key absent, not just null) — the same "one malformed row
        // must never throw for the whole batch" guarantee this struct's
        // custom decoder exists for.
        let claim = try decodeClaim("""
        {
          "id": "00000000-0000-0000-0000-000000000000",
          "amount_vnd": 0,
          "reason": "guest_cancelled",
          "status": "owed"
        }
        """)
        XCTAssertEqual(claim.eventName, "")
        XCTAssertNil(claim.eventKey)
        XCTAssertEqual(claim.guestName, "")
    }
}
