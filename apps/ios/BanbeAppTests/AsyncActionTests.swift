import XCTest
@testable import BanbeApp

/// Mirrors tests/unit/asyncAction.test.mjs — change both together.
final class AsyncActionTests: XCTestCase {
    private func run(_ events: [AsyncActionState.Event], from: AsyncActionState = .init()) -> AsyncActionState {
        events.reduce(from) { $0.reduce($1) }
    }

    func testHappyPathFiresOnce() {
        var s = run([.start])
        XCTAssertEqual(s.phase, .pending)
        s = s.reduce(.resolve(ok: true, error: nil))
        XCTAssertEqual(s.phase, .success)
        XCTAssertFalse(s.fired)
        s = s.reduce(.animDone)
        XCTAssertEqual(s.phase, .completed)
        XCTAssertTrue(s.fired)
        XCTAssertEqual(s.reduce(.animDone), s)
    }

    func testDuplicateStartIgnored() {
        let p = run([.start])
        XCTAssertEqual(p.reduce(.start), p)
        let ok = run([.start, .resolve(ok: true, error: nil)])
        XCTAssertEqual(ok.reduce(.start), ok)
        XCTAssertTrue(AsyncActionPhase.pending.isLocked && AsyncActionPhase.success.isLocked && AsyncActionPhase.completed.isLocked)
        XCTAssertFalse(AsyncActionPhase.idle.isLocked || AsyncActionPhase.failure.isLocked)
    }

    func testFailureNeverSucceedsAndResetsKeepingError() {
        var s = run([.start, .resolve(ok: false, error: "NETWORK")])
        XCTAssertEqual(s.phase, .failure)
        XCTAssertEqual(s.reduce(.animDone), s)
        s = s.reduce(.reset)
        XCTAssertEqual(s, AsyncActionState(phase: .idle, error: "NETWORK", fired: false))
        XCTAssertNil(s.reduce(.start).error)
    }

    func testResolveOutsidePendingAndResetWhilePendingIgnored() {
        let idle = AsyncActionState()
        XCTAssertEqual(idle.reduce(.resolve(ok: true, error: nil)), idle)
        let p = run([.start])
        XCTAssertEqual(p.reduce(.reset), p)
    }

    func testCompletedStayAndUpdateResets() {
        XCTAssertEqual(run([.start, .resolve(ok: true, error: nil), .animDone, .reset]), AsyncActionState())
    }
}
