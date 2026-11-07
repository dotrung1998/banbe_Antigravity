import SwiftUI

/// Liquid Glass switch (first built for the migration-181 master switch, shared with Admin > Feature switches):
/// frosted track that darkens when on, glass knob with a spring slide. Purely presentational: the caller decides
/// what a tap means.
struct GlassSwitch: View {
    @EnvironmentObject private var app: AppState
    let isOn: Bool
    var loading = false
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            action()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                glassSurface(Capsule(), tint: app.palette.ink.opacity(isOn ? 0.82 : 0.10))
                    .frame(width: 64, height: 38)
                glassSurface(Circle(), tint: .white.opacity(0.85))
                    .frame(width: 30, height: 30)
                    .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
                    .padding(4)
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.72), value: isOn)
            .opacity(loading ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(loading)
        .accessibilityIdentifier(identifier)
        .accessibilityValue(isOn ? "on" : "off")
    }

    @ViewBuilder
    private func glassSurface<S: Shape>(_ shape: S, tint: Color) -> some View {
        if #available(iOS 26.0, *) {
            shape.fill(tint).glassEffect(.regular.interactive(), in: shape)
        } else {
            shape.fill(tint).background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.4), lineWidth: 1))
        }
    }
}
