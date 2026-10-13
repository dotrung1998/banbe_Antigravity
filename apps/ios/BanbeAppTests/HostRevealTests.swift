import XCTest
@testable import BanbeApp

final class HostRevealTests: XCTestCase {
    private let view = HostReveal.View(cx: 200, cy: 300, radius: 90)
    private func make() -> [HostReveal.Particle] {
        HostReveal.buildParticles(
            count: 300,
            sources: [.init(rect: CGRect(x: 20, y: 100, width: 360, height: 160)), .init(rect: CGRect(x: 20, y: 700, width: 360, height: 50))],
            target: CGRect(x: 20, y: 120, width: 360, height: 90), view: view, seed: 3)
    }

    func testTimelineTotal() {
        let t = HostReveal.Timeline.self
        XCTAssertEqual(t.total, t.gather + t.form + t.spin + t.coalesce)
    }

    func testSphereSitsOnSphereMidSpinAndEndsInsideTargetFaded() {
        let parts = make()
        let mid = HostReveal.Timeline.gather + HostReveal.Timeline.form + HostReveal.Timeline.spin / 2
        for p in parts {
            let s = HostReveal.state(p, at: mid, view: view)
            XCTAssertLessThanOrEqual(hypot(s.x - view.cx, s.y - view.cy), view.radius + 1e-6)
            let e = HostReveal.state(p, at: HostReveal.Timeline.total, view: view)
            XCTAssertTrue(e.x >= 19 && e.x <= 381 && e.y >= 119 && e.y <= 211)
            XCTAssertEqual(e.alpha, 0)
        }
    }

    func testAlphaAndRadiusStayInRange() {
        let parts = make()
        var t = 0.0
        while t <= HostReveal.Timeline.total {
            for p in parts { let s = HostReveal.state(p, at: t, view: view); XCTAssertTrue(s.alpha >= 0 && s.alpha <= 1 && s.r > 0) }
            t += 200
        }
    }

    func testStockCoversRender() {
        XCTAssertEqual(Set(HostStockCover.all.map(\.id)).count, HostStockCover.all.count)
        XCTAssertEqual(HostStockCover.all[0].image(side: 64).size.width, 64)
    }
}
