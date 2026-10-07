import XCTest
@testable import BanbeApp

@MainActor
final class FollowingTests: XCTestCase {
    private func org(_ id: String, _ name: String) -> FollowLogic.OrgRow {
        FollowLogic.OrgRow(id: id, name: name, avatarPath: nil, avatarR2Ref: nil, verified: false)
    }

    func testApplyChangeIsIdempotent() {
        XCTAssertEqual(FollowLogic.applyChange(["a"], "a", following: true), ["a"])
        XCTAssertEqual(FollowLogic.applyChange(["a"], "b", following: true), ["a", "b"])
        XCTAssertEqual(FollowLogic.applyChange(["a", "b"], "a", following: false), ["b"])
        XCTAssertEqual(FollowLogic.applyChange(["a"], "zz", following: false), ["a"])
    }

    func testBuildSortsAlphabeticallyAndKeepsUnavailableHostsLast() {
        let rows = FollowLogic.build(followIDs: ["z", "gone", "a", "a"], orgs: [org("a", "Álpha"), org("z", "Zed")])
        XCTAssertEqual(rows.map(\.organizerID), ["a", "z", "gone"])
        XCTAssertFalse(rows[2].available)
    }

    func testSearchIsAccentInsensitiveNameOnlyAndSkipsUnavailable() {
        let rows = FollowLogic.build(followIDs: ["a", "gone"], orgs: [org("a", "Álpha")])
        XCTAssertEqual(FollowLogic.filter(rows, query: "alpha").map(\.organizerID), ["a"])
        XCTAssertTrue(FollowLogic.filter(rows, query: "gone").isEmpty)
        XCTAssertEqual(FollowLogic.filter(rows, query: "  ").count, 2)
    }

    func testResetClearsEverythingForAnAccountSwitch() {
        let app = AppState()
        app.followedOrgIDs = ["a"]
        app.followedHosts = FollowLogic.build(followIDs: ["a"], orgs: [org("a", "A")])
        app.followedStatus = .loaded
        app.followWriteError = "x"
        app.resetFollowState()
        XCTAssertTrue(app.followedOrgIDs.isEmpty)
        XCTAssertTrue(app.followedHosts.isEmpty)
        XCTAssertEqual(app.followedStatus, .idle)
        XCTAssertEqual(app.followWriteError, "")
    }

    func testSettingWithoutAnAccountDoesNothing() async {
        let app = AppState()
        app.userID = nil
        let ok = await app.setFollowing("a", true)
        XCTAssertFalse(ok)
        XCTAssertTrue(app.followedOrgIDs.isEmpty)
    }

    func testReconcileFoldsInAFreshServerFlagOnlyOnceLoaded() {
        let app = AppState()
        XCTAssertFalse(app.reconcileFollow("a", following: true))
        app.followedStatus = .loaded
        XCTAssertTrue(app.reconcileFollow("a", following: true))
        XCTAssertTrue(app.followedOrgIDs.contains("a"))
        XCTAssertFalse(app.reconcileFollow("a", following: true))
    }

    func testMapForYouCandidateMatchesHomeCandidateRules() {
        // One shared builder: price/zone/bookability normalise identically for Home and Map rows.
        let c = ForYou.candidate(key: "k", catKey: "music", cat2Key: nil, priceVnd: 100_000, isFree: false,
                                 countryCode: "VN", stateProvince: nil, startsAt: nil, isBookable: true)
        XCTAssertEqual(c.priceAmount, 100_000)
        XCTAssertEqual(c.priceCurrency, "VND")
        XCTAssertEqual(c.timeZone?.identifier, "Asia/Ho_Chi_Minh")
        XCTAssertEqual(c.categories, ["music"])
        let free = ForYou.candidate(key: "f", catKey: nil, cat2Key: nil, priceVnd: 5, isFree: true,
                                    countryCode: "US", stateProvince: "CA", startsAt: nil, isBookable: false)
        XCTAssertEqual(free.priceAmount, 0)
        XCTAssertNil(free.priceCurrency)
        XCTAssertEqual(free.timeZone?.identifier, "America/Los_Angeles")
        XCTAssertFalse(free.isBookable)
    }
}
