import XCTest
@testable import BanbeApp

final class EnsureOrganizerTests: XCTestCase {
    func testShouldEnsureOnlyWhenConfirmedEmptyAndIdle() {
        func go(_ mode: Bool = true, _ st: String = "loaded", _ n: Int = 0, _ e: String = "idle", user: Bool = true) -> Bool {
            EnsureOrganizerLogic.shouldEnsure(hasUser: user, organizerMode: mode, idsStatus: st, ownedCount: n, ensureStatus: e)
        }
        XCTAssertTrue(go())
        XCTAssertFalse(go(false))
        XCTAssertFalse(go(user: false))
        XCTAssertFalse(go(true, "loaded", 1))
        for st in ["idle", "loading", "error"] { XCTAssertFalse(go(true, st)) }
        XCTAssertFalse(go(true, "loaded", 0, "loading"))
        XCTAssertFalse(go(true, "loaded", 0, "error"), "no automatic retry loop")
    }

    func testDefaultName() {
        XCTAssertEqual(EnsureOrganizerLogic.defaultName(displayName: "Linh", isEN: true), "Linh Events")
        XCTAssertEqual(EnsureOrganizerLogic.defaultName(displayName: "Linh", isEN: false), "Linh Sự kiện")
        XCTAssertEqual(EnsureOrganizerLogic.defaultName(displayName: "  ", isEN: true), "My events")
        XCTAssertEqual(EnsureOrganizerLogic.defaultName(displayName: nil, isEN: false), "Sự kiện của tôi")
    }

    func testNameNeverFromEmailOrPhone() {
        for v in ["a@b.com", "linh@gmail.com", "+84 912 345 678", "0912345678"] {
            let n = EnsureOrganizerLogic.defaultName(displayName: v, isEN: true)
            XCTAssertEqual(n, "My events")
        }
    }
}
