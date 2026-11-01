import XCTest

/// Map redesign phase 2 (web twin: tests/map-viewport.spec.js): the explored map area defines the results. Uses the
/// DEBUG `shell.map` fixture (opens straight on the Map; live public events), so no sign-in is needed.
final class MapViewportUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-banbe.onboarded", "YES", "-uiFixture", "shell.map"]
        app.launch()
        return app
    }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    /// Every result is in exactly one marker: pins count 1, clusters, stacks and city bubbles their value.
    private func markerTotal(_ app: XCUIApplication) -> Int {
        let any = app.descendants(matching: .any)
        let pins = any.matching(NSPredicate(format: "identifier BEGINSWITH 'map.pin.'")).count
        let groups = any.matching(NSPredicate(format: "identifier BEGINSWITH 'map.cluster.' OR identifier BEGINSWITH 'map.stack.' OR identifier BEGINSWITH 'map.cityBubble.'"))
        let grouped = (0..<groups.count).reduce(0) { $0 + (Int(groups.element(boundBy: $1).value as? String ?? "0") ?? 0) }
        return pins + grouped
    }

    private func count(_ app: XCUIApplication) -> String {
        app.staticTexts["map.resultCount"].label
    }

    private func waitForCount(_ app: XCUIApplication) -> String {
        let label = app.staticTexts["map.resultCount"]
        XCTAssertTrue(label.waitForExistence(timeout: 30))
        let settled = NSPredicate(format: "label MATCHES %@", ".*\\d+ (sự kiện|events?).*")
        expectation(for: settled, evaluatedWith: label)
        waitForExpectations(timeout: 30)
        return label.label
    }

    func testFirstOpenFramesResultsAndPinsMatchTheCount() throws {
        let app = launch()
        let text = waitForCount(app)
        let n = Int(text.components(separatedBy: CharacterSet.decimalDigits.inverted).first { !$0.isEmpty } ?? "0") ?? 0
        XCTAssertGreaterThan(n, 0, "first open should frame the relevant events, not an empty part of the world")
        XCTAssertEqual(markerTotal(app), n, "markers and count come from the same results")
        XCTAssertFalse(app.buttons["map.searchHere"].exists, "results follow the map; no Search here button")
    }

    func testPanningFarAwayCommitsANewAreaAndShowNearestBringsResultsBack() throws {
        let app = launch()
        let before = waitForCount(app)
        // Fling the map far east several times (a user gesture): the area changes once each settle.
        let map = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        for _ in 0..<4 {
            map.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.3)))
        }
        let changed = NSPredicate(format: "label != %@", before)
        expectation(for: changed, evaluatedWith: app.staticTexts["map.resultCount"])
        waitForExpectations(timeout: 10)
        // Panning dropped the sheet to peek (note 73); tap the strip's summary to bring the list (and its empty state)
        // back (its chip row has its own taps, note 74).
        let peek = el(app, "map.peekSummary")
        if peek.waitForExistence(timeout: 3) { peek.tap() }
        let nearest = app.buttons["map.showNearest"]
        if nearest.waitForExistence(timeout: 3) {
            nearest.tap()
            let back = NSPredicate(format: "NOT (label BEGINSWITH '0 ')")
            expectation(for: back, evaluatedWith: app.staticTexts["map.resultCount"])
            waitForExpectations(timeout: 10)
        }
    }

    // MARK: Phase 3 — shared, contextual filters

    func testTimeChipFiltersInPlaceAndPinsFollowTheCount() throws {
        let app = launch()
        _ = waitForCount(app)
        let weekend = app.buttons["map.weekend"]
        XCTAssertTrue(weekend.waitForExistence(timeout: 10))
        weekend.tap()
        XCTAssertTrue(weekend.isSelected, "the chip shows its state")
        sleep(1)
        let text = count(app)
        let n = Int(text.components(separatedBy: CharacterSet.decimalDigits.inverted).first { !$0.isEmpty } ?? "0") ?? 0
        XCTAssertEqual(markerTotal(app), n, "markers and count stay one list under a time filter")
        weekend.tap()
        XCTAssertFalse(weekend.isSelected)
    }

    func testFilterSheetCloseDiscardsAndApplyCommits() throws {
        let app = launch()
        let before = waitForCount(app)
        let filtersChip = app.buttons["map.filters"]
        XCTAssertTrue(filtersChip.waitForExistence(timeout: 10))
        filtersChip.tap()
        let week = app.buttons["home.filter.date.week"]
        XCTAssertTrue(week.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.filter.date.tonight"].exists, "Map offers Tonight")
        XCTAssertFalse(app.buttons["home.filter.area"].exists, "the map is the location")
        week.tap()
        app.buttons["home.filter.close"].tap()
        sleep(1)
        XCTAssertEqual(count(app), before, "Close discards the draft")
        XCTAssertFalse(app.buttons["map.filters"].label.contains("·"))

        app.buttons["map.filters"].tap()
        XCTAssertTrue(week.waitForExistence(timeout: 5))
        week.tap()
        let apply = app.buttons["home.filter.apply"]
        let shown = Int(apply.value as? String ?? "0") ?? 0
        try XCTSkipIf(shown == 0, "no live event in the next 7 days")
        apply.tap()
        sleep(1)
        XCTAssertTrue(count(app).hasPrefix("\(shown) "), "Show N is the resulting list")
        XCTAssertTrue(app.buttons["map.filters"].label.contains("· 1"))
    }

    // MARK: Phase 4 — price pins, clusters

    func testZoomedOutEventsClusterAndAClusterTapZoomsIn() throws {
        let app = launch()
        let before = waitForCount(app)
        // The MapKit view itself (not the first "other" element, which can be the dock).
        // SwiftUI's Map isn't an accessibility element of its own; a pinch that starts on a pin still reaches MapKit's
        // pinch recognizer (it lives on the map, the pin's ancestor).
        // XCUITest's smallest pinch scale depends on the touched element's size (0.40 for a pin), so 0.5 a few times.
        // Stops at the first cluster: further out (below city zoom, note 73) the markers become city bubbles.
        let groupMarker = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'map.cluster.' OR identifier BEGINSWITH 'map.cityBubble.'")).firstMatch
        for _ in 0..<4 {
            if groupMarker.exists { break }
            let anyMarker = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'map.pin.' OR identifier BEGINSWITH 'map.cluster.'")).firstMatch
            XCTAssertTrue(anyMarker.waitForExistence(timeout: 10))
            anyMarker.pinch(withScale: 0.5, velocity: -2)
            sleep(1)
        }
        let cluster = groupMarker
        XCTAssertTrue(cluster.waitForExistence(timeout: 10), "nearby events cluster (or join their city) when zoomed out")
        sleep(2)
        let text = count(app)
        let n = Int(text.components(separatedBy: CharacterSet.decimalDigits.inverted).first { !$0.isEmpty } ?? "0") ?? 0
        // After a pinch some results can sit under the mid sheet (still in the area, by design) and iOS leaves those
        // out of the accessibility snapshot; markers must never exceed the count (first open checks equality).
        let shown = markerTotal(app)
        XCTAssertTrue(shown > 0 && shown <= n, "clusters never add results: \(shown) of \(n)")
        _ = before
        cluster.tap()
        sleep(2)
        let after = count(app)
        let m = Int(after.components(separatedBy: CharacterSet.decimalDigits.inverted).first { !$0.isEmpty } ?? "0") ?? 0
        XCTAssertLessThanOrEqual(markerTotal(app), m)
    }

    func testPricePinsShowThePricePerTicket() throws {
        let app = launch()
        _ = waitForCount(app)
        let pin = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'map.pin.'")).firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 10))
        XCTAssertTrue(pin.label.contains("₫") || pin.label.contains("$") || pin.label.contains("Miễn phí") || pin.label.contains("Free"),
                      "a pin reads its price: \(pin.label)")
    }

    func testSelectingAPinRevealsItWithoutANewSearch() throws {
        let app = launch()
        let before = waitForCount(app)
        let pin = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'map.pin.'")).firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 10))
        pin.tap()
        sleep(3) // the reveal flight + its settle
        XCTAssertEqual(count(app), before, "a reveal never changes the area, the results or the count")
    }

    // MARK: Map v5 (note 73) — dock on demand, selection in the sheet, pan → peek, cities

    func testDockIsHiddenAtMidAndReturnsAtTall() throws {
        let app = launch()
        _ = waitForCount(app)
        // Opens at mid: the dock (its own window) is gone, so nothing covers the chips or the first rows.
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: el(app, "tab.home"))
        waitForExpectations(timeout: 6)
        // Swipe the sheet up from its non-scrolling header (the count line) to tall: the dock comes back.
        let count = app.staticTexts["map.resultCount"]
        count.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))
        XCTAssertTrue(el(app, "tab.home").waitForExistence(timeout: 6), "the dock shows at tall")
    }

    func testSelectingAPinPutsTheEventFirstInTheSheet() throws {
        let app = launch()
        _ = waitForCount(app)
        let pin = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'map.pin.'")).firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 10))
        pin.tap()
        XCTAssertTrue(el(app, "map.selectedRow").waitForExistence(timeout: 6), "the selection is a row in the sheet")
        XCTAssertFalse(el(app, "map.selectedCard").exists, "no floating card over the map any more")
        XCTAssertTrue(el(app, "map.selectedRow.details").exists)
        el(app, "map.selectedRow.close").tap()
        XCTAssertTrue(el(app, "map.selectedRow").waitForNonExistence(timeout: 5))
    }

    func testPanningDropsTheSheetToPeekWithTheFilterSummary() throws {
        let app = launch()
        _ = waitForCount(app)
        XCTAssertFalse(el(app, "map.peekSummary").exists, "opens at mid")
        // A short user drag on the map (above the mid sheet).
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.25))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.3)))
        XCTAssertTrue(el(app, "map.peekSummary").waitForExistence(timeout: 6), "a pan drops the sheet to peek")
        XCTAssertTrue(app.staticTexts["map.resultCount"].exists, "peek keeps the count")
        // Tapping the strip (its summary line) brings the list back at mid.
        el(app, "map.peekSummary").tap()
        XCTAssertTrue(app.buttons["map.filters"].waitForExistence(timeout: 6))
    }

    func testTypingACityOffersToFlyThere() throws {
        let app = launch()
        _ = waitForCount(app)
        let field = app.textFields["map.searchInput"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("sai gon")
        let city = el(app, "map.city.vn-hcm")
        XCTAssertTrue(city.waitForExistence(timeout: 6), "a city match is listed first")
        city.tap()
        XCTAssertFalse(el(app, "map.city.vn-hcm").waitForExistence(timeout: 2), "the query is cleared after flying there")
        _ = waitForCount(app)
        // Landed above city zoom: the city's own events, never its bubble again.
        sleep(2)
        let any = app.descendants(matching: .any)
        XCTAssertEqual(any.matching(NSPredicate(format: "identifier BEGINSWITH 'map.cityBubble.'")).count, 0,
                       "flying to a city never lands on its own bubble")
        let markers = any.matching(NSPredicate(format: "identifier BEGINSWITH 'map.pin.' OR identifier BEGINSWITH 'map.cluster.' OR identifier BEGINSWITH 'map.stack.'"))
        XCTAssertTrue(markers.firstMatch.waitForExistence(timeout: 5), "pins / clusters show after flying to the city")
    }

    // MARK: Map v6 (note 74) — city in the area tree, one tap, peek strip, peek → full, Large cards + photo pager

    /// A user pan on the map above the mid sheet: drops the sheet to peek.
    private func panToPeek(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.25))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.3)))
        XCTAssertTrue(el(app, "map.peekSummary").waitForExistence(timeout: 6), "a pan drops the sheet to peek")
    }

    func testAreaTreeShowsTheCityAndOneTapPicksIt() throws {
        let app = launch()
        _ = waitForCount(app)
        let chip = app.buttons["map.area"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        chip.tap()
        let city = el(app, "area.node.c:VN|ci:TP. Hồ Chí Minh")
        XCTAssertTrue(city.waitForExistence(timeout: 6), "Vietnam → TP. Hồ Chí Minh in the tree")
        XCTAssertTrue(el(app, "area.chevron.c:VN|ci:TP. Hồ Chí Minh").exists, "only the chevron expands")
        city.tap()
        XCTAssertTrue(el(app, "map.area.close").waitForNonExistence(timeout: 5), "one tap picks and closes")
        let label = app.buttons["map.area"].label
        XCTAssertTrue(label.contains("Hồ Chí Minh") || label.contains("Ho Chi Minh"), "the chip names the city: \(label)")
    }

    func testPeekStripHasSearchAndChipsAndAChipOpensMid() throws {
        let app = launch()
        _ = waitForCount(app)
        panToPeek(app)
        XCTAssertTrue(el(app, "map.peek.search").exists, "the search button is on the peek strip")
        XCTAssertTrue(el(app, "map.peek.allFilters").exists)
        let tonight = el(app, "map.peek.chip.tonight")
        XCTAssertTrue(tonight.exists)
        tonight.tap()
        XCTAssertTrue(app.buttons["map.filters"].waitForExistence(timeout: 6), "a chip applies and opens the list at mid")
        XCTAssertTrue(app.buttons["map.tonight"].isSelected)
    }

    func testPeekSearchButtonOpensTheSearchWithSuggestions() throws {
        let app = launch()
        _ = waitForCount(app)
        panToPeek(app)
        el(app, "map.peek.search").tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 8), "the keyboard is up")
        XCTAssertTrue(el(app, "map.search.suggestions").waitForExistence(timeout: 5), "never a blank search")
        XCTAssertTrue(el(app, "map.search.city.vn-hcm").exists)
        el(app, "map.search.cancel").tap()
        XCTAssertTrue(el(app, "map.peekSummary").waitForExistence(timeout: 6), "Cancel goes back to peek")
    }

    func testSwipingUpFromPeekLandsAtFullWithLargePhotoCards() throws {
        let app = launch()
        _ = waitForCount(app)
        panToPeek(app)
        el(app, "map.peekSummary").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)))
        let large = el(app, "map.layout.large")
        XCTAssertTrue(large.waitForExistence(timeout: 6), "one drag from peek lands at full")
        XCTAssertTrue(large.isSelected, "full opens on Large cards")
        // A photo pager on a large card: a sideways swipe changes the photo, never the screen / dock tab.
        let counter = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'photoPager.counter.'")).firstMatch
        XCTAssertTrue(counter.waitForExistence(timeout: 10), "large cards have a photo pager")
        let id = String(counter.identifier.dropFirst("photoPager.counter.".count))
        let before = counter.value as? String ?? ""
        el(app, "photoPager.\(id)").swipeLeft()
        sleep(1)
        XCTAssertNotEqual(el(app, "photoPager.counter.\(id)").value as? String ?? "", before, "the swipe paged the photos")
        XCTAssertTrue(el(app, "map.layout.large").exists, "still on the Map: a photo swipe never switches tabs")
        XCTAssertTrue(app.staticTexts["map.resultCount"].exists)
        // Compact list toggle.
        el(app, "map.layout.compact").tap()
        XCTAssertTrue(el(app, "map.layout.compact").isSelected)
    }
}
