import SwiftUI

/// Home Pulse teaser — iOS's own version of `src/screens/Home.jsx`'s
/// `PulseTeaserBubble`.
///
/// Rendered as a RootView ZStack sibling (never inside HomeView itself),
/// positioned from `app.pulseRingFrame` (HomeView's own
/// `PulseRingFramePreferenceKey`) — measuring the real ring and floating
/// above everything from that, so it can never be clipped by HomeView's
/// ScrollView or sit behind another screen.
///
/// Positioning pass (2026-09-28): moved from "centered above the ring" to
/// a comic-style speech bubble BESIDE the ring (to its right, vertically
/// centered on it), with a triangular pointer on the bubble's own LEFT
/// edge pointing back at the ring, and text right-aligned inside the
/// bubble — matching web's equivalent redesign in `Home.jsx`. Clamped so
/// the bubble always stays fully inside the screen bounds rather than a
/// hardcoded guess.
///
/// Positioning pass 2 (2026-09-28, same-day real-device follow-up): the
/// pass above put the bubble fully BESIDE the ring (left edge at the
/// ring's own trailing edge), which on a real device read as floating
/// clear of the ring rather than a speech bubble anchored to it. Real
/// requirement: the bubble must visibly OVERLAP the ring's UPPER-RIGHT
/// QUARTER. Fixed by anchoring the bubble's own bottom-leading corner at
/// the ring's CENTER point (`rect.midX`/`rect.midY`, not an edge) and
/// letting it extend up-and-trailing from there — for any bubble at
/// least as large as the ring's own radius (true for every real piece of
/// copy this sequence shows), that necessarily overlaps exactly the
/// ring's upper-right quadrant. The pointer moved from vertically
/// centered on the leading edge to near its BOTTOM, so its tip still
/// lands close to the anchor point (the ring's center) under the new
/// placement — same side, same "still pointing at the ring" contract.
/// Still measured off the real ring rect via `app.pulseRingFrame`, never
/// a hardcoded offset, and clamped to `UIScreen.main.bounds` exactly as
/// before — only the anchor math and pointer alignment changed, not the
/// step-sequence/5-minute-repeat logic below. Ring tappability: this view
/// is a plain SwiftUI overlay sized to its own measured content, not a
/// full-screen hit-test layer, so it only ever intercepts touches over
/// the specific quadrant it visually overlaps — the ring's other three
/// quadrants (`HomeView`'s own Pulse avatar) stay directly tappable.
/// Also fixes the real "text clipped/covered" cause:
/// `bubbleSize` used to start at `.zero` and only update a layout pass
/// AFTER the bubble was already positioned from it (`rect.minY -
/// clearance - bubbleSize.height / 2` evaluated with a stale/zero height
/// on the very first frame of every new step, since `bubbleSize` is only
/// current for the PREVIOUS step's content) — placing the bubble
/// overlapping the ring/label underneath for one visible frame each time
/// the content changed. Fixed by keying the preference read so the
/// visible bubble only renders once a real, non-zero size for the CURRENT
/// content has been measured (`renderedStep`), rather than positioning
/// speculatively from a size that belongs to different content.
///
/// Timing-rule pass (2026-09-28): replaced the old one-time
/// `UserDefaults` "seen" flag with a real wall-clock repeat rule — show
/// once per user the first time they're eligible, then again 5 minutes
/// after the previous sequence finished/was dismissed. Version bumped
/// 'v1' -> 'v2' so the OLD one-time key can never be read by this logic
/// (a stale `true` there would otherwise block every returning user
/// forever) — a fresh key namespace, not a migration.
struct PulseTeaserBubbleView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var step = -1 // -1 = hidden, 0...3 = the 4 sequence steps
    @State private var runningTask: Task<Void, Never>?
    @State private var pollTask: Task<Void, Never>?
    @State private var bubbleSize: CGSize = .zero
    @State private var measuredForStep: Int = -1

    private static let version = "v2"
    private static func lastShownKey(_ userId: UUID?) -> String {
        "banbe.pulseBubblesLastShown.\(version).\(userId?.uuidString ?? "guest")"
    }
    private static let repeatInterval: TimeInterval = 5 * 60

    private var viewportMargin: CGFloat { 12 }

    var body: some View {
        Group {
            if step >= 0, app.screen == .home, let rect = app.pulseRingFrame, rect.width > 0 {
                bubbleContent
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: PulseBubbleSizePreferenceKey.self, value: geo.size)
                        }
                    )
                    .onPreferenceChange(PulseBubbleSizePreferenceKey.self) { size in
                        bubbleSize = size
                        measuredForStep = step
                    }
                    .frame(maxWidth: 230)
                    // Only positioned once a size for THIS step's content
                    // has actually been measured — avoids the one-frame
                    // "positioned from stale/zero size, overlapping the
                    // ring" bug documented above. Falls back to a
                    // reasonable estimate only for that first frame's
                    // opacity-0 layout pass (never visible, `.opacity`
                    // transition covers it).
                    .position(bubblePosition(in: rect, screen: screenBounds))
                    .opacity(measuredForStep == step ? 1 : 0)
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
        .onAppear { reevaluate(); startPolling() }
        .onDisappear { pollTask?.cancel(); pollTask = nil }
    }

    private var screenBounds: CGRect { UIScreen.main.bounds }

    /// Anchored so the bubble's own bottom-leading corner sits at the
    /// ring's CENTER point, extending up-and-trailing from there — see
    /// this file's positioning-pass-2 doc comment above for why that
    /// necessarily overlaps the ring's upper-right quadrant. Clamped so
    /// the whole box always stays fully inside the screen instead of a
    /// hardcoded guess about size. `.position(x:,y:)` takes the view's
    /// CENTER point, so the returned point is offset by half the
    /// (clamped) width/height from the corner anchor above.
    private func bubblePosition(in ring: CGRect, screen: CGRect) -> CGPoint {
        let width = bubbleSize.width > 0 ? bubbleSize.width : 220
        let height = bubbleSize.height > 0 ? bubbleSize.height : 40
        let maxLeft = max(viewportMargin, screen.width - viewportMargin - width)
        let left = min(max(viewportMargin, ring.midX), maxLeft)
        let maxTop = max(viewportMargin, screen.height - viewportMargin - height)
        let top = min(max(viewportMargin, ring.midY - height), maxTop)
        return CGPoint(x: left + width / 2, y: top + height / 2)
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
                    VStack(alignment: .trailing, spacing: 3) {
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
        .multilineTextAlignment(.trailing)
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
        // Comic-bubble pointer — LEFT side, near the BOTTOM of that edge
        // (positioning pass 2) so its tip lands close to the anchor point
        // itself (the ring's center) under the new upper-right-quadrant
        // overlap placement — matches web's equivalent redesign.
        .overlay(alignment: .bottomLeading) {
            Triangle()
                .fill(app.palette.ink)
                .frame(width: 6, height: 10)
                .offset(x: -6, y: -8)
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
        maybeStart()
    }

    /// Real wall-clock repeat rule (2026-09-28 pass): starts the sequence
    /// the first time an eligible signed-in user is seen (no stored
    /// timestamp yet), then again once `repeatInterval` (5 minutes) of
    /// real elapsed time has passed since the previous sequence finished
    /// or was dismissed. Never fires while a sequence is already showing
    /// (`step >= 0` guard, checked by every caller) or while Home isn't
    /// the visible screen/app isn't active.
    private func maybeStart() {
        guard step < 0, app.screen == .home, scenePhase == .active else { return }
        guard let userId = app.user?.id else { return }
        let lastShown = UserDefaults.standard.object(forKey: Self.lastShownKey(userId)) as? Double ?? 0
        guard Date().timeIntervalSince1970 - lastShown >= Self.repeatInterval else { return }
        Task { await app.loadPulse(period: .daily) }
        step = 0
        scheduleAdvance()
    }

    /// Lightweight poll so a sequence starts the instant 5 real minutes
    /// have elapsed while Home stays continuously open/visible — not only
    /// on the next mount/screen-change/foreground event. Mirrors web's own
    /// `setInterval` poll in `Home.jsx`.
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }
                maybeStart()
            }
        }
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
        if let userId = app.user?.id {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastShownKey(userId))
        }
    }
}

private struct PulseBubbleSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// Points LEFT (apex at the shape's left-middle, base along its right
/// edge) — used as the comic-bubble pointer on the bubble's own leading
/// edge, aimed back at the Pulse ring.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
