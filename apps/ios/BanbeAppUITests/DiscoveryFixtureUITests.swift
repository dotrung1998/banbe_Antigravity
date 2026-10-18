import XCTest

/// Note 50 — discovery Home, filter sheet, Search and the create-flow recipe, on the REAL RootView with
/// seeded fixture data and no network (`-uiFixture shell.*`). When the runner has `SCREENSHOT_DIR` set
/// (xcodebuild `TEST_RUNNER_SCREENSHOT_DIR=…`), each step also writes a PNG there for visual review.
final class DiscoveryFixtureUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func launch(_ variant: String, theme: String = "light", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiFixture", "shell.\(variant)", "-banbe.lang", "en", "-banbe.theme", theme,
                                "-uiTesting", "1", "-banbe.onboarded", "YES"] + extra
        app.launch()
        return app
    }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func shot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    // MARK: Home

    private func checkHome(theme: String) {
        let app = launch("home", theme: theme)
        XCTAssertTrue(el(app, "home.title").waitForExistence(timeout: 20))
        el(app, "home.layout.cards").tap() // the layout is remembered on the device
        XCTAssertTrue(el(app, "home.searchBar").exists, "full-width search bar")
        XCTAssertTrue(el(app, "header.area").exists, "location pill")
        XCTAssertFalse(el(app, "header.lang").exists, "EN/VN moved to Settings")
        XCTAssertFalse(el(app, "header.theme").exists, "Light/Dark moved to Settings")
        XCTAssertTrue(el(app, "filter.popup").exists, "category tiles include Pop-up")
        XCTAssertTrue(el(app, "home.filtersButton").exists)
        XCTAssertTrue(el(app, "home.sortButton").exists)
        XCTAssertTrue(el(app, "home.resultCount").exists)
        XCTAssertTrue(app.buttons["Fixture host supper"].firstMatch.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.0)
        shot("home-cards-\(theme)")
        el(app, "home.layout.list").tap()
        Thread.sleep(forTimeInterval: 0.8)
        shot("home-list-\(theme)")
        XCTAssertTrue(app.buttons["Fixture host supper"].firstMatch.exists, "list rows keep the event")
        el(app, "home.layout.cards").tap()
    }

    func testHomeDiscoveryLight() { checkHome(theme: "light") }
    func testHomeDiscoveryDark() { checkHome(theme: "dark") }

    /// The fixture's real fill (18 of 20 booked) shows as "Almost full · 2 left"; the quick chip finds it.
    func testAlmostFullBadgeAndQuickChip() {
        let app = launch("home")
        XCTAssertTrue(el(app, "home.title").waitForExistence(timeout: 20))
        let chip = el(app, "home.quick.almostFull")
        XCTAssertTrue(chip.waitForExistence(timeout: 10), "a quick chip with events is shown")
        chip.tap()
        let badge = el(app, "home.card.almostFull")
        XCTAssertTrue(badge.waitForExistence(timeout: 5))
        XCTAssertEqual(badge.label, "ALMOST FULL · 2 LEFT")
        XCTAssertTrue(app.buttons["Fixture host supper"].firstMatch.exists)
        XCTAssertFalse(app.buttons["Fixture rooftop set"].firstMatch.exists, "6 of 20 is not almost full")
    }

    // MARK: Filter sheet

    private func checkFilters(theme: String) {
        let app = launch("home", theme: theme, extra: ["-uiFixtureFilters", "YES"])
        let apply = el(app, "home.filter.apply")
        XCTAssertTrue(apply.waitForExistence(timeout: 20))
        XCTAssertTrue(el(app, "home.filter.date.weekend").exists)
        XCTAssertTrue(el(app, "home.filter.forTwo").exists)
        Thread.sleep(forTimeInterval: 0.8)
        shot("filters-\(theme)")
        let before = apply.label
        el(app, "home.filter.cat.gallery").tap()
        XCTAssertNotEqual(apply.label, before, "the CTA count follows the draft")
        apply.tap()
        XCTAssertTrue(apply.waitForNonExistence(timeout: 5), "the sheet closes on apply")
        XCTAssertTrue(el(app, "home.filtersButton").label.contains("1"), "badge counts the active filter")
    }

    func testFilterSheetLight() { checkFilters(theme: "light") }
    func testFilterSheetDark() { checkFilters(theme: "dark") }

    // MARK: Search

    private func checkSearch(theme: String) {
        let idle = launch("search", theme: theme)
        XCTAssertTrue(el(idle, "search.input").waitForExistence(timeout: 20))
        XCTAssertTrue(el(idle, "search.cat.supper").exists)
        Thread.sleep(forTimeInterval: 0.8)
        shot("search-idle-\(theme)")
        idle.terminate()
        let app = launch("search", theme: theme, extra: ["-uiFixtureSearch", "fixture"])
        XCTAssertTrue(el(app, "search.group.events").waitForExistence(timeout: 20))
        XCTAssertTrue(el(app, "search.seeOnMap").exists)
        Thread.sleep(forTimeInterval: 0.8)
        shot("search-results-\(theme)")
    }

    func testSearchLight() { checkSearch(theme: "light") }
    func testSearchDark() { checkSearch(theme: "dark") }

    // MARK: Create flow recipe

    private func checkCreate(theme: String) {
        let app = launch("create", theme: theme, extra: ["-uiFixtureBench", "YES"])
        let meter = el(app, "create.recipeMeter")
        XCTAssertTrue(meter.waitForExistence(timeout: 20), "the recipe meter sits under the step bar")
        XCTAssertTrue(el(app, "create.goal.fill_seats").exists, "goal pills on Basics")
        Thread.sleep(forTimeInterval: 1.0)
        shot("create-basics-\(theme)")
        meter.tap()
        XCTAssertTrue(el(app, "recipe.photos").waitForExistence(timeout: 5), "the sheet lists the ingredients")
        Thread.sleep(forTimeInterval: 0.8)
        shot("create-recipe-sheet-\(theme)")
        el(app, "create.recipe.close").tap()
        // Basics → When & where → Tickets.
        XCTAssertTrue(el(app, "create.step.next").waitForExistence(timeout: 5))
        el(app, "create.step.next").tap()
        Thread.sleep(forTimeInterval: 0.6)
        shot("create-when-\(theme)")
        el(app, "create.step.next").tap()
        XCTAssertTrue(el(app, "create.priceMarket").waitForExistence(timeout: 5), "benchmarks draw the price market")
        Thread.sleep(forTimeInterval: 0.6)
        shot("create-tickets-\(theme)")
        app.swipeUp()
        XCTAssertTrue(el(app, "create.outcome").waitForExistence(timeout: 5), "live outcome estimate")
        Thread.sleep(forTimeInterval: 0.6)
        shot("create-tickets-outcome-\(theme)")
    }

    func testCreateRecipeLight() { checkCreate(theme: "light") }
    func testCreateRecipeDark() { checkCreate(theme: "dark") }

}
