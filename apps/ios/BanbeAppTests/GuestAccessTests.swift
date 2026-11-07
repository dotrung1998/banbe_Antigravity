import XCTest
@testable import BanbeApp

/// Note 48 — read-only guest browsing and contextual sign-in prompts.
@MainActor
final class GuestAccessTests: XCTestCase {

    func testBrowseScreensAreGuestAllowedButPersonalScreensAreNot() {
        for screen in [Screen.home, .mapExplore, .event] {
            XCTAssertTrue(AppState.guestAllowedScreens.contains(screen), "\(screen) should be browsable signed out")
        }
        for screen in [Screen.reserve, .chat, .inbox, .profile, .schedule, .notifications, .confirmed, .create, .myRefunds] {
            XCTAssertFalse(AppState.guestAllowedScreens.contains(screen), "\(screen) must stay behind sign-in")
        }
    }

    func testLoginBackReturnsToTheBrowseScreenTheGuestCameFrom() {
        let fromHome = PublicEntryRouting.protectedRedirect(isSignedIn: false, target: .schedule,
                                                            guestAllowed: AppState.guestAllowedScreens,
                                                            from: .home, browsable: AppState.guestBrowseScreens)
        XCTAssertEqual(fromHome, .init(returnTo: .schedule, backTo: .home))
        let fromLogin = PublicEntryRouting.protectedRedirect(isSignedIn: false, target: .schedule,
                                                             guestAllowed: AppState.guestAllowedScreens,
                                                             from: .login, browsable: AppState.guestBrowseScreens)
        XCTAssertEqual(fromLogin?.backTo, .welcome, "a non-browse origin falls back to welcome")
    }

    func testGuestSaveAsksInsteadOfFlippingLocally() {
        let app = AppState()
        app.screen = .event
        app.toggleFavorite("evt-1")
        XCTAssertEqual(app.favorites, [], "a guest save must not pretend to persist")
        XCTAssertEqual(app.guestPrompt?.context, .save)
        XCTAssertEqual(app.guestPrompt?.returnTo, .event)
    }

    func testGuestReserveResumesThroughGoReserveAfterSignIn() {
        let app = AppState()
        app.screen = .event
        app.eventKey = "evt-1"
        app.goReserve()
        XCTAssertEqual(app.screen, .event, "the prompt shows over the event, no jump yet")
        XCTAssertEqual(app.guestPrompt?.context, .reserve)

        app.continueFromGuestPrompt(.signup)
        XCTAssertNil(app.guestPrompt)
        XCTAssertEqual(app.screen, .login)
        XCTAssertEqual(app.authIntent, .signup)
        XCTAssertEqual(app.authReturnScreen, .event)
        XCTAssertEqual(app.authBackScreen, .event)
        XCTAssertEqual(app.pendingAuthResume, .reserve(eventKey: "evt-1"))

        // Signed out, resuming does nothing (and keeps the pending work).
        app.runPendingAuthResume()
        XCTAssertEqual(app.pendingAuthResume, .reserve(eventKey: "evt-1"))
    }

    func testNotNowLeavesTheGuestWhereTheyWere() {
        let app = AppState()
        app.screen = .home
        app.toggleFollow("evt-2")
        XCTAssertEqual(app.guestPrompt?.context, .follow)
        app.guestPrompt = nil
        XCTAssertEqual(app.screen, .home)
        XCTAssertNil(app.pendingAuthResume)
        XCTAssertEqual(app.following, [])
    }

    func testEveryPromptContextHasCopy() {
        let contexts: [GuestPromptContext] = [.save, .follow, .reserve, .message, .like]
        for c in contexts {
            let en = AppState.guestPromptCopy(c) { _, en in en }
            let vi = AppState.guestPromptCopy(c) { vi, _ in vi }
            XCTAssertFalse(en.title.isEmpty || en.body.isEmpty || vi.title.isEmpty || vi.body.isEmpty)
            XCTAssertFalse(en.title.localizedCaseInsensitiveContains("sign up"), "the ask is framed as keeping, not signing up")
        }
    }
}
