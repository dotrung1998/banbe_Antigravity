import Foundation
import UIKit
import CoreMotion

// Motion model for the profile keychain (note 35 contract numbers):
//   theta'' = -(g/L) sin(theta) - c theta' + impulse
//   stretch s in [-0.12, +0.35] (fraction of the charm length), spring + damping
//   angle clamp +-0.9 rad; settle when |theta|<0.004 && |theta'|<0.02 && |s|<0.002.
// Pure value type: no UIKit/time/sensor dependency, fully testable via step(dt).

struct KeychainPhysics: Equatable {
    // contract limits
    static let maxAngle = 0.9
    static let minStretch = -0.12
    static let maxStretch = 0.35
    static let angleEpsilon = 0.004
    static let velocityEpsilon = 0.02
    static let stretchEpsilon = 0.002
    /// Sensor / shake impulse cap (rad/s) per event.
    static let sensorImpulseCap = 0.35
    /// "Swing" button / accessibility impulse (rad/s): bounded, visibly lively.
    static let swingImpulse = 2.2
    /// Cap for any caller-provided (non-sensor) impulse.
    static let userImpulseCap = 3.0
    static let maxVelocity = 8.0

    // tunables (shared numbers)
    var gOverL = 36.0          // omega0 = 6 rad/s, ~1 s period
    var damping = 1.1          // c, 1/s
    var stretchK = 140.0
    var stretchDamping = 9.0
    var maxStep = 1.0 / 120.0
    var maxFrameDt = 1.0 / 15.0

    private(set) var angle = 0.0
    private(set) var angularVelocity = 0.0
    private(set) var stretch = 0.0
    private(set) var stretchVelocity = 0.0
    private(set) var isDragging = false

    var isSettled: Bool {
        !isDragging && abs(angle) < Self.angleEpsilon && abs(angularVelocity) < Self.velocityEpsilon
            && abs(stretch) < Self.stretchEpsilon
    }

    /// Adds angular velocity, capped (default: the sensor cap). Returns the applied delta.
    @discardableResult
    mutating func applyImpulse(_ dOmega: Double, cap: Double = KeychainPhysics.sensorImpulseCap) -> Double {
        guard dOmega.isFinite else { return 0 }
        let c = min(abs(cap), Self.userImpulseCap)
        let d = max(-c, min(c, dOmega))
        angularVelocity = max(-Self.maxVelocity, min(Self.maxVelocity, angularVelocity + d))
        return d
    }

    /// The Swing button: one bounded impulse in `direction` (+1 / -1).
    mutating func swing(direction: Double = 1) {
        applyImpulse((direction < 0 ? -1 : 1) * Self.swingImpulse, cap: Self.userImpulseCap)
    }

    /// Finger is holding the charm: stretch/angle are driven, not integrated.
    mutating func drag(stretch s: Double, angle a: Double) {
        isDragging = true
        stretch = Self.clamp(s, Self.minStretch, Self.maxStretch)
        angle = Self.clamp(a, -Self.maxAngle, Self.maxAngle)
        angularVelocity = 0
        stretchVelocity = 0
    }

    /// Let go: damped settle from wherever the finger left it.
    mutating func release(angularVelocity w: Double = 0, stretchVelocity sv: Double = 0) {
        isDragging = false
        angularVelocity = Self.clamp(w.isFinite ? w : 0, -Self.maxVelocity, Self.maxVelocity)
        stretchVelocity = Self.clamp(sv.isFinite ? sv : 0, -Self.maxVelocity, Self.maxVelocity)
    }

    mutating func reset() { isDragging = false; rest() }

    init() {}

    /// Advances by `dt` seconds (sub-stepped, semi-implicit Euler). Snaps to
    /// rest exactly when the settle test passes.
    mutating func step(_ dt: Double) {
        guard !isDragging, dt.isFinite, dt > 0 else { return }
        var remaining = min(dt, maxFrameDt)
        while remaining > 1e-9 {
            let h = min(remaining, maxStep)
            remaining -= h
            angularVelocity += (-gOverL * sin(angle) - damping * angularVelocity) * h
            angularVelocity = Self.clamp(angularVelocity, -Self.maxVelocity, Self.maxVelocity)
            angle += angularVelocity * h
            if abs(angle) > Self.maxAngle { angle = Self.clamp(angle, -Self.maxAngle, Self.maxAngle); angularVelocity = 0 }

            stretchVelocity += (-stretchK * stretch - stretchDamping * stretchVelocity) * h
            stretchVelocity = Self.clamp(stretchVelocity, -Self.maxVelocity * 4, Self.maxVelocity * 4)
            stretch += stretchVelocity * h
            if stretch > Self.maxStretch || stretch < Self.minStretch {
                stretch = Self.clamp(stretch, Self.minStretch, Self.maxStretch); stretchVelocity = 0
            }
            if isSettled { rest(); return }
        }
    }

    private mutating func rest() { angle = 0; angularVelocity = 0; stretch = 0; stretchVelocity = 0 }

    static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { max(lo, min(hi, v)) }
}

// MARK: - Sensor source (protocol so tests inject a fake)

struct KeychainMotionSample: Equatable {
    /// Seconds on a monotonic clock (CMDeviceMotion.timestamp).
    var timestamp: TimeInterval
    /// Lateral user acceleration in g (shake), +x = device right.
    var accelX: Double
    /// Rotation rate about the device y axis (rad/s) — a tilt/roll flick.
    var rotationY: Double
}

protocol KeychainMotionSource: AnyObject {
    var isAvailable: Bool { get }
    /// Begins low-rate updates; the handler is delivered on the main queue.
    func start(interval: TimeInterval, handler: @escaping (KeychainMotionSample) -> Void)
    func stop()
}

final class CoreKeychainMotionSource: KeychainMotionSource {
    private let manager = CMMotionManager()
    var isAvailable: Bool { manager.isDeviceMotionAvailable }
    func start(interval: TimeInterval, handler: @escaping (KeychainMotionSample) -> Void) {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = interval
        manager.startDeviceMotionUpdates(to: .main) { motion, _ in
            guard let m = motion else { return }
            handler(KeychainMotionSample(timestamp: m.timestamp, accelX: m.userAcceleration.x, rotationY: m.rotationRate.y))
        }
    }
    func stop() { if manager.isDeviceMotionActive { manager.stopDeviceMotionUpdates() } }
}

/// Decides WHEN sensors run and converts samples to capped impulses.
/// Sensors run only while: visible AND foreground AND motion enabled AND not
/// Reduce Motion AND the source is available AND not idle for `idleTimeout`
/// (battery bound; any interaction / re-appearance wakes it again).
@MainActor
final class KeychainMotionController {
    static let updateInterval: TimeInterval = 1.0 / 30.0
    static let minImpulseSpacing: TimeInterval = 0.12
    static let noiseFloor = 0.03
    static let idleTimeout: TimeInterval = 60

    struct Conditions: Equatable {
        var visible = false
        var foreground = false
        var motionEnabled = false
        var reduceMotion = false
    }

    private let source: KeychainMotionSource
    private let onImpulse: (Double) -> Void
    private(set) var conditions = Conditions()
    private(set) var isRunning = false
    private var lastImpulseTime: TimeInterval = -.infinity
    private var lastActivityTime: TimeInterval?
    private var sessionStart: TimeInterval?

    init(source: KeychainMotionSource, onImpulse: @escaping (Double) -> Void) {
        self.source = source
        self.onImpulse = onImpulse
    }

    var shouldRun: Bool {
        conditions.visible && conditions.foreground && conditions.motionEnabled && !conditions.reduceMotion && source.isAvailable
    }

    func update(_ new: Conditions) {
        let becameVisible = new.visible && !conditions.visible
        conditions = new
        if becameVisible { lastActivityTime = nil; sessionStart = nil }
        reconcile()
    }

    /// Call on user interaction (swing/drag) to restart the idle window.
    func noteActivity() {
        lastActivityTime = nil; sessionStart = nil
        reconcile()
    }

    func stop() { conditions = Conditions(); reconcile() }

    private func reconcile() {
        if shouldRun, !isRunning {
            isRunning = true
            source.start(interval: Self.updateInterval) { [weak self] s in
                MainActor.assumeIsolated { self?.handle(s) }
            }
        } else if !shouldRun, isRunning {
            isRunning = false
            source.stop()
        }
    }

    /// Public for tests (the fake source forwards here via its handler).
    func handle(_ s: KeychainMotionSample) {
        guard isRunning else { return }
        if sessionStart == nil { sessionStart = s.timestamp; lastActivityTime = s.timestamp }
        let raw = -(s.accelX * 1.2 + s.rotationY * 0.08)
        guard raw.isFinite, abs(raw) >= Self.noiseFloor else {
            if let last = lastActivityTime, s.timestamp - last >= Self.idleTimeout { isRunning = false; source.stop() }
            return
        }
        guard s.timestamp - lastImpulseTime >= Self.minImpulseSpacing else { return }
        lastImpulseTime = s.timestamp
        lastActivityTime = s.timestamp
        onImpulse(KeychainPhysics.clamp(raw, -KeychainPhysics.sensorImpulseCap, KeychainPhysics.sensorImpulseCap))
    }
}
