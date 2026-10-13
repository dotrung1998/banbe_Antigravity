import CoreGraphics
import Foundation

/// Pure math for the host-profile reveal (mirror of src/lib/hostReveal.js): dots leave the setup
/// sheet, swirl into a rotating Earth-like sphere, then coalesce into the host card. No UI here.
enum HostReveal {
    enum Timeline {
        static let gather = 900.0     // sheet elements -> loose cloud, swirling
        static let form = 1700.0      // cloud -> sphere
        static let spin = 1100.0      // sphere rotates on its own
        static let coalesce = 1100.0  // sphere -> host card
        static var total: Double { gather + form + spin + coalesce }
        static var coalesceStart: Double { gather + form + spin }
    }

    struct SourceRect { var rect: CGRect; var radius: CGFloat = 14 }

    struct Particle {
        var sx: Double, sy: Double
        var cloudX: Double, cloudY: Double
        var sx3: Double, sy3: Double, sz3: Double   // point on the unit sphere
        var land: Bool
        var dx: Double, dy: Double
        var size: Double
        var swirl: Double
        var delay: Double
    }

    struct State { var x: Double, y: Double, r: Double, alpha: Double, depth: Double }

    struct View { var cx: Double, cy: Double, radius: Double
        var tilt = 0.35, spinRate = 0.0011 }

    static func clamp01(_ v: Double) -> Double { min(1, max(0, v)) }
    static func easeInOut(_ t: Double) -> Double { t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
    static func easeOut(_ t: Double) -> Double { 1 - pow(1 - t, 3) }
    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    /// Deterministic PRNG so a given reveal looks the same in tests.
    struct Mulberry32 {
        private var a: UInt32
        init(seed: UInt32) { a = seed }
        mutating func next() -> Double {
            a = a &+ 0x6D2B79F5
            var t = a
            t = (t ^ (t >> 15)) &* (t | 1)
            t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
            return Double(t ^ (t >> 14)) / 4294967296.0
        }
    }

    static func fibonacciSphere(_ n: Int) -> [(x: Double, y: Double, z: Double)] {
        let golden = Double.pi * (3 - sqrt(5.0))
        return (0..<n).map { i in
            let y = 1 - (Double(i) / Double(max(1, n - 1))) * 2
            let r = sqrt(max(0, 1 - y * y))
            let th = golden * Double(i)
            return (cos(th) * r, y, sin(th) * r)
        }
    }

    /// Cheap continent-ish mask (true = "land", drawn brighter).
    static func isLand(x: Double, y: Double, z: Double) -> Bool {
        let lon = atan2(z, x), lat = asin(y)
        let v = sin(lon * 2 + 0.7) * cos(lat * 3 - 0.4) + 0.6 * sin(lon * 5 - lat * 2 + 1.3) + 0.35 * cos(lon * 9 + lat * 4)
        return v > 0.25
    }

    static func sample(in rect: CGRect, radius: CGFloat, rng: inout Mulberry32) -> CGPoint {
        let r = min(radius, rect.width / 2, rect.height / 2)
        var p = CGPoint.zero
        for _ in 0..<8 {
            p = CGPoint(x: rect.minX + rng.next() * rect.width, y: rect.minY + rng.next() * rect.height)
            let dx = max(rect.minX + r - p.x, 0, p.x - (rect.maxX - r))
            let dy = max(rect.minY + r - p.y, 0, p.y - (rect.maxY - r))
            if dx * dx + dy * dy <= r * r { return p }
        }
        return p
    }

    static func buildParticles(count: Int, sources: [SourceRect], target: CGRect?, view: View, seed: UInt32 = 7, targetRadius: CGFloat = 22) -> [Particle] {
        var rng = Mulberry32(seed: seed)
        let sphere = fibonacciSphere(count)
        let totalArea = max(1, sources.reduce(0) { $0 + Double($1.rect.width * $1.rect.height) })
        var out: [Particle] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            var pick = rng.next() * totalArea
            var src = sources.first
            for s in sources { pick -= Double(s.rect.width * s.rect.height); if pick <= 0 { src = s; break } }
            let start = src.map { sample(in: $0.rect, radius: $0.radius, rng: &rng) } ?? CGPoint(x: view.cx, y: view.cy)
            let ang = rng.next() * .pi * 2
            let dist = view.radius * (0.9 + rng.next() * 1.1)
            let dst: CGPoint
            if let target { dst = sample(in: target, radius: targetRadius, rng: &rng) }
            else { dst = CGPoint(x: view.cx + (rng.next() - 0.5) * view.radius, y: view.cy + (rng.next() - 0.5) * view.radius) }
            let sp = sphere[i]
            out.append(Particle(
                sx: start.x, sy: start.y,
                cloudX: view.cx + cos(ang) * dist, cloudY: view.cy + sin(ang) * dist * 0.8,
                sx3: sp.x, sy3: sp.y, sz3: sp.z, land: isLand(x: sp.x, y: sp.y, z: sp.z),
                dx: dst.x, dy: dst.y,
                size: 0.9 + rng.next() * 1.1, swirl: 0.8 + rng.next() * 0.6, delay: rng.next() * 0.18))
        }
        return out
    }

    static func state(_ p: Particle, at t: Double, view v: View) -> State {
        let gather = Timeline.gather, form = Timeline.form, coalesce = Timeline.coalesce
        let tForm0 = gather, tSpin0 = gather + form, tCoal0 = Timeline.coalesceStart
        func sphereAt(_ time: Double) -> (x: Double, y: Double, depth: Double) {
            let rot = time * v.spinRate
            let x = p.sx3 * cos(rot) - p.sz3 * sin(rot)
            var z = p.sx3 * sin(rot) + p.sz3 * cos(rot)
            let y = p.sy3 * cos(v.tilt) - z * sin(v.tilt)
            z = p.sy3 * sin(v.tilt) + z * cos(v.tilt)
            return (v.cx + x * v.radius, v.cy + y * v.radius, z)
        }
        func swirl(_ x: Double, _ y: Double, _ turns: Double) -> (Double, Double) {
            let ox = x - v.cx, oy = y - v.cy, a = turns * .pi * 2, c = cos(a), s = sin(a)
            return (v.cx + ox * c - oy * s, v.cy + ox * s + oy * c)
        }
        var x = 0.0, y = 0.0, depth = 0.0, alpha = 1.0, scale = 1.0
        if t < tForm0 {
            let k = easeInOut(clamp01((t / gather - p.delay) / (1 - p.delay)))
            let sw = swirl(lerp(p.sx, p.cloudX, k), lerp(p.sy, p.cloudY, k), 0.25 * p.swirl * k)
            x = sw.0; y = sw.1; alpha = 0.35 + 0.65 * k
        } else if t < tSpin0 {
            let k = easeInOut(clamp01((t - tForm0) / form))
            let s = sphereAt(t)
            let sw = swirl(lerp(p.cloudX, s.x, k), lerp(p.cloudY, s.y, k), (1 - k) * 1.15 * p.swirl)
            x = sw.0; y = sw.1; depth = s.depth * k
        } else if t < tCoal0 {
            let s = sphereAt(t)
            x = s.x; y = s.y; depth = s.depth
        } else {
            let k = easeInOut(clamp01((t - tCoal0) / coalesce))
            let s = sphereAt(t)
            let sw = swirl(lerp(s.x, p.dx, k), lerp(s.y, p.dy, k), (1 - k) * 0.12 * p.swirl)
            x = lerp(sw.0, p.dx, k * k); y = lerp(sw.1, p.dy, k * k)
            depth = s.depth * (1 - k)
            alpha = 1 - easeOut(clamp01((k - 0.75) / 0.25))
        }
        if t >= tForm0 {
            let d = (depth + 1) / 2
            scale = 0.65 + 0.7 * d
            alpha *= (0.25 + 0.75 * d) * (p.land ? 1 : 0.62)
        }
        return State(x: x, y: y, r: p.size * scale, alpha: clamp01(alpha), depth: depth)
    }
}
