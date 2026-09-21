import SwiftUI

// Task 3.4 (07-notifications.md) — the story progression viewer. A
// deliberately SEPARATE view/state from PhotoViewerView/ChatPhotoViewerView
// (14-photo-viewer.md's own instruction not to conflate origin/back
// semantics across viewer kinds).
private let storyDurationSeconds: Double = 5

struct StoryViewerView: View {
    @EnvironmentObject var app: AppState
    @State private var progress: Double = 0
    @State private var timerTask: Task<Void, Never>?

    var body: some View {
        if let viewer = app.storyViewer, let story = viewer.stories[safe: viewer.index] {
            ZStack {
                Color.black.ignoresSafeArea()

                AsyncImage(url: story.url) { $0.resizable().scaledToFit() } placeholder: { ProgressView().tint(.white) }
                    .accessibilityIdentifier("story.viewer.image")

                HStack(spacing: 4) {
                    ForEach(Array(viewer.stories.enumerated()), id: \.offset) { i, _ in
                        GeometryReader { geo in
                            Capsule().fill(Color.white.opacity(0.35))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(Color.white)
                                        .frame(width: geo.size.width * (i < viewer.index ? 1 : i == viewer.index ? progress : 0))
                                }
                        }
                        .frame(height: 2.5)
                    }
                }
                .padding(.horizontal, 12)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 54)

                Button { app.closeStoryViewer() } label: {
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

                // Left/right tap zones — mirrors PhotoViewer's own half-width
                // convention, adapted for a single non-swipe-browsable image.
                HStack(spacing: 0) {
                    Color.clear.contentShape(Rectangle()).onTapGesture { app.storyPrev() }
                    Color.clear.contentShape(Rectangle()).onTapGesture { advance() }
                }
            }
            .transition(.opacity)
            .zIndex(27)
            .onChange(of: viewer.index) { _, _ in restartTimer() }
            .onAppear {
                Task { await app.viewStoryTick(story.id) }
                restartTimer()
            }
            .onDisappear { timerTask?.cancel() }
        }
    }

    private func advance() { app.storyNext() }

    private func restartTimer() {
        guard let viewer = app.storyViewer, let story = viewer.stories[safe: viewer.index] else { return }
        Task { await app.viewStoryTick(story.id) }
        timerTask?.cancel()
        progress = 0
        timerTask = Task {
            let steps = 60
            for i in 0...steps {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: UInt64(storyDurationSeconds * 1_000_000_000 / Double(steps)))
                if Task.isCancelled { return }
                await MainActor.run { progress = Double(i) / Double(steps) }
            }
            if !Task.isCancelled { await MainActor.run { advance() } }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
