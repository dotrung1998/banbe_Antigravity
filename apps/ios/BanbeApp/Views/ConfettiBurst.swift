import SwiftUI

/// A short, one-shot confetti burst for a flow's peak moment (note 53, peak-end rule): the onboarding reveal and a
/// submitted event. Bits fly out, then drop and fade (~1.1s). Nothing at all under Reduce Motion.
/// Web twin: src/components/ui/ConfettiBurst.jsx (same palette, same geometry).
struct ConfettiBurst: View {
    var count = 26
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 = gathered, 1 = flown out, 2 = fallen and faded.
    @State private var phase: CGFloat = 0

    private static let colors: [Color] = [
        Color(hex: 0xE0A526), Color(hex: 0x9C5B3B), Color(hex: 0x485834),
        Color(hex: 0xC8CBB2), Color(hex: 0xE8715B), Color(hex: 0x1B1916),
    ]

    var body: some View {
        if !reduceMotion {
            ZStack {
                ForEach(0..<count, id: \.self) { i in
                    let angle = Double(i) / Double(count) * .pi * 2 + Double(i % 3) * 0.17
                    let dist = Double(90 + (i * 37) % 80)
                    let dx = cos(angle) * dist
                    let dy = sin(angle) * dist * 0.7 - 40
                    let w: CGFloat = i % 2 == 0 ? 8 : 6
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Self.colors[i % Self.colors.count])
                        .frame(width: w, height: w * 1.6)
                        .rotationEffect(.degrees(phase == 0 ? 0 : Double((i * 47) % 360) * (phase >= 2 ? 1 : 0.6)))
                        .offset(x: phase == 0 ? 0 : dx, y: phase == 0 ? 0 : (phase >= 2 ? dy + 110 : dy))
                        .opacity(phase >= 2 ? 0 : 1)
                }
            }
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                withAnimation(.easeOut(duration: 0.6)) { phase = 1 }
                withAnimation(.easeIn(duration: 0.5).delay(0.6)) { phase = 2 }
            }
        }
    }
}
