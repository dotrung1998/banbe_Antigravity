import Foundation

/// Platform feature flags (migration 187, note 51): a platform admin can hide a feature everywhere without a
/// release. Web twin: src/lib/featureFlags.js — keep both and their tests in sync.
///
/// Rules, so a flag can never hide something by accident:
/// - A key that is MISSING means "on". Only an explicit `false` from the server hides a feature.
/// - The server answer is cached on the device, so a cold start without network keeps the last-known value instead
///   of flipping a hidden feature back on (or a visible one off). The very first run, before any answer, shows
///   everything, which is the behaviour from before flags existed.
/// - Anything that is not a boolean, and any key this build does not know, is ignored.
enum FeatureFlags {
    static let keys = ["rewards"]
    static let cacheKey = "banbe.featureFlags.v1"

    /// Keep only known keys with real booleans.
    static func normalize(_ raw: [String: Bool?]) -> [String: Bool] {
        var out: [String: Bool] = [:]
        for k in keys { if let v = raw[k], let b = v { out[k] = b } }
        return out
    }

    /// Missing key = on.
    static func isOn(_ flags: [String: Bool], _ key: String) -> Bool { flags[key] != false }

    static func read(_ defaults: UserDefaults = .standard) -> [String: Bool] {
        guard let data = defaults.data(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode([String: Bool].self, from: data) else { return [:] }
        return normalize(decoded.mapValues { Optional($0) })
    }

    static func write(_ flags: [String: Bool], _ defaults: UserDefaults = .standard) {
        let clean = normalize(flags.mapValues { Optional($0) })
        if let data = try? JSONEncoder().encode(clean) { defaults.set(data, forKey: cacheKey) }
    }
}
