import XCTest
import UIKit
@testable import BanbeApp

final class KeychainPhysicsTests: XCTestCase {
    func testBoundedAndDamped() {
        var p = KeychainPhysics()
        p.applyImpulse(100, cap: 100)      // clamps to userImpulseCap
        var peak = 0.0
        for _ in 0..<600 {
            p.step(1.0 / 60.0)
            peak = max(peak, abs(p.angle))
            XCTAssertLessThanOrEqual(abs(p.angle), KeychainPhysics.maxAngle + 1e-9)
            XCTAssertLessThanOrEqual(p.stretch, KeychainPhysics.maxStretch)
            XCTAssertGreaterThanOrEqual(p.stretch, KeychainPhysics.minStretch)
        }
        XCTAssertGreaterThan(peak, 0.1)
        XCTAssertTrue(p.isSettled, "must settle within 10s")
        XCTAssertEqual(p.angle, 0)
    }

    func testSettlesAndRestsExactly() {
        var p = KeychainPhysics()
        p.swing()
        var t = 0.0
        while !p.isSettled && t < 30 { p.step(1.0 / 60.0); t += 1.0 / 60.0 }
        XCTAssertTrue(p.isSettled)
        XCTAssertLessThan(t, 15)
        XCTAssertEqual(p.angularVelocity, 0)
    }

    func testSensorImpulseCap() {
        var p = KeychainPhysics()
        let applied = p.applyImpulse(5)
        XCTAssertEqual(applied, KeychainPhysics.sensorImpulseCap, accuracy: 1e-12)
        XCTAssertEqual(p.angularVelocity, 0.35, accuracy: 1e-12)
        p.applyImpulse(-.infinity)
        XCTAssertEqual(p.angularVelocity, 0.35, accuracy: 1e-12)
    }

    func testDragClampsAndReleaseSettles() {
        var p = KeychainPhysics()
        p.drag(stretch: 9, angle: 9)
        XCTAssertEqual(p.stretch, KeychainPhysics.maxStretch)
        XCTAssertEqual(p.angle, KeychainPhysics.maxAngle)
        XCTAssertTrue(p.isDragging); XCTAssertFalse(p.isSettled)
        p.step(0.1)
        XCTAssertEqual(p.angle, KeychainPhysics.maxAngle, "no integration while held")
        p.release()
        for _ in 0..<900 { p.step(1.0 / 60.0) }
        XCTAssertTrue(p.isSettled)
    }

    func testHugeDtIsBounded() {
        var p = KeychainPhysics()
        p.swing()
        p.step(1000)
        XCTAssertTrue(p.angle.isFinite)
        XCTAssertLessThanOrEqual(abs(p.angle), KeychainPhysics.maxAngle)
    }
}

final class KeychainManifestTests: XCTestCase {
    private func loadManifest() throws -> KeychainManifest {
        if let m = KeychainManifest.bundled { return m }
        // Fallback: repo path (tests may run without the resource in the host bundle).
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<2 { url.deleteLastPathComponent() }   // apps/ios
        let json = url.appendingPathComponent("BanbeApp/Resources/Keychains/manifest.json")
        let data = try Data(contentsOf: json)
        return try XCTUnwrap(KeychainManifest.decode(data))
    }

    func testManifestHas24FreeDesignsPlus3RewardDesigns() throws {
        let m = try loadManifest()
        XCTAssertEqual(m.designs.count, 27)
        XCTAssertEqual(Set(m.designs.map(\.id)).count, 27)
        XCTAssertEqual(m.designs.filter { $0.reward != true }.count, 24, "the free basic charms remain")
        XCTAssertEqual(m.designs.filter { $0.reward == true }.map(\.id), ["rwd-comet", "rwd-lantern", "rwd-crown"])
        XCTAssertEqual(m.groups.count, 8)
        let expected = ["sky": 3, "love": 3, "bloom": 4, "cafe": 3, "pals": 3, "trip": 4, "banbe": 4, "rewards": 3]
        for (g, n) in expected { XCTAssertEqual(m.designs(in: g).count, n, g) }
        XCTAssertEqual(m.pivot.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(m.pivot.y, 0.045, accuracy: 1e-9)
        XCTAssertEqual(m.scale(.s), 0.7); XCTAssertEqual(m.scale(.l), 1.35)
    }

    func testEveryDesignHasAPng() throws {
        let m = try loadManifest()
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<2 { url.deleteLastPathComponent() }
        let dir = url.appendingPathComponent("BanbeApp/Resources/Keychains")
        for d in m.designs {
            XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(d.file).path), d.file)
        }
    }

    func testConfigDecodingIsTolerant() throws {
        let c = try JSONDecoder().decode(KeychainConfig.self, from: Data(#"{"enabled":true,"anchor":"nope","size":"xl"}"#.utf8))
        XCTAssertTrue(c.enabled); XCTAssertEqual(c.anchor, .topRight); XCTAssertEqual(c.size, .m)
        XCTAssertEqual(c.designId, "sky-star")
    }
}

final class KeychainArtValidatorTests: XCTestCase {
    private func png(_ w: Int, _ h: Int) -> Data {
        let f = UIGraphicsImageRendererFormat.default(); f.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: f).image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }.pngData()!
    }

    func testRejectsSVGHTMLGIFHEICAndSpoofs() {
        let svg = Data(#"<svg xmlns="http://www.w3.org/2000/svg"/>"#.utf8)
        let html = Data("<html><script>alert(1)</script></html>".utf8)
        let gif = Data("GIF89a".utf8) + Data(repeating: 0, count: 32)
        let heic = Data([0, 0, 0, 24]) + Data("ftypheic".utf8) + Data(repeating: 0, count: 16)
        for d in [svg, html, gif, heic] {
            XCTAssertThrowsError(try KeychainArtValidator.prepare(d)) { XCTAssertEqual($0 as? KeychainArtError, .unsupportedType) }
        }
    }

    func testRejectsOversizeInput() {
        let big = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + Data(repeating: 0, count: KeychainArtValidator.maxInputBytes)
        XCTAssertThrowsError(try KeychainArtValidator.prepare(big)) { XCTAssertEqual($0 as? KeychainArtError, .fileTooLarge) }
    }

    func testTruncatedPngFailsToDecode() {
        let bad = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])
        XCTAssertThrowsError(try KeychainArtValidator.prepare(bad))
    }

    func testDownscalesToLongEdge512AndStaysUnder256KB() throws {
        let out = try KeychainArtValidator.prepare(png(1500, 1000))
        XCTAssertLessThanOrEqual(max(out.width, out.height), 512)
        XCTAssertLessThanOrEqual(out.data.count, KeychainArtValidator.maxOutputBytes)
        XCTAssertEqual(KeychainArtValidator.sniff(out.data), .png)
    }

    func testServerErrorMapping() {
        XCTAssertEqual(KeychainArtService.map(status: 429, error: nil), .rateLimited)
        XCTAssertEqual(KeychainArtService.map(status: 400, error: "quota_exceeded"), .quotaExceeded)
        XCTAssertEqual(KeychainArtService.map(status: 401, error: nil), .notSignedIn)
        XCTAssertFalse(KeychainArtError.quotaExceeded.message({ vi, _ in vi }).isEmpty)
    }
}

private final class FakeMotionSource: KeychainMotionSource {
    var isAvailable = true
    var starts = 0, stops = 0
    var handler: ((KeychainMotionSample) -> Void)?
    func start(interval: TimeInterval, handler: @escaping (KeychainMotionSample) -> Void) { starts += 1; self.handler = handler }
    func stop() { stops += 1; handler = nil }
}

@MainActor
final class KeychainMotionControllerTests: XCTestCase {
    private func on() -> KeychainMotionController.Conditions {
        .init(visible: true, foreground: true, motionEnabled: true, reduceMotion: false)
    }

    func testStartsOnlyWhenAllConditionsHold() {
        let src = FakeMotionSource()
        let c = KeychainMotionController(source: src) { _ in }
        var cond = on()
        for flip in 0..<4 {
            cond = on()
            switch flip { case 0: cond.visible = false; case 1: cond.foreground = false
                          case 2: cond.motionEnabled = false; default: cond.reduceMotion = true }
            c.update(cond)
            XCTAssertFalse(c.isRunning); XCTAssertEqual(src.starts, 0)
        }
        c.update(on())
        XCTAssertTrue(c.isRunning); XCTAssertEqual(src.starts, 1)
        c.update(on())                       // idempotent
        XCTAssertEqual(src.starts, 1)
    }

    func testStopsOnBackgroundDisableAndUnavailable() {
        let src = FakeMotionSource()
        let c = KeychainMotionController(source: src) { _ in }
        c.update(on()); XCTAssertTrue(c.isRunning)
        var bg = on(); bg.foreground = false
        c.update(bg); XCTAssertFalse(c.isRunning); XCTAssertEqual(src.stops, 1)
        c.update(on()); XCTAssertTrue(c.isRunning)
        var off = on(); off.motionEnabled = false
        c.update(off); XCTAssertFalse(c.isRunning)
        src.isAvailable = false
        c.update(on()); XCTAssertFalse(c.isRunning)
    }

    func testImpulsesAreCappedAndRateLimited() {
        let src = FakeMotionSource()
        var got: [Double] = []
        let c = KeychainMotionController(source: src) { got.append($0) }
        c.update(on())
        c.handle(.init(timestamp: 10.00, accelX: -5, rotationY: 0))      // huge -> capped
        c.handle(.init(timestamp: 10.05, accelX: -5, rotationY: 0))      // < 120 ms -> dropped
        c.handle(.init(timestamp: 10.13, accelX: 0.001, rotationY: 0))   // noise -> ignored
        c.handle(.init(timestamp: 10.20, accelX: 5, rotationY: 0))
        XCTAssertEqual(got.count, 2)
        XCTAssertEqual(got[0], 0.35, accuracy: 1e-12)
        XCTAssertEqual(got[1], -0.35, accuracy: 1e-12)
    }

    func testIdleTimeoutStopsSensor() {
        let src = FakeMotionSource()
        let c = KeychainMotionController(source: src) { _ in }
        c.update(on())
        c.handle(.init(timestamp: 0, accelX: 0, rotationY: 0))
        c.handle(.init(timestamp: KeychainMotionController.idleTimeout + 1, accelX: 0, rotationY: 0))
        XCTAssertFalse(c.isRunning)
        c.noteActivity()                     // interaction wakes it
        XCTAssertTrue(c.isRunning)
    }
}
