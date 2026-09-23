import XCTest

/// Terminal-driven "Screenshot Catalog" — walks the app through named,
/// deterministic flows and captures a presentation-ready PNG for each one.
/// Not a regression suite: assertions here exist only to confirm a screen
/// actually reached its destination state before the shot is taken, not to
/// exhaustively validate behavior (that's NavigationUITests/BottomTabBarUITests/
/// etc.'s job).
///
/// Run via `scripts/capture_ios_catalog.sh`, which exports every attachment
/// this file records into `docs/demo-screenshots/`. See that script's own
/// comments for the xcresulttool export mechanics.
///
/// Signed-in flows reuse the SAME shared, dedicated test account
/// (`doqanh0906+banbe-fast-suite-shared@gmail.com`) `EventDetailOpenInMapUITests`/
/// `MapExploreSelectionUITests` already sign into over the real network —
/// the only signed-in fixture this codebase has (09-auth-onboarding.md: "no
/// guest browsing of any screen" means every screen but splash/langPick/
/// themePick/login/policy requires a real session). This is a deliberate
/// reuse of that existing convention, not a new one — see this repo's own
/// `AppState.guestAllowedScreens` doc comment. Because it's real account
/// data (not a seeded fixture), some opportunistic flows (an existing
/// unread thread, an active story, a chat attachment) may or may not exist
/// at run time; those are captured only when found and otherwise skipped
/// via `skip(_:)` (a recorded, non-failing note), never faked. See
/// `docs/demo-screenshots/README.md`'s own "Not captured yet" section for
/// the flows this pass could not reach at all, and why.
final class ScreenshotCatalogTests: XCTestCase {

    private let testEmail = "doqanh0906+banbe-fast-suite-shared@gmail.com"
    private let testPassword = "BanbeE2e!Test1234"

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: - Launch / sign-in

    private func launch(onboarded: Bool = true, role: String = "goer", scenario: String = "default") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-banbe.onboarded", onboarded ? "YES" : "NO",
            "-uiTesting", "1",
            "-screenshotCatalog", "1",
            "-demoRole", role,
            "-demoScenario", scenario,
        ]
        app.launch()
        return app
    }

    /// Signs into the shared fast-suite account if the login gate appears
    /// (a truly fresh simulator); no-ops if a session already persists in
    /// the Simulator's own keychain from a prior run. Mirrors
    /// `EventDetailOpenInMapUITests.launchSignedIn()`/
    /// `MapExploreSelectionUITests.launchIntoMap()` exactly — not a second,
    /// independently-tuned login flow.
    @discardableResult
    private func launchSignedIn(role: String = "goer", scenario: String = "default") -> XCUIApplication {
        let app = launch(role: role, scenario: scenario)
        if app.otherElements["screen.login"].waitForExistence(timeout: 45) {
            app.buttons["login.method.password"].tap()
            let email = app.textFields["login.email"]
            XCTAssertTrue(email.waitForExistence(timeout: 5))
            email.tap()
            email.typeText(testEmail)
            let password = app.secureTextFields["login.password"]
            XCTAssertTrue(password.waitForExistence(timeout: 5))
            password.tap()
            password.typeText(testPassword)
            app.buttons["login.submit"].tap()
        }
        XCTAssertTrue(app.otherElements["screen.home"].waitForExistence(timeout: 45),
                      "Expected to land on Home after sign-in")
        return app
    }

    // MARK: - Capture

    private struct ScreenshotMeta: Encodable {
        let group: String
        let order: Int
        let slug: String
        let title: String
        let description: String
        let role: String
        let testName: String
        let generatedAt: String
    }

    /// Captures one catalog entry: the PNG screenshot plus a small JSON
    /// metadata attachment (group/order/slug/title/description/role/source
    /// test), both `.keepAlways` so `xcresulttool export attachments` picks
    /// them up regardless of whether the test that captured them passed.
    /// `<group>/<order>-<slug>` (zero-padded) becomes the attachment name —
    /// `scripts/capture_ios_catalog.sh` parses that back out on export to
    /// build the deterministic `NN-slug.png` filename.
    private func capture(
        _ group: String, _ order: Int, _ slug: String, _ title: String, _ description: String,
        role: String, app: XCUIApplication, testName: String = #function
    ) {
        let orderStr = String(format: "%02d", order)
        let baseName = "\(group)/\(orderStr)-\(slug)"
        XCTContext.runActivity(named: "capture \(baseName) — \(title)") { activity in
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = baseName
            shot.lifetime = .keepAlways
            activity.add(shot)

            let meta = ScreenshotMeta(
                group: group, order: order, slug: slug, title: title, description: description,
                role: role, testName: testName, generatedAt: ISO8601DateFormatter().string(from: Date())
            )
            if let data = try? JSONEncoder().encode(meta) {
                let metaAttachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                metaAttachment.name = "\(baseName).meta"
                metaAttachment.lifetime = .keepAlways
                activity.add(metaAttachment)
            }
        }
    }

    /// Records an opportunistic flow that could not be reached THIS run
    /// (the shared account currently has no unread thread / active story /
    /// etc.) — a visible, non-failing note in the result bundle, never a
    /// faked screenshot.
    private func skip(_ reason: String) {
        XCTContext.runActivity(named: "SKIPPED — \(reason)") { _ in }
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval = 8) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// The bottom dock (BottomTabBar.swift) is the ONLY working navigation
    /// entry point to Map/Notifications/Inbox/Account — `header.account`/
    /// `header.mapExplore` (used by `NavigationUITests`/
    /// `EventDetailOpenInMapUITests`/`MapExploreSelectionUITests`) do not
    /// exist anywhere in the current view tree (confirmed by grep across
    /// `Views/*.swift`); those identifiers are stale, left over from a top
    /// header row BottomTabBar.swift's own doc comment says it replaced.
    /// `BottomTabBarUITests.tab(_:_:)` is the current, actually-working
    /// pattern (its own doc comment explains why `.any`/`.descendants` is
    /// needed here, not `.buttons`) — copied verbatim rather than
    /// reinventing it.
    private func tab(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Same reasoning as `tab(_:_:)` above, generalized: several
    /// identifiers referenced below sit on plain containers (a `VStack`/
    /// `HStack` with `.onTapGesture`, or content nested inside one that
    /// bubbles its container's identifier — see
    /// `EventDetailOpenInMapUITests`'s own comment on `map.selectedCard`),
    /// not always a native `Button`/`Image` — `.any`/`.descendants` finds
    /// them regardless of which concrete XCUIElementType SwiftUI ends up
    /// exposing.
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// A plain `.tap()` lands on an element's center by default — for a
    /// tall element (Home's first feed card; Account's bottom-most
    /// organizer rows) that center can sit inside
    /// `BottomTabBarOverlay`'s own bottom hit-testable band (see that
    /// file's own doc comment on this exact class of bug: a genuinely
    /// separate always-on-top `UIWindow` silently absorbing a touch meant
    /// for real content underneath it). Confirmed by an actual run on this
    /// machine — `card.bepnho`'s reported frame extended to y≈816 on an
    /// 874pt-tall window, and `host.verifications`/`host.receipts` sit
    /// right above the dock too; tapping their center intermittently never
    /// navigated. Tapping near the TOP of the element instead keeps clear
    /// of that band without touching product code — the deliberate "last
    /// resort" exception for exactly this known, already-documented
    /// interaction, not a routine coordinate tap.
    private func tapNearTop(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
    }

    // MARK: - A. Onboarding / auth

    func testGroupA_OnboardingAuth() {
        let app = launch(onboarded: false, role: "goer", scenario: "onboarding")

        if app.otherElements["screen.splash"].waitForExistence(timeout: 5) {
            capture("01-onboarding-auth", 1, "splash", "Splash", "First launch mark/wordmark before onboarding starts.", role: "goer", app: app)
            app.tap()
        }

        XCTAssertTrue(app.otherElements["screen.langPick"].waitForExistence(timeout: 18))
        capture("01-onboarding-auth", 2, "language-pick", "Language picker", "First onboarding step — Vietnamese/English.", role: "goer", app: app)
        app.buttons["lang.vi"].tap()

        XCTAssertTrue(app.otherElements["screen.themePick"].waitForExistence(timeout: 5))
        capture("01-onboarding-auth", 3, "theme-pick", "Theme picker", "Second onboarding step — light/dark.", role: "goer", app: app)
        app.buttons["theme.dark"].tap()
        app.buttons["theme.light"].tap() // back to the default theme so downstream groups aren't affected.
        app.buttons["onboarding.continue"].tap()

        if app.otherElements["screen.login"].waitForExistence(timeout: 18) {
            capture("01-onboarding-auth", 4, "login", "Login", "Mandatory sign-in gate — no guest browsing exists in this app.", role: "goer", app: app)
            app.buttons["login.method.password"].tap()
            let email = app.textFields["login.email"]
            XCTAssertTrue(email.waitForExistence(timeout: 5))
            email.tap()
            email.typeText(testEmail)
            let password = app.secureTextFields["login.password"]
            XCTAssertTrue(password.waitForExistence(timeout: 5))
            password.tap()
            password.typeText(testPassword)
            app.buttons["login.submit"].tap()
        } else {
            skip("login screen — a session already persisted on this simulator, so the gate never appeared this run")
        }

        XCTAssertTrue(app.otherElements["screen.home"].waitForExistence(timeout: 45))
        tab(app, "tab.profile").tap()
        XCTAssertTrue(app.otherElements["screen.profile"].waitForExistence(timeout: 15))
        capture("01-onboarding-auth", 5, "account-after-onboarding", "Account, freshly signed in", "First Account view right after onboarding/login completes.", role: "goer", app: app)
    }

    // MARK: - B. Home / discovery

    func testGroupB_HomeDiscovery() {
        let app = launchSignedIn(role: "goer", scenario: "home")

        XCTAssertTrue(app.buttons["card.bepnho"].waitForExistence(timeout: 20), "Expected the catalogue feed to render")
        capture("02-home-discovery", 1, "home-feed", "Home feed", "The event catalogue, default area/filter.", role: "goer", app: app)

        app.buttons["filter.music"].tap()
        XCTAssertTrue(waitForDisappearance(of: app.buttons["card.bepnho"]))
        capture("02-home-discovery", 2, "home-filters", "Home, category filter applied", "Music-only filter narrowing the feed.", role: "goer", app: app)
        app.buttons["filter.all"].tap()
        XCTAssertTrue(app.buttons["card.bepnho"].waitForExistence(timeout: 18))

        // Event Detail / Map Explore captured BEFORE the EventList
        // round-trips below, not after — confirmed by multiple actual runs
        // on this machine: tapping into Event Detail specifically AFTER
        // three EventList back-and-forths in the same continuous session
        // reproducibly never navigated (a real, reproducible app-state
        // issue, out of this ticket's scope to chase further — this
        // reordering sidesteps it rather than papering over it with a
        // longer timeout, which did not help).
        tapNearTop(app.buttons["card.bepnho"])
        XCTAssertTrue(app.otherElements["screen.event"].waitForExistence(timeout: 18))
        capture("02-home-discovery", 6, "event-detail", "Event Detail", "Reached from Home — includes the \"Open in map\" action.", role: "goer", app: app)

        if app.buttons["event.openInMap"].waitForExistence(timeout: 5) {
            app.buttons["event.openInMap"].tap()
            XCTAssertTrue(app.otherElements["screen.mapExplore"].waitForExistence(timeout: 18))
            capture("02-home-discovery", 7, "event-detail-open-in-map", "Event Detail → Map Explore", "Landing on Map Explore centered on the event just viewed.", role: "goer", app: app)

            if app.descendants(matching: .any).matching(identifier: "map.selectedCard").firstMatch.waitForExistence(timeout: 18) {
                capture("02-home-discovery", 8, "map-explore-event-sheet", "Map Explore, event card", "The selected-pin info card/sheet.", role: "goer", app: app)
            } else {
                skip("map-explore-event-sheet — the selected-pin card did not resolve within the wait")
            }
            tab(app, "tab.home").tap()
        } else {
            skip("event-detail-open-in-map / map-explore-event-sheet — \"Open in map\" was not present")
            app.buttons["event.back"].tap()
        }

        tab(app, "tab.profile").tap()
        XCTAssertTrue(app.otherElements["screen.profile"].waitForExistence(timeout: 15))

        app.buttons["account.goingCard"].tap()
        if app.otherElements["screen.eventList"].waitForExistence(timeout: 18) {
            capture("02-home-discovery", 3, "going-list", "Going", "Events the account is currently attending.", role: "goer", app: app)
            app.buttons["‹"].firstMatch.tap() // EventListView's own back chevron — no accessibilityIdentifier, no BackLink component.
        }
        if !app.otherElements["screen.profile"].waitForExistence(timeout: 5) { tab(app, "tab.profile").tap() }
        XCTAssertTrue(app.otherElements["screen.profile"].waitForExistence(timeout: 18))

        app.buttons["account.savedCard"].tap()
        if app.otherElements["screen.eventList"].waitForExistence(timeout: 18) {
            capture("02-home-discovery", 4, "saved-list", "Saved", "Events the account has favorited.", role: "goer", app: app)
            app.buttons["‹"].firstMatch.tap() // EventListView's own back chevron — no accessibilityIdentifier, no BackLink component.
        }
        if !app.otherElements["screen.profile"].waitForExistence(timeout: 5) { tab(app, "tab.profile").tap() }
        XCTAssertTrue(app.otherElements["screen.profile"].waitForExistence(timeout: 18))

        app.buttons["account.completedList"].tap()
        if app.otherElements["screen.eventList"].waitForExistence(timeout: 18) {
            capture("02-home-discovery", 5, "completed-list", "Completed events", "Events that have already ended.", role: "goer", app: app)
            app.buttons["‹"].firstMatch.tap() // EventListView's own back chevron — no accessibilityIdentifier, no BackLink component.
        }
    }

    // MARK: - C. Booking / payment — see README "Not captured yet"

    // Deliberately no test here: every state in this group (holding a seat,
    // an awaiting-verification payment, a confirmed/cancelled booking)
    // requires actually reserving/paying for a real seat on the shared
    // fast-suite account. That would mutate shared fixture state other
    // suites (EventDetailOpenInMapUITests, MapExploreSelectionUITests, the
    // web Playwright suite's own use of the same account) depend on, which
    // this ticket's "do not alter production data" explicitly rules out —
    // and there is no read-only path to these specific states. See
    // `docs/demo-screenshots/README.md`.

    // MARK: - D. Messaging

    func testGroupD_Messaging() {
        let app = launchSignedIn(role: "goer", scenario: "messaging")

        tab(app, "tab.inbox").tap()
        XCTAssertTrue(app.otherElements["screen.inbox"].waitForExistence(timeout: 15))
        capture("04-messaging", 1, "inbox", "Inbox", "Conversation list — whatever mix of read/unread the account currently has.", role: "goer", app: app)

        if app.buttons["inbox.settingsToggle"].waitForExistence(timeout: 5) {
            app.buttons["inbox.settingsToggle"].tap()
            if app.buttons["inbox.settings.archived"].waitForExistence(timeout: 5) {
                app.buttons["inbox.settings.archived"].tap()
                XCTAssertTrue(app.otherElements["screen.inbox"].waitForExistence(timeout: 5))
                capture("04-messaging", 2, "inbox-archived", "Inbox, Archived", "The archived-conversations view.", role: "goer", app: app)
                app.buttons["‹ Quay lại Tin nhắn"].firstMatch.tap()
            }
        }

        let thread = any(app, "inbox.threadRow")
        if thread.waitForExistence(timeout: 5) {
            thread.tap()
            XCTAssertTrue(app.otherElements["screen.chat"].waitForExistence(timeout: 18))
            capture("04-messaging", 3, "chat-thread", "Chat thread", "An open conversation.", role: "goer", app: app)

            if any(app, "chat.unreadDivider").waitForExistence(timeout: 3) {
                capture("04-messaging", 4, "chat-unread-divider", "Chat, unread divider", "The \"unread messages\" separator within a thread.", role: "goer", app: app)
            } else {
                skip("chat-unread-divider — this thread has no unread separator right now")
            }

            if any(app, "chat.systemCard").waitForExistence(timeout: 3) {
                capture("04-messaging", 5, "chat-system-card", "Chat, system/payment card", "A payment/system event rendered inline in the thread.", role: "goer", app: app)
            } else {
                skip("chat-system-card — no system/payment card in this thread")
            }

            let attachment = any(app, "chat.attachment")
            if attachment.waitForExistence(timeout: 3) {
                capture("04-messaging", 6, "chat-image-attachment", "Chat, image attachment", "A photo message inline in the thread.", role: "goer", app: app)

                // The thumbnail can exist off-screen (scrolled above the
                // fold in a long thread) — confirmed by an actual run on
                // this machine, where a plain `.tap()` here failed with
                // "not hittable". Scroll it into view first, same pattern
                // NavigationUITests' testEventOpensTheOrganizerPage already
                // uses, rather than a fragile coordinate tap.
                var swipes = 0
                while !attachment.isHittable, attachment.exists, swipes < 6 {
                    app.swipeDown()
                    swipes += 1
                }
                if attachment.isHittable {
                    attachment.tap()
                    // ChatPhotoViewerView.swift is outside this ticket's
                    // read scope, so its own accessibility identifiers are
                    // unknown — a short fixed settle (not a fragile
                    // coordinate tap) is the deliberate exception this
                    // ticket allows as "a last resort" for exactly this case.
                    Thread.sleep(forTimeInterval: 1.0)
                    capture("04-messaging", 7, "chat-image-fullscreen", "Chat, fullscreen image viewer", "The attachment opened fullscreen.", role: "goer", app: app)
                    app.tap()
                } else {
                    skip("chat-image-fullscreen — the attachment thumbnail never became hittable")
                }
            } else {
                skip("chat-image-attachment / chat-image-fullscreen — no image attachment in this thread")
            }
        } else {
            skip("chat-thread and everything nested under it — the shared account currently has no conversations")
        }
    }

    // MARK: - E. Notifications

    func testGroupE_Notifications() {
        let app = launchSignedIn(role: "goer", scenario: "notifications")

        tab(app, "tab.notifications").tap()
        XCTAssertTrue(app.otherElements["screen.notifications"].waitForExistence(timeout: 15))
        capture("05-notifications", 1, "list", "Notification list", "Whatever notifications currently exist for the account.", role: "goer", app: app)

        let firstRow = any(app, "notification.row")
        let hasRows = firstRow.waitForExistence(timeout: 3)
        if !hasRows {
            capture("05-notifications", 5, "empty", "Notifications, empty state", "No notifications currently exist for the account.", role: "goer", app: app)
        }

        app.buttons["notifications.searchToggle"].tap()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5))
        capture("05-notifications", 2, "search", "Notifications, search", "The search field open, matching Inbox's own control.", role: "goer", app: app)
        app.buttons["notifications.searchToggle"].tap()

        if hasRows, app.buttons["notifications.selectMode"].waitForExistence(timeout: 5) {
            app.buttons["notifications.selectMode"].tap()
            XCTAssertTrue(app.buttons["notifications.selectAll"].waitForExistence(timeout: 5))
            capture("05-notifications", 3, "selection-mode", "Notifications, selection mode", "Select all / Cancel controls active.", role: "goer", app: app)
            app.buttons["notifications.selection.cancel"].tap()

            firstRow.press(forDuration: 1.0)
            if any(app, "notification-menu").waitForExistence(timeout: 5) {
                capture("05-notifications", 4, "action-menu", "Notification action menu", "Mark read/unread, mute, delete.", role: "goer", app: app)
                app.tap()
            } else {
                skip("action-menu — did not resolve from a long-press within the wait")
            }
        } else if !hasRows {
            skip("selection-mode / action-menu — no notifications to select")
        }
    }

    // MARK: - F. Stories (opportunistic — active-story-dependent)

    func testGroupF_Stories() {
        let app = launchSignedIn(role: "goer", scenario: "stories")

        let ring = any(app, "home.storyAvatar")
        guard ring.waitForExistence(timeout: 5) else {
            skip("home-story-row / story-viewer / story-event-share-card / story-event-cta — no active story exists on the shared account right now")
            return
        }
        capture("06-stories", 1, "home-story-row", "Home, story row", "The active-story ring above the feed.", role: "goer", app: app)
        ring.tap()

        if any(app, "story.viewer.image").waitForExistence(timeout: 18) {
            capture("06-stories", 2, "story-viewer", "Story viewer", "A story open fullscreen.", role: "goer", app: app)
        }

        if any(app, "story.eventCard").waitForExistence(timeout: 3) {
            capture("06-stories", 3, "story-event-share-card", "Story, event-share card", "An event shared as a story card.", role: "goer", app: app)
            if any(app, "story.eventCard.cta").waitForExistence(timeout: 3) {
                any(app, "story.eventCard.cta").tap()
                if app.otherElements["screen.event"].waitForExistence(timeout: 18) {
                    capture("06-stories", 4, "story-event-cta", "Story CTA → Event Detail", "Tapping the story's event card opens its Event Detail.", role: "goer", app: app)
                }
            }
        } else {
            skip("story-event-share-card / story-event-cta — the active story is not an event-share card")
        }
    }

    // MARK: - G. Organizer

    func testGroupG_Organizer() {
        let app = launchSignedIn(role: "host", scenario: "organizer")

        tab(app, "tab.profile").tap()
        XCTAssertTrue(app.otherElements["screen.profile"].waitForExistence(timeout: 15))

        guard app.buttons["host.verifications"].waitForExistence(timeout: 5) else {
            skip("verification-queue / documents-receipts (host) / organizer-dashboard / check-in-attendance — the shared account is not currently enrolled as an organizer; this pass will not toggle organizer mode on, since that would mutate shared account state")
            return
        }

        tapNearTop(app.buttons["host.verifications"])
        XCTAssertTrue(app.otherElements["screen.verifications"].waitForExistence(timeout: 18))
        capture("07-organizer", 1, "verification-queue", "Verification queue", "Bookings awaiting payment verification.", role: "host", app: app)

        // Fresh launch for receipts-issued rather than backing out of
        // Verifications and navigating again in the SAME session — a
        // second deep navigation chained after the first reproducibly
        // failed to land across multiple actual runs on this machine (a
        // real, reproducible issue with this exact call sequence, out of
        // this ticket's scope to chase further); starting clean sidesteps
        // it instead of masking it with a longer timeout, which did not help.
        let app2 = launchSignedIn(role: "host", scenario: "organizer-receipts")
        tab(app2, "tab.profile").tap()
        XCTAssertTrue(app2.otherElements["screen.profile"].waitForExistence(timeout: 15))
        if app2.buttons["host.receipts"].waitForExistence(timeout: 5) {
            tapNearTop(app2.buttons["host.receipts"])
            XCTAssertTrue(app2.otherElements["screen.documents"].waitForExistence(timeout: 18))
            capture("07-organizer", 2, "receipts-issued", "Receipts issued", "The organizer's own issued-receipts list.", role: "host", app: app2)
        } else {
            skip("receipts-issued — host.receipts was not present on this fresh launch")
        }

        // Organizer Dashboard and Check-in/Attendance are reached through
        // DashboardView.swift, which is outside this ticket's read scope —
        // no verified stable identifier path exists to them from here. See
        // README "Not captured yet". Refund queue: no such screen/identifier
        // was found within this ticket's read scope either.
        skip("organizer-dashboard / check-in-attendance — reached only via DashboardView.swift, outside this ticket's read scope")
        skip("refund-queue — no refund-queue screen/identifier found within this ticket's read scope")
    }

    // MARK: - H. Account / settings

    func testGroupH_AccountSettings() {
        let app = launchSignedIn(role: "goer", scenario: "account-settings")

        tab(app, "tab.profile").tap()
        XCTAssertTrue(app.otherElements["screen.profile"].waitForExistence(timeout: 15))
        capture("08-account-settings", 1, "account", "Account", "Signed-in Account screen.", role: "goer", app: app)

        app.buttons["account.preferences"].tap()
        XCTAssertTrue(app.otherElements["screen.preferences"].waitForExistence(timeout: 18))
        capture("08-account-settings", 2, "app-preferences", "App preferences", "Language + theme, renamed from \"Language & appearance\".", role: "goer", app: app)
        app.buttons["‹ Tài khoản"].tap()
        XCTAssertTrue(app.otherElements["screen.profile"].waitForExistence(timeout: 18))

        app.buttons["account.receipts"].tap()
        XCTAssertTrue(app.otherElements["screen.documents"].waitForExistence(timeout: 18))
        capture("08-account-settings", 3, "documents-receipts", "Receipts", "The guest's own receipts.", role: "goer", app: app)
        // DocumentsView.swift's own `documents.back` — the bottom dock is
        // hidden on this screen (not in BottomTabBar.visibleScreens), so
        // `tab.profile` does not exist here; confirmed by an actual failed
        // run before this fix.
        app.buttons["documents.back"].tap()
        XCTAssertTrue(app.otherElements["screen.profile"].waitForExistence(timeout: 18))

        app.buttons["account.security"].tap()
        XCTAssertTrue(app.otherElements["screen.security"].waitForExistence(timeout: 18))
        capture("08-account-settings", 4, "security", "Security", "Account security settings.", role: "goer", app: app)
    }
}
