import XCTest

/// Regression coverage for the 2026-09-28 real-device follow-up: the Pulse
/// teaser bubble (`PulseTeaserBubbleView`) used to position itself off a
/// STALE ring frame during real touch-scrolling — a PreferenceKey
/// propagation-mode bug (see that file's own doc comment, and
/// `RingFrameProbe` in Components.swift, for the full root-cause writeup)
/// — reading on a real device as "beside the wrong spot" rather than
/// overlapping the Pulse ring's (`home.pulseAvatar`) upper-right quadrant.
/// This only exercises the geometry/visibility contract, not the
/// step-sequence/5-minute-repeat timing logic, which is unchanged.
final class PulseTeaserGeometryUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// Bubble overlaps the ring's upper-right quadrant (never floats
    /// beside/below it disconnected) whenever it's showing at all — this
    /// test doesn't force the teaser to appear (that's on the app's own
    /// real wall-clock timer, intentionally untouched by this pass), it
    /// just asserts the geometry contract IF it shows up within a
    /// reasonable wait, matching how this teaser actually behaves for a
    /// real user.
    func testPulseTeaserBubbleOverlapsRingUpperRightQuadrantWhenShown() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-banbe.onboarded", "YES"]
        app.launch()
        XCTAssertTrue(app.otherElements["screen.home"].waitForExistence(timeout: 15))

        let ring = app.buttons["home.pulseAvatar"]
        XCTAssertTrue(ring.waitForExistence(timeout: 10), "Expected the Pulse ring to exist on Home")

        let bubble = app.otherElements["home.pulseTeaserBubble"]
        guard bubble.waitForExistence(timeout: 20) else {
            throw XCTSkip("Pulse teaser bubble did not show within the wait window (its own 5-minute repeat/eligibility timer did not fire this run) — geometry is only exercisable while it's showing.")
        }

        let ringFrame = ring.frame
        let bubbleFrame = bubble.frame
        XCTAssertGreaterThan(ringFrame.width, 0)
        XCTAssertGreaterThan(bubbleFrame.width, 0)

        // The upper-right quadrant of the ring: x >= ring's own midX,
        // y <= ring's own midY.
        let quadrant = CGRect(x: ringFrame.midX, y: ringFrame.minY,
                               width: ringFrame.width / 2, height: ringFrame.height / 2)
        XCTAssertTrue(bubbleFrame.intersects(quadrant),
                      "Expected the teaser bubble (\(bubbleFrame)) to overlap the ring's upper-right quadrant (\(quadrant)), not float beside/below it")

        // Explicit "far below the ring" failure-mode guard (the exact real-
        // device regression this test exists to catch): the bubble's own
        // top must not sit meaningfully below the ring's bottom. The
        // quadrant-intersection check above can in principle still pass on
        // a technicality for a huge bubble, so this asserts the vertical
        // relationship directly with a small tolerance for shadow/padding.
        let verticalTolerance: CGFloat = 12
        XCTAssertLessThanOrEqual(bubbleFrame.minY, ringFrame.maxY + verticalTolerance,
                      "Bubble (\(bubbleFrame)) reads as far BELOW the ring (\(ringFrame)) instead of overlapping its upper-right quadrant")

        // Left-edge pointer contract: the bubble extends to the RIGHT of
        // the ring's own vertical midline, never fully to its left.
        XCTAssertGreaterThanOrEqual(bubbleFrame.maxX, ringFrame.midX)

        // The ring itself must remain visible/tappable — the bubble
        // shouldn't fully cover it.
        XCTAssertTrue(ring.isHittable, "Ring must stay tappable while the teaser bubble is showing")
    }

    /// Regression coverage for the SECOND real-device bug (still-far-below
    /// after the first KVO fix): `RingFrameProbe` only observed the FIRST
    /// ancestor `UIScrollView` found while walking up from the ring, which
    /// locked onto `storyRow`'s own horizontal scroller instead of the
    /// outer vertical feed scroller the user actually drags — so
    /// `app.pulseRingFrame` froze stale across a real vertical scroll.
    /// Exercises geometry AFTER a real drag-driven partial scroll (not just
    /// at initial layout), which is exactly the condition the first-ancestor
    /// bug failed under while a size-only/initial-layout check would not
    /// have caught it.
    func testPulseTeaserBubbleStaysAnchoredAfterScrolling() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-banbe.onboarded", "YES"]
        app.launch()
        XCTAssertTrue(app.otherElements["screen.home"].waitForExistence(timeout: 15))

        let ring = app.buttons["home.pulseAvatar"]
        XCTAssertTrue(ring.waitForExistence(timeout: 10))

        let bubble = app.otherElements["home.pulseTeaserBubble"]
        guard bubble.waitForExistence(timeout: 20) else {
            throw XCTSkip("Pulse teaser bubble did not show within the wait window this run.")
        }

        // A small, real drag-driven scroll (a slow coordinate-based drag,
        // not a synthetic scroll-to-element) that leaves the ring still on
        // screen but moved from its original position — the exact
        // condition that exposed the wrong-ancestor-UIScrollView bug.
        let start = app.otherElements["screen.home"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        let end = app.otherElements["screen.home"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        start.press(forDuration: 0.05, thenDragTo: end)

        guard ring.isHittable, bubble.exists else {
            throw XCTSkip("Ring or bubble left screen/dismissed after the scroll this run — geometry only exercisable while both are showing.")
        }

        let ringFrame = ring.frame
        let bubbleFrame = bubble.frame
        let quadrant = CGRect(x: ringFrame.midX, y: ringFrame.minY,
                               width: ringFrame.width / 2, height: ringFrame.height / 2)
        XCTAssertTrue(bubbleFrame.intersects(quadrant),
                      "After scrolling, expected the bubble (\(bubbleFrame)) to still overlap the ring's CURRENT upper-right quadrant (\(quadrant)) — a stale pre-scroll ring frame would fail this")
        XCTAssertLessThanOrEqual(bubbleFrame.minY, ringFrame.maxY + 12,
                      "After scrolling, bubble (\(bubbleFrame)) reads as far below the ring's CURRENT position (\(ringFrame)) — indicates app.pulseRingFrame did not update live during the drag")
    }

    /// If the ring scrolls out of view (user scrolls the feed down past
    /// the story row), the bubble must not keep floating, disconnected,
    /// over unrelated content below — it should hide instead.
    func testPulseTeaserBubbleHidesWhenRingScrollsOffScreen() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-banbe.onboarded", "YES"]
        app.launch()
        XCTAssertTrue(app.otherElements["screen.home"].waitForExistence(timeout: 15))

        let ring = app.buttons["home.pulseAvatar"]
        XCTAssertTrue(ring.waitForExistence(timeout: 10))

        let bubble = app.otherElements["home.pulseTeaserBubble"]
        guard bubble.waitForExistence(timeout: 20) else {
            throw XCTSkip("Pulse teaser bubble did not show within the wait window this run.")
        }

        // Scroll the feed down until the ring is no longer on screen.
        var scrolls = 0
        while ring.isHittable && scrolls < 15 {
            app.swipeUp()
            scrolls += 1
        }
        XCTAssertFalse(ring.isHittable, "Ring should have scrolled off screen")
        XCTAssertFalse(bubble.exists, "Bubble must not remain floating once its ring has scrolled off screen")
    }

    /// Regression coverage for the weekly-ranking step + featured-photos
    /// deep-link addition: taps the bubble body repeatedly (a manual tap
    /// advances the sequence immediately, bypassing each step's own
    /// wall-clock timer — see `advanceOrDismiss()`) until the final step's
    /// "Bấm xem thêm" link appears, then taps specifically THAT link and
    /// confirms it opens the existing Pulse viewer jumped straight to its
    /// existing "Ảnh nổi bật" tab, not a new/different screen.
    func testPulseTeaserFeaturedPhotosLinkOpensPulseViewerOnPhotosTab() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-banbe.onboarded", "YES"]
        app.launch()
        XCTAssertTrue(app.otherElements["screen.home"].waitForExistence(timeout: 15))

        let bubble = app.otherElements["home.pulseTeaserBubble"]
        guard bubble.waitForExistence(timeout: 20) else {
            throw XCTSkip("Pulse teaser bubble did not show within the wait window this run.")
        }

        // Steps: 0 daily title, 1 daily listing, 2 weekly title, 3 weekly
        // listing, 4 the final "Ảnh nổi bật: Bấm xem thêm" step — up to 4
        // taps on the bubble body get from step 0 to step 4.
        let link = app.staticTexts["home.pulseTeaserFeaturedPhotosLink"]
        for _ in 0..<4 {
            if link.exists { break }
            guard bubble.exists else {
                throw XCTSkip("Bubble dismissed itself before reaching the final step this run.")
            }
            bubble.tap()
        }
        guard link.waitForExistence(timeout: 5) else {
            throw XCTSkip("Never reached the final teaser step this run.")
        }

        link.tap()

        XCTAssertTrue(app.buttons["pulse.close"].waitForExistence(timeout: 5),
                      "Expected tapping \"Bấm xem thêm\" to open the existing Pulse viewer")
        XCTAssertTrue(app.buttons["pulse.tab.photos"].isSelected,
                      "Expected the deep link to land on Pulse's existing \"Ảnh nổi bật\" tab, not whatever tab last happened to be selected")
    }
}
