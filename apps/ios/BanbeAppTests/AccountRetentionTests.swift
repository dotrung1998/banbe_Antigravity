import XCTest
@testable import BanbeApp

/// Mirrors tests/unit/accountRetention.test.mjs — keep both in step.
final class AccountRetentionTests: XCTestCase {
    func testEveryReasonMapsToOneOffer() {
        XCTAssertEqual(AccountRetention.offer(for: "too_many_notifications"), .quieterNotifications)
        XCTAssertEqual(AccountRetention.offer(for: "not_using"), .retuneForYou)
        XCTAssertEqual(AccountRetention.offer(for: "privacy"), .reviewPrivacy)
        for r in ["found_alternative", "other", "prefer_not_say"] {
            XCTAssertEqual(AccountRetention.offer(for: r), .takeABreak)
        }
        XCTAssertNil(AccountRetention.offer(for: ""))
        for r in AccountRetention.reasons { XCTAssertNotNil(AccountRetention.offer(for: r.code), r.code) }
    }

    func testReasonCodesMatchServerContract() {
        XCTAssertEqual(AccountRetention.reasons.map(\.code),
                       ["not_using", "privacy", "found_alternative", "too_many_notifications", "other", "prefer_not_say"])
    }

    func testQuieterNotificationsKeepsTransactionalKinds() {
        for k in ["payment_confirmed", "hold_created", "refund_marked_sent", "dispute_message", "booking_cancelled", "checked_in"] {
            XCTAssertFalse(AccountRetention.quietedNotificationKinds.contains(k), k)
        }
    }

    func testLossRows() {
        typealias Row = AccountRetention.LossRow
        XCTAssertEqual(AccountRetention.lossRows(bookedEvents: 0, savedEvents: 0, followedHosts: 0,
                                                 coins: nil, rewardsEnabled: true, hostedEvents: 0), [])
        XCTAssertEqual(AccountRetention.lossRows(bookedEvents: 2, savedEvents: 0, followedHosts: 3,
                                                 coins: 40, rewardsEnabled: false, hostedEvents: 1),
                       [Row(kind: .bookedEvents, count: 2), Row(kind: .hostedEvents, count: 1), Row(kind: .followedHosts, count: 3)])
        XCTAssertEqual(AccountRetention.lossRows(bookedEvents: 0, savedEvents: 1, followedHosts: 0,
                                                 coins: 40, rewardsEnabled: true, hostedEvents: 0),
                       [Row(kind: .savedEvents, count: 1), Row(kind: .coins, count: 40)])
    }
}
