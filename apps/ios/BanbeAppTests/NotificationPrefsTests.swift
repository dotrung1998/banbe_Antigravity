import XCTest
@testable import BanbeApp

/// Port of tests/unit/notificationPrefs.test.mjs.
final class NotificationPrefsTests: XCTestCase {
    private var byKey: [String: NotificationPrefs.Group] {
        Dictionary(uniqueKeysWithValues: NotificationPrefs.groups.map { ($0.key, $0) })
    }

    func testGroupsNeverContainDisputesMessagesOrDigest() {
        let all = NotificationPrefs.groups.flatMap(\.kinds)
        for k in ["dispute_message", "dispute_resolved", "payment_disputed", "new_message", "weekly_digest"] {
            XCTAssertFalse(all.contains(k), k)
        }
        XCTAssertEqual(Set(all).count, all.count, "a kind belongs to one group only")
    }

    func testHoldsAreTicketsRemindersAreEvents() {
        XCTAssertTrue(byKey["tickets"]!.kinds.contains("hold_created"))
        XCTAssertFalse(byKey["payments"]!.kinds.contains("hold_created"))
        XCTAssertTrue(byKey["events"]!.kinds.contains("event_reminder_day"))
    }

    func testToggleMutesAllKindsThenRestoresTheRest() {
        let off = NotificationPrefs.toggled(["something_else"], byKey["payments"]!)
        XCTAssertFalse(NotificationPrefs.isOn(off, byKey["payments"]!))
        XCTAssertTrue(off.contains("something_else"))
        XCTAssertEqual(NotificationPrefs.toggled(off, byKey["payments"]!), ["something_else"])
    }

    func testPartlyMutedGroupReadsOffAndTurnsFullyOn() {
        let partial = [byKey["tickets"]!.kinds[0]]
        XCTAssertFalse(NotificationPrefs.isOn(partial, byKey["tickets"]!))
        XCTAssertEqual(NotificationPrefs.toggled(partial, byKey["tickets"]!), [])
    }

    func testSummary() {
        XCTAssertEqual(NotificationPrefs.summary([], isEN: true), "All on")
        XCTAssertEqual(NotificationPrefs.summary(byKey["events"]!.kinds, isEN: true), "2 of 3 on")
        XCTAssertEqual(NotificationPrefs.summary(NotificationPrefs.groups.flatMap(\.kinds), isEN: true), "All off")
    }
}
