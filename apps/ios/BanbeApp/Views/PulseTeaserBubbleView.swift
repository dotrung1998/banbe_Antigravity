import SwiftUI

/// Home Pulse teaser (real-device follow-up, 2026-09-27) — iOS's own
/// version of `src/screens/Home.jsx`'s `PulseTeaserBubble`. Root cause of
/// "teaser never appears on iOS", confirmed by grep before writing a single
/// line here: this view never existed at all — the previous pass built it
/// only on web. Not a visibility/zIndex/seen-key bug to patch; a missing
/// feature to build, matching web's sequence/timing/pause/tap-to-advance
/// behavior as closely as SwiftUI allows.
///
/// Rendered as a RootView ZStack sibling (never inside HomeView itself),
/// positioned from `app.pulseRingFrame` (HomeView's own
/// `PulseRingFramePreferenceKey`) — the same "measure the real ring, float
/// above everything from that" fix web's own bug (2) used, so it can never
/// be clipped by HomeView's ScrollView or sit behind another screen.
struct PulseTeaserBubbleView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var step = -1 // -1 = hidden, 0...3 = the 4 sequence steps
    @State private var runningTask: Task<Void, Never>?
    @State private var bubbleSize: CGSize = .zero

    // Stays 'v1' — this is iOS's FIRST real implementation, not a
    // corrected re-roll of a previously-broken one, so there's no old key
    // to invalidate. (Web's own 'v1' also stays unchanged — its bug was
    // timing/positioning, not the sequence's content — see that file.)
    private static let version = "v1"
    private static func seenKey(_ userId: UUID?) -> String {
        "banbe.pulseBubblesSeen.\(version).\(userId?.uuidString ?? "guest")"
    }

    private var ringClearance: CGFloat { 16 }

    var body: some View {
        Group {
            if step >= 0, app.screen == .home, let rect = app.pulseRingFrame, rect.width > 0 {
                bubbleContent
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: PulseBubbleSizePreferenceKey.self, value: geo.size)
                        }
                    )
                    .onPreferenceChange(PulseBubbleSizePreferenceKey.self) { bubbleSize = $0 }
                    .frame(maxWidth: 230)
                    .position(x: rect.midX, y: max(70, rect.minY - ringClearance - bubbleSize.height / 2))
                    .transition(reduceMotion ? .identity : .opacity)
                    .onTapGesture { advanceOrDismiss() }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("home.pulseTeaserBubble")
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: step)
        .onChange(of: app.screen) { _, newScreen in
            if newScreen == .home { reevaluate() } else { suspend() }
        }
        .onChange(of: app.user?.id) { _, _ in reevaluate() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reevaluate() } else { suspend() }
        }
        .onAppear { reevaluate() }
    }

    @ViewBuilder
    private var bubbleContent: some View {
        Group {
            if step == 0 {
                Text(app.T("Top sự kiện hôm nay", "Today's top events"))
            } else if step == 1 {
                if app.pulseDaily.isEmpty {
                    // Never invented — a truthful, short empty hint
                    // instead of placeholder names when there's genuinely
                    // no ranking yet.
                    Text(app.T("Chưa có xếp hạng hôm nay", "Nothing ranked yet today"))
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(app.pulseDaily.prefix(3).enumerated()), id: \.element.id) { i, item in
                            Text("\(i + 1). \(item.eventName)")
                                .lineLimit(1)
                        }
                    }
                }
            } else if step == 2 {
                Text(app.T("Top sự kiện tuần này", "This week's top events"))
            } else {
                Text(app.T("Ảnh nổi bật", "Featured photos"))
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(app.palette.paper)
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
        .overlay(alignment: .bottom) {
            Triangle()
                .fill(app.palette.ink)
                .frame(width: 10, height: 6)
                .offset(y: 6)
        }
    }

    /// Checked from every place that could make this newly eligible
    /// (screen becoming .home, the user id resolving, the app becoming
    /// active again) — starts the sequence at most once per real
    /// eligibility, never re-triggered by an unrelated re-render (this
    /// view has no dependency on anything that changes on every SwiftUI
    /// body re-evaluation other than the explicit `.onChange`s above).
    private func reevaluate() {
        guard app.screen == .home, scenePhase == .active, runningTask == nil else { return }
        // Case 1: a sequence was already running (step 0-3) and got
        // suspended (background/leaving Home) — resume it, restarting the
        // CURRENT step's own timer at full duration (same intentionally-
        // simple "pause" semantics as the web fix — not literal
        // remaining-time bookkeeping).
        if step >= 0 { scheduleAdvance(); return }
        // Case 2: never started this session — only ever begins ONCE per
        // user/version, ever (UserDefaults, not per-session).
        guard let userId = app.user?.id else { return }
        if UserDefaults.standard.bool(forKey: Self.seenKey(userId)) { return }
        // Written immediately, not only on completion — Home's own view
        // can be torn down/rebuilt by navigation well before the sequence
        // finishes; gating on completion would replay it on every later
        // Home visit (the exact bug this pass's own web-side test caught).
        UserDefaults.standard.set(true, forKey: Self.seenKey(userId))
        Task { await app.loadPulse(period: .daily) }
        step = 0
        scheduleAdvance()
    }

    /// Pauses (cancels any pending advance) without losing the CURRENT
    /// step — resuming (via reevaluate(), called from the same
    /// `.onChange`s) restarts that step's own timer at full duration, the
    /// same intentionally-simple "pause" semantics as the web fix.
    private func suspend() {
        runningTask?.cancel()
        runningTask = nil
    }

    private func scheduleAdvance() {
        runningTask?.cancel()
        guard step >= 0 else { return }
        if step == 0, app.pulseDailyLoading {
            // Hold on step 0 until the real data actually arrives — poll
            // lightly rather than needing a Combine subscription for one
            // Bool.
            runningTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                if !Task.isCancelled { scheduleAdvance() }
            }
            return
        }
        let seconds: Double = step == 0 ? 4.6 : 3.2
        runningTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if step >= 3 { dismiss() } else { step += 1; scheduleAdvance() }
        }
    }

    private func advanceOrDismiss() {
        guard step >= 0 else { return }
        if step >= 3 { dismiss() } else { step += 1; scheduleAdvance() }
    }

    private func dismiss() {
        suspend()
        step = -1
    }
}

private struct PulseBubbleSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
