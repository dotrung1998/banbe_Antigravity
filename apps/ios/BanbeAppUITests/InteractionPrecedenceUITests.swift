import XCTest

/// iPhone fix pass (2026-09-27, post-ec06c78) — focused regression coverage
/// for three interaction bugs traced back to a single shared root cause:
/// `RootView.rootScreenStack`'s ForEach used to give the CURRENT screen an
/// explicit `.zIndex(1)` that leaked out and outranked every OTHER,
/// implicitly-zIndex-0 sibling in RootView's own outer ZStack (the
/// leading-edge `edgeSwipe` strip, `PhotoViewerView`, ...) — see
/// RootView.swift's own `rootScreenStack` doc comment for the full
/// writeup. These assert the FUNCTIONAL/state-level contract each bug
/// broke; XCUITest's synthetic touches don't fully reproduce real-device
/// gesture-recognizer arbitration timing, so a clean run here is not by
/// itself proof the on-device feel is fixed — only that these three
/// specific navigation/precedence outcomes hold.
///
/// Not run as part of this pass (no simulator/device execution) — see the
/// ticket's own output for what remains genuinely unverified.
final class InteractionPrecedenceUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    @discardableResult
    private func launchToHome() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-banbe.onboarded", "YES"]
        app.launch()
        XCTAssertTrue(app.otherElements["screen.home"].waitForExistence(timeout: 15))
        return app
    }

    /// Issue 1 — a completed leading-edge drag on a PUSHED (non-root)
    /// screen must reach the same back target the explicit Back button
    /// does, exactly like before `rootScreenStack`'s zIndex leak started
    /// swallowing the touch before `edgeSwipe`'s own `.highPriorityGesture`
    /// strip ever saw it. Does not (and cannot, via XCUITest's atomic
    /// press-drag-release) assert the live mid-drag "previous screen
    /// visible under the finger" feel — only the completed outcome.
    func testEdgeSwipeBackFromEventDetailReachesHome() {
        let app = launchToHome()
        app.buttons["card.bepnho"].tap()
        XCTAssertTrue(app.otherElements["screen.event"].waitForExistence(timeout: 5))

        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        start.press(forDuration: 0.3, thenDragTo: end)

        XCTAssertTrue(app.otherElements["screen.home"].waitForExistence(timeout: 5),
                      "A completed leading-edge drag on a pushed screen should reach the same back target the Back button does")
        XCTAssertFalse(app.otherElements["screen.event"].exists)
    }

    /// Issue 2 — tapping a gallery photo must show the viewer immediately,
    /// as the TOP, hittable presentation (not merely present-but-hidden
    /// behind Event Detail's own zIndex-1 content); dismissing it must
    /// land back on Event Detail specifically, never skip past it to a
    /// previous screen (the "flash, then a previous page slides over it"
    /// regression).
    func testPhotoViewerOpensOnTopAndDismissReturnsToEventDetail() {
        let app = launchToHome()
        app.buttons["card.bepnho"].tap()
        XCTAssertTrue(app.otherElements["screen.event"].waitForExistence(timeout: 5))

        let photo = app.buttons["event.photo.0"]
        var scrolls = 0
        while !photo.isHittable && scrolls < 12 {
            app.swipeUp()
            scrolls += 1
        }
        XCTAssertTrue(photo.isHittable, "Never reached the event's photo strip")
        photo.tap()

        let opened = app.images["photoViewer.photo"]
        XCTAssertTrue(opened.waitForExistence(timeout: 3), "The viewer should appear immediately on tap")
        XCTAssertTrue(opened.isHittable, "The viewer must be the top, interactive presentation, not hidden behind Event Detail")

        // A plain tap on the photo dismisses it — must return to Event
        // Detail exactly, never fall through to Home underneath.
        opened.tap()
        XCTAssertTrue(app.otherElements["screen.event"].waitForExistence(timeout: 5),
                      "Dismissing the viewer should return to Event Detail, not skip past it")
        XCTAssertFalse(app.otherElements["screen.home"].exists)
    }

    /// Issue 3 — one tap on an Account subtab switches immediately and
    /// exactly once, even though `tabSwipeGesture`'s own
    /// `.simultaneousGesture(DragGesture(minimumDistance: 8))` spans the
    /// whole of Account (a root dock screen). Skips gracefully where this
    /// session's account has no organizer mode (so no Tổ chức tab exists to
    /// switch to) rather than asserting on setup it doesn't control.
    func testAccountSubtabTapsSwitchImmediatelyAndExactlyOnce() throws {
        let app = launchToHome()
        app.buttons["header.account"].tap()
        XCTAssertTrue(app.otherElements["screen.profile"].waitForExistence(timeout: 5))

        let hostTab = app.buttons["account.tab.host"]
        try XCTSkipUnless(hostTab.waitForExistence(timeout: 3), "Organizer mode not enabled on this session")

        hostTab.tap()
        XCTAssertTrue(app.buttons["org.profile.card"].waitForExistence(timeout: 3),
                      "One tap on Tổ chức should switch immediately")

        app.buttons["account.tab.personal"].tap()
        XCTAssertTrue(app.buttons["account.organizerToggle"].waitForExistence(timeout: 3),
                      "One tap on Cá nhân should switch immediately, exactly once")
        XCTAssertFalse(app.buttons["org.profile.card"].exists)
    }

    /// Regression coverage for the e56aeb2 over-correction: that pass's
    /// touch-start-Y guard (`AppState.horizontalSwipeRowRegionMinY`, now
    /// `horizontalSwipeRowFrames`) published ONE Y coordinate (the Inbox
    /// header's bottom edge) and blocked root-tab swipe for ANY touch at
    /// or below it — a coarse band covering the entire list area, not just
    /// actual rows — which is why swiping Inbox -> another tab stopped
    /// working AT ALL on a real device. Signs into the shared fast-suite
    /// account (the only signed-in fixture this codebase has — Inbox is
    /// not in `AppState.guestAllowedScreens`, see EventDetailOpenInMapUITests'/
    /// MapExploreSelectionUITests' own `launchSignedIn()`, mirrored here)
    /// and swipes starting in the HEADER — never on a row, so this needs
    /// no seeded/locale-dependent conversation content — asserting it
    /// still reaches an adjacent root tab exactly as it did before
    /// e56aeb2 ever existed.
    func testInboxHeaderSwipeStillNavigatesRootTabs() {
        let app = launchSignedIn()
        app.buttons["tab.inbox"].tap()
        XCTAssertTrue(app.otherElements["screen.inbox"].waitForExistence(timeout: 5))

        // dockOrder is [home, map, notifications, inbox, profile] — a
        // leftward swipe (negative translation) commits to the NEXT tab,
        // profile. dy=0.06 lands well inside the header/search-and-
        // settings row, above where the List's rows begin.
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.06))
        start.press(forDuration: 0.1, thenDragTo: end)

        XCTAssertTrue(app.otherElements["screen.profile"].waitForExistence(timeout: 5),
                      "A horizontal swipe starting in Inbox's header (never on a row) should still navigate root tabs, exactly as before the row-swipe guard existed")
        XCTAssertFalse(app.otherElements["screen.inbox"].exists)
    }

    /// Companion to the header-space test above: a swipe that starts ON an
    /// actual Inbox row must be claimed by that row's own native
    /// `.swipeActions` and must NEVER trigger root-tab navigation — the
    /// precision half of the e56aeb2 fix-up (a single Y-band can't tell
    /// these two cases apart; per-row measured frames can). Uses
    /// `InboxRow`'s existing `inbox.threadRow` accessibility identifier
    /// (stable, not locale-dependent — the label text itself, e.g.
    /// "Lưu trữ"/"Archive", is deliberately never asserted here) rather
    /// than matching any row's display text. Opportunistic like
    /// `ScreenshotCatalogTests`: the shared account is real backend data,
    /// so this skips (not fails) if it currently has no conversations.
    func testInboxRowSwipeNeverTriggersRootTabSwipe() throws {
        let app = launchSignedIn()
        app.buttons["tab.inbox"].tap()
        XCTAssertTrue(app.otherElements["screen.inbox"].waitForExistence(timeout: 5))

        let row = app.buttons["inbox.threadRow"].firstMatch
        try XCTSkipUnless(row.waitForExistence(timeout: 5),
                          "Shared test account has no conversations right now — on-row swipe needs a real thread")

        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        let end = row.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)

        XCTAssertTrue(app.otherElements["screen.inbox"].waitForExistence(timeout: 3),
                      "A swipe starting on a real Inbox row must never trigger root-tab navigation")
        XCTAssertFalse(app.otherElements["screen.profile"].exists)
        XCTAssertFalse(app.otherElements["screen.notifications"].exists)
    }

    @discardableResult
    private func launchSignedIn() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-banbe.onboarded", "YES"]
        app.launch()

        if app.otherElements["screen.login"].waitForExistence(timeout: 45) {
            app.buttons["login.method.password"].tap()
            let email = app.textFields["login.email"]
            XCTAssertTrue(email.waitForExistence(timeout: 5))
            email.tap()
            email.typeText("doqanh0906+banbe-fast-suite-shared@gmail.com")
            let password = app.secureTextFields["login.password"]
            XCTAssertTrue(password.waitForExistence(timeout: 5))
            password.tap()
            password.typeText("BanbeE2e!Test1234")
            app.buttons["login.submit"].tap()
        }

        XCTAssertTrue(app.otherElements["screen.home"].waitForExistence(timeout: 45),
                      "Expected to land on Home after sign-in")
        return app
    }
}
