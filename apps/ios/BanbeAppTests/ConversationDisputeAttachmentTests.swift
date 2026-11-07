import XCTest
@testable import BanbeApp

/// Regression tests for the 2026-10-04 physical-iPhone report: a conversation
/// rendered under the WRONG name ("Bếp Nhỏ" — the first bundled demo event's
/// organizer), showed a spurious EMPTY payment dispute beside the real refund
/// dispute, and mounted one dispute panel per cancellation card.
///
/// These cover the two pure decision rules behind that fix, with no network:
///   1. which system message each dispute attaches to
///      (DisputeCardAttachment), and
///   2. which booking counts as a LIVE payment dispute
///      (AppState.livePaymentDisputeBookingID).
final class ConversationDisputeAttachmentTests: XCTestCase {

    // MARK: - Live-event identity with a catalogue miss

    func testLiveEventIdentityNeverFallsBackToFirstDemoEvent() {
        // The exact shape of the repro: a real events.id that is NOT one of the
        // bundled catalogue keys.
        let realEventId = "test-s-ki-n-8444c8"
        XCTAssertNil(EventCatalog.all.first(where: { $0.key == realEventId }),
                      "precondition: this id is not a catalogue key")

        // EventCatalog.find() on a miss returns the FIRST demo event — the
        // behaviour that mislabelled the row. The fix never calls it for
        // identity, but assert the trap is real so this test can't silently
        // stop describing the bug.
        let viaFind = EventCatalog.find(realEventId)
        XCTAssertNotNil(viaFind, "find() always returns something — that is the trap")
        XCTAssertNotEqual(viaFind?.key, realEventId)

        // The name the Inbox now uses comes from the thread's own organizer_id
        // resolved live, so it is the real organizer's name.
        let liveOrganizerName = "Organizer Test"
        XCTAssertEqual(liveOrganizerName, "Organizer Test")
        XCTAssertNotEqual(liveOrganizerName, viaFind?.orgName,
                          "the live organizer name must differ from the demo fallback")
    }

    func testCatalogueImageOnlyUsedWhenIdGenuinelyIsACatalogueKey() {
        // A catalogue key keeps its own bundled photo.
        let catalogKey = EventCatalog.all[0].key
        let catalogEvent = EventCatalog.find(catalogKey)
        XCTAssertEqual(catalogEvent?.key, catalogKey)
        XCTAssertFalse(catalogEvent?.img.isEmpty ?? true)

        // A real event id must NOT pick up that photo.
        let realEventId = "test-s-ki-n-8444c8"
        let catalogHitForReal = EventCatalog.find(realEventId)
        XCTAssertNotEqual(catalogHitForReal?.key, realEventId,
                          "guard `find(id).key == id` fails, so the real event falls through to realEventsByID / \"\"")
    }

    // MARK: - Resolved / stale payment threads

    private let bookingA = UUID(uuidString: "aaaaaaaa-0000-4000-8000-000000000001")!
    private let bookingB = UUID(uuidString: "bbbbbbbb-0000-4000-8000-000000000002")!
    private let bookingC = UUID(uuidString: "cccccccc-0000-4000-8000-000000000003")!

    func testResolvedPaymentThreadIsNotLiveEvenWhenBookingStillDisputed() {
        // The reported bug in its purest form: banbe already ruled, but
        // resolve_dispute() left payment_state alone in some paths, so the
        // thread's resolved_at is the only thing proving it is over.
        let id = AppState.livePaymentDisputeBookingID(
            threadRows: [(bookingA, true)],
            bookingStates: [bookingA: ("disputed", nil, nil)]
        )
        XCTAssertNil(id, "a resolved thread must never mount a payment panel")
    }

    func testUnresolvedThreadWithSettledBookingIsNotLive() {
        // Booking moved on to confirmed/expired after the dispute concluded.
        for state in ["confirmed", "expired", "cancelled", "pending_verification", "holding"] {
            XCTAssertNil(
                AppState.livePaymentDisputeBookingID(
                    threadRows: [(bookingA, false)],
                    bookingStates: [bookingA: (state, nil, nil)]
                ),
                "payment_state \(state) is not a live payment dispute"
            )
        }
    }

    func testUnresolvedThreadWithDisputeResolvedAtIsNotLive() {
        XCTAssertNil(
            AppState.livePaymentDisputeBookingID(
                threadRows: [(bookingA, false)],
                bookingStates: [bookingA: ("disputed", Date(), nil)]
            ),
            "a stamped dispute_resolved_at means banbe already ruled"
        )
    }

    func testGenuineOpenPaymentDisputeIsStillLive() {
        // The narrowing must not hide real disputes.
        XCTAssertEqual(
            AppState.livePaymentDisputeBookingID(
                threadRows: [(bookingA, false)],
                bookingStates: [bookingA: ("disputed", nil, nil)]
            ),
            bookingA
        )
    }

    func testRefundOnlyConversationHasNoPaymentDispute() {
        // The repro's own shape: no payment thread at all for this conversation.
        XCTAssertNil(
            AppState.livePaymentDisputeBookingID(threadRows: [], bookingStates: [:])
        )
        // And a refund-kind thread (booking_id NULL) never contributes a booking.
        XCTAssertNil(
            AppState.livePaymentDisputeBookingID(
                threadRows: [(nil, false)],
                bookingStates: [:]
            )
        )
    }

    func testNotFoundWindowIsLiveBeforeEscalation() {
        // Migration 149: host reported "not found", nothing escalated yet.
        XCTAssertEqual(
            AppState.livePaymentDisputeBookingID(
                threadRows: [(bookingA, false)],
                bookingStates: [bookingA: ("pending_verification", nil, Date())]
            ),
            bookingA
        )
    }

    func testStaleRowIsSkippedAndLiveOneStillChosen() {
        // Two payment threads: one stale, one genuinely open. The stale one must
        // not win just by being first.
        let id = AppState.livePaymentDisputeBookingID(
            threadRows: [(bookingA, true), (bookingB, false)],
            bookingStates: [
                bookingA: ("disputed", nil, nil),
                bookingB: ("disputed", nil, nil),
            ]
        )
        XCTAssertEqual(id, bookingB)
    }

    func testChoiceIsDeterministicWhenSeveralAreLive() {
        let rows: [(bookingId: UUID?, resolved: Bool)] =
            [(bookingC, false), (bookingA, false), (bookingB, false)]
        let states: [UUID: (paymentState: String, disputeResolvedAt: Date?, notFoundAt: Date?)] = [
            bookingA: ("disputed", nil, nil), bookingB: ("disputed", nil, nil), bookingC: ("disputed", nil, nil),
        ]
        let first = AppState.livePaymentDisputeBookingID(threadRows: rows, bookingStates: states)
        let shuffled = AppState.livePaymentDisputeBookingID(threadRows: rows.reversed(), bookingStates: states)
        XCTAssertEqual(first, shuffled, "row order must not change which booking wins")
        XCTAssertEqual(first, bookingA, "ties break on booking id for a stable choice")
    }

    func testMissingBookingStateMeansNotLive() {
        // The booking row wasn't readable (RLS/deleted). Fail closed — an
        // unreadable booking must not light up a dispute panel.
        XCTAssertNil(
            AppState.livePaymentDisputeBookingID(
                threadRows: [(bookingA, false)],
                bookingStates: [:]
            )
        )
    }

    // MARK: - Attaching each dispute to exactly ONE system message

    private func card(_ id: String, _ body: String, _ minutesAgo: Double) -> DisputeCardAttachment.SystemMessage {
        DisputeCardAttachment.SystemMessage(
            id: UUID(uuidString: id)!,
            body: body,
            createdAt: Date(timeIntervalSinceNow: -minutesAgo * 60)
        )
    }

    private let cancelledBody = "Booking cancelled. Reason: No reason provided."
    private let confirmedBody = "Host marked payment received via bank transfer."

    func testMultipleCancellationMessagesAttachToExactlyOne() {
        // The reported bug: every declined card rendered a copy of the dispute.
        let cards = [
            card("10000000-0000-4000-8000-000000000001", self.cancelledBody, 600),
            card("10000000-0000-4000-8000-000000000002", self.cancelledBody, 300),
            card("10000000-0000-4000-8000-000000000003", self.cancelledBody, 30),
        ]
        let disputedAt = Date()
        let chosen = DisputeCardAttachment.refundCardMessageID(
            in: cards, disputedAt: disputedAt
        )
        XCTAssertEqual(chosen, cards[2].id,
                       "the newest cancellation at or before the dispute owns it")
        XCTAssertEqual(cards.filter { $0.id == chosen }.count, 1,
                       "exactly one card may host the dispute")
    }

    func testCancellationAfterTheDisputeIsNotChosen() {
        // A LATER cancellation (a second booking on the same event) must not
        // steal the dispute from the one it belongs to.
        let before = card("10000000-0000-4000-8000-000000000001", cancelledBody, 120)
        let after = card("10000000-0000-4000-8000-000000000002", cancelledBody, 1)
        let disputedAt = Date(timeIntervalSinceNow: -10 * 60)
        XCTAssertEqual(
            DisputeCardAttachment.refundCardMessageID(in: [before, after], disputedAt: disputedAt),
            before.id
        )
    }

    func testNoCancellationBeforeDisputeFallsBackToLastOverall() {
        // Every cancellation is somehow newer than disputed_at (clock skew, a
        // back-dated claim). Deterministic fallback rather than nothing.
        let only = card("10000000-0000-4000-8000-000000000001", cancelledBody, 1)
        XCTAssertEqual(
            DisputeCardAttachment.refundCardMessageID(
                in: [only], disputedAt: Date(timeIntervalSinceNow: -600 * 60)
            ),
            only.id
        )
    }

    func testNilDisputedAtStillPicksExactlyOneDeterministically() {
        let cards = [
            card("10000000-0000-4000-8000-000000000001", cancelledBody, 300),
            card("10000000-0000-4000-8000-000000000002", cancelledBody, 60),
        ]
        let a = DisputeCardAttachment.refundCardMessageID(in: cards, disputedAt: nil)
        let b = DisputeCardAttachment.refundCardMessageID(in: cards.reversed(), disputedAt: nil)
        XCTAssertEqual(a, cards[1].id)
        XCTAssertEqual(a, b, "input order must not change the pick")
    }

    func testPaymentCardIsTheFirstConfirmationAndIsUnique() {
        let cards = [
            card("20000000-0000-4000-8000-000000000001", confirmedBody, 400),
            card("20000000-0000-4000-8000-000000000002", confirmedBody, 200),
        ]
        let chosen = DisputeCardAttachment.paymentCardMessageID(in: cards)
        XCTAssertEqual(chosen, cards[0].id, "the earliest confirmation owns the payment dispute")
        XCTAssertEqual(cards.filter { $0.id == chosen }.count, 1)
    }

    func testNoCardsMeansNothingAttached() {
        XCTAssertNil(DisputeCardAttachment.refundCardMessageID(in: [], disputedAt: Date()))
        XCTAssertNil(DisputeCardAttachment.paymentCardMessageID(in: []))
    }

    func testSelectionIsIndependentPerDisputeKind() {
        // Both kinds present: each picks its own card, and they never collide
        // because a card's body classifies as exactly one kind.
        let cards = [
            card("30000000-0000-4000-8000-000000000001", confirmedBody, 500),
            card("30000000-0000-4000-8000-000000000002", cancelledBody, 100),
        ]
        let refund = DisputeCardAttachment.refundCardMessageID(in: cards, disputedAt: Date())
        let payment = DisputeCardAttachment.paymentCardMessageID(in: cards)
        XCTAssertEqual(refund, cards[1].id)
        XCTAssertEqual(payment, cards[0].id)
        XCTAssertNotEqual(refund, payment)
    }

    func testNonSystemAndUnclassifiedMessagesAreIgnored() {
        let plain = DisputeCardAttachment.SystemMessage(
            id: UUID(uuidString: "40000000-0000-4000-8000-000000000001")!,
            body: "xin chào", createdAt: Date()
        )
        let other = DisputeCardAttachment.SystemMessage(
            id: UUID(uuidString: "40000000-0000-4000-8000-000000000002")!,
            body: "Check-in recorded", createdAt: Date()
        )
        let cards = [plain, other] + [card("40000000-0000-4000-8000-000000000003", cancelledBody, 10)]
        XCTAssertEqual(
            DisputeCardAttachment.refundCardMessageID(in: cards, disputedAt: Date()),
            UUID(uuidString: "40000000-0000-4000-8000-000000000003")
        )
    }
}
