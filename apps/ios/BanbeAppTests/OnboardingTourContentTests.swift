import XCTest
@testable import BanbeApp

/// Mirrors tests/unit/onboardingTour.test.mjs (web): same chapters, do-it taps and host-only chapter.
final class OnboardingTourContentTests: XCTestCase {
    func testEveryChapterStepExistsAndIDsAreUnique() {
        let ids = OnboardingTourContent.steps.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        for c in OnboardingTourContent.chapters { for id in c.stepIDs { XCTAssertTrue(ids.contains(id), id) } }
        for s in OnboardingTourContent.steps {
            XCTAssertTrue(["home", "inbox", "profile"].contains(s.screen), s.id)
            XCTAssertFalse(s.vi.title.isEmpty || s.en.title.isEmpty)
        }
    }

    func testHostingChapterOnlyForOrganizers() {
        let guest = OnboardingTourContent.plan(organizerMode: false, simpleShell: false).map(\.chapter.id)
        let host = OnboardingTourContent.plan(organizerMode: true, simpleShell: false).map(\.chapter.id)
        XCTAssertFalse(guest.contains("host"))
        XCTAssertTrue(host.contains("host"))
        XCTAssertEqual(OnboardingTourContent.eligible(organizerMode: true).count, OnboardingTourContent.steps.count)
    }

    func testDoItStepsArePrototypeTaps() {
        XCTAssertEqual(Set(OnboardingTourContent.doIt.keys), ["home.tonight", "dock.activity", "dock.account", "host.tab"])
    }

    func testAccountShortcutsCopyFollowsRewardsSwitch() throws {
        let step = try XCTUnwrap(OnboardingTourContent.steps.first { $0.id == "account.shortcuts" })
        XCTAssertTrue(step.copy(rewardsOn: true, english: true).body.hasSuffix("Saved events, and Rewards."))
        XCTAssertTrue(step.copy(rewardsOn: false, english: true).body.hasSuffix("Saved events, and Help."))
        XCTAssertTrue(step.copy(rewardsOn: true, english: false).body.hasSuffix("Phần thưởng."))
        XCTAssertTrue(step.copy(rewardsOn: false, english: false).body.hasSuffix("Trợ giúp."))
        let other = try XCTUnwrap(OnboardingTourContent.steps.first { $0.id == "dock.account" })
        XCTAssertEqual(other.copy(rewardsOn: false, english: true).title, other.en.title)
    }
}
