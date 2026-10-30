import XCTest
import SwiftUI
@testable import BanbeApp

/// Mirrors tests/unit/designTokens.test.mjs through the shared tests/fixtures/design-tokens.json (note 66):
/// `Palette` matches the web tokens, text keeps WCAG AA on every surface, and the theme choice rules match.
final class DesignTokensTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("tests/fixtures/design-tokens.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func rgb(_ color: Color) -> (Double, Double, Double, Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
    }

    private func rgb(hex: String) -> (Double, Double, Double) {
        let v = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }

    private func lum(_ c: (Double, Double, Double)) -> Double {
        func ch(_ x: Double) -> Double { x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        return 0.2126 * ch(c.0) + 0.7152 * ch(c.1) + 0.0722 * ch(c.2)
    }

    private func ratio(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        let x = lum(a), y = lum(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// Composites a translucent colour over an opaque background.
    private func flat(_ c: Color, over bg: Color) -> (Double, Double, Double) {
        let f = rgb(c), b = rgb(bg)
        return (f.0 * f.3 + b.0 * (1 - f.3), f.1 * f.3 + b.1 * (1 - f.3), f.2 * f.3 + b.2 * (1 - f.3))
    }

    private func assertSame(_ color: Color, _ hex: String, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let c = rgb(color), h = rgb(hex: hex)
        XCTAssertEqual(c.0, h.0, accuracy: 0.003, label, file: file, line: line)
        XCTAssertEqual(c.1, h.1, accuracy: 0.003, label, file: file, line: line)
        XCTAssertEqual(c.2, h.2, accuracy: 0.003, label, file: file, line: line)
    }

    func testPaletteMatchesWebTokensAndKeepsContrast() throws {
        let fx = try fixture()
        let minContrast = try XCTUnwrap(fx["minContrast"] as? [String: Double])
        for (name, palette) in [("light", Palette.light), ("dark", Palette.dark)] {
            let t = try XCTUnwrap(fx[name] as? [String: Any])
            let hexes: [(Color, String)] = [(palette.paper, "paper"), (palette.ink, "ink"), (palette.field, "field"),
                                            (palette.surface1, "surface1"), (palette.surface2, "surface2"),
                                            (palette.surface3, "surface3"), (palette.clay, "clay"), (palette.honey, "honey")]
            for (color, key) in hexes { assertSame(color, try XCTUnwrap(t[key] as? String), "\(name) \(key)") }
            XCTAssertEqual(rgb(palette.ink2).3, try XCTUnwrap(t["ink2Alpha"] as? Double), accuracy: 0.003, "\(name) ink2")
            XCTAssertEqual(rgb(palette.ink3).3, try XCTUnwrap(t["ink3Alpha"] as? Double), accuracy: 0.003, "\(name) ink3")

            let alert = rgb(hex: try XCTUnwrap(t["alert"] as? String))
            for bg in [palette.paper, palette.surface1, palette.surface2, palette.surface3, palette.field] {
                let b = flat(bg, over: bg)
                XCTAssertGreaterThanOrEqual(ratio(flat(palette.ink, over: bg), b), minContrast["ink"]!, "\(name) ink")
                XCTAssertGreaterThanOrEqual(ratio(flat(palette.ink2, over: bg), b), minContrast["ink2"]!, "\(name) ink2")
                XCTAssertGreaterThanOrEqual(ratio(flat(palette.ink3, over: bg), b), minContrast["ink3"]!, "\(name) ink3")
                XCTAssertGreaterThanOrEqual(ratio(alert, b), minContrast["alert"]!, "\(name) alert")
            }
        }
    }

    func testThemeChoiceRulesMatchWeb() throws {
        let fx = try fixture()
        for c in try XCTUnwrap(fx["themeChoice"] as? [[String: Any]]) {
            XCTAssertEqual(ThemeChoice.normalize(c["stored"] as? String, fresh: c["fresh"] as? Bool ?? false),
                           c["choice"] as? String, "\(c)")
        }
        for c in try XCTUnwrap(fx["themeResolve"] as? [[String: Any]]) {
            XCTAssertEqual(ThemeChoice.resolve(c["choice"] as! String, systemIsDark: c["systemDark"] as! Bool),
                           c["theme"] as? String, "\(c)")
        }
    }
}
