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
                                            (palette.surface3, "surface3"), (palette.clay, "clay"), (palette.honey, "honey"),
                                            (palette.block, "block"), (palette.blockInset, "blockInset"),
                                            (palette.mat, "mat"), (palette.matSlot, "matSlot")]
            for (color, key) in hexes { assertSame(color, try XCTUnwrap(t[key] as? String), "\(name) \(key)") }
            XCTAssertEqual(rgb(palette.ink2).3, try XCTUnwrap(t["ink2Alpha"] as? Double), accuracy: 0.003, "\(name) ink2")
            XCTAssertEqual(rgb(palette.ink3).3, try XCTUnwrap(t["ink3Alpha"] as? Double), accuracy: 0.003, "\(name) ink3")

            let alert = rgb(hex: try XCTUnwrap(t["alert"] as? String))
            for bg in [palette.paper, palette.surface1, palette.surface2, palette.surface3, palette.field,
                       palette.block, palette.blockInset, palette.mat] {
                let b = flat(bg, over: bg)
                XCTAssertGreaterThanOrEqual(ratio(flat(palette.ink, over: bg), b), minContrast["ink"]!, "\(name) ink")
                XCTAssertGreaterThanOrEqual(ratio(flat(palette.ink2, over: bg), b), minContrast["ink2"]!, "\(name) ink2")
                XCTAssertGreaterThanOrEqual(ratio(flat(palette.ink3, over: bg), b), minContrast["ink3"]!, "\(name) ink3")
                XCTAssertGreaterThanOrEqual(ratio(alert, b), minContrast["alert"]!, "\(name) alert")
            }
        }
    }

    /// Plan item 5: blocks are the warm beige in light (= surface2) and today's card fill in dark (= surface1, so dark
    /// mode is unchanged); honey text keeps AA on every surface it is used on (fixture `honeyOn`).
    func testBlockTokensAndHoneyContrast() throws {
        let fx = try fixture()
        let minHoney = try XCTUnwrap((fx["minContrast"] as? [String: Double])?["honey"])
        let honeyOn = try XCTUnwrap(fx["honeyOn"] as? [String])
        for (name, palette) in [("light", Palette.light), ("dark", Palette.dark)] {
            let byKey: [String: Color] = ["paper": palette.paper, "surface1": palette.surface1, "surface2": palette.surface2,
                                          "surface3": palette.surface3, "field": palette.field,
                                          "block": palette.block, "blockInset": palette.blockInset]
            for key in honeyOn {
                let bg = try XCTUnwrap(byKey[key], key)
                XCTAssertGreaterThanOrEqual(ratio(flat(palette.honey, over: bg), flat(bg, over: bg)), minHoney, "\(name) honey on \(key)")
            }
            // Note 71: clay text keeps AA where it is used as text (fixture `clayOn`; not on light block, 4.33:1).
            let minClay = try XCTUnwrap((fx["minContrast"] as? [String: Double])?["clay"])
            for key in try XCTUnwrap(fx["clayOn"] as? [String]) {
                let bg = try XCTUnwrap(key == "mat" ? palette.mat : byKey[key], key)
                XCTAssertGreaterThanOrEqual(ratio(flat(palette.clay, over: bg), flat(bg, over: bg)), minClay, "\(name) clay on \(key)")
            }
        }
        assertSame(Palette.light.block, "#EEE8DA", "light block = surface2")
        assertSame(Palette.dark.block, "#1A1815", "dark block = today's surface1")
        let lightBlock = rgb(Palette.light.block), lightS2 = rgb(Palette.light.surface2)
        XCTAssertEqual(lightBlock.0, lightS2.0, accuracy: 0.003)
        let darkBlock = rgb(Palette.dark.block), darkS1 = rgb(Palette.dark.surface1)
        XCTAssertEqual(darkBlock.0, darkS1.0, accuracy: 0.003)
    }

    /// Note 71 phase 4: the white glyph on the controls over a cover photo keeps AA over the worst photos (the material
    /// under the fill is treated as one more photo).
    func testPhotoControlKeepsContrastOverAnyPhoto() throws {
        let pc = try XCTUnwrap(try fixture()["photoControl"] as? [String: Any])
        assertSame(BanbeTheme.photoControl, try XCTUnwrap(pc["hex"] as? String), "photoControl")
        XCTAssertEqual(BanbeTheme.photoControlAlpha, try XCTUnwrap(pc["alpha"] as? Double), accuracy: 0.001)
        let minC = try XCTUnwrap(pc["minContrast"] as? Double)
        let fill = rgb(BanbeTheme.photoControl)
        for photo in try XCTUnwrap(pc["photos"] as? [String]) {
            let p = rgb(hex: photo), a = BanbeTheme.photoControlAlpha
            let bg = (fill.0 * a + p.0 * (1 - a), fill.1 * a + p.1 * (1 - a), fill.2 * a + p.2 * (1 - a))
            XCTAssertGreaterThanOrEqual(ratio((1, 1, 1), bg), minC, "white on photo control over \(photo)")
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
