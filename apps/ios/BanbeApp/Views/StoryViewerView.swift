import SwiftUI

// Task 3.4 (07-notifications.md) — the story progression viewer. A
// deliberately SEPARATE view/state from PhotoViewerView/ChatPhotoViewerView
// (14-photo-viewer.md's own instruction not to conflate origin/back
// semantics across viewer kinds) even though it reuses the same
// blurred-fullscreen visual language and, as of this pass, the same
// live-drag-follow / hold-to-pause CONVENTIONS ChatPhotoViewerView
// established (b75b884) — not its state, per that same instruction.
//
// BUG 5 fix (2026-09-22 follow-up) — `app.storyViewer` now stores the FULL
// ordered deck (`groups`/`groupIndex`/`storyIndex`), not one organizer's
// stories in isolation — see AppState.swift's own comment on
// openStoryViewer()/storyNext()/storyPrev().
private let storyDurationSeconds: Double = 5
private let dismissMs: Double = 0.26
private let dismissThreshold: CGFloat = 90
private let dragRevealDistance: CGFloat = 220
private let holdThresholdMs: Int = 180 // a plain tap stays a tap
private let hswipeThreshold: CGFloat = 60 // pt of horizontal travel that commits to prev/next
private let hswipeVelocity: CGFloat = 0.6 // pt/ms — a fast flick commits even under the distance threshold
private let hswipeSettleMs: Double = 0.19 // banbe's own "gallery drift" settle duration, not Instagram's

struct StoryViewerView: View {
    @EnvironmentObject var app: AppState
    // FEATURE 3 (2026-09-22 follow-up) — respects the system's own
    // reduce-motion setting: no perspective/depth companion card, just a
    // plain slide/fade, per this ticket's own accessibility requirement.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // BUG 1 fix (2026-09-22 tenth follow-up) — true for the whole time an
    // Event Detail opened FROM a story is the nominal top screen
    // (RootView's own `storyUnderlaysEvent`), including while it's being
    // peeked at during an edge-swipe. Pauses the timer/gesture entirely —
    // this single retained instance must not silently keep advancing (or
    // accept touches meant for Event Detail) while it isn't the thing the
    // user is actually looking at.
    var isSuspended: Bool = false

    // Progress — driven by elapsed real time (Task 3), not discrete sleep
    // ticks. `advanceTask` is the ONE thing that actually calls
    // storyNext() when the duration elapses; the TimelineView below only
    // ever reads elapsed time to draw, never mutates state mid-render.
    @State private var startDate = Date()
    @State private var pausedElapsed: TimeInterval = 0
    @State private var isPaused = false
    @State private var advanceTask: Task<Void, Never>?

    // Drag-to-dismiss (vertical) + swipe-to-navigate (horizontal) +
    // hold-to-pause — one gesture, disambiguated by direction/duration,
    // mirroring ChatPhotoViewerView's stage gesture.
    @State private var dragOffsetY: CGFloat = 0
    @State private var dragOffsetX: CGFloat = 0
    private enum DragKind { case vertical, horizontal }
    @State private var dragKind: DragKind?
    @State private var isHolding = false
    @State private var touchDown = false
    @State private var closing = false
    // Gallery-drift companion (Feature 3) — the incoming neighbor's soft
    // glass "peek" card, purely transform/opacity driven off the SAME
    // drag state as `dragOffsetX`, not a second independent state machine.
    @State private var companionOpacity: Double = 0
    @State private var companionScale: CGFloat = 0.86
    @State private var lastDragX: CGFloat = 0
    @State private var lastDragAt: Date = .now
    @State private var dragVelocity: CGFloat = 0
    // BUG 4 (2026-09-22 tenth follow-up) — fades the WHOLE viewer away to
    // reveal whatever's already mounted underneath (Home/Account) during
    // the "final story of the final host, swipe forward" case, instead of
    // a gray/empty companion. 1 = fully opaque (normal), 0 = fully revealed.
    @State private var revealOpacity: Double = 1

    private var dragProgress: CGFloat { min(1, max(0, dragOffsetY) / dragRevealDistance) }
    private var stageWidth: CGFloat { UIScreen.main.bounds.width }
    // PRODUCT CHANGE 3 (2026-09-22 tenth follow-up) — whether a horizontal
    // swipe in each direction actually has another HOST to land on;
    // decides companion-peek vs BUG 4's reveal-underneath treatment.
    private func hasNextHost(_ v: StoryViewerState) -> Bool { v.groups[(v.groupIndex + 1)...].contains { !$0.stories.isEmpty } }
    private func hasPrevHost(_ v: StoryViewerState) -> Bool { v.groups[..<v.groupIndex].contains { !$0.stories.isEmpty } }

    var body: some View {
        if let viewer = app.storyViewer, let group = viewer.groups[safe: viewer.groupIndex], let story = group.stories[safe: viewer.storyIndex] {
            ZStack {
                Color.black.ignoresSafeArea()

                // Gallery-drift companion — a single flat glass panel (not
                // Instagram's rotated 3D side-card stack), scaling/fading
                // in from whichever edge the swipe is headed toward. Only
                // ever represents a REAL adjacent host (see
                // `hasNextHost`/`hasPrevHost`) — BUG 4's reveal-underneath
                // case never shows this at all.
                if !reduceMotion {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
                        .padding(EdgeInsets(top: 60, leading: 28, bottom: 60, trailing: 28))
                        .scaleEffect(companionScale)
                        .opacity(companionOpacity)
                        .allowsHitTesting(false)
                }

                Group {
                    if story.kind == "event_share" {
                        EventShareCard(story: story)
                    } else {
                        AsyncImage(url: story.url) { $0.resizable().scaledToFit() } placeholder: { ProgressView().tint(.white) }
                            .accessibilityIdentifier("story.viewer.image")
                    }
                }
                .offset(x: dragOffsetX, y: dragOffsetY)
                .scaleEffect(1 - dragProgress * 0.08 - min(1, abs(dragOffsetX) / max(1, stageWidth)) * 0.06)

                chrome(group: group, storyIndex: viewer.storyIndex)
            }
            .opacity(closing ? 0 : revealOpacity)
            .contentShape(Rectangle())
            .gesture(stageGesture, including: isSuspended ? .none : .all)
            .allowsHitTesting(!isSuspended)
            .transition(.opacity)
            .onChange(of: viewer.groupIndex) { _, _ in resetProgress(); tickCurrentStory(); resetDragTransforms() }
            .onChange(of: viewer.storyIndex) { _, _ in resetProgress(); tickCurrentStory(); resetDragTransforms() }
            .onChange(of: isSuspended) { _, suspended in
                if suspended { pauseProgress() } else { resumeProgress() }
            }
            .onAppear {
                tickCurrentStory()
                if !isSuspended { resetProgress() }
            }
            .onDisappear { advanceTask?.cancel() }
        }
    }

    /// A settled gallery-drift transition already resets `dragOffsetX`/the
    /// companion before calling `storyNext()`/`storyPrev()` (see
    /// `stageGesture`'s `.onEnded` below); this is the defensive reset for
    /// every OTHER way `groupIndex`/`storyIndex` can change (tap-to-
    /// advance, auto-advance on timeout) — a fresh story should never
    /// inherit a leftover drag transform.
    private func resetDragTransforms() {
        dragOffsetX = 0
        companionOpacity = 0
        companionScale = 0.86
        lastDragX = 0
        dragVelocity = 0
        revealOpacity = 1
    }

    private func chrome(group: StoryGroup, storyIndex: Int) -> some View {
        ZStack {
            // Progress bars — one per story in the CURRENT host's own
            // group (resets per host, standard deck behavior), smooth
            // elapsed-time-driven fill (Task 3), paused while held/dragged.
            TimelineView(.animation(paused: isPaused)) { context in
                let elapsed = pausedElapsed + (isPaused ? 0 : context.date.timeIntervalSince(startDate))
                let progress = min(1, max(0, elapsed / storyDurationSeconds))
                HStack(spacing: 4) {
                    ForEach(Array(group.stories.enumerated()), id: \.offset) { i, _ in
                        GeometryReader { geo in
                            Capsule().fill(Color.white.opacity(0.35))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(Color.white)
                                        .frame(width: geo.size.width * (i < storyIndex ? 1 : i == storyIndex ? progress : 0))
                                }
                        }
                        .frame(height: 2.5)
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 54)

            Text(group.orgName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 62).padding(.leading, 16)

            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
            }
            .accessibilityIdentifier("story.viewer.close")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.top, 60).padding(.trailing, 16)

            Text("banbe ▪︎ \(app.T("story", "story"))")
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.75))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 18).padding(.bottom, 40)
        }
        .opacity(isHolding ? 0 : Double(1 - dragProgress))
        .allowsHitTesting(!isHolding)
        .animation(.easeInOut(duration: 0.15), value: isHolding)
    }

    // MARK: - Gesture (tap zones / hold-to-pause / vertical drag-dismiss /
    // horizontal swipe-navigate — BUG 5's cross-host manual navigation)

    private var stageGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !touchDown {
                    touchDown = true
                    scheduleHoldDetection()
                }
                let dy = value.translation.height
                let dx = value.translation.width
                if dragKind == nil && !isHolding {
                    // Direction is only classified once movement clears a
                    // small threshold (never on the very first pixel), so
                    // a vertical dismiss and a horizontal swipe can never
                    // both fire for the same gesture.
                    if dy > 6, dy > abs(dx) {
                        dragKind = .vertical
                        pauseProgress()
                    } else if abs(dx) > 6, abs(dx) > abs(dy) {
                        dragKind = .horizontal
                        pauseProgress()
                        lastDragX = dx
                        lastDragAt = Date()
                    } else {
                        return
                    }
                }
                if dragKind == .vertical {
                    dragOffsetY = dy
                } else if dragKind == .horizontal {
                    let now = Date()
                    let elapsedMs = max(1, now.timeIntervalSince(lastDragAt) * 1000)
                    dragVelocity = (dx - lastDragX) / elapsedMs
                    lastDragX = dx
                    lastDragAt = now
                    dragOffsetX = dx
                    // PRODUCT CHANGE 3 — the drag only ever targets the
                    // adjacent HOST, never the current host's own next/prev
                    // post (that's storyNext()/storyPrev()'s job — the
                    // timer and tap zones, untouched). BUG 4 fix: when
                    // there's no adjacent host in this direction, reveal
                    // whatever's already mounted underneath (Home/Account)
                    // instead of the abstract companion card.
                    if let v = app.storyViewer {
                        let goingNext = dx < 0
                        let revealingUnderneath = goingNext ? !hasNextHost(v) : !hasPrevHost(v)
                        if revealingUnderneath {
                            // Only the FORWARD case actually reveals
                            // anything (BUG 4) — backward "no previous
                            // host" has nothing real to reveal (nothing
                            // logically precedes the deck's very first
                            // host), so it just rubber-bands the current
                            // card and always springs back on release.
                            if goingNext { revealOpacity = 1 - min(1, abs(dx) / stageWidth) }
                        } else if !reduceMotion {
                            let progress = min(1, abs(dx) / max(1, stageWidth))
                            companionOpacity = min(0.92, progress * 1.15)
                            companionScale = 0.86 + progress * 0.14
                        }
                    }
                }
            }
            .onEnded { value in
                touchDown = false
                let kind = dragKind
                dragKind = nil
                if kind == .vertical {
                    if dragOffsetY > dismissThreshold {
                        dismiss()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragOffsetY = 0 }
                        resumeProgress()
                    }
                    return
                }
                if kind == .horizontal {
                    let dx = value.translation.width
                    let goingNext = dx < 0
                    let v = app.storyViewer
                    // PRODUCT CHANGE 3 — a backward swipe past the
                    // beginning of the WHOLE deck (no previous host at
                    // all) never commits to anything; it only ever springs
                    // back — "no logical prior context" per BUG 4's own
                    // symmetry requirement.
                    let canCommit = v.map { goingNext ? hasNextHost($0) : hasPrevHost($0) } ?? false
                    let beyondThreshold = abs(dx) > hswipeThreshold || abs(dragVelocity) > hswipeVelocity
                    let committed = canCommit && beyondThreshold
                    if committed {
                        // Settle: finish the drift the rest of the way out,
                        // THEN advance — storyNextHost()/storyPrevHost()
                        // change groupIndex/storyIndex, which is what
                        // actually swaps the content; finishing the
                        // outward motion first is what reads as one
                        // continuous "gallery drift" instead of a
                        // snap-then-jump. No mark-viewed side effect here
                        // — that stays solely in the onChange handlers above.
                        withAnimation(.easeOut(duration: hswipeSettleMs)) {
                            dragOffsetX = goingNext ? -stageWidth : stageWidth
                            if !reduceMotion { companionOpacity = 1; companionScale = 1 }
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + hswipeSettleMs) {
                            dragOffsetX = 0
                            companionOpacity = 0
                            companionScale = 0.86
                            if goingNext { app.storyNextHost() } else { app.storyPrevHost() }
                        }
                    } else if goingNext, let v, !hasNextHost(v), beyondThreshold {
                        // BUG 4 — the final story of the final host, swipe
                        // forward, PAST the commit threshold: complete the
                        // reveal into Home/Account instead of springing
                        // back. Dock visibility only restores once
                        // `closeStoryViewer()` actually runs.
                        withAnimation(.easeOut(duration: hswipeSettleMs)) {
                            revealOpacity = 0
                            dragOffsetX = -stageWidth
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + hswipeSettleMs) {
                            app.closeStoryViewer()
                        }
                    } else {
                        // Short of threshold/velocity (or no adjacent host
                        // to land on) — spring the current card back, fade
                        // the companion out, undo any reveal-underneath
                        // progress, then resume where it was. Does NOT
                        // reset story position/progress — same "no state
                        // reset" contract as every other cancelled gesture.
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            dragOffsetX = 0
                            companionOpacity = 0
                            companionScale = 0.86
                            revealOpacity = 1
                        }
                        resumeProgress()
                    }
                    return
                }
                if isHolding {
                    isHolding = false
                    resumeProgress()
                    return // a hold-and-release never navigates
                }
                let x = value.location.x
                let width = UIScreen.main.bounds.width
                if x < width / 2 { app.storyPrev() } else { app.storyNext() }
            }
    }

    /// A press held past `holdThresholdMs` with no significant movement
    /// pauses instead of counting as a tap — scheduled once per touch-down,
    /// independent of whether SwiftUI's DragGesture fires any further
    /// onChanged callbacks for a genuinely stationary finger.
    private func scheduleHoldDetection() {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(holdThresholdMs)) {
            guard touchDown, dragKind == nil, !isHolding else { return }
            isHolding = true
            pauseProgress()
        }
    }

    /// BUG 1 fix (2026-09-22 follow-up) — real bug, confirmed by reading:
    /// `.onAppear` only ever fires once, the first time this view enters
    /// the hierarchy — navigating from story 1 to story 2 within the SAME
    /// `StoryViewerView` instance just re-evaluates `body` (a new
    /// `storyViewer.storyIndex`), it does not remount the view, so
    /// `.onAppear`'s single `viewStoryTick` call never fired again. Every
    /// story after the very first one in a deck was therefore NEVER
    /// recorded as viewed at all — `allViewed`/the ring could never
    /// subdue no matter how many stories were actually watched. The web
    /// StoryViewer.jsx already got this right (its `useEffect` re-fires on
    /// every `groupIndex`/`storyIndex` change) — this ports the same fix:
    /// tick the CURRENTLY shown story from both `.onChange` handlers, not
    /// only `.onAppear`.
    private func tickCurrentStory() {
        guard let v = app.storyViewer, let g = v.groups[safe: v.groupIndex], let st = g.stories[safe: v.storyIndex] else { return }
        Task { await app.viewStoryTick(st.id) }
    }

    private func dismiss() {
        guard !closing else { return }
        pauseProgress()
        withAnimation(.easeOut(duration: dismissMs)) { closing = true; dragOffsetY = UIScreen.main.bounds.height }
        DispatchQueue.main.asyncAfter(deadline: .now() + dismissMs) { app.closeStoryViewer() }
    }

    // MARK: - Progress (Task 3 — elapsed real time, not discrete ticks)

    private func resetProgress() {
        advanceTask?.cancel()
        startDate = Date()
        pausedElapsed = 0
        isPaused = false
        scheduleAdvance(after: storyDurationSeconds)
    }
    private func pauseProgress() {
        guard !isPaused else { return }
        pausedElapsed += Date().timeIntervalSince(startDate)
        isPaused = true
        advanceTask?.cancel()
    }
    private func resumeProgress() {
        guard isPaused else { return }
        startDate = Date()
        isPaused = false
        scheduleAdvance(after: storyDurationSeconds - pausedElapsed)
    }
    private func scheduleAdvance(after seconds: TimeInterval) {
        advanceTask?.cancel()
        let clamped = max(0, seconds)
        advanceTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(clamped * 1_000_000_000))
            if !Task.isCancelled { await MainActor.run { app.storyNext() } }
        }
    }
}

// Task 4 — an event-share story renders as a dedicated card, not a plain
// photo. `story.eventSnapshot` is denormalized at load time (loadHomeStories())
// from the same static catalogue every other event screen already reads —
// see AppState+Data.swift's own comment on why.
private struct EventShareCard: View {
    @EnvironmentObject var app: AppState
    let story: StoryItem

    /// BUG 2 (2026-09-22 tenth follow-up) — real bug, confirmed by reading:
    /// this card used to show `snap.location` (== the catalogue's raw
    /// `where` string) directly — a single pre-baked string with the
    /// STATIC placeholder km number embedded in it (e.g. "Bình Thạnh ▪︎
    /// 2,1 km từ bạn ▪︎ ..."), shown UNCONDITIONALLY regardless of
    /// location permission or any real coordinate. That's what "km in
    /// event stories is still wrong" actually was on iOS — not a subtle
    /// coordinate-source mismatch (the catalogue and the real `events` DB
    /// rows were verified identical for every seeded demo event), just a
    /// hardcoded number with zero live computation behind it at all.
    /// Fixed: drop `snap.location` entirely and compute a live distance
    /// via the SAME canonical `haversineKm(from:toCoords:)` primitive
    /// MapExplore/Event Detail use, from `snap.lat`/`snap.lng` — recomputed
    /// on every render from `app.userCoords` (never cached at story-open),
    /// omitted entirely whenever a real value isn't available. Matches
    /// web's own StoryViewer.jsx `EventShareCard`, which never showed
    /// `where` at all.
    private var distanceText: String? {
        guard app.located == true, let lat = story.eventSnapshot?.lat, let lng = story.eventSnapshot?.lng,
              let km = haversineKm(from: app.userCoords, toCoords: Coordinates(lat: lat, lng: lng)) else { return nil }
        return String(format: "%.1f", km).replacingOccurrences(of: ".", with: ",") + " km"
    }

    var body: some View {
        if let snap = story.eventSnapshot {
            VStack(spacing: 0) {
                CatalogPhoto(path: snap.img, height: 340, cornerRadius: 0)
                VStack(alignment: .leading, spacing: 4) {
                    Text(snap.name).font(BanbeTheme.display(18)).foregroundStyle(app.palette.ink)
                    Text(snap.when + (distanceText.map { " ▪︎ \($0)" } ?? ""))
                        .font(.system(size: 12)).foregroundStyle(app.palette.ink.opacity(0.7))
                        .accessibilityIdentifier("story.eventCard.distance")
                    Button {
                        app.goEventFromStory(snap.eventKey)
                    } label: {
                        Text(app.T("Xem sự kiện", "View event"))
                            .font(.system(size: 13.5, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(app.palette.paper)
                            .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                    .accessibilityIdentifier("story.eventCard.cta")
                }
                .padding(16)
            }
            .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .frame(maxWidth: 340)
            .shadow(radius: 24)
            .accessibilityIdentifier("story.eventCard")
            .onTapGesture { app.goEventFromStory(snap.eventKey) }
        } else {
            Text(app.T("Sự kiện này không còn khả dụng.", "This event is no longer available."))
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(24)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
