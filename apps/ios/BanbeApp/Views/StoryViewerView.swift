import SwiftUI

// Task 3.4 (07-notifications.md) — the story progression viewer. A
// deliberately SEPARATE view/state from PhotoViewerView/ChatPhotoViewerView
// (14-photo-viewer.md's own instruction not to conflate origin/back
// semantics across viewer kinds) even though it reuses the same
// blurred-fullscreen visual language and, as of this pass, the same
// live-drag-follow / hold-to-pause CONVENTIONS ChatPhotoViewerView
// established (b75b884) — not its state, per that same instruction.
private let storyDurationSeconds: Double = 5
private let dismissMs: Double = 0.26
private let dismissThreshold: CGFloat = 90
private let dragRevealDistance: CGFloat = 220
private let holdThresholdMs: Int = 180 // a plain tap stays a tap

struct StoryViewerView: View {
    @EnvironmentObject var app: AppState

    // Progress — driven by elapsed real time (Task 3), not discrete sleep
    // ticks. `advanceTask` is the ONE thing that actually calls
    // storyNext() when the duration elapses; the TimelineView below only
    // ever reads elapsed time to draw, never mutates state mid-render.
    @State private var startDate = Date()
    @State private var pausedElapsed: TimeInterval = 0
    @State private var isPaused = false
    @State private var advanceTask: Task<Void, Never>?

    // Drag-to-dismiss + hold-to-pause — one gesture, disambiguated by
    // direction/duration, mirroring ChatPhotoViewerView's stage gesture.
    @State private var dragOffsetY: CGFloat = 0
    @State private var isDragging = false
    @State private var isHolding = false
    @State private var touchDown = false
    @State private var gestureStart: CGPoint = .zero
    @State private var closing = false

    private var dragProgress: CGFloat { min(1, max(0, dragOffsetY) / dragRevealDistance) }

    var body: some View {
        if let viewer = app.storyViewer, let story = viewer.stories[safe: viewer.index] {
            ZStack {
                Color.black.ignoresSafeArea()

                Group {
                    if story.kind == "event_share" {
                        EventShareCard(story: story)
                    } else {
                        AsyncImage(url: story.url) { $0.resizable().scaledToFit() } placeholder: { ProgressView().tint(.white) }
                            .accessibilityIdentifier("story.viewer.image")
                    }
                }
                .offset(y: dragOffsetY)
                .scaleEffect(1 - dragProgress * 0.08)

                chrome(viewer: viewer, index: viewer.index)
            }
            .opacity(closing ? 0 : 1)
            .contentShape(Rectangle())
            .gesture(stageGesture(viewer: viewer))
            .transition(.opacity)
            .zIndex(27)
            .onChange(of: viewer.index) { _, _ in resetProgress() }
            .onAppear {
                Task { await app.viewStoryTick(story.id) }
                resetProgress()
            }
            .onDisappear { advanceTask?.cancel() }
        }
    }

    private func chrome(viewer: StoryViewerState, index: Int) -> some View {
        ZStack {
            // Progress bars — smooth, elapsed-time-driven fill (Task 3),
            // paused (no ticking) while held/dragged.
            TimelineView(.animation(paused: isPaused)) { context in
                let elapsed = pausedElapsed + (isPaused ? 0 : context.date.timeIntervalSince(startDate))
                let progress = min(1, max(0, elapsed / storyDurationSeconds))
                HStack(spacing: 4) {
                    ForEach(Array(viewer.stories.enumerated()), id: \.offset) { i, _ in
                        GeometryReader { geo in
                            Capsule().fill(Color.white.opacity(0.35))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(Color.white)
                                        .frame(width: geo.size.width * (i < index ? 1 : i == index ? progress : 0))
                                }
                        }
                        .frame(height: 2.5)
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 54)

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

    // MARK: - Gesture (tap zones / hold-to-pause / drag-to-dismiss)

    private func stageGesture(viewer: StoryViewerState) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !touchDown {
                    touchDown = true
                    gestureStart = value.startLocation
                    scheduleHoldDetection()
                }
                let dy = value.translation.height
                let dx = value.translation.width
                if !isDragging && !isHolding {
                    guard dy > 6, dy > abs(dx) else { return }
                    isDragging = true
                    pauseProgress()
                }
                if isDragging { dragOffsetY = dy }
            }
            .onEnded { value in
                touchDown = false
                defer { isDragging = false }
                if isDragging {
                    if dragOffsetY > dismissThreshold {
                        dismiss()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragOffsetY = 0 }
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
            guard touchDown, !isDragging, !isHolding else { return }
            isHolding = true
            pauseProgress()
        }
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

    var body: some View {
        if let snap = story.eventSnapshot {
            VStack(spacing: 0) {
                AsyncImage(url: URL(string: snap.img)) { $0.resizable().scaledToFill() } placeholder: { app.palette.field }
                    .frame(height: 340)
                    .clipped()
                VStack(alignment: .leading, spacing: 4) {
                    Text(snap.name).font(BanbeTheme.display(18)).foregroundStyle(app.palette.ink)
                    Text("\(snap.when) · \(snap.location)")
                        .font(.system(size: 12)).foregroundStyle(app.palette.ink.opacity(0.7))
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
