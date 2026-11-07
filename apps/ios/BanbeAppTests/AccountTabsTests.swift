import XCTest
@testable import BanbeApp

/// Note 69: Account tabs follow Hosting mode.
final class AccountTabsTests: XCTestCase {
    func testHostingOffNonAdminHasNoTabs() {
        XCTAssertEqual(AccountTabs.tabs(isAdmin: false, hostMode: false), [])
    }

    func testHostingOffAdminHasPersonalAndAdmin() {
        XCTAssertEqual(AccountTabs.tabs(isAdmin: true, hostMode: false), ["personal", "admin"])
    }

    func testHostingOnPutsHostFirst() {
        XCTAssertEqual(AccountTabs.tabs(isAdmin: false, hostMode: true), ["host", "personal"])
    }

    func testHostingOnAdminAddsAdminLast() {
        XCTAssertEqual(AccountTabs.tabs(isAdmin: true, hostMode: true), ["host", "personal", "admin"])
    }

    func testResolveFallsBackToFirstTab() {
        XCTAssertEqual(AccountTabs.resolve("admin", tabs: ["host", "personal"]), "host")
        XCTAssertEqual(AccountTabs.resolve("host", tabs: ["personal", "admin"]), "personal")
        XCTAssertEqual(AccountTabs.resolve("host", tabs: []), "personal")
        XCTAssertEqual(AccountTabs.resolve("personal", tabs: ["host", "personal"]), "personal")
    }
}
