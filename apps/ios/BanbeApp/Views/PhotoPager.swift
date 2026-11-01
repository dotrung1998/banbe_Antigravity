import SwiftUI

/// Map v6 (note 74): an event's photos you swipe sideways (Airbnb-style), on Map Large cards and Home's discovery
/// cards. Web twin: src/components/PhotoPager.jsx.
///
/// - Horizontal `ScrollView` + `.scrollTargetBehavior(.paging)` (same mechanism as HowBanbeWorksView's deck); pages
///   are lazy (`LazyHStack`), each a `CatalogPhoto` decoded at the card's size (PhotoLoader cache, note 22).
/// - `rootSwipeExclusion("pager.<eventId>.<context>")`: a photo swipe never switches dock tabs
///   (`RootView.tabSwipeGesture`).
/// - Dots + a "2/5" counter; VoiceOver reads "Photo 2 of 5" and pages with swipe up / down (adjustable).
/// - One photo (or none): exactly the plain photo, no dots, no counter, no scrolling.
/// - Reduce Motion: the adjustable action and dot changes jump without animation.
struct PhotoPager: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let eventID: String
    let paths: [String]
    /// Keeps exclusion zones apart when the same event shows twice (e.g. "map", "home").
    var context: String = "card"
    var cornerRadius: CGFloat = 16
    /// Identifier of the photo element itself (Home keeps `card.<key>` there for its UI tests).
    var photoIdentifier: String? = nil
    var placeholder: Color? = nil

    @State private var page: Int? = 0

    private var current: Int { min(max(page ?? 0, 0), max(paths.count - 1, 0)) }

    var body: some View {
        GeometryReader { geo in
            if paths.count <= 1 {
                single(size: geo.size)
            } else {
                pager(size: geo.size)
            }
        }
    }

    @ViewBuilder
    private func single(size: CGSize) -> some View {
        if let path = paths.first, !path.isEmpty {
            CatalogPhoto(path: path, height: size.height, width: size.width, cornerRadius: cornerRadius)
                .accessibilityIdentifier(photoIdentifier ?? "photoPager.photo.\(eventID)")
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(placeholder ?? app.palette.field)
                .overlay { Text(app.T("Chưa có ảnh", "No photo yet")).font(.system(size: 12)).opacity(0.55) }
                .foregroundStyle(app.palette.ink)
                .accessibilityLabel(app.T("Chưa có ảnh", "No photo yet"))
                .accessibilityIdentifier(photoIdentifier ?? "photoPager.photo.\(eventID)")
        }
    }

    private func pager(size: CGSize) -> some View {
        let n = paths.count
        if size.width > 0 { CardPhotoPrefetch.measuredWidth = size.width }
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(Array(paths.enumerated()), id: \.offset) { i, path in
                    CatalogPhoto(path: path, height: size.height, width: size.width, cornerRadius: 0)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                        .id(i)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $page)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.T("Ảnh \(current + 1) / \(n)", "Photo \(current + 1) of \(n)"))
        .accessibilityAddTraits(.isImage)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: go(to: current + 1)
            case .decrement: go(to: current - 1)
            @unknown default: break
            }
        }
        .accessibilityIdentifier(photoIdentifier ?? "photoPager.photo.\(eventID)")
        .overlay(alignment: .bottom) {
            HStack(spacing: 5) {
                ForEach(0..<n, id: \.self) { i in
                    Circle()
                        .fill(Color.white.opacity(i == current ? 1 : 0.55))
                        .frame(width: i == current ? 7 : 6, height: i == current ? 7 : 6)
                }
            }
            .padding(.horizontal, 7).padding(.vertical, 5)
            .background(Color.black.opacity(0.28), in: Capsule())
            .padding(.bottom, 10)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: current)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .overlay(alignment: .bottomTrailing) {
            Text("\(current + 1)/\(n)")
                .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Color.black.opacity(0.45), in: Capsule())
                .padding(10)
                .allowsHitTesting(false)
                .accessibilityLabel(app.T("Ảnh \(current + 1) / \(n)", "Photo \(current + 1) of \(n)"))
                .accessibilityValue("\(current + 1)/\(n)")
                .accessibilityIdentifier("photoPager.counter.\(eventID)")
        }
        // A photo swipe never switches dock tabs. The frame goes to a plain store (PagerSwipeZones), NOT to the
        // @Published `rootGestureExclusionZones`: publishing it re-rendered the whole app on every frame of a vertical
        // Home scroll (each visible pager's frame moves), which made Home laggy and, after a photo swipe, froze it
        // (the modifier and Home's preference handler kept overwriting each other's zones).
        .background {
            GeometryReader { geo in
                let zone = "pager.\(eventID).\(context)"
                Color.clear
                    .onAppear { PagerSwipeZones.set(zone, geo.frame(in: .named("rootGesture")), screen: app.screen) }
                    .onChange(of: geo.frame(in: .named("rootGesture"))) { _, f in PagerSwipeZones.set(zone, f, screen: app.screen) }
                    .onDisappear { PagerSwipeZones.set(zone, nil) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("photoPager.\(eventID)")
    }

    private func go(to i: Int) {
        let next = min(max(i, 0), paths.count - 1)
        if reduceMotion { page = next } else { withAnimation(.easeOut(duration: 0.25)) { page = next } }
    }
}

/// Photo pagers' on-screen frames (in the "rootGesture" space), read once by `RootView.tabSwipeGesture` when a drag
/// starts. Deliberately not observable: frames change on every scroll frame and nothing needs to re-render for it.
enum PagerSwipeZones {
    /// Tagged with the screen it was measured on: Home can stay mounted under another tab, and its stale frames must
    /// not block that tab's swipes.
    @MainActor private static var zones: [String: (frame: CGRect, screen: Screen)] = [:]
    @MainActor static func set(_ id: String, _ frame: CGRect?, screen: Screen = .home) {
        zones[id] = frame.map { ($0, screen) }
    }
    @MainActor static func contains(_ point: CGPoint, on screen: Screen) -> Bool {
        zones.values.contains { $0.screen == screen && $0.frame.contains(point) }
    }
}

/// Warms PhotoLoader's cache with card photos at EXACTLY the size the cards decode them (same cache key), so a card
/// that appears later (the Map sheet opening to full, owner 2026-11-01) paints at once instead of from a blurry
/// stand-in. A pager decodes at its measured width; a single photo at CatalogPhoto's 420 pt fallback.
enum CardPhotoPrefetch {
    @MainActor static var measuredWidth: CGFloat?

    @MainActor static func run(_ lists: [[String]], limit: Int = 8) {
        let scale = UIScreen.main.scale
        let pagerPx = (measuredWidth ?? UIScreen.main.bounds.width - 56) * scale
        let singlePx = 420 * scale
        let jobs: [(String, CGFloat)] = lists.prefix(limit).flatMap { paths -> [(String, CGFloat)] in
            paths.count > 1 ? paths.prefix(2).map { ($0, pagerPx) } : paths.prefix(1).map { ($0, singlePx) }
        }
        let todo = jobs.filter { !$0.0.isEmpty && PhotoLoader.cached(path: $0.0, maxPixel: $0.1) == nil }
        guard !todo.isEmpty else { return }
        Task(priority: .utility) {
            for (path, px) in todo { _ = await PhotoLoader.load(path: path, maxPixel: px) }
        }
    }
}
