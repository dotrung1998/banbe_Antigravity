import SwiftUI

/// Manages the five-step Home Pulse teaser. The visible bubble is rendered
/// inside HomeView.storyRow so it scrolls with the Pulse ring.
struct PulseTeaserBubbleView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.scenePhase) private var scenePhase

    @State private var step = -1 // -1 = not yet eligible; 0...4 = visible
    @State private var runningTask: Task<Void, Never>?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: step) { _, newStep in
                app.pulseTeaserStep = newStep
            }
            .onChange(of: app.screen) { _, newScreen in
                if newScreen == .home { reevaluate() } else { suspend() }
            }
            .onChange(of: app.user?.id) { _, _ in reevaluate() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { reevaluate() } else { suspend() }
            }
            .onAppear {
                app.pulseTeaserAdvance = { advance() }
                app.pulseTeaserOpenPhotos = { openFeaturedPhotos() }
                app.pulseTeaserStep = step
                reevaluate()
            }
            .onDisappear {
                suspend()
                app.pulseTeaserStep = -1
                app.pulseTeaserAdvance = nil
                app.pulseTeaserOpenPhotos = nil
            }
    }

    private func reevaluate() {
        guard app.screen == .home,
              scenePhase == .active,
              runningTask == nil,
              app.user?.id != nil else { return }

        if step < 0 {
            Task { await app.loadPulse(period: .daily) }
            Task { await app.loadPulse(period: .weekly) }
            step = 0
        }
        scheduleAdvance()
    }

    private func suspend() {
        runningTask?.cancel()
        runningTask = nil
        // Keep the current step so it can resume on returning to Home.
    }

    private func scheduleAdvance() {
        runningTask?.cancel()
        guard step >= 0,
              app.screen == .home,
              scenePhase == .active else {
            runningTask = nil
            return
        }

        let stillLoading = (step == 0 && app.pulseDailyLoading)
            || (step == 2 && app.pulseWeeklyLoading)
        if stillLoading {
            runningTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                scheduleAdvance()
            }
            return
        }

        let seconds: Double = (step == 0 || step == 2) ? 4.6 : 3.2
        runningTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            step = (step + 1) % 5
            scheduleAdvance()
        }
    }

    private func advance() {
        guard step >= 0 else { return }
        step = (step + 1) % 5
        scheduleAdvance()
    }

    private func openFeaturedPhotos() {
        // Keep the sequence alive; the Pulse viewer covers Home while open.
        app.openPulseViewer()
        app.pulseTab = .photos
    }
}

/// Drawn by HomeView.storyRow in the same scrolling coordinate space as
/// the Pulse ring. The row anchors its bottom-leading corner at the ring's
/// center, overlapping the ring's upper-right quadrant.
struct PulseTeaserBubbleContent: View {
    @EnvironmentObject var app: AppState
    let step: Int
    let onTap: () -> Void
    let onOpenFeaturedPhotos: () -> Void

    var body: some View {
        Group {
            if step == 0 {
                Text(app.T("Top sự kiện\nhôm nay", "Top events\nToday"))
            } else if step == 1 {
                rankedList(
                    app.pulseDaily,
                    empty: app.T("Chưa có xếp hạng hôm nay", "Nothing ranked yet today")
                )
            } else if step == 2 {
                Text(app.T("Top sự kiện\ntuần này", "Top events\nThis week"))
            } else if step == 3 {
                rankedList(
                    app.pulseWeekly,
                    empty: app.T("Chưa có xếp hạng tuần này", "Nothing ranked yet this week")
                )
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.T("Ảnh nổi bật:", "Featured photos:"))
                    Text(app.T("Bấm xem thêm", "Tap to view"))
                        .underline()
                        .onTapGesture { onOpenFeaturedPhotos() }
                        .accessibilityIdentifier("home.pulseTeaserFeaturedPhotosLink")
                }
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(app.palette.paper)
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            app.palette.ink,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
        // Tail repositioned (2026-09-29 follow-up) — was a sideways,
        // left-pointing wedge sticking out of the bubble's left EDGE; now a
        // downward-pointing tail sitting at the bubble's bottom-LEFT
        // CORNER instead (`Triangle`'s own path flipped to match).
        .overlay(alignment: .bottomLeading) {
            Triangle()
                .fill(app.palette.ink)
                .frame(width: 12, height: 7)
                .offset(x: 6, y: 3)
        }
        .onTapGesture { onTap() }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.pulseTeaserBubble")
    }

    @ViewBuilder
    private func rankedList(_ ranking: [PulseItem], empty: String) -> some View {
        if ranking.isEmpty {
            Text(empty)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(ranking.prefix(3).enumerated()), id: \.element.id) { i, item in
                    Text("\(i + 1). \(item.eventName)")
                        .lineLimit(1)
                }
            }
        }
    }
}

/// Points DOWN (flat edge on top, apex at the bottom) — was a sideways,
/// left-pointing wedge (apex at `minX, midY`, flat edge on the right).
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}