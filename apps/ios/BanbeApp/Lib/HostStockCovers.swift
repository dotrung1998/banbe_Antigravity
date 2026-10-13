import SwiftUI
import UIKit

/// Built-in cover designs for the host profile (mirror of src/lib/hostStockCovers.js): soft
/// two-stop gradients with a light bloom, drawn in code so there are no photos to license.
struct HostStockCover: Identifiable, Equatable {
    let id: String, vi: String, en: String
    let a: UInt32, b: UInt32, glow: UInt32

    static let all: [HostStockCover] = [
        .init(id: "dawn", vi: "Bình minh", en: "Dawn", a: 0xF6DDB5, b: 0xE7A488, glow: 0xFFF3DB),
        .init(id: "moss", vi: "Rêu", en: "Moss", a: 0xB4C2A4, b: 0x4E6B52, glow: 0xE4EBD8),
        .init(id: "sea", vi: "Biển", en: "Sea", a: 0xA5CBCD, b: 0x2F5D6B, glow: 0xDDF0EF),
        .init(id: "honey", vi: "Mật ong", en: "Honey", a: 0xF4D885, b: 0xC58519, glow: 0xFFF1C4),
        .init(id: "rose", vi: "Hồng phấn", en: "Rose", a: 0xEBBEBE, b: 0xA4566B, glow: 0xFFE6E6),
        .init(id: "clay", vi: "Đất nung", en: "Clay", a: 0xD89E7E, b: 0x8A4C38, glow: 0xF7D9C6),
        .init(id: "dusk", vi: "Hoàng hôn", en: "Dusk", a: 0x7B6BA3, b: 0x2E294A, glow: 0xC9BFE6),
        .init(id: "ink", vi: "Mực", en: "Ink", a: 0x47423B, b: 0x14120E, glow: 0x8A7F6B),
    ]

    private static func cg(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    func image(side: CGFloat) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        fmt.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: fmt).image { ctx in
            let c = ctx.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            if let g = CGGradient(colorsSpace: space, colors: [Self.cg(a), Self.cg(b)] as CFArray, locations: [0, 1]) {
                c.drawLinearGradient(g, start: .zero, end: CGPoint(x: side, y: side), options: [])
            }
            func bloom(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ alpha: CGFloat) {
                guard let g = CGGradient(colorsSpace: space, colors: [Self.cg(glow, alpha: alpha), Self.cg(glow, alpha: 0)] as CFArray, locations: [0, 1]) else { return }
                c.drawRadialGradient(g, startCenter: CGPoint(x: x * side, y: y * side), startRadius: 0,
                                     endCenter: CGPoint(x: x * side, y: y * side), endRadius: r * side, options: [])
            }
            bloom(0.28, 0.22, 0.75, 0.75)
            bloom(0.82, 0.88, 0.55, 0.35)
        }
    }
}
