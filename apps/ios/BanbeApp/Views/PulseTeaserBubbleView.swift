import SwiftUI

/// Home Pulse teaser — iOS's own version of `src/screens/Home.jsx`'s
/// `PulseTeaserBubble`.
///
/// Rendered as a RootView ZStack sibling (never inside HomeView itself),
/// positioned from `app.pulseRingFrame` — measuring the real ring and
/// floating above everything from that, so it can never be clipped by
/// HomeView's ScrollView or sit behind another screen.
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
///
/// Real-device positioning follow-up (2026-09-28, this pass): pass 2's own
/// anchor math above (bottom-leading corner at the ring's center) was
/// already correct on paper — and still is, unchanged here — but a real
/// iPhone kept showing the bubble beside the WRONG spot (right-and-lower
/// of the ring's true position) anyway. Root cause was never the anchor
/// formula or the `.global` coordinate space, both of which check out:
/// it was a TIMING/propagation-mode bug in how the ring's frame reached
/// `app.pulseRingFrame` at all. `HomeView` used to report the ring's
/// frame through a `GeometryReader` + `PreferenceKey`
/// (`geo.frame(in: .global)`) — SwiftUI PreferenceKey values only
/// propagate while the run loop is in `.default` mode, but a real finger
/// actively dragging Home's own feed ScrollView runs that drag in
/// `.tracking` mode (this exact limitation is already independently
/// diagnosed in this codebase, see `ScaffoldScrollProbe`'s own doc
/// comment in Components.swift, for the identical bug on scroll-offset
/// reporting). So for the entire duration of any real touch-scroll, the
/// ring's reported frame froze at its last `.default`-mode value —
/// typically close to its very first, pre-layout/pre-safe-area frame,
/// since a user can start scrolling within a fraction of a second of
/// Home appearing — while the ring itself kept moving for real. This
/// view then positioned the bubble off that stale rect, which is exactly
/// what "beside the wrong spot" on a real device (vs. a simulator's
/// mouse-driven scroll, which doesn't reliably trigger the same
/// tracking-mode RunLoop behavior) looks like. Fixed in `HomeView.swift`:
/// the ring now reports its frame via `RingFrameProbe` (Components.swift)
/// — a UIViewRepresentable that reads the ring's real frame off UIKit
/// directly via KVO on the ancestor UIScrollView's `contentOffset`, which
/// fires synchronously in ANY RunLoop mode — writing straight into
/// `app.pulseRingFrame`, bypassing the PreferenceKey pipeline (and its
/// tracking-mode gap) entirely. Nothing in THIS file's own anchor
/// math/placement changed.
///
/// Off-screen-ring handling (same pass): `RingFrameProbe` now also keeps
/// `app.pulseRingFrame` live and current WHILE the user scrolls (the old
/// PreferenceKey path only ever updated between drags before), which
/// means this view's own `rect` can legitimately describe a ring that has
/// scrolled fully off the visible screen. Since the ring is Home's own
/// FIRST story-row item near the very top of the feed, scrolling it out
/// of view means the user scrolled down past the header entirely — the
/// bubble must not keep floating over unrelated content below it in that
/// case. Gated in `body` below: the bubble only renders while `rect`
/// still intersects the real screen bounds; it hides the instant the
/// ring scrolls off (either edge) and reappears the instant the ring
/// scrolls back on, with no separate timer/dismiss-state change (the
/// step sequence and 5-minute repeat rule keep running untouched — this
/// is purely a render-visibility gate, mirroring "hide with the ring"
/// rather than "dismiss the sequence").
///
/// Weekly-ranking + featured-photos deep-link pass (this pass): the
/// sequence gained a real 4th step (now step 3, after the pre-existing
/// "Top sự kiện tuần này" title at step 2) that lists the actual weekly
/// top 3 — mirroring step 0/1's own daily title-then-listing pattern —
/// sourced from `app.pulseWeekly` (the SAME `goc_pulse_ranked('weekly')`
/// data Pulse's own "Tuần này" tab already loads, kicked off here too so
/// it's ready by the time this step is reached, never a separate/fake
/// query). The final step's copy changed from a bare "Ảnh nổi bật" title
/// to "Ảnh nổi bật: Bấm xem thêm", with only "Bấm xem thêm" tappable —
/// tapping it dismisses the teaser and opens the SAME existing Pulse
/// viewer every ring tap already opens, jumped straight to its
/// pre-existing "Ảnh nổi bật" tab (`app.pulseTab = .photos`) rather than
/// a new screen. Sequencing/timing (5-minute repeat, per-step duration,
/// manual-tap-to-advance) is otherwise unchanged — this only inserts one
/// step's content and re-numbers the final step.
struct PulseTeaserBubbleView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var step = -1 // -1 = hidden, 0...4 = the 5 sequence steps
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
            if step >= 0, app.screen == .home, let rect = app.pulseRingFrame, rect.width > 0, rect.intersects(screenBounds) {
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
                rankedList(app.pulseDaily, empty: app.T("Chưa có xếp hạng hôm nay", "Nothing ranked yet today"))
            } else if step == 2 {
                Text(app.T("Top sự kiện tuần này", "This week's top events"))
            } else if step == 3 {
                // Mirrors step 1 exactly (same numbered-list shape, same
                // empty-state pattern), sourced from `app.pulseWeekly` — the
                // existing weekly ranking Pulse's own "Tuần này" tab already
                // loads via `goc_pulse_ranked('weekly')`, never a separate
                // or invented query.
                rankedList(app.pulseWeekly, empty: app.T("Chưa có xếp hạng tuần này", "Nothing ranked yet this week"))
            } else {
                // Final step — only "Bấm xem thêm" is tappable; tapping it
                // dismisses the teaser and jumps straight into Pulse's own
                // existing "Ảnh nổi bật" tab (see `openFeaturedPhotos()`).
                // A tap anywhere else on the bubble still just
                // advances/dismisses like every other step, via the
                // Group-level `.onTapGesture` in `body`.
                HStack(spacing: 4) {
                    Text(app.T("Ảnh nổi bật:", "Featured photos:"))
                    Text(app.T("Bấm xem thêm", "Tap to view"))
                        .underline()
                        .onTapGesture { openFeaturedPhotos() }
                        .accessibilityIdentifier("home.pulseTeaserFeaturedPhotosLink")
                }
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

    /// Shared shape for step 1 (daily) and step 3 (weekly) — a truthful,
    /// numbered top-3 list, gracefully handling fewer than 3 real results
    /// (no padding with placeholders) and a genuinely empty ranking (a
    /// short empty-state line instead of a blank bubble).
    @ViewBuilder
    private func rankedList(_ ranking: [PulseItem], empty: String) -> some View {
        if ranking.isEmpty {
            Text(empty)
        } else {
            VStack(alignment: .trailing, spacing: 3) {
                ForEach(Array(ranking.prefix(3).enumerated()), id: \.element.id) { i, item in
                    Text("\(i + 1). \(item.eventName)")
                        .lineLimit(1)
                }
            }
        }
    }

    /// Routes into the SAME existing Pulse viewer every ring tap already
    /// opens, jumped straight to its pre-existing "Ảnh nổi bật" tab —
    /// `openPulseViewer()` itself always resets `pulseTab` to `.daily`
    /// (its own documented "never leave a previous session's rank sitting
    /// there" rule), so the override here has to happen AFTER that call,
    /// not before. Dismisses the teaser sequence first so it can't keep
    /// rendering on top of the Pulse viewer it just opened.
    private func openFeaturedPhotos() {
        dismiss()
        app.openPulseViewer()
        app.pulseTab = .photos
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
        // Weekly-ranking step (step 3) reads `app.pulseWeekly` — kicked off
        // here too, alongside daily, so it's already loading well before
        // the sequence reaches that step rather than starting a fetch only
        // once step 2's title is showing.
        Task { await app.loadPulse(period: .weekly) }
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
        // Hold on a title step until ITS OWN data has actually arrived —
        // step 0 (daily title, gates on `pulseDailyLoading`) and step 2
        // (weekly title, gates on `pulseWeeklyLoading`) each precede a
        // listing step that reads that same data. Polls lightly rather
        // than needing a Combine subscription for one Bool.
        let stillLoading = (step == 0 && app.pulseDailyLoading) || (step == 2 && app.pulseWeeklyLoading)
        if stillLoading {
            runningTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                if !Task.isCancelled { scheduleAdvance() }
            }
            return
        }
        let seconds: Double = (step == 0 || step == 2) ? 4.6 : 3.2
        runningTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if step >= 4 { dismiss() } else { step += 1; scheduleAdvance() }
        }
    }

    private func advanceOrDismiss() {
        guard step >= 0 else { return }
        if step >= 4 { dismiss() } else { step += 1; scheduleAdvance() }
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
