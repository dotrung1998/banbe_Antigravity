import SwiftUI

/// "Event reminder" for the Home "Your events" strip — mirrors web
/// src/lib/eventReminder.js: from 24h before the start until the event is over.
/// Events have no end time, so "ongoing" is capped at `ongoingCapHours` after the start.
enum EventReminder {
    enum Phase { case soon, live }

    static let leadHours: Double = 24
    static let ongoingCapHours: Double = 12

    static func phase(startsAt: Date?, now: Date = Date()) -> Phase? {
        guard let startsAt else { return nil }
        let delta = startsAt.timeIntervalSince(now)
        if delta > leadHours * 3600 { return nil }
        if delta > 0 { return .soon }
        return -delta <= ongoingCapHours * 3600 ? .live : nil
    }
}

/// Gold border + a halo that pulses 3 times each time `trigger` changes (Home becoming
/// visible again), then fades; the border stays. Static under Reduce Motion.
struct EventReminderHalo: View {
    let trigger: Int
    var cornerRadius: CGFloat = 12
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse: CGFloat = 1

    private let gold = Color(hex: 0xE0A526)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius + 10 * pulse, style: .continuous)
                .stroke(gold.opacity(0.65 * (1 - pulse)), lineWidth: 2)
                .padding(-10 * pulse)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(gold, lineWidth: 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, _ in play() }
        .onAppear { play() }
    }

    private func play() {
        guard !reduceMotion else { pulse = 1; return }
        pulse = 0
        withAnimation(.easeOut(duration: 1.4).repeatCount(3, autoreverses: false)) { pulse = 1 }
    }
}
