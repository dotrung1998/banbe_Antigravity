import SwiftUI

/// Map controls come in two looks, switchable in Account > Language & Appearance (no trip to iOS Settings):
/// Option 1 "glass" = the native Liquid Glass of `nativeGlass`; Option 2 "solid" = static, coloured surfaces
/// (docs/prototypes/map-options-v5.html). Only the map's own controls read this.
enum MapSurfaceStyle: String {
    case glass, solid
    static let defaultsKey = "banbe.mapSurface.v1"
}

private struct MapSurfaceModifier<S: Shape>: ViewModifier {
    @EnvironmentObject private var app: AppState
    @AppStorage(MapSurfaceStyle.defaultsKey) private var style = MapSurfaceStyle.glass.rawValue
    let shape: S
    let interactive: Bool

    func body(content: Content) -> some View {
        if style == MapSurfaceStyle.solid.rawValue {
            content
                .background(app.palette.surface1, in: shape)
                .overlay(shape.stroke(app.palette.ink.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.16), radius: 6, x: 0, y: 2)
        } else {
            content.nativeGlass(shape, interactive: interactive)
        }
    }
}

extension View {
    /// Glass or static-colour surface for a map control, per the in-app setting.
    func mapSurface<S: Shape>(_ shape: S, interactive: Bool = false) -> some View {
        modifier(MapSurfaceModifier(shape: shape, interactive: interactive))
    }
    func mapSurfaceCapsule(interactive: Bool = false) -> some View { mapSurface(Capsule(), interactive: interactive) }
}
