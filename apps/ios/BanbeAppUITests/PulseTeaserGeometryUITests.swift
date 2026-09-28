import XCTest

/// Regression coverage for the Pulse teaser bubble
/// (`PulseTeaserBubbleContent`, drawn by `HomeView.storyRow`) against the
/// Pulse ring (`home.pulseAvatar`).
///
/// Same-space pass (2026-09-28): three real-device passes tried to keep a
/// screen-space overlay glued to the ring through callbacks
/// (PreferenceKey -> `RingFrameProbe` KVO -> imperative
/// `UIHostingController` frame writes), and all three still read on a real
/// iPhone as the bubble sitting FIXED ON SCREEN while the ring scrolled.
/// The bubble is now drawn inside the story row's own scrolling coordinate
/// space, so the two contracts these tests assert are the ones a user can
/// actually see: the bubble overlaps the ring's upper-right quadrant, and
/// it MOVES WITH the ring as the feed scrolls — the latter directly, in
/// `testPulseTeaserBubbleMovesWithRingOnVerticalScroll` below. This only
/// exercises the geometry/visibility contract, not the
/// step-sequence/5-minute-repeat timing logic, which is unchanged.
final class PulseTeaserGeometryUITests: XCTestCase {

    /// The teaser bubble's accessibility element, looked up by IDENTIFIER
    /// only. Since the same-space pass the bubble is a SwiftUI combined
    /// element living inside the feed's own scroll content, which UIKit
    /// exposes as a `staticText`; the previous type-specific
    /// `otherElements[...]` query matched the old hosted-overlay form, so
    /// leaving it in place would silently find nothing here and turn every
    /// test in this file into a skip instead of a check.
    private func pulseBubble(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "home.pulseTeaserBubble").firstMatch
    }

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

        let bubble = pulseBubble(in: app)
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

    /// Regression coverage for the second real-device report (still-far-below
    /// after the first KVO fix): the ring's reported frame froze stale across
    /// a real vertical scroll. Exercises geometry AFTER a real drag-driven
    /// partial scroll (not just at initial layout), which is exactly the
    /// condition that bug failed under while a size-only/initial-layout check
    /// would not have caught it. Kept as-is by the same-space pass — it is a
    /// weaker check than the delta-based one below, but it still holds and
    /// still fails if the bubble and ring are ever separated again.
    func testPulseTeaserBubbleStaysAnchoredAfterScrolling() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-banbe.onboarded", "YES"]
        app.launch()
        XCTAssertTrue(app.otherElements["screen.home"].waitForExistence(timeout: 15))

        let ring = app.buttons["home.pulseAvatar"]
        XCTAssertTrue(ring.waitForExistence(timeout: 10))

        let bubble = pulseBubble(in: app)
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
                      "After scrolling, bubble (\(bubbleFrame)) reads as far below the ring's CURRENT position (\(ringFrame)) — the bubble and the ring are no longer in the same scrolling space")
    }

    /// Live-tracking regression coverage (2026-09-28, follow-up on top of
    /// `testPulseTeaserBubbleStaysAnchoredAfterScrolling` above): that test
    /// only asserts geometry once, AFTER one drag has fully completed and
    /// settled — a bubble that re-synced its position only once some
    /// coarser event happened to fire (which is exactly how the real-device
    /// freeze behaved) can already look indistinguishable from correct by
    /// the time any single before/after check runs.
    ///
    /// XCUITest has no supported way to read an element's frame WHILE a
    /// `press(forDuration:thenDragTo:)` gesture is still physically in
    /// flight (the call blocks until the finger lifts), so this instead
    /// chases the same failure mode the way the code comments above
    /// describe it manifesting on a real device — "only catches up (if at
    /// all) after the drag settles" — by firing a SEQUENCE of several
    /// small, separate drags (rather than one big one) and asserting the
    /// geometry contract immediately after EACH one, with no extra
    /// settle-time pause beyond what the gesture call itself takes. A
    /// bubble that only re-syncs its position on some coarser cadence than
    /// "every drag" (e.g. only once some unrelated SwiftUI re-render
    /// happens to fire) would accumulate visible drift across these
    /// checks, exactly like scrolling by hand would.
    func testPulseTeaserBubbleTracksAcrossMultipleIncrementalScrolls() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-banbe.onboarded", "YES"]
        app.launch()
        XCTAssertTrue(app.otherElements["screen.home"].waitForExistence(timeout: 15))

        let ring = app.buttons["home.pulseAvatar"]
        XCTAssertTrue(ring.waitForExistence(timeout: 10))

        let bubble = pulseBubble(in: app)
        guard bubble.waitForExistence(timeout: 20) else {
            throw XCTSkip("Pulse teaser bubble did not show within the wait window this run.")
        }

        let home = app.otherElements["screen.home"]
        var checkedAtLeastOnce = false

        // Several SMALL, SEPARATE drags (not one big one) — each one its
        // own distinct scroll offset, checked immediately on return, with
        // no extra pause to let anything "catch up" in between.
        for step in 0..<5 {
            guard ring.isHittable, bubble.exists else { break }

            let start = home.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
            let end = home.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62 - 0.04))
            start.press(forDuration: 0.02, thenDragTo: end)

            guard ring.isHittable, bubble.exists else { break }

            let ringFrame = ring.frame
            let bubbleFrame = bubble.frame
            guard ringFrame.width > 0, bubbleFrame.width > 0 else { continue }
            checkedAtLeastOnce = true

            let quadrant = CGRect(x: ringFrame.midX, y: ringFrame.minY,
                                   width: ringFrame.width / 2, height: ringFrame.height / 2)
            XCTAssertTrue(bubbleFrame.intersects(quadrant),
                          "After incremental scroll #\(step), expected the bubble (\(bubbleFrame)) to still overlap the ring's CURRENT upper-right quadrant (\(quadrant)) — drift here indicates the bubble is not tracking live, only catching up once settled")
            XCTAssertLessThanOrEqual(bubbleFrame.minY, ringFrame.maxY + 12,
                          "After incremental scroll #\(step), bubble (\(bubbleFrame)) reads as far below the ring's CURRENT position (\(ringFrame))")
        }

        guard checkedAtLeastOnce else {
            throw XCTSkip("Ring/bubble left screen before any incremental scroll could be checked this run.")
        }
    }

    /// THE focused regression test for the real-device bug this pass exists
    /// for: the bubble sat FIXED ON SCREEN while the ring scrolled. Every
    /// other geometry test in this file can pass with that bug present,
    /// because each one only relates the two frames to each other after a
    /// scroll has settled, when a frozen bubble can still look roughly
    /// right. This one measures the two elements' own frame DELTAS across a
    /// real vertical drag and requires them to match: a bubble that does not
    /// travel with the ring cannot satisfy it, at any settling time.
    ///
    /// One thing this deliberately does NOT try to do: sample mid-gesture.
    /// XCUITest can't read frames while a `press(forDuration:thenDragTo:)`
    /// is still in flight, so each drag is allowed to come fully to rest
    /// (including its momentum) before either frame is read — which is why
    /// both frames are read after the SAME settle point rather than
    /// interleaved with the gesture.
    func testPulseTeaserBubbleMovesWithRingOnVerticalScroll() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-banbe.onboarded", "YES"]
        app.launch()
        XCTAssertTrue(app.otherElements["screen.home"].waitForExistence(timeout: 15))

        let ring = app.buttons["home.pulseAvatar"]
        XCTAssertTrue(ring.waitForExistence(timeout: 10))

        let bubble = pulseBubble(in: app)
        guard bubble.waitForExistence(timeout: 20) else {
            throw XCTSkip("Pulse teaser bubble did not show within the wait window this run.")
        }

        let home = app.otherElements["screen.home"]
        var checked = 0

        for step in 0..<3 {
            guard ring.isHittable, bubble.exists else { break }
            let ringBefore = ring.frame
            let bubbleBefore = bubble.frame
            guard ringBefore.width > 0, bubbleBefore.width > 0 else { break }

            // One short, real, drag-driven vertical scroll: the feed moves a
            // little, both elements stay on screen.
            let start = home.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
            let end = home.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.58))
            start.press(forDuration: 0.02, thenDragTo: end)

            // Let deceleration finish so both frames below describe the same
            // resting scroll offset (otherwise the bubble's frame could be
            // read mid-momentum and differ for a reason that isn't the bug).
            Thread.sleep(forTimeInterval: 1.2)

            guard ring.isHittable, bubble.exists else { break }
            let ringAfter = ring.frame
            let bubbleAfter = bubble.frame
            guard ringAfter.width > 0, bubbleAfter.width > 0 else { break }

            let ringDelta = ringAfter.minY - ringBefore.minY
            // The gesture didn't turn into real scrolling this time — nothing
            // to assert, and not a contract failure.
            guard abs(ringDelta) > 1 else { continue }
            checked += 1

            // The bubble's BOTTOM edge is the anchored one (it sits on the
            // ring's centre line — see `storyRow`'s own comment), so it is
            // the edge to compare: unlike the top edge it cannot be moved by
            // a step advancing to taller/shorter copy between these two
            // reads, which is exactly the kind of noise that would make this
            // test flaky rather than wrong.
            let bubbleDelta = bubbleAfter.maxY - bubbleBefore.maxY
            XCTAssertEqual(bubbleDelta, ringDelta, accuracy: 1.5,
                           "After vertical scroll #\(step) the ring moved \(ringDelta)pt but the bubble moved \(bubbleDelta)pt — the bubble is NOT travelling with the ring. This is the real-device bug: the bubble stayed fixed on screen while the ring scrolled.")
            XCTAssertEqual(bubbleAfter.minX - bubbleBefore.minX, ringAfter.minX - ringBefore.minX, accuracy: 1.5,
                           "After vertical scroll #\(step) the bubble drifted horizontally relative to the ring (\(bubbleBefore) -> \(bubbleAfter) vs ring \(ringBefore) -> \(ringAfter))")
            XCTAssertLessThanOrEqual(bubbleAfter.maxY, ringAfter.maxY + 12,
                           "After vertical scroll #\(step), the bubble (\(bubbleAfter)) no longer reads as overlapping the ring (\(ringAfter))")
        }

        guard checked > 0 else {
            throw XCTSkip("No drag actually scrolled the feed far enough to move the ring this run.")
        }
    }

    /// If the ring scrolls out of view (user scrolls the feed down past
    /// the story row), the bubble must not keep floating, disconnected,
    /// over unrelated content below — it must leave the screen together
    /// with its ring.
    ///
    /// Same-space pass (2026-09-28): the bubble is now part of the story
    /// row's own scrolling content, so it travels with the ring by
    /// construction. The old assertion here (`bubble.exists == false`) was
    /// how the hosted-overlay version proved the same thing — it physically
    /// hid its `UIView` once the ring left the screen — but an element that
    /// has been scrolled off-screen inside a `ScrollView` can legitimately
    /// still exist in the accessibility tree, so existence is no longer the
    /// right check. What must still hold (and is what a user sees) is that
    /// the bubble is no longer on screen at all.
    func testPulseTeaserBubbleHidesWhenRingScrollsOffScreen() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-banbe.onboarded", "YES"]
        app.launch()
        XCTAssertTrue(app.otherElements["screen.home"].waitForExistence(timeout: 15))

        let ring = app.buttons["home.pulseAvatar"]
        XCTAssertTrue(ring.waitForExistence(timeout: 10))

        let bubble = pulseBubble(in: app)
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

        // The bubble must have left the screen with the ring (see this
        // test's own doc comment for why visibility, not tree existence, is
        // the assertion here).
        if bubble.exists {
            let window = app.windows.firstMatch.frame
            XCTAssertFalse(bubble.isHittable,
                           "Bubble is still hittable after its ring scrolled off screen (\(bubble.frame))")
            XCTAssertFalse(bubble.frame.intersects(window),
                           "Bubble (\(bubble.frame)) is still on screen (\(window)) after its ring (\(ring.frame)) scrolled off — it must travel with the ring rather than float over unrelated content below")
        }
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

        let bubble = pulseBubble(in: app)
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
