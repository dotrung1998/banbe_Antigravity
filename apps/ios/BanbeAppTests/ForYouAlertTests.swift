import XCTest
@testable import BanbeApp

/// Mirrors tests/unit/forYouAlert.test.mjs.
final class ForYouAlertTests: XCTestCase {
    private func m(_ id: String, _ v: String = "v1", accessible: Bool = true, draft: Bool = false) -> ForYouAlertMatch {
        ForYouAlertMatch(id: id, version: v, accessible: accessible, draft: draft)
    }
    private func obs(_ s: ForYouAlertState, _ ms: [ForYouAlertMatch], pv: Int = 1, loading: Bool = false, limit: Int = 1000) -> ForYouAlertState {
        ForYouAlert.observe(s, matches: ms, prefsVersion: pv, loading: loading, limit: limit)
    }
    private func suite() -> UserDefaults {
        let d = UserDefaults(suiteName: "ForYouAlertTests.\(UUID().uuidString)")!
        return d
    }

    func testFirstObservationBaselinesSilently() {
        let s = obs(ForYouAlertState(), [m("a"), m("b")])
        XCTAssertTrue(s.baselined); XCTAssertFalse(s.hasPending)
        XCTAssertEqual(Set(s.seen.keys), ["a", "b"])
    }

    func testOnlyNewMatchesBecomePendingAndPollingDoesNotReplay() {
        var s = obs(ForYouAlertState(), [m("a")])
        s = obs(s, [m("a"), m("b")])
        XCTAssertEqual(Set(s.pending.keys), ["b"])
        let again = obs(s, [m("a"), m("b")])
        XCTAssertEqual(Set(again.pending.keys), ["b"]); XCTAssertEqual(again.seen, s.seen)
    }

    func testNonMatchingEventsNeverAlert() {
        var s = obs(ForYouAlertState(), [m("a")])
        s = obs(s, [m("a")])
        XCTAssertFalse(s.hasPending)
    }

    func testVersionBumpReAlerts() {
        var s = obs(ForYouAlertState(), [m("a", "v1")])
        s = obs(s, [m("a", "v2")])
        XCTAssertEqual(Set(s.pending.keys), ["a"])
        XCTAssertNotEqual(ForYouAlert.version(reviewedAt: nil, submittedAt: nil, status: "draft", visibility: "invite"),
                          ForYouAlert.version(reviewedAt: nil, submittedAt: nil, status: "live", visibility: "public"))
    }

    func testDraftsAndInaccessibleDropped() {
        var s = obs(ForYouAlertState(), [m("a")])
        s = obs(s, [m("a"), m("b"), m("d", draft: true), m("x", accessible: false)])
        XCTAssertEqual(Set(s.pending.keys), ["b"])
        s = obs(s, [m("a"), m("b", accessible: false)])
        XCTAssertFalse(s.hasPending)
    }

    func testPendingThatStopsMatchingIsDropped() {
        var s = obs(ForYouAlertState(), [m("a")])
        s = obs(s, [m("a"), m("b")])
        s = obs(s, [m("a")])
        XCTAssertFalse(s.hasPending)
    }

    func testPersistenceRoundTripAndRelaunchNoReplay() {
        let d = suite()
        var s = obs(ForYouAlertState(), [m("a")])
        s = obs(s, [m("a"), m("b")])
        ForYouAlert.save(s, userID: "u1", defaults: d)
        let back = ForYouAlert.load(userID: "u1", defaults: d)
        XCTAssertEqual(back, s)
        XCTAssertEqual(Set(obs(back, [m("a"), m("b")]).pending.keys), ["b"])
        let acked = ForYouAlert.acknowledge(back, loadedIDs: ["b"])
        ForYouAlert.save(acked, userID: "u1", defaults: d)
        XCTAssertFalse(obs(ForYouAlert.load(userID: "u1", defaults: d), [m("a"), m("b")]).hasPending)
    }

    func testPerAccountIsolation() {
        let d = suite()
        ForYouAlert.save(obs(ForYouAlertState(), [m("a")]), userID: "u1", defaults: d)
        let s2 = ForYouAlert.load(userID: "u2", defaults: d)
        XCTAssertFalse(s2.baselined); XCTAssertTrue(s2.seen.isEmpty)
    }

    func testPrefsVersionChangeRebaselines() {
        var s = obs(ForYouAlertState(), [m("a")], pv: 1)
        s = obs(s, [m("a"), m("b")], pv: 1)
        XCTAssertTrue(s.hasPending)
        s = obs(s, [m("a"), m("b"), m("c")], pv: 2)
        XCTAssertFalse(s.hasPending); XCTAssertEqual(s.prefsVersion, 2); XCTAssertNotNil(s.seen["c"])
    }

    func testAcknowledgeClearsOnlyLoadedIDs() {
        var s = obs(ForYouAlertState(), [m("a")])
        s = obs(s, [m("a"), m("b"), m("c")])
        s = ForYouAlert.acknowledge(s, loadedIDs: ["a", "b", "c"])
        XCTAssertFalse(s.hasPending)
        s = obs(s, [m("a"), m("b"), m("c"), m("d")])
        XCTAssertEqual(Set(ForYouAlert.acknowledge(s, loadedIDs: ["x"]).pending.keys), ["d"])
        s = obs(s, [m("a"), m("b"), m("c"), m("d"), m("e")])
        s = ForYouAlert.acknowledge(s, loadedIDs: ["d"])
        XCTAssertEqual(Set(s.pending.keys), ["e"])
    }

    func testLoadingSkipsObservation() {
        let s0 = ForYouAlertState()
        XCTAssertEqual(obs(s0, [m("a")], loading: true), s0)
        let s = obs(s0, [m("a")])
        XCTAssertEqual(obs(s, [], loading: true), s)
    }

    func testSeenIsBounded() {
        var s = obs(ForYouAlertState(), [m("a0")], limit: 5)
        s = obs(s, (0..<8).map { m("n\($0)") }, limit: 5)
        XCTAssertEqual(s.seen.count, 5); XCTAssertEqual(s.order.count, 5)
        XCTAssertNil(s.seen["a0"]); XCTAssertNotNil(s.seen["n7"])
    }
}
