import XCTest

/// The photo viewer opens over a blurred backdrop with the photo centred.
/// Centring is the part worth a test: the backdrop is deliberately larger
/// than the screen, and sizing it with a frame rather than a scaleEffect
/// silently pushed the whole overlay down and to the right, because a ZStack
/// takes the size of its largest child and GeometryReader places its content
/// topLeading rather than centred.
final class PhotoViewerUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testTappingAGalleryPhotoOpensACentredViewer() {
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
        XCTAssertEqual(opened.frame.midY, screen.midY, accuracy: 1,
                       "The photo is not vertically centred on the screen")

        // Credit top-left, tagline bottom-left, actions bottom-right — all
        // on the blur, none of them over the photo.
        let credit = app.staticTexts["photoViewer.credit"]
        let tagline = app.staticTexts["photoViewer.tagline"]
        let share = app.buttons["photoViewer.share"]
        XCTAssertTrue(credit.exists && tagline.exists && share.exists)
        XCTAssertLessThan(credit.frame.midY, opened.frame.minY, "Credit should sit above the photo")
        XCTAssertGreaterThan(tagline.frame.midY, opened.frame.maxY, "Tagline should sit below the photo")
        XCTAssertGreaterThan(share.frame.midX, screen.midX, "Actions belong on the right")
        XCTAssertLessThan(tagline.frame.midX, screen.midX, "Tagline belongs on the left")

        // Liking and saving act without closing the viewer.
        app.buttons["photoViewer.like"].tap()
        app.buttons["photoViewer.save"].tap()
        XCTAssertTrue(opened.exists, "Tapping an action should not dismiss the viewer")

        // Tapping the backdrop does close it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).tap()
        XCTAssertTrue(app.otherElements["screen.event"].waitForExistence(timeout: 5))
    }
}
