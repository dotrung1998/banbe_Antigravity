import Foundation
import UIKit

// Profile keychain (note 35, "Shared keychain contract"). Appearance metadata
// only — never sensor readings or drag positions.

enum KeychainAnchor: String, Codable, CaseIterable, Identifiable {
    case topLeft = "top_left", topRight = "top_right", bottomLeft = "bottom_left", bottomRight = "bottom_right"
    var id: String { rawValue }
    /// PHYSICAL corners (not leading/trailing) — documented: a keychain on the
    /// "left" stays on the left in RTL layouts too, matching the web.
    var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    var isTop: Bool { self == .topLeft || self == .topRight }
    func label(_ T: (String, String) -> String) -> String {
        switch self {
        case .topLeft: return T("Trên trái", "Top left")
        case .topRight: return T("Trên phải", "Top right")
        case .bottomLeft: return T("Dưới trái", "Bottom left")
        case .bottomRight: return T("Dưới phải", "Bottom right")
        }
    }
}

enum KeychainSize: String, Codable, CaseIterable, Identifiable {
    case s, m, l
    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
}

/// Server config (camelCase JSON). Decoding is tolerant: unknown/invalid
/// values fall back to the contract defaults so a bad row can never crash.
struct KeychainConfig: Codable, Equatable {
    struct CustomAsset: Codable, Equatable {
        var id: String
        var path: String
        var width: Int?
        var height: Int?
    }
    static let customDesignID = "custom"
    static let defaultDesignID = "sky-star"

    var enabled: Bool = false
    var designId: String = KeychainConfig.defaultDesignID
    var anchor: KeychainAnchor = .topRight
    var size: KeychainSize = .m
    var motionEnabled: Bool = true
    var customAsset: CustomAsset?
    var updatedAt: String?

    static let `default` = KeychainConfig()

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? false
        designId = (try? c.decode(String.self, forKey: .designId)) ?? Self.defaultDesignID
        anchor = (try? c.decode(KeychainAnchor.self, forKey: .anchor)) ?? .topRight
        size = (try? c.decode(KeychainSize.self, forKey: .size)) ?? .m
        motionEnabled = (try? c.decode(Bool.self, forKey: .motionEnabled)) ?? true
        customAsset = try? c.decodeIfPresent(CustomAsset.self, forKey: .customAsset)
        updatedAt = try? c.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    /// Params for `save_my_keychain` (`customAssetId` only for custom art).
    func savePayload() -> [String: AnyJSONValue] {
        var p: [String: AnyJSONValue] = [
            "enabled": .bool(enabled), "designId": .string(designId),
            "anchor": .string(anchor.rawValue), "size": .string(size.rawValue),
            "motionEnabled": .bool(motionEnabled),
        ]
        if designId == Self.customDesignID, let id = customAsset?.id { p["customAssetId"] = .string(id) }
        else { p["customAssetId"] = .null }
        return p
    }
}

/// Tiny JSON value for the RPC argument (keeps this file free of the Supabase import).
enum AnyJSONValue: Encodable, Equatable {
    case string(String), bool(Bool), null
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .bool(let b): try c.encode(b)
        case .null: try c.encodeNil()
        }
    }
}

struct KeychainEnvelope: Decodable {
    let success: Bool?
    let error: String?
    let keychain: KeychainConfig?
}

// MARK: manifest

struct KeychainManifest: Decodable, Equatable {
    struct Point: Decodable, Equatable { let x: Double; let y: Double }
    struct ImageSize: Decodable, Equatable { let width: Double; let height: Double }
    struct Group: Decodable, Equatable, Identifiable { let id: String; let vi: String; let en: String }
    struct Design: Decodable, Equatable, Identifiable {
        let id: String; let group: String; let vi: String; let en: String; let file: String
        /// Optional cosmetic unlocked via Rewards (migration 165); the built-in charms are always free.
        var reward: Bool? = nil
    }
    let version: Int
    let pivot: Point
    let imageSize: ImageSize
    let anchors: [String]
    let sizes: [String: Double]
    let baseWidth: Double
    let groups: [Group]
    let designs: [Design]

    func design(_ id: String) -> Design? { designs.first { $0.id == id } }
    func designs(in group: String) -> [Design] { designs.filter { $0.group == group } }
    func scale(_ size: KeychainSize) -> Double { sizes[size.rawValue] ?? 1 }
    /// Rendered width in points for a size.
    func width(_ size: KeychainSize) -> Double { baseWidth * scale(size) }
    func height(_ size: KeychainSize) -> Double { width(size) * imageSize.height / max(imageSize.width, 1) }

    static func decode(_ data: Data) -> KeychainManifest? {
        try? JSONDecoder().decode(KeychainManifest.self, from: data)
    }

    /// Decoded once from the bundle (`Keychains/manifest.json`, or flattened).
    static let bundled: KeychainManifest? = {
        let b = Bundle.main
        guard let url = b.url(forResource: "manifest", withExtension: "json", subdirectory: "Keychains")
                ?? b.url(forResource: "manifest", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }()
}

enum KeychainArtwork {
    private static let cache = NSCache<NSString, UIImage>()

    /// URL of a bundled design PNG (subfolder first, then flattened).
    static func bundledURL(for design: KeychainManifest.Design, bundle: Bundle = .main) -> URL? {
        let name = (design.file as NSString).deletingPathExtension
        let ext = (design.file as NSString).pathExtension.isEmpty ? "png" : (design.file as NSString).pathExtension
        return bundle.url(forResource: name, withExtension: ext, subdirectory: "Keychains")
            ?? bundle.url(forResource: name, withExtension: ext)
    }

    static func bundledImage(_ design: KeychainManifest.Design) -> UIImage? {
        if let hit = cache.object(forKey: design.id as NSString) { return hit }
        guard let url = bundledURL(for: design), let img = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(img, forKey: design.id as NSString)
        return img
    }
}
