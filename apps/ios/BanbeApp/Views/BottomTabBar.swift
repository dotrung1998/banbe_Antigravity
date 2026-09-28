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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let visibleScreens: Set<Screen> = [.home, .mapExplore, .notifications, .inbox, .profile]
    // Stage 2 (2026-09-27 nav/discovery pass) — the ordered list RootView's
    // own root-tab swipe gesture navigates through; must match this file's
    // own `items` order exactly (that array can't be reused directly — it's
    // built with @EnvironmentObject-dependent actions/labels below).
    static let dockOrder: [Screen] = [.home, .mapExplore, .notifications, .inbox, .profile]
    static func goto(_ screen: Screen, app: AppState) {
        switch screen {
        case .home: app.goHome()
        case .mapExplore: app.goMapExplore()
        case .notifications: app.goNotifications()
        case .inbox: app.goInbox()
        case .profile: app.goProfile()
        default: break
        }
    }

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
    // Stage 3 — widened further (340→380) now that there's no label text
    // to wrap/clip; matches the web bar's own bump.
    static let barWidth: CGFloat = 380
    static let barHorizontalPadding: CGFloat = 20
    static let bottomOffset: CGFloat = 2
    // TASK 1 — shared with the create-"+" button (DockCreateButtonView) and
    // DockRow's own gap/margin, so "one layout group, shared vertical
    // center" is structural, not two independently-tuned numbers that can
    // drift apart.
    static let dockMargin: CGFloat = 16
    static let dockGap: CGFloat = 10
    static let createButtonSize: CGFloat = barHeight
    // Stage 3 (2026-09-27 nav/discovery pass) — bumped back up (20→26) now
    // that the on-dock text labels are gone (see the removed `dockLabel`
    // field/Text below) — the icon itself is the only thing left to read
    // at a glance, so it gets the room the labels used to occupy.
    private let iconSize: CGFloat = 26
    private var barHeight: CGFloat { Self.barHeight }

    private struct Item: Identifiable {
        let id: String
        let icon: (Color, Bool) -> AnyView
        let label: String
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
            Item(id: "home", icon: { AnyView(HomeGlyph(color: $0, filled: $1)) }, label: app.T("Trang chính", "Home"), action: { app.goHome() }, badge: 0),
            Item(id: "map", icon: { AnyView(MapGlyph(color: $0, filled: $1)) }, label: app.T("Bản đồ", "Map"), action: { app.goMapExplore() }, badge: 0),
            Item(id: "notifications", icon: { AnyView(NotificationsGlyph(color: $0, filled: $1)) }, label: app.T("Thông báo", "Notifications"), action: { app.goNotifications() }, badge: app.unreadNotifications, badgeCapped: true),
            // Unread count: number of conversations with an unread message
            // — see refreshUnreadMessageCount() (AppState+Data.swift),
            // refreshed on the same 5s poll as unreadNotifications.
            Item(id: "inbox", icon: { AnyView(InboxGlyph(color: $0, filled: $1)) }, label: app.T("Tin nhắn", "Messages"), action: { app.goInbox() }, badge: app.unreadMessages),
            Item(id: "profile", icon: { AnyView(ProfileGlyph(color: $0, filled: $1)) }, label: app.T("Tài khoản", "Account"), action: { app.goProfile() }, badge: 0),
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
    // Dock-drag fix pass (2026-09-27, follow-up B) — the real root cause of
    // "dragging jumps from slot to slot": the highlight used to be driven
    // purely by `activeID`/`activeIndex`, a DISCRETE per-tab identity that
    // only ever changes once `hitTest` crosses into a neighboring item's
    // frame, then springs there via `withAnimation` — nothing here ever
    // read the finger's actual continuous x position. `dragIndexFloat` is
    // that continuous position instead, in "index space" (0 = Home's
    // center, 1 = Map's, ...), updated on every `onChanged` with NO
    // animation wrapper so it tracks the finger with zero lag, including
    // the space BETWEEN two icons. `nil` whenever no drag is live, so the
    // body falls back to the discrete `activeIndex` (unchanged for a tap
    // and for `syncActiveToScreen()`'s own resting-state placement).
    @State private var dragIndexFloat: CGFloat?

    // Liquid-glass droplet pass (2026-09-28 follow-up, real-iPhone report) —
    // the drag highlight used to be a single Capsule that only widened
    // ("bulge") as it moved, which on a real device still read as "a plain
    // oval sliding/teleporting," not the intended liquid-glass blob. SwiftUI
    // (this project's deployment target, iOS 17) has no built-in gooey/
    // metaball filter the way an SVG blur+contrast filter gives web (see
    // BottomTabBar.jsx's own goo-layer comment) — `dragAnchorIndex` +
    // `hasMovedEnough` below drive the CLOSEST practical approximation:
    // two overlapping translucent blobs (one pinned at the tab this
    // gesture started from, one following the finger) plus a separate
    // connecting capsule between them that visibly narrows and fades as
    // they pull apart — a stand-in for an elastic "neck," not a literal
    // metaball. `dragAnchorIndex` is captured once, on the FIRST gesture
    // change past the movement threshold, from `activeIndex` as it stood
    // BEFORE this gesture's own hit-testing overwrites `activeID` — i.e.
    // the previously-selected tab, matching "neck stretches back toward
    // the previously selected tab" rather than wherever the finger first
    // touched down.
    @State private var dragAnchorIndex: Int?
    @State private var hasMovedEnough = false
    @State private var gestureStartLocation: CGPoint?

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

    // Continuous "index space" position for a raw touch x — 0 at Home's own
    // center, `items.count - 1` at Account's, fractional in between. Clamped
    // to the two end items' centers (a drag past either edge still reads as
    // that end, matching `hitTest`'s own edge behavior) rather than the raw
    // frame edges, so the capsule's CENTER never overshoots past the first/
    // last icon's own position.
    private func indexFloat(for x: CGFloat, barWidth: CGFloat) -> CGFloat? {
        guard !items.isEmpty, barWidth > 0 else { return nil }
        let tabWidth = barWidth / CGFloat(items.count)
        let raw = x / tabWidth - 0.5
        return min(CGFloat(items.count - 1), max(0, raw))
    }

    private func scrubGesture(barWidth: CGFloat) -> some Gesture {
        // minimumDistance: 0 so this also fires for a plain tap-and-release
        // — a tap that never moves still lands on, and navigates to,
        // whichever tab it started on.
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                isDragging = true
                // Captured on the very first change of a gesture, from
                // `activeIndex` as it stood BEFORE this line's own
                // hit-testing can move it — the tab this gesture started
                // from, i.e. the droplet's anchor (see that state's own
                // doc comment above).
                if gestureStartLocation == nil {
                    gestureStartLocation = value.startLocation
                    dragAnchorIndex = activeIndex
                }
                let id = hitTest(value.location.x)
                if id != activeID { activeID = id }
                // No `withAnimation` here, deliberately — this needs to
                // track the finger with zero lag, the actual fix for
                // "jumps from slot to slot." Reduce Motion still gets the
                // continuous tracking (it isn't the bouncy spring that
                // setting objects to); only the settle below drops its glide.
                dragIndexFloat = indexFloat(for: value.location.x, barWidth: barWidth)
                // Below this much travel, a press still reads as a plain
                // tap-in-progress — keeps a real tap instant/blob-free (a
                // plain tap needs no gooey animation) without a separate
                // tap/drag branch in the commit logic above. Reduce Motion
                // never engages the two-blob approximation at all (see the
                // rendering branch in `body`), so this only matters when
                // motion isn't reduced.
                if !reduceMotion, !hasMovedEnough, let start = gestureStartLocation {
                    let dx = value.location.x - start.x
                    let dy = value.location.y - start.y
                    if dx * dx + dy * dy > 16 { hasMovedEnough = true }
                }
            }
            .onEnded { value in
                let id = hitTest(value.location.x)
                let settle = {
                    activeID = id
                    dragIndexFloat = nil
                    // Resets INSIDE the same animation block as the settle
                    // above so the two-blob approximation crossfades into
                    // the single settled highlight rather than cutting
                    // instantly.
                    hasMovedEnough = false
                    dragAnchorIndex = nil
                    gestureStartLocation = nil
                }
                if reduceMotion { settle() } else {
                    withAnimation(.interpolatingSpring(stiffness: 260, damping: 22)) { settle() }
                }
                // BUG 1 fix: leave the highlight exactly where the drag
                // landed instead of clearing it to nil — it stays lit on
                // the tab just navigated to. `isDragging = false` hands
                // ownership back to syncActiveToScreen(), which is a no-op
                // here since `activeID` already matches (or will match, the
                // moment `app.screen` catches up via its own onChange).
                isDragging = false
                if let id, let item = items.first(where: { $0.id == id }) { item.action() }
            }
    }

    // BUG (2026-09-25 iOS fix pass) — root cause of "indicator misaligned
    // after the 300->340 width change / when + joins the row": the
    // highlight used to be drawn from `itemFrames[activeID]`, resolved by
    // `resolveFrames(_:_:)` below, which only re-runs `onAppear` and
    // `onChange(of: proxy.size)` on a SEPARATE `backgroundPreferenceValue`
    // GeometryReader — a real caching layer with its own update timing,
    // one layout pass removed from this body's own render. Every item is
    // already an equal `.frame(maxWidth: .infinity)` share of this bar (see
    // the HStack below, spacing 0), so "item i's box" is always exactly the
    // i-th `1/items.count` slice of whatever this view's OWN live width is
    // — expressed here as a plain fraction of `geo.size.width`, resolved
    // fresh on every single render this GeometryReader participates in,
    // with no cache to go stale: identical in spirit to
    // `src/screens/BottomTabBar.jsx`'s own CSS-percentage fix (same
    // "equal-flex slice of the live container," ported to SwiftUI's own
    // layout system rather than copying the DOM/CSS mechanism 1:1).
    // `itemFrames`/`resolveFrames` are kept ONLY for `hitTest` below (the
    // scrub-drag's touch→tab mapping), which genuinely needs real anchor
    // frames — SwiftUI already reports `DragGesture(coordinateSpace: .local)`
    // touch points in this view's own pre-transform layout space, so that
    // path was never affected by the ancestor `DockRow.scaleEffect` bug
    // class the highlight itself was exposed to.
    private var activeIndex: Int? {
        guard let activeID else { return nil }
        return items.firstIndex(where: { $0.id == activeID })
    }

    // Stage 3 (2026-09-27 nav/discovery pass) — extracted out of `body`'s
    // own `ForEach` (a real, confirmed Swift type-checker timeout when
    // this whole modifier chain sat inline there: "unable to type-check
    // this expression in reasonable time"). The on-dock text label is
    // gone; the icon (now filled/outline per selection) is the only
    // visible content, at a 44pt+ tap target via the frame below.
    // `accessibilityLabel` keeps VoiceOver announcing the real
    // destination name.
    @ViewBuilder
    private func tabItem(_ item: Item) -> some View {
        let isActive = activeID == item.id
        let badgeText: String = (item.badgeCapped && item.badge > 9) ? "9+" : String(item.badge)
        ZStack(alignment: .topTrailing) {
            item.icon(app.palette.ink, isActive)
                .frame(width: iconSize, height: iconSize)
                .opacity(isActive ? 1 : 0.72)
            if item.badge > 0 {
                Text(badgeText)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 14, minHeight: 14)
                    .background(BanbeTheme.alert, in: Capsule())
                    .offset(x: 7, y: -5)
            }
        }
        .frame(minWidth: 44, maxWidth: .infinity, minHeight: barHeight)
        .accessibilityIdentifier("tab.\(item.id)")
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        .anchorPreference(key: TabItemFrameKey.self, value: .bounds) { [item.id: $0] }
    }

    var body: some View {
        GeometryReader { geo in
        ZStack(alignment: .leading) {
            // Soft, blurred, darker highlight blob. Dock-drag fix pass
            // (2026-09-27, follow-up B) — `dragIndexFloat` (continuous,
            // set live by `scrubGesture`) takes over from the discrete
            // `activeIndex` the instant a drag is live, so this now
            // interpolates center, width AND corner curvature continuously
            // between two icons instead of snapping between fixed slots:
            // at its resting width exactly centered on an icon, stretched
            // (soft "droplet" bulge) exactly halfway between two, easing
            // between those two extremes as the raw x position moves.
            // Position/width are still a live fraction of `geo.size.width`
            // (see this view's own now-legacy `activeIndex` doc comment
            // above) — never itemFrames — so this stays correct through the
            // "+" button appearing/shrinking the row and DockRow's own
            // collapse/expand `scaleEffect`.
            if hasMovedEnough, !reduceMotion, let anchorIdx = dragAnchorIndex, let indexFloat = dragIndexFloat {
                // Two-blob droplet approximation (see `dragAnchorIndex`'s
                // own doc comment for why this isn't a literal metaball —
                // SwiftUI/iOS 17 has no built-in gooey filter). One blob
                // stays pinned at the tab this gesture started from, one
                // follows the finger; a separate connecting capsule between
                // their centers narrows and fades as they pull apart,
                // standing in for an elastic neck that "detaches" once the
                // drag has traveled far enough — an emergent-looking effect
                // achieved here by explicit distance-based interpolation,
                // not a real filter.
                let count = max(items.count, 1)
                let tabWidth = geo.size.width / CGFloat(count)
                let anchorX = tabWidth * (CGFloat(anchorIdx) + 0.5)
                let clampedIndexFloat = min(CGFloat(count - 1), max(0, indexFloat))
                let dragX = tabWidth * (clampedIndexFloat + 0.5)
                let blobWidth = tabWidth * 0.62
                let blobHeight = barHeight - 14
                let distance = abs(dragX - anchorX)
                // Beyond ~1.6 slot-widths of travel the neck has fully
                // "detached" — connects across roughly one dock slot,
                // matching the reference's "short" elastic neck rather than
                // staying connected across the whole bar.
                let maxConnect = tabWidth * 1.6
                let neckProgress = max(0, 1 - distance / maxConnect)
                let neckHeight = blobHeight * (0.1 + 0.55 * neckProgress)
                let neckOpacity = 0.12 * neckProgress

                ZStack {
                    Capsule()
                        .fill(app.palette.ink.opacity(neckOpacity))
                        .frame(width: distance + blobWidth * 0.5, height: neckHeight)
                        .position(x: (anchorX + dragX) / 2, y: barHeight / 2)
                    Capsule()
                        .fill(app.palette.ink.opacity(0.12))
                        .frame(width: blobWidth, height: blobHeight)
                        .position(x: anchorX, y: barHeight / 2)
                    Capsule()
                        .fill(app.palette.ink.opacity(0.12))
                        .frame(width: blobWidth, height: blobHeight)
                        .position(x: dragX, y: barHeight / 2)
                }
                .blur(radius: 0.6)
                .allowsHitTesting(false)
            } else if let indexFloat = dragIndexFloat ?? activeIndex.map(CGFloat.init) {
                let count = max(items.count, 1)
                let tabWidth = geo.size.width / CGFloat(count)
                // 0 exactly on an icon's own center, 0.5 exactly between
                // two icons — the point of maximum stretch. This branch now
                // covers only: a plain tap (never crosses the movement
                // threshold above), the at-rest/settled state, and the
                // entire Reduce Motion path — the two-blob approximation
                // above never engages for any of those, per this ticket's
                // own "no gooey animation for a simple tap" / Reduce Motion
                // fallback instructions.
                let fracFromCenter = abs(indexFloat - indexFloat.rounded())
                let bulge = 1 + 0.5 * sin(min(1, fracFromCenter / 0.5) * (.pi / 2))
                let width = tabWidth * bulge
                let clampedIndexFloat = min(CGFloat(count - 1), max(0, indexFloat))
                let center = tabWidth * (clampedIndexFloat + 0.5)
                let x = min(geo.size.width - width / 2, max(width / 2, center))
                // A very slight extra corner rounding at the bulge's peak
                // reads as more "liquid" than a fixed capsule radius that
                // just stretches uniformly.
                Capsule()
                    .fill(app.palette.ink.opacity(0.12))
                    .frame(width: width, height: (barHeight - 10) * (1 + 0.03 * (bulge - 1)))
                    .position(x: x, y: barHeight / 2)
                    .blur(radius: 0.5)
                    .allowsHitTesting(false)
            }

            HStack(spacing: 0) {
                ForEach(items) { item in
                    tabItem(item)
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(scrubGesture(barWidth: geo.size.width))
        }
        .frame(height: barHeight)
        // Task 1b follow-up: widened from 320 (fit for 4 icons) to fit the
        // new Home tab without cramping the existing four — matches the
        // web bar's own bump. Task 5: widened again, to `Self.barWidth`,
        // as part of the flatter/more-elongated pill shape.
        .frame(maxWidth: Self.barWidth)
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
            // Stage 3 (2026-09-27 nav/discovery pass) — honors Reduce
            // Motion: the spring glide becomes a plain, near-instant snap.
            withAnimation(reduceMotion ? .linear(duration: 0.01) : .interpolatingSpring(stiffness: 260, damping: 22)) {
                syncActiveToScreen()
            }
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

/// Refresh-indicator fix pass (2026-09-27, follow-up A) — the same
/// dominant outline coordinates each Glyph below already draws, exposed
/// standalone (keyed by `Screen`, not by an icon id) so
/// `RootRefreshIndicator` can `.trim()` a travel segment around the REAL
/// icon shape instead of a generic circle. A fresh `Path` built here
/// rather than reaching into each private Glyph struct, so those stay
/// untouched.
enum RootTabOutline {
    static func path(for screen: Screen, size: CGFloat) -> Path {
        let s = size / 24
        switch screen {
        case .home:
            return Path { p in
                p.move(to: CGPoint(x: 6 * s, y: 19.5 * s))
                p.addLine(to: CGPoint(x: 6 * s, y: 10 * s))
                p.addLine(to: CGPoint(x: 4 * s, y: 11.5 * s))
                p.addLine(to: CGPoint(x: 12 * s, y: 4 * s))
                p.addLine(to: CGPoint(x: 20 * s, y: 11.5 * s))
                p.addLine(to: CGPoint(x: 18 * s, y: 10 * s))
                p.addLine(to: CGPoint(x: 18 * s, y: 19.5 * s))
                p.closeSubpath()
            }
        case .mapExplore:
            return Path { p in
                p.move(to: CGPoint(x: 12 * s, y: 3 * s))
                p.addCurve(to: CGPoint(x: 6 * s, y: 9.1 * s), control1: CGPoint(x: 8.7 * s, y: 3 * s), control2: CGPoint(x: 6 * s, y: 5.6 * s))
                p.addCurve(to: CGPoint(x: 12 * s, y: 21 * s), control1: CGPoint(x: 6 * s, y: 13.4 * s), control2: CGPoint(x: 12 * s, y: 21 * s))
                p.addCurve(to: CGPoint(x: 18 * s, y: 9.1 * s), control1: CGPoint(x: 12 * s, y: 21 * s), control2: CGPoint(x: 18 * s, y: 13.4 * s))
                p.addCurve(to: CGPoint(x: 12 * s, y: 3 * s), control1: CGPoint(x: 18 * s, y: 5.6 * s), control2: CGPoint(x: 15.3 * s, y: 3 * s))
                p.closeSubpath()
            }
        case .notifications:
            return Path { p in
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
        case .inbox:
            // Refresh-indicator fix pass (2026-09-27, follow-up B) — a bare
            // rounded rectangle reads as a generic box, not the dock's own
            // envelope; the real glyph (InboxGlyph) is the rect PLUS its V
            // flap, so this now traces both in one Path (real coordinates,
            // matching InboxGlyph's `position(x:12*s,y:12.5*s)` frame).
            var path = RoundedRectangle(cornerRadius: 2.4 * s, style: .continuous)
                .path(in: CGRect(x: 4.5 * s, y: 7 * s, width: 15 * s, height: 11 * s))
            path.move(to: CGPoint(x: 5.5 * s, y: 8.2 * s))
            path.addLine(to: CGPoint(x: 12 * s, y: 13.5 * s))
            path.addLine(to: CGPoint(x: 18.5 * s, y: 8.2 * s))
            return path
        default: // .profile (this function is only ever called for the five root tabs) — same fix:
            // a bare circle reads as a dot/badge, not a person; the real glyph
            // (ProfileGlyph) is the head circle PLUS the shoulders curve, so
            // both are traced here too.
            var path = Circle().path(in: CGRect(x: (12 - 3.8) * s, y: (8 - 3.8) * s, width: 7.6 * s, height: 7.6 * s))
            path.move(to: CGPoint(x: 5 * s, y: 19.2 * s))
            path.addCurve(to: CGPoint(x: 19 * s, y: 19.2 * s), control1: CGPoint(x: 6.3 * s, y: 15.3 * s), control2: CGPoint(x: 17.7 * s, y: 15.3 * s))
            return path
        }
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
// Stage 3 (2026-09-27 nav/discovery pass) — each glyph now takes `filled`
// (selected) vs outline (unselected), matching SF Symbol's own filled/
// outline convention. NotificationsGlyph used to be a solid shape
// UNCONDITIONALLY (no outline variant existed), which is the actual "bell
// stays filled even when Notifications isn't the active tab" bug this
// fixes.
private struct MapGlyph: View {
    let color: Color
    var filled: Bool = false
    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 24
            ZStack {
                let outline = Path { p in
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
                if filled { outline.fill(color) }
                outline.stroke(color, style: StrokeStyle(lineWidth: 2.4 * s, lineCap: .round, lineJoin: .round))
                Circle().fill(filled ? Color(uiColor: .systemBackground) : color).frame(width: 4.6 * s, height: 4.6 * s).position(x: 12 * s, y: 9.3 * s)
            }
        }
    }
}

private struct NotificationsGlyph: View {
    let color: Color
    var filled: Bool = false
    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 24
            let bell = Path { p in
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
            ZStack {
                if filled { bell.fill(color) } else { bell.stroke(color, style: StrokeStyle(lineWidth: 2.2 * s, lineJoin: .round)) }
                Path { p in p.addArc(center: CGPoint(x: 12 * s, y: 18.6 * s), radius: 2.4 * s, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false) }
                    .stroke(color, style: StrokeStyle(lineWidth: 2 * s, lineCap: .round))
            }
        }
    }
}

private struct InboxGlyph: View {
    let color: Color
    var filled: Bool = false
    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 24
            ZStack {
                let rect = RoundedRectangle(cornerRadius: 2.4 * s, style: .continuous)
                if filled {
                    rect.fill(color).frame(width: 15 * s, height: 11 * s).position(x: 12 * s, y: 12.5 * s)
                } else {
                    rect.stroke(color, lineWidth: 2.4 * s).frame(width: 15 * s, height: 11 * s).position(x: 12 * s, y: 12.5 * s)
                }
                Path { p in
                    p.move(to: CGPoint(x: 5.5 * s, y: 8.2 * s))
                    p.addLine(to: CGPoint(x: 12 * s, y: 13.5 * s))
                    p.addLine(to: CGPoint(x: 18.5 * s, y: 8.2 * s))
                }
                .stroke(filled ? Color(uiColor: .systemBackground) : color, style: StrokeStyle(lineWidth: 2.2 * s, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

private struct ProfileGlyph: View {
    let color: Color
    var filled: Bool = false
    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 24
            ZStack {
                if filled {
                    Circle().fill(color).frame(width: 7.6 * s, height: 7.6 * s).position(x: 12 * s, y: 8 * s)
                } else {
                    Circle().stroke(color, lineWidth: 2.6 * s).frame(width: 7.6 * s, height: 7.6 * s).position(x: 12 * s, y: 8 * s)
                }
                Path { p in
                    p.move(to: CGPoint(x: 5 * s, y: 19.2 * s))
                    p.addCurve(to: CGPoint(x: 19 * s, y: 19.2 * s), control1: CGPoint(x: 6.3 * s, y: 15.3 * s), control2: CGPoint(x: 17.7 * s, y: 15.3 * s))
                    p.addLine(to: CGPoint(x: 19 * s, y: 21 * s))
                    p.addLine(to: CGPoint(x: 5 * s, y: 21 * s))
                    p.closeSubpath()
                }
                .fill(filled ? color : Color.clear)
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
    var filled: Bool = false
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
                let house = Path { p in
                    p.move(to: CGPoint(x: 6 * s, y: 10 * s))
                    p.addLine(to: CGPoint(x: 6 * s, y: 19.5 * s))
                    p.addLine(to: CGPoint(x: 18 * s, y: 19.5 * s))
                    p.addLine(to: CGPoint(x: 18 * s, y: 10 * s))
                }
                if filled { house.fill(color) }
                house.stroke(color, style: StrokeStyle(lineWidth: 2.4 * s, lineJoin: .round))
            }
        }
    }
}
