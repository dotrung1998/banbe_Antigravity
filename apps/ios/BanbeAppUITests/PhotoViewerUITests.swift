import XCTest

/// The photo viewer opens over a blurred backdrop with the photo
/// horizontally centred and the credit/tagline/actions hugging its own top
/// and bottom edges (not the screen's), and a left/right swipe moves
/// through the rest of the gallery without closing the viewer.
final class PhotoViewerUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testGalleryPhotoViewerLayoutAndSwipe() {
        let app = XCUIApplication()
        app.launchArguments += ["-banbe.onboarded", "YES"]
        app.launch()
        XCTAssertTrue(app.otherElements["screen.home"].waitForExistence(timeout: 15))

        app.buttons["card.bepnho"].tap()
        XCTAssertTrue(app.otherElements["screen.event"].waitForExistence(timeout: 10))

        // The gallery sits well below the fold.
        let photo = app.buttons["event.photo.0"]
        var scrolls = 0
        while !photo.isHittable && scrolls < 12 {
            app.swipeUp()
            scrolls += 1
        }
        XCTAssertTrue(photo.isHittable, "Never reached the event's photo strip")
        photo.tap()

        let opened = app.images["photoViewer.photo"]
        XCTAssertTrue(opened.waitForExistence(timeout: 10), "Expected the photo viewer to open")

        let screen = app.windows.firstMatch.frame
        XCTAssertEqual(opened.frame.midX, screen.midX, accuracy: 1,
                       "The photo is not horizontally centred on the screen")

        // Credit and tagline/actions sit close against the photo's own top
        // and bottom edges — not pinned to the screen's — so the gap
        // between them and the photo should be small either way.
        let credit = app.staticTexts["photoViewer.credit"]
        let tagline = app.staticTexts["photoViewer.tagline"]
        let share = app.buttons["photoViewer.share"]
        XCTAssertTrue(credit.exists && tagline.exists && share.exists)
        XCTAssertLessThan(credit.frame.maxY, opened.frame.minY, "Credit should sit above the photo")
        XCTAssertLessThan(opened.frame.minY - credit.frame.maxY, 20, "Credit should hug the photo's top edge")
        XCTAssertGreaterThan(tagline.frame.minY, opened.frame.maxY, "Tagline should sit below the photo")
        // A little more slack than the credit's gap: the tagline shares its
        // row with the 34pt-tall action buttons, bottom-aligned, so the
        // text itself sits a bit higher than a plain 8pt spacer would put it.
        XCTAssertLessThan(tagline.frame.minY - opened.frame.maxY, 36, "Tagline should hug the photo's bottom edge")
        XCTAssertGreaterThan(share.frame.midX, screen.midX, "Actions belong on the right")
        XCTAssertLessThan(tagline.frame.midX, screen.midX, "Tagline belongs on the left")

        // Liking and saving act without closing the viewer — the swipe
        // gesture covering the same area must not steal the button taps.
        app.buttons["photoViewer.like"].tap()
        XCTAssertTrue(opened.exists, "Liking should not dismiss the viewer")
        app.buttons["photoViewer.save"].tap()
        XCTAssertTrue(opened.exists, "Saving should not dismiss the viewer")

        // A left swipe on the photo moves to the next one in the gallery
        // instead of closing the viewer.
        let start = opened.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        let end = opened.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(opened.waitForExistence(timeout: 5), "Swiping should not close the viewer")

        // ...and a right swipe moves back.
        end.press(forDuration: 0.05, thenDragTo: start)
        XCTAssertTrue(opened.waitForExistence(timeout: 5))

        // A plain tap (no movement) does close it.
        opened.tap()
        XCTAssertTrue(app.otherElements["screen.event"].waitForExistence(timeout: 5))
    }
}
