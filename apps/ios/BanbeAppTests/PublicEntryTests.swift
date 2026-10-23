import SwiftUI
import XCTest
@testable import BanbeApp

@MainActor
final class PublicEntryTests: XCTestCase {

    // MARK: launch routing

    func testSignedInBypassesPublicEntry() {
        XCTAssertEqual(PublicEntryRouting.destination(isSignedIn: true, restored: nil), .home)
        XCTAssertEqual(PublicEntryRouting.destination(isSignedIn: true, restored: .myRefunds), .myRefunds)
        XCTAssertEqual(PublicEntryRouting.destination(isSignedIn: false, restored: nil), .welcome)
        XCTAssertEqual(PublicEntryRouting.destination(isSignedIn: false, restored: .myRefunds), .welcome,
                       "a restorable screen is never honored while signed out")
    }

    func testDismissSplashRoutesAfterLanguageThemeSetup() {
        let key = "banbe.onboarded"
        let previous = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }

        UserDefaults.standard.set(false, forKey: key)
        let first = AppState()
        first.screen = .splash
        first.dismissSplash(isSignedIn: false)
        XCTAssertEqual(first.screen, .langPick, "first-device language/theme setup still comes first")

        UserDefaults.standard.set(true, forKey: key)
        let out = AppState()
        out.screen = .splash
        out.dismissSplash(isSignedIn: false)
        XCTAssertEqual(out.screen, .welcome)
        XCTAssertFalse(out.authMandatory)
        XCTAssertEqual(out.authBackScreen, .welcome)

        let signedIn = AppState()
        signedIn.screen = .splash
        signedIn.dismissSplash(isSignedIn: true)
        XCTAssertEqual(signedIn.screen, .home)
    }

    func testProtectedActionGoesToLoginWithReturnAndBackToWelcome() {
        let r = PublicEntryRouting.protectedRedirect(isSignedIn: false, target: .schedule, guestAllowed: AppState.guestAllowedScreens)
        XCTAssertEqual(r, .init(returnTo: .schedule, backTo: .welcome))
        XCTAssertNil(PublicEntryRouting.protectedRedirect(isSignedIn: false, target: .welcome, guestAllowed: AppState.guestAllowedScreens))
        XCTAssertNil(PublicEntryRouting.protectedRedirect(isSignedIn: false, target: .login, guestAllowed: AppState.guestAllowedScreens))
        XCTAssertNil(PublicEntryRouting.protectedRedirect(isSignedIn: true, target: .schedule, guestAllowed: AppState.guestAllowedScreens))
        XCTAssertTrue(AppState.guestAllowedScreens.contains(.welcome))
        XCTAssertFalse(AppState.guestAllowedScreens.contains(.schedule))
    }

    func testRequireAuthKeepsExistingReturnContract() {
        let app = AppState()
        app.screen = .event
        app.requireAuth(returnTo: .reserve, backTo: .event)
        XCTAssertEqual(app.screen, .login)
        XCTAssertEqual(app.authReturnScreen, .reserve)
        XCTAssertEqual(app.authBackScreen, .event)
    }

    // MARK: public entry actions

    func testLogInIsOneTapAndGetStartedOpensSignUp() {
        let app = AppState()
        app.screen = .welcome
        app.openAuth(.login)
        XCTAssertEqual(app.screen, .login)
        XCTAssertEqual(app.authIntent.mode, .login)
        XCTAssertEqual(app.authBackScreen, .welcome)
        XCTAssertFalse(app.authMandatory, "Login entered voluntarily always has Back")

        app.backFromLogin()
        XCTAssertEqual(app.screen, .welcome)
        XCTAssertFalse(app.authNavForward, "Back reverses direction")

        app.openAuth(.signup)
        XCTAssertEqual(app.authIntent.mode, .signup)
        XCTAssertTrue(app.authNavForward)
    }

    func testTypedEmailAndNameSurviveBackButNotSignIn() {
        let app = AppState()
        app.openAuth(.signup)
        app.authDraftEmail = "someone@example.com"
        app.authDraftName = "Lan"
        app.backFromLogin()
        app.openAuth(.login)
        XCTAssertEqual(app.authDraftEmail, "someone@example.com")
        XCTAssertEqual(app.authDraftName, "Lan")
        app.clearAuthDraft()
        XCTAssertEqual(app.authDraftEmail, "")
        XCTAssertEqual(app.authIntent, .login)
    }

    func testOptionalStoryForwardBackSkip() {
        var s = PublicStoryState()
        XCTAssertFalse(s.isOnStory)
        s.open()
        XCTAssertEqual(s.page, 0)
        s.next()
        XCTAssertEqual(s.page, 1)
        XCTAssertFalse(s.isLastPage, "the host pages follow")
        s.next(); s.next()
        XCTAssertEqual(s.page, 3)
        XCTAssertTrue(s.isLastPage)
        s.next()
        XCTAssertEqual(s.page, 3, "never auto-advances past the last page")
        s.back(); s.back(); s.back()
        XCTAssertEqual(s.page, 0)
        XCTAssertFalse(s.forward)
        s.back()
        XCTAssertNil(s.page, "Back from the first page returns to the welcome screen")
        s.open(); s.next(); s.close()
        XCTAssertNil(s.page)
    }

    func testStorySeenMarkerIsRemembered() throws {
        let d = try XCTUnwrap(UserDefaults(suiteName: "test.story.\(UUID().uuidString)"))
        XCTAssertFalse(PublicStoryMarker.hasSeen(d))
        PublicStoryMarker.markSeen(d)
        XCTAssertTrue(PublicStoryMarker.hasSeen(d))
    }

    // MARK: motion

    func testMotionDirectionAndReduceMotion() {
        XCTAssertEqual(AuthMotion.style(forward: true, reduceMotion: false), .slide(insertionFrom: .trailing, distance: 28))
        XCTAssertEqual(AuthMotion.style(forward: false, reduceMotion: false), .slide(insertionFrom: .leading, distance: 28))
        XCTAssertEqual(AuthMotion.style(forward: true, reduceMotion: true), .fade)
        XCTAssertEqual(AuthMotion.style(forward: false, reduceMotion: true), .fade)
        XCTAssertGreaterThanOrEqual(AuthMotion.duration, 0.18)
        XCTAssertLessThanOrEqual(AuthMotion.duration, 0.22)
        XCTAssertLessThan(AuthMotion.reducedDuration, AuthMotion.duration)
    }

    // MARK: dock + notifications re-entry

    func testDockHasExactlyFiveWithScheduleInNotificationsSlot() {
        XCTAssertEqual(BottomTabBar.dockOrder, [.home, .mapExplore, .schedule, .inbox, .profile])
        XCTAssertEqual(BottomTabBar.visibleScreens, Set(BottomTabBar.dockOrder))
        XCTAssertFalse(BottomTabBar.visibleScreens.contains(.notifications))
    }

    func testNotificationsReturnsToWhereItWasOpened() {
        let app = AppState()
        // From Home, Notifications slides in as an overlay over the live Home (the screen itself stays Home).
        app.screen = .home
        app.goNotifications(back: .home)
        XCTAssertEqual(app.screen, .home)
        XCTAssertTrue(app.notificationsOverlayOpen)
        XCTAssertEqual(app.notificationsBack, .home)
        app.notificationsOverlayOpen = false

        app.screen = .profile
        app.goNotifications(back: .profile)
        XCTAssertEqual(app.backTargetScreen, .profile)
        app.goBack()
        XCTAssertEqual(app.screen, .profile)

        // Re-entering from a deep-linked child keeps the original origin.
        app.screen = .schedule
        app.goNotifications()
        XCTAssertEqual(app.notificationsBack, .schedule)
        app.goNotifications()
        XCTAssertEqual(app.notificationsBack, .schedule)
    }

    func testScheduleTabBackGoesHomeAndCannotSwipeFromWelcome() {
        let app = AppState()
        app.screen = .schedule
        XCTAssertEqual(app.backTargetScreen, .home)
        app.screen = .welcome
        XCTAssertFalse(app.canSwipeBack)
    }
}
