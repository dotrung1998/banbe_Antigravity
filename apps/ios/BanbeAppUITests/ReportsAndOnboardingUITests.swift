import XCTest

/// Reports dashboard + onboarding flow against the DEBUG-only fixtures
/// (App/UITestFixtures.swift): no network, no real account, deterministic.
final class ReportsAndOnboardingUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func launch(_ fixture: String, lang: String = "en", reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiFixture", fixture, "-banbe.lang", lang, "-uiTesting", "1",
                                "-uiFixtureReset", reset ? "YES" : "NO"]
        app.launch()
        return app
    }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    // MARK: Reports

    func testPersonalDashboardSectionsAndDetail() {
        let app = launch("reports.personal")
        XCTAssertTrue(el(app, "reports.primary.confirmed_bookings").waitForExistence(timeout: 10))
        XCTAssertTrue(el(app, "reports.kpi.upcoming_events").exists)
        XCTAssertTrue(el(app, "reports.attention.outstanding_refunds").exists)
        XCTAssertFalse(el(app, "reports.kpi.outstanding_refunds").exists, "a flagged metric is not repeated")
        XCTAssertTrue(el(app, "reports.menu").exists)

        el(app, "reports.attention.outstanding_refunds").tap()
        XCTAssertTrue(el(app, "reports.detail.csv").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Host marked as sent"].exists, "status is localized, not a raw key")
        XCTAssertFalse(app.staticTexts["host_marked_sent"].exists)
        el(app, "reports.detail.close").tap()
        XCTAssertTrue(el(app, "reports.primary.confirmed_bookings").waitForExistence(timeout: 5))
    }

    func testHostDashboardShowsOverdueFirst() {
        let app = launch("reports.host")
        XCTAssertTrue(el(app, "reports.primary.confirmed_seats").waitForExistence(timeout: 10))
        let overdue = el(app, "reports.attention.refunds_overdue")
        let owed = el(app, "reports.attention.refunds_owed")
        XCTAssertTrue(overdue.exists && owed.exists)
        XCTAssertLessThan(overdue.frame.minY, owed.frame.minY)
        XCTAssertTrue(el(app, "reports.kpi.confirmed_payment_amount").exists)
    }

    func testAdminLeadsWithBacklog() {
        let app = launch("reports.admin")
        let reviews = el(app, "reports.attention.pending_event_reviews")
        XCTAssertTrue(reviews.waitForExistence(timeout: 10))
        let primary = el(app, "reports.primary.platform_new_bookings")
        XCTAssertTrue(primary.exists)
        XCTAssertLessThan(reviews.frame.minY, primary.frame.minY)
    }

    func testExportMenuKeepsPdfAndJson() {
        let app = launch("reports.host")
        XCTAssertTrue(el(app, "reports.menu").waitForExistence(timeout: 10))
        el(app, "reports.menu").tap()
        XCTAssertTrue(app.buttons["PDF report"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["JSON data"].exists)
    }

    func testLoadingErrorStaleAndEmptyStates() {
        var app = launch("reports.loading.host")
        XCTAssertTrue(el(app, "reports.skeleton").waitForExistence(timeout: 10))
        app.terminate()
        app = launch("reports.error.host")
        XCTAssertTrue(el(app, "reports.retry").waitForExistence(timeout: 10))
        app.terminate()
        app = launch("reports.stale.host")
        XCTAssertTrue(el(app, "reports.stale").waitForExistence(timeout: 10))
        XCTAssertTrue(el(app, "reports.primary.confirmed_seats").exists, "stale data stays visible")
        app.terminate()
        app = launch("reports.empty.personal")
        XCTAssertTrue(el(app, "reports.empty").waitForExistence(timeout: 10))
    }

    // MARK: Onboarding

    func testAnswerSkipBackAndComplete() {
        let app = launch("onboarding")
        XCTAssertTrue(el(app, "onboarding.start").waitForExistence(timeout: 10))
        el(app, "onboarding.start").tap()

        XCTAssertTrue(el(app, "onboarding.question.goals").waitForExistence(timeout: 5))
        XCTAssertEqual(el(app, "onboarding.progress").label, "1 of 5")
        el(app, "onboarding.goals.meet_people").tap()
        el(app, "onboarding.goals.learn").tap()
        XCTAssertTrue(el(app, "onboarding.goals.learn").isSelected)
        el(app, "onboarding.goals.no_preference").tap()
        XCTAssertFalse(el(app, "onboarding.goals.learn").isSelected, "No preference is exclusive")
        el(app, "onboarding.goals.learn").tap()
        el(app, "onboarding.next").tap()

        XCTAssertTrue(el(app, "onboarding.question.interests").waitForExistence(timeout: 5))
        el(app, "onboarding.interests.music").tap()
        el(app, "onboarding.back").tap()
        XCTAssertTrue(el(app, "onboarding.question.goals").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "onboarding.goals.learn").isSelected, "Back keeps answers")
        el(app, "onboarding.next").tap()
        XCTAssertTrue(el(app, "onboarding.interests.music").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "onboarding.interests.music").isSelected)
        el(app, "onboarding.next").tap()

        XCTAssertTrue(el(app, "onboarding.question.availability").waitForExistence(timeout: 5))
        el(app, "onboarding.skipQuestion").tap()
        XCTAssertTrue(el(app, "onboarding.question.budget").waitForExistence(timeout: 5))
        el(app, "onboarding.budget.free").tap()
        el(app, "onboarding.next").tap()
        XCTAssertTrue(el(app, "onboarding.question.languages").waitForExistence(timeout: 5))
        XCTAssertEqual(el(app, "onboarding.progress").label, "5 of 5")
        el(app, "onboarding.next").tap()

        XCTAssertTrue(el(app, "onboarding.reveal").waitForExistence(timeout: 10))
        XCTAssertTrue(el(app, "onboarding.reveal.count").waitForExistence(timeout: 5))
        XCTAssertEqual(el(app, "onboarding.reveal.count").label, "2 upcoming events fit you")
        XCTAssertTrue(el(app, "onboarding.reveal.impacts").exists)
        el(app, "onboarding.reveal.continue").tap()
        XCTAssertTrue(el(app, "fixture.finished").waitForExistence(timeout: 5))
    }

    func testSkipAllFromWelcome() {
        let app = launch("onboarding")
        XCTAssertTrue(el(app, "onboarding.skipAll").waitForExistence(timeout: 10))
        el(app, "onboarding.skipAll").tap()
        XCTAssertTrue(el(app, "fixture.finished").waitForExistence(timeout: 5), "skip all saves nothing and shows no reveal")
    }

    func testSaveFailureIsHonestAndRecoverable() {
        let app = launch("onboarding.saveFails")
        XCTAssertTrue(el(app, "onboarding.start").waitForExistence(timeout: 10))
        el(app, "onboarding.start").tap()
        for _ in 0..<5 {
            XCTAssertTrue(el(app, "onboarding.next").waitForExistence(timeout: 5))
            el(app, "onboarding.next").tap()
        }
        XCTAssertTrue(el(app, "onboarding.saveFailed").waitForExistence(timeout: 10))
        el(app, "onboarding.failed.back").tap()
        XCTAssertTrue(el(app, "onboarding.question.languages").waitForExistence(timeout: 5))
        el(app, "onboarding.next").tap()
        XCTAssertTrue(el(app, "onboarding.failed.skip").waitForExistence(timeout: 10))
        el(app, "onboarding.failed.skip").tap()
        XCTAssertTrue(el(app, "fixture.finished").waitForExistence(timeout: 5))
    }

    func testZeroMatchesAndOfflineReveal() {
        var app = launch("onboarding.zero")
        el(app, "onboarding.start").tap()
        XCTAssertTrue(el(app, "onboarding.question.goals").waitForExistence(timeout: 5))
        el(app, "onboarding.next").tap()
        el(app, "onboarding.interests.music").tap()
        for _ in 0..<4 { el(app, "onboarding.next").tap() }
        XCTAssertTrue(el(app, "onboarding.reveal.empty").waitForExistence(timeout: 10))
        app.terminate()

        app = launch("onboarding.offline")
        el(app, "onboarding.start").tap()
        XCTAssertTrue(el(app, "onboarding.question.goals").waitForExistence(timeout: 5))
        el(app, "onboarding.goals.learn").tap()
        for _ in 0..<5 { el(app, "onboarding.next").tap() }
        XCTAssertTrue(el(app, "onboarding.reveal.failed").waitForExistence(timeout: 10))
        XCTAssertTrue(el(app, "onboarding.reveal.retry").exists)
    }

    func testDraftSurvivesRelaunch() {
        var app = launch("onboarding")
        el(app, "onboarding.start").tap()
        XCTAssertTrue(el(app, "onboarding.goals.learn").waitForExistence(timeout: 5))
        el(app, "onboarding.goals.learn").tap()
        el(app, "onboarding.next").tap()
        XCTAssertTrue(el(app, "onboarding.question.interests").waitForExistence(timeout: 5))
        app.terminate()

        app = launch("onboarding", reset: false)
        XCTAssertTrue(el(app, "onboarding.question.interests").waitForExistence(timeout: 10), "resumes at the same question")
        el(app, "onboarding.back").tap()
        XCTAssertTrue(el(app, "onboarding.goals.learn").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "onboarding.goals.learn").isSelected, "answer restored")
    }

    func testVietnameseCopy() {
        let app = launch("onboarding", lang: "vi")
        XCTAssertTrue(el(app, "onboarding.start").waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Bắt đầu"].exists)
        el(app, "onboarding.start").tap()
        XCTAssertEqual(el(app, "onboarding.progress").label, "Câu 1/5")
    }
}
