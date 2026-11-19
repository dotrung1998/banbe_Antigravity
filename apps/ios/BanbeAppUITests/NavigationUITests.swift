import XCTest

/// Smoke coverage for the screens and the navigation between them — the
/// iOS counterpart of the web app's Playwright suite. Each screen names
/// itself with a `screen.<name>` accessibility identifier (see RootView)
/// and the controls carry stable ids, the same way the web screens use
/// data-screen-label / data-testid rather than display copy (which is
/// bilingual and would break when the language changes).
///
/// These deliberately avoid anything needing a signed-in session: the
/// signed-out paths behave identically on every machine.
final class NavigationUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// Launches straight into the feed, past onboarding.
    @discardableResult
    private func launchToHome() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-banbe.onboarded", "YES"]
        app.launch()
        XCTAssertTrue(app.otherElements["screen.home"].waitForExistence(timeout: 15),
                      "Expected the feed to be the first screen")
        return app
    }

    func testOnboardingRunsThroughLanguageAndTheme() {
        let app = XCUIApplication()
        app.launchArguments += ["-banbe.onboarded", "NO"]
        app.launch()

        // The splash auto-advances after a moment; tapping skips the wait.
        if app.otherElements["screen.splash"].waitForExistence(timeout: 3) {
            app.tap()
        }
        XCTAssertTrue(app.otherElements["screen.langPick"].waitForExistence(timeout: 10))

        app.buttons["lang.vi"].tap()
        XCTAssertTrue(app.otherElements["screen.themePick"].waitForExistence(timeout: 5))

        app.buttons["theme.dark"].tap()
        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(app.otherElements["screen.home"].waitForExistence(timeout: 5))
    }

    /// Home's controls sit below the fold, and the bottom of the window is the
    /// dock's own strip — a tap there lands on the dock, not the row. Scroll
    /// until the element is really on screen and clear of that strip.
    private func reveal(_ app: XCUIApplication, _ element: XCUIElement, swipes: Int = 8) {
        for _ in 0..<swipes {
            guard element.exists else { app.swipeUp(); continue }
            if element.frame.midY > 120 && element.frame.midY < 620 { return }
            app.swipeUp()
        }
        // One swipe too far puts the row under the top band; bring it back once.
        if element.exists && element.frame.midY < 120 { app.swipeDown() }
    }

    /// The hero card's identifier is repeated on its own labels, so the card
    /// rows in the shortlist (one button per event) are what a tap uses — they
    /// sit under the hero and are scrolled into view first, like a reader would.
    private func openFeedEvent(_ app: XCUIApplication) {
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "home.hero.card.bepnho").firstMatch
                        .waitForExistence(timeout: 45), "Expected the catalogue feed to render")
        let row = app.buttons["home.event.bepnho"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Expected the shortlist to render")
        reveal(app, row)
        XCTAssertTrue(row.isHittable, "Expected the shortlist row on screen")
        row.tap()
        XCTAssertTrue(app.otherElements["screen.event"].waitForExistence(timeout: 15))
    }

    func testFeedOpensAnEventAndComesBack() {
        let app = launchToHome()
        openFeedEvent(app)

        // Detail shows what the row doesn't — the hero title and the price strip.
        let heroTitle = app.descendants(matching: .any).matching(identifier: "event.heroTitle").firstMatch
        XCTAssertTrue(heroTitle.waitForExistence(timeout: 5), "Expected the detail hero title")
        let priceStrip = app.descendants(matching: .any).matching(identifier: "event.priceStrip").firstMatch
        XCTAssertTrue(priceStrip.waitForExistence(timeout: 5), "Expected the ticket stub")

        app.buttons["event.back"].tap()
        XCTAssertTrue(app.otherElements["screen.home"].waitForExistence(timeout: 5))
    }

    func testEventOpensTheOrganizerPage() {
        let app = launchToHome()
        openFeedEvent(app)

        // The host cards live on the Host tab of the v2.3 page, so open it and
        // scroll the row into view first — same as for a real user.
        let hostTab = app.buttons["event.tab.host"]
        XCTAssertTrue(hostTab.waitForExistence(timeout: 10), "Expected the Event Detail tabs")
        reveal(app, hostTab)
        hostTab.tap()
        let organizerRow = app.buttons["event.organizer"]
        XCTAssertTrue(organizerRow.waitForExistence(timeout: 10))
        reveal(app, organizerRow)
        organizerRow.tap()

        // The standalone organizer page is retired: the row opens the
        // organizer profile (resolved from the event's organizer id). A host
        // account opens the organizer profile; a member-hosted event opens the
        // public profile.
        let profile = app.otherElements["screen.organizerProfile"].waitForExistence(timeout: 10)
            || app.otherElements["screen.publicProfile"].waitForExistence(timeout: 5)
        XCTAssertTrue(profile, "Expected the host profile to open")
    }

    func testCategoryFilterNarrowsTheFeed() {
        let app = launchToHome()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "home.hero.card.bepnho").firstMatch
                        .waitForExistence(timeout: 45), "Expected the catalogue feed to render")

        // The shortlist's summary line opens Home's own filter sheet; the
        // category pills live there.
        let summary = app.buttons["home.filterSummary"]
        // Full-screen swipes overshoot this page by ~700 pt; drag in smaller
        // steps so the row lands in the middle of the window, not under a band.
        let grab = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        let drop = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.46))
        for _ in 0..<14 {
            guard summary.exists else { grab.press(forDuration: 0.05, thenDragTo: drop); continue }
            let y = summary.frame.midY
            if y >= 220 && y <= 620 { break }
            if y < 220 {
                grab.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92)))
            } else {
                grab.press(forDuration: 0.05, thenDragTo: drop)
            }
        }
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "Expected the shortlist summary line")
        summary.tap()

        let sheet = app.descendants(matching: .any).matching(identifier: "home.filterSheet").firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "Expected the filter sheet")

        // The sheet shows unified Type tiles behind `unified_discovery` and the
        // legacy Category pills without it; tap whichever this build renders.
        let categoryGallery = app.buttons["home.filter.cat.gallery"]
        if categoryGallery.waitForExistence(timeout: 3) {
            categoryGallery.tap()
        } else {
            let typeGallery = app.buttons["home.filter.type.gallery"]
            XCTAssertTrue(typeGallery.waitForExistence(timeout: 5), "Expected a gallery filter")
            typeGallery.tap()
        }
        // The sheet's own CTA carries the live result count: a gallery-only
        // slice of the same For You list must be smaller than the whole.
        let apply = app.buttons["home.filter.apply"]
        let narrowed = Int(apply.value as? String ?? "") ?? 0
        XCTAssertGreaterThan(narrowed, 0, "Expected gallery events in the feed")
        XCTAssertLessThan(narrowed, 7, "Filter did not narrow the feed")
        apply.tap()

        // A supper club drops out of a gallery-only feed.
        XCTAssertTrue(waitForDisappearance(of: app.buttons["home.event.bepnho"], timeout: 10),
                      "Filter did not narrow the feed")
    }

    /// The area control is a native `Menu` (the same mechanism as the chat
    /// composer's "+" attach button), so "All locations" is one of its rows and
    /// the searchable hierarchy is reachable through its "Search locations…"
    /// row. Both paths are driven here so a regression in either one — a menu
    /// that no longer opens, a selection that no longer filters the feed —
    /// fails this test.
    func testAreaSheetOpensAndFiltersTheFeed() {
        let app = launchToHome()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "home.hero.card.bepnho").firstMatch.waitForExistence(timeout: 45))

        // 1. The menu itself.
        app.buttons["header.area"].tap()
        let searchRow = app.buttons["area.search"]
        XCTAssertTrue(searchRow.waitForExistence(timeout: 5), "Area menu did not open")
        searchRow.tap()

        // 2. Pick a district through the searchable list.
        let target = app.buttons["area.thaodien"]
        XCTAssertTrue(target.waitForExistence(timeout: 5), "Searchable location list did not open")
        target.tap()
        XCTAssertTrue(waitForDisappearance(of: app.buttons["area.thaodien"]))
        // The area chip names the chosen district, and Bình Thạnh events are
        // gone from the feed.
        let areaButton = app.buttons["header.area"]
        XCTAssertTrue(areaButton.label.contains("Thảo Điền"), "Area chip did not take: \(areaButton.label)")
        XCTAssertTrue(waitForDisappearance(of: app.descendants(matching: .any)
                        .matching(identifier: "home.hero.card.bepnho").firstMatch, timeout: 10))

        // 3. Back to "All locations" from the menu's own first row.
        app.buttons["header.area"].tap()
        let all = app.buttons["area.all"]
        XCTAssertTrue(all.waitForExistence(timeout: 5), "Area menu did not reopen")
        all.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "home.hero.card.bepnho").firstMatch.waitForExistence(timeout: 15),
                      "Choosing All locations did not restore the full feed")
    }


    func testAccountAndPreferencesSwitchLanguage() {
        let app = launchToHome()
        app.buttons["tab.profile"].firstMatch.tap()
        XCTAssertTrue(app.otherElements["screen.profile"].waitForExistence(timeout: 5))

        app.buttons["account.preferences"].tap()
        XCTAssertTrue(app.otherElements["screen.preferences"].waitForExistence(timeout: 5))

        // Switching to English retitles the screen in place.
        app.buttons["pref.lang.en"].tap()
        XCTAssertTrue(app.staticTexts["Language & appearance"].waitForExistence(timeout: 5))

        // Put it back, so a rerun starts from the same place.
        app.buttons["pref.lang.vi"].tap()
        XCTAssertTrue(app.staticTexts["Ngôn ngữ & hiển thị"].waitForExistence(timeout: 5))
    }

    /// Security used to be a subsection buried inside Language & appearance;
    /// it's its own row on Account and its own screen now.
    func testSecurityIsItsOwnScreenOffAccount() {
        let app = launchToHome()
        let account = app.buttons["tab.profile"].firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 15), "Expected the dock to render")
        account.tap()
        XCTAssertTrue(app.otherElements["screen.profile"].waitForExistence(timeout: 5))

        // A host account opens on the Host tab; these rows live on Personal.
        let personal = app.buttons["account.tab.personal"]
        if personal.waitForExistence(timeout: 3) { personal.tap() }

        // It is no longer reachable from inside the Settings group.
        let more = app.buttons["account.moreSettings"]
        reveal(app, more, swipes: 8)
        XCTAssertTrue(more.waitForExistence(timeout: 5), "Expected the Settings group row")
        more.tap()
        XCTAssertTrue(app.otherElements["screen.accountGroup"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Bảo mật"].exists)
        app.buttons["accountGroup.back"].tap()
        XCTAssertTrue(app.otherElements["screen.profile"].waitForExistence(timeout: 5))

        // It is reachable as its own row, and back returns to Account.
        let security = app.buttons["account.security"]
        reveal(app, security, swipes: 8)
        XCTAssertTrue(security.waitForExistence(timeout: 5), "Expected the Security row")
        security.tap()
        XCTAssertTrue(app.otherElements["screen.security"].waitForExistence(timeout: 5))
        app.buttons["security.back"].firstMatch.tap()
        XCTAssertTrue(app.otherElements["screen.profile"].waitForExistence(timeout: 5))
    }

    func testDarkThemeRepaintsTheApp() {
        let app = launchToHome()
        app.buttons["tab.profile"].firstMatch.tap()
        app.buttons["account.preferences"].tap()
        XCTAssertTrue(app.otherElements["screen.preferences"].waitForExistence(timeout: 5))

        app.buttons["pref.theme.dark"].tap()
        // Nothing to assert on colour directly, but the screen must survive
        // the repaint and stay interactive.
        XCTAssertTrue(app.buttons["pref.theme.light"].waitForExistence(timeout: 5))
        app.buttons["pref.theme.light"].tap()
        XCTAssertTrue(app.otherElements["screen.preferences"].exists)
    }

    /// The submit button is the app's promise that the address can be sent
    /// to, so it stays away until the format actually holds up — and says
    /// why rather than just sitting there greyed out.
    func testLoginHidesSubmitUntilTheEmailLooksLikeAnEmail() throws {
        let app = launchToHome()
        app.buttons["tab.profile"].firstMatch.tap()
        XCTAssertTrue(app.otherElements["screen.profile"].waitForExistence(timeout: 5))

        let signIn = app.buttons["account.signIn"]
        try XCTSkipUnless(signIn.waitForExistence(timeout: 3), "Already signed in on this simulator")
        signIn.tap()
        XCTAssertTrue(app.otherElements["screen.login"].waitForExistence(timeout: 5))

        let email = app.textFields["login.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))

        // Untouched: nothing to submit yet, nothing to complain about either.
        XCTAssertFalse(app.buttons["login.submit"].exists)
        XCTAssertFalse(app.staticTexts["login.emailError"].exists)

        // Rejected by the server's own pattern, so the button must not offer.
        email.tap()
        for bad in ["not-an-email", "a@b"] {
            email.press(forDuration: 1.1)
            if app.menuItems["Select All"].waitForExistence(timeout: 2) {
                app.menuItems["Select All"].tap()
            }
            email.typeText(bad)
            XCTAssertTrue(app.staticTexts["login.emailError"].waitForExistence(timeout: 3),
                          "Expected a format complaint for \(bad)")
            XCTAssertFalse(app.buttons["login.submit"].exists,
                           "Submit should stay hidden for \(bad)")
        }

        // A real address brings the button back and clears the complaint.
        email.press(forDuration: 1.1)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) {
            app.menuItems["Select All"].tap()
        }
        email.typeText("ban@email.com")
        XCTAssertTrue(app.buttons["login.submit"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["login.emailError"].exists)
    }

    func testSignedOutAccountOffersSignIn() throws {
        let app = launchToHome()
        app.buttons["tab.profile"].firstMatch.tap()
        XCTAssertTrue(app.otherElements["screen.profile"].waitForExistence(timeout: 5))

        // Only meaningful signed out; a restored session makes this a no-op.
        let signIn = app.buttons["account.signIn"]
        try XCTSkipUnless(signIn.waitForExistence(timeout: 3), "Already signed in on this simulator")

        signIn.tap()
        XCTAssertTrue(app.otherElements["screen.login"].waitForExistence(timeout: 5))
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval = 8) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: element
        )
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
