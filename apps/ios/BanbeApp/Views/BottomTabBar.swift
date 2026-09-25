import SwiftUI

/// Floating glass tab bar — the iOS port of src/screens/BottomTabBar.jsx.
/// Deployment target is iOS 17 (apps/ios/project.yml: deploymentTarget.iOS
/// = "17.0"), so the native iOS 26 `.tabBarMinimizeBehavior(.onScrollDown)`
/// isn't available; this hand-rolls the same "shrink on scroll down,
/// restore on scroll up" behavior off AppState.bottomBarCollapsed (see
/// ScreenScaffold's scroll-offset tracking / AppState.noteScaffoldScroll(),
/// which now throttles + animates that mutation — see its own doc comment).
/// Same four destinations as the old header row (Map/Notifications/Inbox/
/// Account). Icons: Map/Notifications/Inbox use distinct pin/bell/envelope
/// silhouettes (see the FEATURE comment above their glyph structs), Profile
/// keeps its original ring+shoulders mark — all four still avoid the
/// classic IG/FB/Twitter shapes (filled house, paper plane, magnifying
/// glass) while reading as this app's own icon family.
struct BottomTabBar: View {
    @EnvironmentObject var app: AppState

    static let visibleScreens: Set<Screen> = [.home, .mapExplore, .notifications, .inbox, .profile]

    // BUG 2 (64f2719) / BUG 3 (623ec1e) follow-ups: bumped up from 22/19
    // (expanded/collapsed) to a single fixed, larger size, then bumped
    // again for BUG 3's "make the resting bar a bit bigger" ask. The
    // shrink-on-scroll effect is a uniform `.scaleEffect` on the whole bar
    // (see body), not a per-icon size change, so one constant is enough and
    // it stays crisp at every scale factor instead of laying out at a
    // smaller intrinsic size.
    //
    // Task 5 follow-up (this session): flattened/elongated — 72→54 tall,
    // 360→420 wide — both to read as a slimmer, more refined pill and,
    // more functionally, to leave more of the screen's bottom edge clear
    // for MapExplore's own sheet list at its tallest detent, where the
    // list scrolls all the way down to the physical bottom edge and was
    // competing with the bar's own (now also tightened, see
    // BottomTabBarOverlay.swift) hit-testable band for the same touches.
    // Icon size trimmed 30→24 to comfortably fit the shorter bar.
    // `static` (not just `private`) so `BottomTabBarOverlay` can size its
    // hosting window's band FROM these values directly instead of an
    // independently-chosen guess — see that type's own doc comment for
    // why keeping the two in lockstep is the actual point this time.
    // Task 5 (2026-09-21 follow-up): bumped 54→64 and icon size trimmed
    // 24→20 to make room for a small label under each icon (was icon-only,
    // no on-screen text telling a first-time user what any of the five do)
    // while keeping the same slim-pill proportions — mirrors the exact same
    // change on `src/screens/BottomTabBar.jsx`. `BottomTabBarOverlay` reads
    // `Self.barHeight` directly for its own hosting window's hit-testable
    // band, so it stays in lockstep automatically.
    static let barHeight: CGFloat = 64
    // TASK 1 (2026-10-05 fix pass) — reduced from 380 to 300 so the dock
    // and the create-"+" button (now ONE laid-out row — see DockRow, this
    // file, and BottomTabBarOverlay.swift's own DockRow usage) could sit
    // side by side without overlapping or blowing past the safe area.
    // BUG 2 (2026-10-07 fix pass) — 300 read as cramped once the material/
    // scale fixes made the two controls look properly related — bumped
    // back up moderately to 340, still well short of 380 (the old overlap-
    // causing width) and still a genuine max/upper bound, not a fixed
    // width: DockRow's HStack still shrinks this further on a narrower
    // screen once the "+" and margins are accounted for (each tab item
    // already uses `.frame(maxWidth: .infinity)`, so the whole row — and
    // the equal spacing between tabs that comes from every item sharing
    // the same flexible width — compresses fluidly rather than clipping).
    static let barWidth: CGFloat = 340
    static let barHorizontalPadding: CGFloat = 20
    static let bottomOffset: CGFloat = 2
    // TASK 1 — shared with the create-"+" button (DockCreateButtonView) and
    // DockRow's own gap/margin, so "one layout group, shared vertical
    // center" is structural, not two independently-tuned numbers that can
    // drift apart.
    static let dockMargin: CGFloat = 16
    static let dockGap: CGFloat = 10
    static let createButtonSize: CGFloat = barHeight
    private let iconSize: CGFloat = 20
    private var barHeight: CGFloat { Self.barHeight }

    private struct Item: Identifiable {
        let id: String
        let icon: (Color) -> AnyView
        let label: String
        // Task 5 (2026-09-21 follow-up): a SHORT (one-word) form of `label`
        // for the on-dock text — "Trang chính"/"Home" is fine as an
        // accessibility label but too long to sit under a 20px icon
        // without wrapping/overflowing.
        let dockLabel: String
        let action: () -> Void
        let badge: Int
        // Notifications' badge (per-account read_at) caps at "9+" — this
        // app's existing convention. Inbox's badge counts CONVERSATIONS
        // with an unread message, not raw messages (refreshUnreadMessageCount(),
        // AppState+Data.swift), which naturally stays small enough that a
        // cap would just hide real information — shown uncapped per this
        // ticket's own ask.
        var badgeCapped: Bool = false
    }

    private var items: [Item] {
        [
            Item(id: "home", icon: { AnyView(HomeGlyph(color: $0)) }, label: app.T("Trang chính", "Home"), dockLabel: app.T("Trang chủ", "Home"), action: { app.goHome() }, badge: 0),
            Item(id: "map", icon: { AnyView(MapGlyph(color: $0)) }, label: app.T("Bản đồ", "Map"), dockLabel: app.T("Bản đồ", "Map"), action: { app.goMapExplore() }, badge: 0),
            Item(id: "notifications", icon: { AnyView(NotificationsGlyph(color: $0)) }, label: app.T("Thông báo", "Notifications"), dockLabel: app.T("Thông báo", "Alerts"), action: { app.goNotifications() }, badge: app.unreadNotifications, badgeCapped: true),
            // Unread count: number of conversations with an unread message
            // — see refreshUnreadMessageCount() (AppState+Data.swift),
            // refreshed on the same 5s poll as unreadNotifications.
            Item(id: "inbox", icon: { AnyView(InboxGlyph(color: $0)) }, label: app.T("Tin nhắn", "Messages"), dockLabel: app.T("Tin nhắn", "Inbox"), action: { app.goInbox() }, badge: app.unreadMessages),
            Item(id: "profile", icon: { AnyView(ProfileGlyph(color: $0)) }, label: app.T("Tài khoản", "Account"), dockLabel: app.T("Tài khoản", "Account"), action: { app.goProfile() }, badge: 0),
        ]
    }

    // FEATURE — scrub-to-select: which tab is currently under the finger
    // during a press/drag, and each tab's own frame (captured via
    // anchorPreference below) so a raw touch x-position can be hit-tested
    // against them.
    @State private var activeID: String?
    @State private var itemFrames: [String: CGRect] = [:]
    // BUG 1 fix (623ec1e real-device report): `activeID` used to be purely
    // drag-transient — `nil` whenever no gesture was in flight, so the
    // highlight vanished the instant the finger lifted. This flag lets the
    // gesture "own" `activeID` live while a drag is happening, and lets
    // `syncActiveToScreen()` own it the rest of the time (after a tap,
    // after a drag release, on first appearance, or after navigating here
    // some other way entirely, e.g. a deep link) so the highlight always
    // sits behind whichever tab is actually current.
    @State private var isDragging = false

    private func syncActiveToScreen() {
        guard !isDragging else { return }
        switch app.screen {
        case .home: activeID = "home"
        case .mapExplore: activeID = "map"
        case .notifications: activeID = "notifications"
        case .inbox: activeID = "inbox"
        case .profile: activeID = "profile"
        default: activeID = nil
        }
    }

    private func hitTest(_ x: CGFloat) -> String? {
        for item in items {
            if let frame = itemFrames[item.id], x >= frame.minX, x <= frame.maxX { return item.id }
        }
        // A drag that slides past either end still resolves to that end's
        // tab, rather than losing the highlight — matches a real segmented
        // control's own edge behavior.
        if let first = items.first, let frame = itemFrames[first.id], x < frame.minX { return first.id }
        if let last = items.last, let frame = itemFrames[last.id], x > frame.maxX { return last.id }
        return nil
    }

    private var scrubGesture: some Gesture {
        // minimumDistance: 0 so this also fires for a plain tap-and-release
        // — a tap that never moves still lands on, and navigates to,
        // whichever tab it started on.
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                isDragging = true
                let id = hitTest(value.location.x)
                if id != activeID {
                    withAnimation(.interactiveSpring()) { activeID = id }
                }
            }
            .onEnded { value in
                let id = hitTest(value.location.x)
                if let id, let item = items.first(where: { $0.id == id }) { item.action() }
                // BUG 1 fix: leave the highlight exactly where the drag
                // landed instead of clearing it to nil — it stays lit on
                // the tab just navigated to. `isDragging = false` hands
                // ownership back to syncActiveToScreen(), which is a no-op
                // here since `activeID` already matches (or will match, the
                // moment `app.screen` catches up via its own onChange).
                isDragging = false
            }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Soft, blurred, darker highlight blob — reuses the ink token
            // (no new color), not a new tint.
            if let activeID, let frame = itemFrames[activeID] {
                Capsule()
                    .fill(app.palette.ink.opacity(0.12))
                    .frame(width: frame.width, height: barHeight - 10)
                    .position(x: frame.midX, y: barHeight / 2)
                    .blur(radius: 0.5)
                    .allowsHitTesting(false)
            }

            HStack(spacing: 0) {
                ForEach(items) { item in
                    VStack(spacing: 3) {
                        ZStack(alignment: .topTrailing) {
                            item.icon(app.palette.ink)
                                .frame(width: iconSize, height: iconSize)
                                .opacity(activeID == item.id ? 1 : 0.86)
                            if item.badge > 0 {
                                Text(item.badgeCapped && item.badge > 9 ? "9+" : "\(item.badge)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .frame(minWidth: 14, minHeight: 14)
                                    .background(BanbeTheme.alert, in: Capsule())
                                    .offset(x: 7, y: -5)
                            }
                        }
                        // Task 5 (2026-09-21 follow-up) — a small label
                        // under each icon so it's not icon-only.
                        Text(item.dockLabel)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(app.palette.ink.opacity(activeID == item.id ? 1 : 0.72))
                    }
                    .frame(maxWidth: .infinity, minHeight: barHeight)
                    .accessibilityIdentifier("tab.\(item.id)")
                    .accessibilityLabel(item.label)
                    .anchorPreference(key: TabItemFrameKey.self, value: .bounds) { [item.id: $0] }
                }
            }
        }
        .frame(height: barHeight)
        // Task 1b follow-up: widened from 320 (fit for 4 icons) to fit the
        // new Home tab without cramping the existing four — matches the
        // web bar's own bump. Task 5: widened again, to `Self.barWidth`,
        // as part of the flatter/more-elongated pill shape.
        .frame(maxWidth: Self.barWidth)
        .contentShape(Rectangle())
        .gesture(scrubGesture)
        .backgroundPreferenceValue(TabItemFrameKey.self) { anchors in
            GeometryReader { proxy in
                Color.clear.onAppear { resolveFrames(anchors, proxy) }
                    .onChange(of: proxy.size) { _, _ in resolveFrames(anchors, proxy) }
            }
        }
        .background(.thinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(app.palette.ink.opacity(0.06)))
        .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 6)
        // BUG (2026-10-06 fix pass) — the shrink-on-scroll `.scaleEffect`
        // used to live HERE, scoped to just this capsule's own body. Since
        // `DockRow` lays this out as one HStack sibling of
        // `DockCreateButtonView`, scaling only THIS child meant the dock
        // visibly shrank on scroll while the "+" beside it stayed full
        // size — exactly the reported "dock changes size but + stays
        // large." Moved to `DockRow` itself (below), scoped to the WHOLE
        // row, so both controls scale as one unit — matches this ticket's
        // own "keep both in the same layout/animation state" instruction.
        // TASK 1 (2026-10-05 fix pass) — the outer horizontal margin and
        // bottom offset used to live here, self-positioning this capsule in
        // isolation. Now that the dock and the create-"+" button lay out
        // together as one row (see DockRow below), that margin/offset moved
        // to the ROW so both controls share exactly one outer margin and
        // one bottom offset instead of each picking its own independently
        // (the real cause of them reading as two unrelated floating shapes
        // rather than one group).
        .onAppear { syncActiveToScreen() }
        .onChange(of: app.screen) { _, _ in
            withAnimation(.easeOut(duration: 0.18)) { syncActiveToScreen() }
        }
        // BUG 3 follow-up (4d137235 real-device report): a `.zIndex()` set
        // HERE, inside this view's own `body`, does NOT affect BottomTabBar's
        // position among its siblings in RootView's ZStack — it only
        // affects ordering within BottomTabBar's own internal view tree
        // (irrelevant, there's no overlap to resolve in here). The actual
        // fix for the bar being covered by MapExploreView's `Map()` lives
        // at the call site in RootView.swift, where BottomTabBar() is a
        // direct ZStack child — see that file's comment.
    }

    private func resolveFrames(_ anchors: [String: Anchor<CGRect>], _ proxy: GeometryProxy) {
        var result: [String: CGRect] = [:]
        for (id, anchor) in anchors { result[id] = proxy[anchor] }
        itemFrames = result
    }
}

/// TASK 1 (2026-10-05 fix pass) — the dock and the create-"+" button as ONE
/// laid-out row, replacing two independently-positioned floating shapes
/// (BottomTabBar centered via its own frame math, DockCreateButtonView
/// pinned bottom-trailing with its own separate padding) that could and did
/// overlap on a real device: BottomTabBar's old 380pt max width left under
/// 4pt of clearance from a 390pt-wide iPhone's edges alone, with nothing
/// left over for a 46-64pt circle beside it.
///
/// An HStack, not two absolutely-positioned views: the "+" is a fixed-size
/// trailing child, the dock is the flexible one (`Self.barWidth` is an
/// upper bound, not a fixed width — see that constant's own comment), and
/// SwiftUI's normal HStack layout does the "shrink the flexible one first"
/// math for free once the available width (this row's own container, i.e.
/// the overlay window — already full device width, see
/// BottomTabBarOverlay.bandWidth's own comment) is narrower than
/// `barWidth + dockGap + createButtonSize`. One shared `dockMargin` on the
/// row itself replaces each control's own independent outer padding, so
/// both ends of the WHOLE group sit at the same distance from the screen
/// edge, and `dockGap` is the one visual separation between them — "clearly
/// two controls, visually one group," per this ticket's own ask.
struct DockRow: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        HStack(alignment: .center, spacing: BottomTabBar.dockGap) {
            BottomTabBar()
            if app.organizerMode {
                DockCreateButtonView()
            }
        }
        .padding(.horizontal, BottomTabBar.dockMargin)
        .padding(.bottom, BottomTabBar.bottomOffset)
        // BUG (2026-10-06 fix pass) — applied to the WHOLE row now, not
        // just `BottomTabBar`'s own body (see that scaleEffect's own
        // former call site, this file) — both controls shrink/expand
        // together on scroll instead of only the dock visibly resizing
        // while the "+" stayed full size beside it.
        .scaleEffect(app.bottomBarCollapsed ? 0.86 : 1, anchor: .bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

private struct TabItemFrameKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// FEATURE follow-up (623ec1e real-device report): Map/Notifications/Inbox
// were still hard to tell apart at a glance despite 64f2719's stroke-count
// trim, so these three moved to unambiguous, differently-shaped silhouettes
// — a pin/marker for Map, a bell for Notifications, an envelope for Inbox —
// instead of iterating further on the shared ring/diagonal-stroke/dot
// vocabulary those three used before (that vocabulary is what made them
// hard to distinguish: they all read as "a ring plus a stroke"). Profile is
// deliberately UNCHANGED (user confirmed it already reads fine) and the new
// three match its stroke weight (2.4-2.6) and rounded joins/caps so the set
// still reads as one family — mirrors src/screens/BottomTabBar.jsx's own
// icon set exactly, shape for shape. See 06-design-tokens.md for the fuller
// rationale.

// BUG 1 follow-up (4d137235 real-device report): this used to be a
// hand-drawn symmetric teardrop approximating the web icon's silhouette
// (two generic cubic curves through (6,5)/(6,15) and (18,15)/(18,5)) rather
// than the ACTUAL path web draws — close enough to read as "a pin" but
// visibly a different shape side by side. Ported exactly instead: the web
// SVG `d="M12 3c-3.3 0-6 2.6-6 6.1C6 13.4 12 21 12 21s6-7.6 6-11.9C18 5.6
// 15.3 3 12 3z"` is 4 cubic Bézier segments once its relative/smooth (c/s)
// commands are resolved to absolute control points — see each addCurve
// below, one SVG command per line, same coordinates, so both platforms
// trace the literal same outline instead of two independently-drawn pins.
private struct MapGlyph: View {
    let color: Color
    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 24
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 12 * s, y: 3 * s))
                    // c -3.3,0 -6,2.6 -6,6.1
                    p.addCurve(to: CGPoint(x: 6 * s, y: 9.1 * s), control1: CGPoint(x: 8.7 * s, y: 3 * s), control2: CGPoint(x: 6 * s, y: 5.6 * s))
                    // C6,13.4 12,21 12,21
                    p.addCurve(to: CGPoint(x: 12 * s, y: 21 * s), control1: CGPoint(x: 6 * s, y: 13.4 * s), control2: CGPoint(x: 12 * s, y: 21 * s))
                    // s6,-7.6 6,-11.9 (smooth: c1 reflects the previous c2 through the current point)
                    p.addCurve(to: CGPoint(x: 18 * s, y: 9.1 * s), control1: CGPoint(x: 12 * s, y: 21 * s), control2: CGPoint(x: 18 * s, y: 13.4 * s))
                    // C18,5.6 15.3,3 12,3
                    p.addCurve(to: CGPoint(x: 12 * s, y: 3 * s), control1: CGPoint(x: 18 * s, y: 5.6 * s), control2: CGPoint(x: 15.3 * s, y: 3 * s))
                    p.closeSubpath()
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2.4 * s, lineCap: .round, lineJoin: .round))
                Circle().fill(color).frame(width: 4.6 * s, height: 4.6 * s).position(x: 12 * s, y: 9.3 * s)
            }
        }
    }
}

private struct NotificationsGlyph: View {
    let color: Color
    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 24
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 7 * s, y: 13.1 * s))
                    p.addLine(to: CGPoint(x: 7 * s, y: 8.5 * s))
                    p.addCurve(to: CGPoint(x: 12 * s, y: 3.5 * s), control1: CGPoint(x: 7 * s, y: 5.7 * s), control2: CGPoint(x: 9.2 * s, y: 3.5 * s))
                    p.addCurve(to: CGPoint(x: 17 * s, y: 8.5 * s), control1: CGPoint(x: 14.8 * s, y: 3.5 * s), control2: CGPoint(x: 17 * s, y: 5.7 * s))
                    p.addLine(to: CGPoint(x: 17 * s, y: 13.1 * s))
                    p.addLine(to: CGPoint(x: 18.7 * s, y: 16.3 * s))
                    p.addCurve(to: CGPoint(x: 18 * s, y: 17.4 * s), control1: CGPoint(x: 19 * s, y: 16.9 * s), control2: CGPoint(x: 18.6 * s, y: 17.4 * s))
                    p.addLine(to: CGPoint(x: 6 * s, y: 17.4 * s))
                    p.addCurve(to: CGPoint(x: 5.3 * s, y: 16.3 * s), control1: CGPoint(x: 5.4 * s, y: 17.4 * s), control2: CGPoint(x: 5 * s, y: 16.9 * s))
                    p.closeSubpath()
                }
                .fill(color)
                Path { p in p.addArc(center: CGPoint(x: 12 * s, y: 18.6 * s), radius: 2.4 * s, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false) }
                    .stroke(color, style: StrokeStyle(lineWidth: 2 * s, lineCap: .round))
            }
        }
    }
}

private struct InboxGlyph: View {
    let color: Color
    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 24
            ZStack {
                RoundedRectangle(cornerRadius: 2.4 * s, style: .continuous)
                    .stroke(color, lineWidth: 2.4 * s)
                    .frame(width: 15 * s, height: 11 * s)
                    .position(x: 12 * s, y: 12.5 * s)
                Path { p in
                    p.move(to: CGPoint(x: 5.5 * s, y: 8.2 * s))
                    p.addLine(to: CGPoint(x: 12 * s, y: 13.5 * s))
                    p.addLine(to: CGPoint(x: 18.5 * s, y: 8.2 * s))
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2.2 * s, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

private struct ProfileGlyph: View {
    let color: Color
    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 24
            ZStack {
                Circle().stroke(color, lineWidth: 2.6 * s).frame(width: 7.6 * s, height: 7.6 * s).position(x: 12 * s, y: 8 * s)
                Path { p in
                    p.move(to: CGPoint(x: 5 * s, y: 19.2 * s))
                    p.addCurve(to: CGPoint(x: 19 * s, y: 19.2 * s), control1: CGPoint(x: 6.3 * s, y: 15.3 * s), control2: CGPoint(x: 17.7 * s, y: 15.3 * s))
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2.6 * s, lineCap: .round))
            }
        }
    }
}

// Task 1b follow-up: a straightforward addition to the existing icon set —
// same stroke weight (2.4) and rounded joins as the other four, a plain
// house silhouette. Unlike the map icon's own earlier "avoid the classic
// filled house outline" constraint (about not using a house FOR a map
// glyph specifically), a house for an actual Home tab is the universally
// understood, semantically correct choice, not a borrowed IG/FB/Twitter
// shape — mirrors src/screens/BottomTabBar.jsx's own Home icon exactly,
// shape for shape.
private struct HomeGlyph: View {
    let color: Color
    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 24
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 4 * s, y: 11.5 * s))
                    p.addLine(to: CGPoint(x: 12 * s, y: 4 * s))
                    p.addLine(to: CGPoint(x: 20 * s, y: 11.5 * s))
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2.4 * s, lineCap: .round, lineJoin: .round))
                Path { p in
                    p.move(to: CGPoint(x: 6 * s, y: 10 * s))
                    p.addLine(to: CGPoint(x: 6 * s, y: 19.5 * s))
                    p.addLine(to: CGPoint(x: 18 * s, y: 19.5 * s))
                    p.addLine(to: CGPoint(x: 18 * s, y: 10 * s))
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2.4 * s, lineJoin: .round))
            }
        }
    }
}
