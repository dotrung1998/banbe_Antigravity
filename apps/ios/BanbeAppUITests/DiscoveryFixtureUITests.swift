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
        XCTAssertTrue(el(app, "header.lang").exists, "EN/VN quick switch sits beside the location pill")
        XCTAssertTrue(el(app, "header.theme").exists, "Light/Dark quick switch sits beside the location pill")
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

    /// Note 71 (Calm Pass phase 3): with `polaroid_cards` on, the card keeps its photo identifier, Save button and
    /// caption, and both themes render (screenshots for review). Largest accessibility text must not truncate the
    /// whole caption away: the event is still reachable by name.
    private func checkPolaroid(theme: String, extra: [String] = []) {
        let app = launch("home", theme: theme, extra: ["-uiFixturePolaroid", "YES", "-uiFixtureSimpleShell", "YES"] + extra)
        XCTAssertTrue(el(app, "home.searchBar").waitForExistence(timeout: 20))
        if el(app, "home.layout.cards").exists { el(app, "home.layout.cards").tap() }
        XCTAssertTrue(app.buttons["Fixture host supper"].firstMatch.waitForExistence(timeout: 10))
        let photo = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'card.'")).firstMatch
        XCTAssertTrue(photo.exists, "card.<key> stays on the photo")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'home.save.'")).firstMatch.exists)
        Thread.sleep(forTimeInterval: 1.0)
        shot("home-polaroid-\(theme)\(extra.isEmpty ? "" : "-xxl")")
    }

    func testPolaroidCardsLight() { checkPolaroid(theme: "light") }
    func testPolaroidCardsDark() { checkPolaroid(theme: "dark") }
    func testPolaroidCardsLargestText() {
        checkPolaroid(theme: "light", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
    }

    /// Note 71 phase 4: Vietnamese (the longest copy) at the largest accessibility text size. The guided Coming up
    /// state wraps instead of clipping and the screen never scrolls sideways.
    func testHostHomeVietnameseLargestText() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiFixture", "shell.home", "-banbe.lang", "vi", "-banbe.theme", "light", "-uiTesting", "1",
                                "-banbe.onboarded", "YES", "-uiFixtureSimpleShell", "YES", "-uiFixtureHostMode", "YES",
                                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let upcoming = el(app, "home.host.upcoming")
        XCTAssertTrue(el(app, "home.modeSwitch").waitForExistence(timeout: 20))
        for _ in 0..<6 where !upcoming.isHittable { app.swipeUp() }
        XCTAssertTrue(upcoming.exists)
        let screen = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(upcoming.frame.minX, screen.minX - 1, "no sideways overflow")
        XCTAssertLessThanOrEqual(upcoming.frame.maxX, screen.maxX + 1, "no sideways overflow")
        XCTAssertLessThanOrEqual(el(app, "home.modeSwitch").frame.maxX, screen.maxX + 1, "the mode switch fits")
        Thread.sleep(forTimeInterval: 0.6)
        shot("host-home-vi-xxxl")
    }

    /// Note 71 (Calm Pass phase 1): Hosting Home on the fixture host ends in Coming up and the numbers, never blank.
    func testHostHomeNeverEndsBlank() {
        for theme in ["light", "dark"] {
            let app = launch("home", theme: theme, extra: ["-uiFixtureSimpleShell", "YES", "-uiFixtureHostMode", "YES"])
            XCTAssertTrue(el(app, "home.host.quick").waitForExistence(timeout: 20))
            XCTAssertTrue(el(app, "home.host.upcoming").waitForExistence(timeout: 5), "Coming up always shows something")
            Thread.sleep(forTimeInterval: 1.0)
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.6)
            shot("host-home-\(theme)")
            app.terminate()
        }
    }
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

    /// Sort is its own pop-up with ONLY the sort options (not the filter sheet).
    func testSortButtonOpensSortMenuOnly() {
        let app = launch("home")
        XCTAssertTrue(el(app, "home.title").waitForExistence(timeout: 20))
        el(app, "home.sortButton").tap()
        XCTAssertTrue(el(app, "home.sort.price").waitForExistence(timeout: 5), "sort options are listed")
        XCTAssertFalse(el(app, "home.filterSheet").exists, "the filter sheet must not open")
        el(app, "home.sort.price").tap()
        XCTAssertFalse(el(app, "home.sort.price").waitForExistence(timeout: 2), "the menu closes after a pick")
        XCTAssertFalse(el(app, "home.filtersButton").label.contains("1"), "sort does not count as a filter")
    }

    /// A category picked on the main row is already ticked when the filter sheet opens, and the other
    /// categories stay available (they used to show 0 and disable, because the sheet only saw the filtered feed).
    func testCategoryPickedOnHomeIsPreselectedInSheet() {
        let app = launch("home")
        XCTAssertTrue(el(app, "home.title").waitForExistence(timeout: 20))
        el(app, "filter.gallery").tap()
        el(app, "home.filtersButton").tap()
        let gallery = el(app, "home.filter.cat.gallery")
        XCTAssertTrue(gallery.waitForExistence(timeout: 5))
        XCTAssertTrue(gallery.isSelected, "the Home category is pre-selected")
        let music = el(app, "home.filter.cat.music")
        XCTAssertTrue(music.exists)
        XCTAssertTrue(music.isEnabled, "other categories are not disabled")
    }

    /// The location picker slides up OVER the filter sheet; "Done" slides it down and the sheet (with its draft) is still there.
    func testLocationPickerOverlaysFilterSheetAndDoneReturns() {
        let app = launch("home", extra: ["-uiFixtureFilters", "YES"])
        XCTAssertTrue(el(app, "home.filter.apply").waitForExistence(timeout: 20))
        el(app, "home.filter.cat.gallery").tap() // a draft change that must survive the picker
        el(app, "home.filter.area").tap()
        let done = el(app, "home.filter.area.done")
        XCTAssertTrue(done.waitForExistence(timeout: 5), "the picker opens with a Done button")
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5), "Done dismisses the picker")
        XCTAssertTrue(el(app, "home.filter.apply").waitForExistence(timeout: 5), "the filter sheet is still open")
        XCTAssertTrue(el(app, "home.filter.cat.gallery").isSelected, "the draft was kept")
    }

    /// The pinned For You chip sits in the same row as Filters / Sort and is vertically centred with them (it used
    /// to be ~8pt shorter). XCUITest reports the chip's inner star icon as the element frame, so this checks the
    /// centre line, and the screenshot shows the height.
    func testForYouChipIsAlignedWithOtherChips() {
        let app = launch("home", extra: ["-uiFixtureForYou", "YES"])
        XCTAssertTrue(el(app, "home.title").waitForExistence(timeout: 20))
        let forYou = app.buttons["filter.foryou"].firstMatch
        XCTAssertTrue(forYou.waitForExistence(timeout: 10), "For You chip is shown for an account with preferences")
        let filters = app.buttons["home.filtersButton"].firstMatch
        Thread.sleep(forTimeInterval: 0.6)
        shot("home-foryou-chip")
        XCTAssertEqual(forYou.frame.midY, filters.frame.midY, accuracy: 1.0, "For You \(forYou.frame) vs Filters \(filters.frame)")
    }

    // MARK: Pulse ticker (note 51)

    /// Pulse is one slim ticker line at the top of the feed, above the categories, and tapping it opens the viewer.
    func testPulseTickerSitsAtTopAndOpensViewer() {
        let app = launch("home", extra: ["-uiFixturePulse", "YES"])
        XCTAssertTrue(el(app, "home.title").waitForExistence(timeout: 20))
        let ticker = app.buttons["home.pulseTicker"].firstMatch
        XCTAssertTrue(ticker.waitForExistence(timeout: 10))
        XCTAssertLessThanOrEqual(ticker.frame.height, 44, "one slim line")
        let screenW = app.windows.firstMatch.frame.width
        XCTAssertLessThanOrEqual(ticker.frame.maxX, screenW - 8, "the capsule stays inside the screen (its text must not widen it)")
        XCTAssertGreaterThanOrEqual(ticker.frame.minX, 8)
        XCTAssertTrue(ticker.label.contains("Gallery walk Bình Thạnh"), "the label lists the ranked events: \(ticker.label)")
        XCTAssertEqual(ticker.value as? String, "3")
        XCTAssertLessThan(ticker.frame.maxY, app.buttons["filter.supper"].firstMatch.frame.minY, "above the category row")
        XCTAssertFalse(el(app, "home.storyAvatar").exists, "no stories: no story row")
        Thread.sleep(forTimeInterval: 0.6)
        shot("home-pulse-ticker")
        ticker.tap()
        XCTAssertTrue(el(app, "pulse.close").waitForExistence(timeout: 6), "the Pulse viewer opens")
    }

    /// Without any ranking the ticker is a static invitation, not an empty box, and it is still tappable.
    func testPulseTickerWithoutRankingIsAStaticInvitation() {
        let app = launch("home")
        XCTAssertTrue(el(app, "home.title").waitForExistence(timeout: 20))
        XCTAssertTrue(el(app, "home.pulseTicker.empty").waitForExistence(timeout: 10))
        app.buttons["home.pulseTicker"].firstMatch.tap()
        XCTAssertTrue(el(app, "pulse.close").waitForExistence(timeout: 6))
    }

    // MARK: Rewards switch (note 51)

    /// An admin hid Rewards & badges: no streak/coins capsule on Home (and it is there when the switch is on).
    func testRewardsSwitchOffHidesTheHomeCapsule() {
        let on = launch("home")
        XCTAssertTrue(el(on, "home.title").waitForExistence(timeout: 20))
        XCTAssertTrue(el(on, "home.coins").waitForExistence(timeout: 5), "capsule is shown while the switch is on")
        on.terminate()
        let off = launch("home", extra: ["-uiFixtureRewards", "off"])
        XCTAssertTrue(el(off, "home.title").waitForExistence(timeout: 20))
        XCTAssertFalse(el(off, "home.coins").waitForExistence(timeout: 3), "capsule is hidden")
        XCTAssertFalse(el(off, "home.streak").exists)
        XCTAssertTrue(el(off, "header.area").exists, "the rest of the header is intact")
    }

    /// The admin screen shows the state, flips it, and Account loses the Rewards row.
    func testAdminFeatureSwitchFlipsState() {
        let app = launch("adminFeatures")
        // Note 64: categories start collapsed; the switch rows only exist once their group is open.
        let group = el(app, "adminFeatures.cat.rewards")
        XCTAssertTrue(group.waitForExistence(timeout: 20))
        XCTAssertFalse(el(app, "adminFeatures.rewards.state").exists)
        group.tap()
        let state = el(app, "adminFeatures.rewards.state")
        XCTAssertTrue(state.waitForExistence(timeout: 20))
        XCTAssertEqual(state.label, "Visible to everyone")
        let sw = el(app, "adminFeatures.rewards.switch")
        XCTAssertEqual(sw.value as? String, "on")
        sw.tap()
        XCTAssertTrue(NSPredicate(format: "label == 'Hidden from everyone'").evaluate(with: state) || state.waitForExistence(timeout: 2))
        let flipped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Hidden from everyone'"), object: state)
        XCTAssertEqual(XCTWaiter().wait(for: [flipped], timeout: 5), .completed)
        XCTAssertEqual(el(app, "adminFeatures.rewards.switch").value as? String, "off")
        shot("admin-feature-switches")
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
        // Note 53: Create opens on step 1 (Host, already ticked); one tap to Basics.
        XCTAssertTrue(el(app, "create.hostPrefilled").exists)
        el(app, "create.step.next").tap()
        XCTAssertTrue(el(app, "create.goal.fill_seats").waitForExistence(timeout: 5), "goal pills on Basics")
        Thread.sleep(forTimeInterval: 1.0)
        shot("create-basics-\(theme)")
        meter.tap()
        XCTAssertTrue(el(app, "recipe.photos").waitForExistence(timeout: 5), "the sheet lists the ingredients")
        Thread.sleep(forTimeInterval: 0.8)
        shot("create-recipe-sheet-\(theme)")
        el(app, "create.recipe.close").tap()
        // Basics (its parts, note 69) → When & where → Tickets.
        XCTAssertTrue(el(app, "create.step.next").waitForExistence(timeout: 5))
        let market = el(app, "create.priceMarket")
        for _ in 0..<10 where !market.exists {
            let next = el(app, "create.step.next")
            for _ in 0..<6 where !next.isHittable { app.swipeUp() }
            next.tap()
            Thread.sleep(forTimeInterval: 0.6)
            if el(app, "create.dateTime").exists { shot("create-when-\(theme)") }
        }
        XCTAssertTrue(market.waitForExistence(timeout: 5), "benchmarks draw the price market")
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
