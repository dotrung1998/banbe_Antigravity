import XCTest
@testable import BanbeApp

/// Q6: banbe offers push reminders once, after a confirmed ticket, only while the switch is on and iOS never asked.
final class PushAskTests: XCTestCase {
    func testOffersOnlyWhenEveryConditionHolds() {
        XCTAssertTrue(PushAsk.shouldOffer(pushEnabled: true, hasConfirmedTicket: true, alreadyOffered: false, systemNotDetermined: true))
    }

    func testNeverWhileTheSwitchIsOff() {
        XCTAssertFalse(PushAsk.shouldOffer(pushEnabled: false, hasConfirmedTicket: true, alreadyOffered: false, systemNotDetermined: true))
    }

    func testNeverBeforeAConfirmedTicket() {
        XCTAssertFalse(PushAsk.shouldOffer(pushEnabled: true, hasConfirmedTicket: false, alreadyOffered: false, systemNotDetermined: true))
    }

    func testOnlyOnceAndNeverAfterIOSAlreadyAsked() {
        XCTAssertFalse(PushAsk.shouldOffer(pushEnabled: true, hasConfirmedTicket: true, alreadyOffered: true, systemNotDetermined: true))
        XCTAssertFalse(PushAsk.shouldOffer(pushEnabled: true, hasConfirmedTicket: true, alreadyOffered: false, systemNotDetermined: false))
    }

    func testPushSwitchIsDarkUntilSet() {
        XCTAssertFalse(FeatureFlags.isOn([:], "push_enabled"))
        XCTAssertFalse(FeatureFlags.isOn(["push_enabled": false], "push_enabled"))
        XCTAssertTrue(FeatureFlags.isOn(["push_enabled": true], "push_enabled"))
    }
}
