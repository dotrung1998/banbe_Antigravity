import XCTest

/// Map redesign phase 2 + Map E+ (note 79, plan step 6; web twins: tests/map-viewport.spec.js, tests/map-eplus.spec.js):
/// the explored map area defines the results; the Map opens on neighbourhood bubbles, a bubble opens the area panel,
/// "List · N" opens the list layer, a pin or a row opens Event Detail. Uses the DEBUG `shell.map` fixture (opens
/// straight on the Map; live public events), so no sign-in is needed.
final class MapViewportUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-banbe.onboarded", "YES", "-uiFixture", "shell.map"]
        app.launch()
        return app
    }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func query(_ app: XCUIApplication, prefix: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
    }

    private func value(_ e: XCUIElement) -> Int { Int(e.value as? String ?? "0") ?? 0 }

    private func total(_ q: XCUIElementQuery) -> Int { (0..<q.count).reduce(0) { $0 + value(q.element(boundBy: $1)) } }

    /// Every result is in exactly one marker: pins count 1, clusters, stacks, city and area bubbles their value.
    private func markerTotal(_ app: XCUIApplication) -> Int {
        let pins = query(app, prefix: "map.pin.").count
        let groups = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH 'map.cluster.' OR identifier BEGINSWITH 'map.stack.' OR identifier BEGINSWITH 'map.cityBubble.' OR identifier BEGINSWITH 'map.areaBubble.'"))
        return pins + total(groups)
    }

    private func number(_ text: String) -> Int {
        Int(text.components(separatedBy: CharacterSet.decimalDigits.inverted).first { !$0.isEmpty } ?? "0") ?? 0
    }

    private func count(_ app: XCUIApplication) -> String { app.staticTexts["map.resultCount"].label }

    @discardableResult
    private func waitForCount(_ app: XCUIApplication) -> String {
        let label = app.staticTexts["map.resultCount"]
        XCTAssertTrue(label.waitForExistence(timeout: 30))
        let settled = NSPredicate(format: "label MATCHES %@", ".*\\d+ (sự kiện|events?).*")
        expectation(for: settled, evaluatedWith: label)
        waitForExpectations(timeout: 30)
        // Let the first-open flight and its commit finish: the area is what the rest of a test compares against.
        sleep(2)
        return label.label
    }

    /// The first bubble that stands for ONE neighbourhood (a merged "N areas" bubble has a "+" in its id).
    private func singleBubble(_ app: XCUIApplication) -> XCUIElement? {
        let q = query(app, prefix: "map.areaBubble.")
        for i in 0..<q.count {
            let b = q.element(boundBy: i)
            if !b.identifier.contains("+") && b.isHittable { return b }
        }
        return nil
    }

    private func openPanel(_ app: XCUIApplication) throws -> (bubble: Int, count: String) {
        let first = query(app, prefix: "map.areaBubble.").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 20), "the map opens on neighbourhood bubbles")
        let bubble = try XCTUnwrap(singleBubble(app), "a one-neighbourhood bubble to open")
        let n = value(bubble)
        let before = count(app)
        bubble.tap()
        XCTAssertTrue(el(app, "map.areaPanel").waitForExistence(timeout: 8), "a bubble tap opens its panel")
        sleep(3) // the opening flight and its settle
        return (n, before)
    }

    // MARK: First open, commits

    func testFirstOpenIsAreaLevelAndBubblesAddUpToTheCount() throws {
        let app = launch()
        let n = number(waitForCount(app))
        XCTAssertGreaterThan(n, 0, "first open should frame the relevant events, not an empty part of the world")
        XCTAssertTrue(query(app, prefix: "map.areaBubble.").firstMatch.waitForExistence(timeout: 15), "a fresh open shows neighbourhood bubbles")
        XCTAssertEqual(query(app, prefix: "map.pin.").count, 0, "never street level on a fresh open")
        XCTAssertEqual(markerTotal(app), n, "bubbles and count come from the same results")
        XCTAssertFalse(app.buttons["map.searchHere"].exists, "results follow the map; no Search here button")
        XCTAssertTrue(el(app, "map.top").exists, "the shared controls are on the map")
        XCTAssertTrue(app.textFields["map.searchInput"].exists, "the search field is always mounted")
        XCTAssertTrue(el(app, "tab.home").exists, "the dock stays at rest")
    }

    func testPanningFarAwayCommitsANewAreaAndShowNearestBringsResultsBack() throws {
        let app = launch()
        let before = waitForCount(app)
        // Fling the map far east several times (a user gesture): the area changes once each settle.
        let map = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        for _ in 0..<4 {
            map.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.4)))
        }
        let changed = NSPredicate(format: "label != %@", before)
        expectation(for: changed, evaluatedWith: app.staticTexts["map.resultCount"])
        waitForExpectations(timeout: 10)
        // Nothing in this part of the map: the same message floats above the buttons while the list is closed.
        let nearest = app.buttons["map.showNearest"]
        if nearest.waitForExistence(timeout: 5) {
            nearest.tap()
            let back = NSPredicate(format: "NOT (label BEGINSWITH '0 ')")
            expectation(for: back, evaluatedWith: app.staticTexts["map.resultCount"])
            waitForExpectations(timeout: 10)
        }
    }

    // MARK: The neighbourhood panel

    func testBubbleTapOpensThePanelAndNeverChangesTheCount() throws {
        let app = launch()
        _ = waitForCount(app)
        let (n, before) = try openPanel(app)
        let title = el(app, "map.areaPanel.title")
        XCTAssertTrue(title.exists)
        XCTAssertEqual(value(title), n, "the panel lists exactly the bubble's events")
        XCTAssertTrue(query(app, prefix: "map.areaItem.").count > 0, "its events are rows")
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: el(app, "tab.home"))
        waitForExpectations(timeout: 6)
        XCTAssertFalse(el(app, "map.listButton").exists, "the buttons step aside while the panel is open")
        XCTAssertEqual(count(app), before, "opening a panel never changes the area or the count")
        XCTAssertGreaterThan(query(app, prefix: "map.pin.").count, 0, "the area's events show as pins above the panel")

        el(app, "map.areaPanel.back").tap()
        XCTAssertTrue(el(app, "map.areaPanel").waitForNonExistence(timeout: 6))
        XCTAssertTrue(el(app, "tab.home").waitForExistence(timeout: 6), "the dock is back")
        XCTAssertTrue(el(app, "map.listButton").waitForExistence(timeout: 6))
        sleep(3)
        XCTAssertEqual(count(app), before, "closing it never changes the count either")
    }

    func testZoomingOutClosesThePanelAndTheViewStays() throws {
        let app = launch()
        _ = waitForCount(app)
        _ = try openPanel(app)
        let panel = el(app, "map.areaPanel")
        // A pinch with both fingers on the map: the DEBUG pad sits in the free band above the panel (touches pass through
        // to the map), so neither finger lands on the shared controls or on the panel, where a pinch turns into a drag.
        // The panel closes at half a level below `areaZoom`, so it takes one or two pinches from the opening zoom.
        let pad = el(app, "map.debug.pinchPad")
        XCTAssertTrue(pad.waitForExistence(timeout: 10))
        let zoom = el(app, "map.debug.zoom")
        let z0 = Double(zoom.value as? String ?? "") ?? 0
        for _ in 0..<4 where panel.exists {
            pad.pinch(withScale: 0.5, velocity: -2)
            sleep(2)
        }
        XCTAssertTrue(panel.waitForNonExistence(timeout: 8), "zooming out of the neighbourhood closes its panel")
        XCTAssertTrue(el(app, "tab.home").waitForExistence(timeout: 6), "and the dock returns")
        let z1 = Double(zoom.value as? String ?? "") ?? 99
        XCTAssertLessThan(z1, z0, "the map did zoom out")
        XCTAssertLessThan(z1, 13, "and it stayed zoomed out: closing the panel never flies back in")
    }

    func testAreaChipsAddUpToTheCountAndOneOpensItsPanel() throws {
        let app = launch()
        let n = number(waitForCount(app))
        let chips = query(app, prefix: "map.areaChip.")
        XCTAssertTrue(chips.firstMatch.waitForExistence(timeout: 15))
        XCTAssertEqual(total(chips), n, "every result is in exactly one neighbourhood chip")
        let chip = chips.firstMatch
        let k = value(chip)
        chip.tap()
        XCTAssertTrue(el(app, "map.areaPanel").waitForExistence(timeout: 8))
        XCTAssertEqual(value(el(app, "map.areaPanel.title")), k)
        XCTAssertFalse(chips.firstMatch.exists, "the chips are hidden while the panel is open")
    }

    func testPinTapOpensEventDetailDirectly() throws {
        let app = launch()
        _ = waitForCount(app)
        _ = try openPanel(app)
        // A pin in the free band above the panel (the panel covers the lower part of the screen).
        let pins = query(app, prefix: "map.pin.")
        XCTAssertTrue(pins.firstMatch.waitForExistence(timeout: 10))
        let pin = (0..<pins.count).map { pins.element(boundBy: $0) }
            .first { $0.isHittable && $0.frame.midY > 200 && $0.frame.midY < app.frame.height * 0.5 } ?? pins.firstMatch
        pin.tap()
        // The Map stays mounted under Event Detail's transition, so look for Event Detail itself.
        XCTAssertTrue(el(app, "event.heroTitle").waitForExistence(timeout: 10), "a pin opens Event Detail, no card first")
    }

    func testPricePinsShowThePricePerTicket() throws {
        let app = launch()
        _ = waitForCount(app)
        _ = try openPanel(app)
        let pin = query(app, prefix: "map.pin.").firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 10))
        XCTAssertTrue(pin.label.contains("₫") || pin.label.contains("$") || pin.label.contains("Miễn phí") || pin.label.contains("Free"),
                      "a pin reads its price: \(pin.label)")
    }

    // MARK: The list layer

    func testListButtonOpensTheListAndTheMapButtonAndAPullCloseIt() throws {
        let app = launch()
        let before = waitForCount(app)
        let n = number(before)
        let button = el(app, "map.listButton")
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        XCTAssertEqual(value(button), n, "List · N carries the result count")
        button.tap()
        let map = el(app, "map.list.mapButton")
        XCTAssertTrue(map.waitForExistence(timeout: 8), "the list layer opens with its Map button")
        XCTAssertTrue(el(app, "map.list.count").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "map.top").exists, "the shared controls stay over the list")
        XCTAssertEqual(count(app), before, "opening the list never changes the count")
        map.tap()
        XCTAssertTrue(el(app, "map.listButton").waitForExistence(timeout: 8), "the Map button returns to the map")
        sleep(1)
        XCTAssertEqual(count(app), before)

        // A pull down at the list's top closes it too: from over a card, and from over the header rows.
        for y in [0.06, 0.35] {
            el(app, "map.listButton").tap()
            XCTAssertTrue(el(app, "map.list.mapButton").waitForExistence(timeout: 8))
            let list = el(app, "map.list")
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: y))
            start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 320)), withVelocity: .slow, thenHoldForDuration: 0.1)
            XCTAssertTrue(el(app, "map.listButton").waitForExistence(timeout: 8), "a swipe down at the top returns to the map (from y \(y))")
            sleep(1)
            XCTAssertEqual(count(app), before)
        }
    }

    func testAListRowOpensEventDetail() throws {
        let app = launch()
        _ = waitForCount(app)
        el(app, "map.listButton").tap()
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'card.' OR identifier BEGINSWITH 'map.listItem.'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "rows exist while the list is open")
        rows.firstMatch.tap()
        XCTAssertTrue(el(app, "event.heroTitle").waitForExistence(timeout: 10), "a row opens Event Detail directly")
    }

    func testLargeCardsHaveAPhotoPagerAndCompactToggles() throws {
        let app = launch()
        _ = waitForCount(app)
        el(app, "map.listButton").tap()
        let large = el(app, "map.layout.large")
        XCTAssertTrue(large.waitForExistence(timeout: 8))
        XCTAssertTrue(large.isSelected, "the list opens on Large cards")
        // A photo pager on a large card: a sideways swipe changes the photo, never the screen / dock tab.
        let counter = query(app, prefix: "photoPager.counter.").firstMatch
        XCTAssertTrue(counter.waitForExistence(timeout: 10), "large cards have a photo pager")
        let id = String(counter.identifier.dropFirst("photoPager.counter.".count))
        let before = counter.value as? String ?? ""
        el(app, "photoPager.\(id)").swipeLeft()
        sleep(1)
        XCTAssertNotEqual(el(app, "photoPager.counter.\(id)").value as? String ?? "", before, "the swipe paged the photos")
        XCTAssertTrue(el(app, "map.layout.large").exists, "still on the Map: a photo swipe never switches tabs")
        el(app, "map.layout.compact").tap()
        XCTAssertTrue(el(app, "map.layout.compact").isSelected)
        XCTAssertTrue(query(app, prefix: "map.listItem.").firstMatch.waitForExistence(timeout: 5), "compact rows")
    }

    // MARK: Phase 3: shared, contextual filters

    func testFilterSheetCloseDiscardsAndApplyCommits() throws {
        let app = launch()
        let before = waitForCount(app)
        let filters = app.buttons["map.filterButton"]
        XCTAssertTrue(filters.waitForExistence(timeout: 10))
        filters.tap()
        // Map E+ (note 79): no date section here; the day and hours are the time bar's. Free is a filter that stays.
        let week = app.buttons["home.filter.free"]
        XCTAssertTrue(week.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["home.filter.date.week"].exists, "the day and hours are the time bar's")
        try XCTSkipUnless(week.isEnabled, "no free live event to filter on")
        XCTAssertFalse(app.buttons["home.filter.area"].exists, "the map is the location")
        week.tap()
        app.buttons["home.filter.close"].tap()
        sleep(1)
        XCTAssertEqual(count(app), before, "Close discards the draft")
        XCTAssertFalse(app.buttons["map.filterButton"].label.contains("1 on") || app.buttons["map.filterButton"].label.contains("1 đang bật"))

        app.buttons["map.filterButton"].tap()
        XCTAssertTrue(week.waitForExistence(timeout: 5))
        week.tap()
        let apply = app.buttons["home.filter.apply"]
        let shown = Int(apply.value as? String ?? "0") ?? 0
        try XCTSkipIf(shown == 0, "no free live event")
        apply.tap()
        sleep(1)
        XCTAssertTrue(count(app).hasPrefix("\(shown) "), "Show N is the resulting list")
        XCTAssertTrue(app.buttons["map.filterButton"].label.contains("1"), "the badge counts the filter")
    }

    // MARK: Zoom levels, cities

    func testZoomedOutShowsCityBubblesThatAddUpAndATapFliesInto() throws {
        let app = launch()
        _ = waitForCount(app)
        // SwiftUI's Map isn't an accessibility element of its own; a pinch that starts on a marker still reaches MapKit's
        // pinch recognizer. 0.5 a few times, until the markers are city bubbles.
        let city = query(app, prefix: "map.cityBubble.").firstMatch
        for _ in 0..<5 {
            if city.exists { break }
            let any = app.descendants(matching: .any).matching(NSPredicate(
                format: "identifier BEGINSWITH 'map.areaBubble.' OR identifier BEGINSWITH 'map.cluster.' OR identifier BEGINSWITH 'map.pin.'")).firstMatch
            XCTAssertTrue(any.waitForExistence(timeout: 10))
            any.pinch(withScale: 0.5, velocity: -2)
            sleep(1)
        }
        XCTAssertTrue(city.waitForExistence(timeout: 10), "zoomed far out, markers become one bubble per city")
        sleep(2)
        let n = number(count(app))
        let shown = markerTotal(app)
        XCTAssertTrue(shown > 0 && shown <= n, "bubbles never add results: \(shown) of \(n)")
        city.tap()
        sleep(3)
        XCTAssertEqual(query(app, prefix: "map.cityBubble.").count, 0, "a city tap flies into the city")
        XCTAssertLessThanOrEqual(markerTotal(app), number(count(app)))
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
        XCTAssertTrue(el(app, "map.search.showList").exists, "and a button offers the matching events")
        city.tap()
        XCTAssertFalse(el(app, "map.city.vn-hcm").waitForExistence(timeout: 2), "the query is cleared after flying there")
        _ = waitForCount(app)
        XCTAssertEqual(query(app, prefix: "map.cityBubble.").count, 0, "flying to a city never lands on its own bubble")
        let markers = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH 'map.areaBubble.' OR identifier BEGINSWITH 'map.pin.' OR identifier BEGINSWITH 'map.cluster.' OR identifier BEGINSWITH 'map.stack.'"))
        XCTAssertTrue(markers.firstMatch.waitForExistence(timeout: 5), "bubbles / pins show after flying to the city")
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
        // The chip names the city once the flight to it has settled (the area commits then).
        let named = NSPredicate(format: "label CONTAINS 'Hồ Chí Minh' OR label CONTAINS 'Ho Chi Minh'")
        expectation(for: named, evaluatedWith: app.buttons["map.area"])
        waitForExpectations(timeout: 15)
    }

    // MARK: Search

    func testFocusedSearchShowsSuggestionsAndCancelClosesThem() throws {
        let app = launch()
        _ = waitForCount(app)
        let field = app.textFields["map.searchInput"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 8), "the keyboard is up")
        XCTAssertTrue(el(app, "map.search.suggestions").waitForExistence(timeout: 5), "never a blank search")
        XCTAssertTrue(el(app, "map.search.city.vn-hcm").exists)
        XCTAssertFalse(el(app, "map.search.quick.tonight").exists, "the time chips left the Map")
        el(app, "map.search.cancel").tap()
        XCTAssertTrue(el(app, "map.search.suggestions").waitForNonExistence(timeout: 5), "Cancel puts the search away")
        XCTAssertTrue(el(app, "map.listButton").waitForExistence(timeout: 5))
    }

    func testShowEventsButtonOpensTheList() throws {
        let app = launch()
        _ = waitForCount(app)
        let field = app.textFields["map.searchInput"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("a")
        let show = el(app, "map.search.showList")
        XCTAssertTrue(show.waitForExistence(timeout: 6))
        show.tap()
        XCTAssertTrue(el(app, "map.list.mapButton").waitForExistence(timeout: 8), "Show N events opens the list")
    }
}
