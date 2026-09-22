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
// A deck this size or smaller preloads in full when the viewer opens; a
// larger one only preloads the current host + its immediate neighbors
// (BUG 3, 2026-09-22 eleventh follow-up) — bounded so a very active
// account doesn't kick off dozens of simultaneous downloads at once.
private let preloadFullDeckStoryLimit = 20

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
    // BUG 3 (2026-09-22 eleventh follow-up) — which neighbor the companion
    // currently represents, purely derived from the live drag direction
    // (no separate imperative state needed — `dragOffsetX` is already
    // `@State`, so this recomputes on the same render pass that moves it).
    private var companionNeighborStory: StoryItem? {
        guard let v = app.storyViewer else { return nil }
        let goingNext = dragOffsetX < 0
        let neighborGroup = goingNext ? v.groups[safe: v.groupIndex + 1] : v.groups[safe: v.groupIndex - 1]
        return neighborGroup?.stories.first
    }
    @ViewBuilder private func companionBackdrop(for story: StoryItem) -> some View {
        Group {
            if story.kind == "event_share", let path = story.eventSnapshot?.img {
                CatalogPhoto(path: path, cornerRadius: 0)
            } else if let url = story.url {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
            }
        }
        .scaleEffect(1.15)
        .blur(radius: 18)
        .saturation(0.85)
    }

    var body: some View {
        if let viewer = app.storyViewer, let group = viewer.groups[safe: viewer.groupIndex], let story = group.stories[safe: viewer.storyIndex] {
            ZStack {
                Color.black.ignoresSafeArea()

                // Gallery-drift companion — a single flat glass panel (not
                // Instagram's rotated 3D side-card stack), scaling/fading
                // in from whichever edge the swipe is headed toward. Only
                // ever represents a REAL adjacent host (see
                // `hasNextHost`/`hasPrevHost`) — BUG 4's reveal-underneath
                // case never shows this at all. BUG 3 (2026-09-22 eleventh
                // follow-up): now shows that adjacent host's own preloaded
                // cover as a blurred, low-detail backdrop underneath the
                // glass tint — a deliberate branded placeholder, never a
                // blank gray panel.
                if !reduceMotion {
                    ZStack {
                        if let neighbor = companionNeighborStory {
                            companionBackdrop(for: neighbor)
                        }
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
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
            // BUG 3 (2026-09-22 eleventh follow-up) — background preload,
            // keyed on `groupIndex` (the target set only actually changes
            // when the host does, not per-post). `.task(id:)` is SwiftUI's
            // own structured-concurrency cancellation: switching hosts (a
            // new id) or this view disappearing entirely (StoryViewer
            // closing) both automatically cancel whatever preload was
            // still in flight — no separate cancellation bookkeeping
            // needed. Runs as a background side effect alongside the
            // current story's own render, never blocking it.
            .task(id: viewer.groupIndex) {
                await preloadAdjacent(viewer)
            }
        }
    }

    /// Preloads the actual renderable media (not just signed URLs, which
    /// iOS's own `loadHomeStories()` already resolves for the WHOLE deck up
    /// front in one batch) for the current host's stories in full, plus
    /// the immediately adjacent hosts' first story/cover — so a host-to-
    /// host swipe never hits a loading gap. Event-share covers go through
    /// `PhotoLoader` (the SAME cache `CatalogPhoto` itself reads from —
    /// see its own `RemoteImage` fix above — so a later `CatalogPhoto`
    /// render for this exact path paints instantly from cache); real
    /// media stories go through a plain prefetch into `URLCache.shared`,
    /// which `AsyncImage`'s own `URLSession.shared`-backed loading also
    /// reads from.
    private func preloadAdjacent(_ viewer: StoryViewerState) async {
        let totalStories = viewer.groups.reduce(0) { $0 + $1.stories.count }
        let targetGroups: [StoryGroup]
        if totalStories <= preloadFullDeckStoryLimit {
            targetGroups = viewer.groups
        } else {
            targetGroups = [viewer.groupIndex - 1, viewer.groupIndex, viewer.groupIndex + 1].compactMap { viewer.groups[safe: $0] }
        }
        let currentOrgId = viewer.groups[safe: viewer.groupIndex]?.organizerId
        await withTaskGroup(of: Void.self) { group in
            for g in targetGroups {
                // The current host's own full set; an adjacent host's just
                // its FIRST story (the one a swipe would actually land on
                // first) — matches this ticket's own "at minimum" scope.
                let stories = g.organizerId == currentOrgId ? g.stories : Array(g.stories.prefix(1))
                for st in stories {
                    group.addTask { await Self.preloadStory(st) }
                }
            }
        }
    }
    private static func preloadStory(_ st: StoryItem) async {
        if st.kind == "event_share" {
            guard let path = st.eventSnapshot?.img else { return }
            _ = await PhotoLoader.load(path: path, maxPixel: 340 * UIScreen.main.scale)
        } else if let url = st.url {
            _ = try? await URLSession.shared.data(from: url)
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
                            // BUG 2 (2026-09-22 eleventh follow-up) — both
                            // edges of the whole deck now reveal Home
                            // identically; this used to only apply to the
                            // FORWARD/no-next-host case, leaving the
                            // BACKWARD/no-prev-host edge (first story,
                            // swipe right) rubber-banding with nothing
                            // shown underneath — an asymmetry this ticket
                            // explicitly calls out.
                            revealOpacity = 1 - min(1, abs(dx) / stageWidth)
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
                    } else if let v, (goingNext ? !hasNextHost(v) : !hasPrevHost(v)), beyondThreshold {
                        // BUG 4 / BUG 2 — EITHER edge of the whole deck
                        // (final story of the final host, swipe forward;
                        // OR first story of the first host, swipe
                        // backward), past the commit threshold: complete
                        // the reveal into Home/Account instead of springing
                        // back. Dock visibility only restores once
                        // `closeStoryViewer()` actually runs.
                        withAnimation(.easeOut(duration: hswipeSettleMs)) {
                            revealOpacity = 0
                            dragOffsetX = goingNext ? -stageWidth : stageWidth
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
