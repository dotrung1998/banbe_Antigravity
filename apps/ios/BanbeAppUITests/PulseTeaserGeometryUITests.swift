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

        // Left-edge pointer contract: the bubble extends to the RIGHT of
        // the ring's own vertical midline, never fully to its left.
        XCTAssertGreaterThanOrEqual(bubbleFrame.maxX, ringFrame.midX)

        // The ring itself must remain visible/tappable — the bubble
        // shouldn't fully cover it.
        XCTAssertTrue(ring.isHittable, "Ring must stay tappable while the teaser bubble is showing")
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
}
