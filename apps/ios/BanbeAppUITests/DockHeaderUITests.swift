import XCTest

/// Note 53 (owner report): the banbe logo + section title must sit at the same place and size on every dock tab
/// (Home, Schedule, Messages, Account — Map has its own search header), so switching tabs never makes them jump.
final class DockHeaderUITests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private func titleFrame(_ variant: String, _ id: String, lang: String) -> CGRect {
        let app = XCUIApplication()
        app.launchArguments += ["-uiFixture", "shell.\(variant)", "-banbe.lang", lang, "-banbe.theme", "light",
                                "-uiTesting", "1", "-banbe.onboarded", "YES"]
        app.launch()
        let title = app.descendants(matching: .any)[id].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 15), "\(id) exists")
        sleep(1)
        let f = title.frame
        print("DOCKHEADER \(lang) \(variant) minX=\(f.minX) midY=\(f.midY) height=\(f.height)")
        app.terminate()
        return f
    }

    private func check(lang: String) {
        let screens = [("home", "home.title"), ("schedule", "schedule.title"), ("inbox", "inbox.title"), ("account", "account.title")]
        let frames = screens.map { titleFrame($0.0, $0.1, lang: lang) }
        let ref = frames[0]
        for (i, f) in frames.enumerated().dropFirst() {
            XCTAssertEqual(f.minX, ref.minX, accuracy: 0.5, "\(screens[i].0): title x (logo width + gap) matches Home")
            XCTAssertEqual(f.midY, ref.midY, accuracy: 0.5, "\(screens[i].0): title y matches Home")
            XCTAssertEqual(f.height, ref.height, accuracy: 0.5, "\(screens[i].0): title size matches Home")
        }
    }

    func testLogoAndTitleSameOnEveryDockTabEN() { check(lang: "en") }
    func testLogoAndTitleSameOnEveryDockTabVI() { check(lang: "vi") }
}
