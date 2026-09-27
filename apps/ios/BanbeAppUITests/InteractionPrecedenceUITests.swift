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
}
