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
        var badgeCap: Int = 9
    }

    // FIX PASS (2026-09-30) — top of the "child row -> group card -> tab ->
    // dock icon" chain (see Lib/Badges.swift's own doc comment for the
    // dedup/permission rules): real admin-moderation + host-duty counts,
    // never a fabricated one. Home/Map/the create "+" deliberately stay
    // `badge: 0` (hidden) — no real underlying actionable source for any.
    private var accountBadge: Int {
        AccountBadges.accountDockBadge(
            accountType: app.accountType,
            organizerMode: app.organizerMode,
            pendingEventsCount: app.pendingEventsCount,
            verificationsCount: app.verifications.count,
            refundQueue: app.refundQueue,
            paymentBookings: app.paymentBookings,
            myRefunds: app.myRefunds,
            holdingCount: app.organizerHoldingSummary?.count ?? 0,
            submittedEventsCount: app.myPendingEvents.count + app.myNeedsFixEvents.count
        )
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
            Item(id: "profile", icon: { AnyView(ProfileGlyph(color: $0, filled: $1)) }, label: app.T("Tài khoản", "Account"), action: { app.goProfile() }, badge: accountBadge, badgeCapped: true, badgeCap: 99),
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

    // Motion refinement pass (2026-09-28 follow-up #3, "improve the motion"
    // ticket) — `dragIndexFloat` above is still the RAW, zero-lag truth (it
    // has to stay that way: `hitTest`/`activeID`/the eventual `item.action()`
    // on release all need the finger's real position with no smoothing
    // layered in). What was missing is a RENDERED position that's allowed to
    // lag behind that truth: previously the glass shape's `.position()` read
    // `selectionIndexFloat` (== `dragIndexFloat` while dragging) directly, so
    // every `onChanged` frame moved the shape to the exact raw value with no
    // `withAnimation` — one bare assignment per touch sample, which reads as
    // "teleports frame to frame" rather than "glides," because there is
    // nothing IN BETWEEN two touch samples for it to visibly travel through.
    // `renderIndexFloat` is that in-between: a separate `@State` this view
    // actually draws from, retargeted with `withAnimation(.spring(...))`
    // every time `selectionIndexFloat` (the target — raw drag position, or
    // the resting tab once a drag ends) changes, via the `.onChange` below.
    // SwiftUI's spring animations are interruptible — retargeting one that's
    // still in flight preserves its current velocity rather than restarting
    // from rest — so a fast continuous stream of retargets (many per second
    // while dragging) reads as one continuously-chasing motion, not a series
    // of separate springs each snapping and stopping. This is what makes the
    // shape visibly travel toward the finger instead of jumping to it, while
    // `dragIndexFloat`/`activeID`/hit-testing all still update immediately.
    @State private var renderIndexFloat: CGFloat?
    // Directional stretch cue (same pass) — `dragStartX` is the touch x the
    // CURRENT drag began at (nil whenever no drag is live); the first
    // `onChanged` sample that has moved meaningfully away from it decides a
    // direction (leading vs trailing) once, drives `stretchAnchor`, and fires
    // one quick scale-up/settle pair via `withAnimation` on `stretchScaleX`.
    // See the real-API verification note above `body` for why this is an
    // ordinary `.scaleEffect` layered on the real glass view rather than a
    // native "stretch" primitive — `glassEffect`'s SDK surface has no such
    // thing (re-verified this pass via the same `strings`-on-SwiftUICore
    // approach the prior pass used; only hit was an unrelated `.stretch`
    // layout/alignment case, not anything glass- or drag-related).
    @State private var dragStartX: CGFloat?
    @State private var stretchScaleX: CGFloat = 1
    @State private var pressScale: CGFloat = 1
    @GestureState private var touchActive = false
    @State private var stretchAnchor: UnitPoint = .center

    // Real Liquid Glass pass (2026-09-28 follow-up #2, real-iPhone report) —
    // the hand-rolled "two overlapping translucent blobs + a fading
    // connector" stand-in from the previous pass is GONE. Root cause of
    // that pass's own reported bug ("dark/opaque patch left behind at the
    // ORIGINAL tab during drag"): the anchor blob (pinned at
    // `dragAnchorIndex`) was drawn at a constant `opacity(0.12)` for the
    // ENTIRE drag, with only the connecting neck's opacity fading as the
    // finger pulled away — so once the neck had visually "detached" you
    // were left with TWO highlights on screen, the live one under the
    // finger (correct) and a stuck one back at the origin tab (the bug).
    //
    // Replaced with exactly ONE view: a single `.glassEffect(_:in:)` capsule
    // (real SwiftUI API — see below) whose `.position()` is driven straight
    // off `selectionIndexFloat`, continuously during a drag and by a spring
    // at settle, so there is structurally nothing left over anywhere except
    // wherever that one shape currently sits. No anchor state, no neck, no
    // "has this drag moved far enough to show the second blob" bookkeeping
    // — `dragAnchorIndex`/`hasMovedEnough`/`gestureStartLocation` (all
    // solely in service of the old two-blob approximation) are deleted, not
    // just unused.
    //
    // API verification (this machine, this SDK — not assumed from training
    // data): Xcode 27 / iPhoneOS27.0 SDK. `strings` over
    // .../XcodeDefault.xctoolchain/usr/lib/swift/iphoneos/prebuilt-modules/
    // 27.0/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftmodule (SwiftUI
    // re-exports SwiftUICore) resolves real, non-fabricated symbols:
    // `glassEffect`, `glassEffectID`, `glassEffectUnion`,
    // `glassEffectTransition`, `GlassEffectContainer`, `Glass.regular`,
    // `Glass.interactive(_:)` — the actual documented iOS 26 Liquid Glass
    // View-modifier API, not invented names. This project's deployment
    // target is still iOS 17 (apps/ios/project.yml), so every use below is
    // gated `if #available(iOS 26.0, *)`; below that (or with Reduce Motion
    // on) it falls back to a plain translucent capsule — same
    // `dockHighlight`-equivalent styling the pre-glass code already used,
    // not a crash and not a second homemade effect.

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

    /// Touch x -> tab, from the bar's OWN live width (every item is an equal
    /// 1/count slice). Replaces the old lookup through `itemFrames`, a cached
    /// anchor-preference snapshot that could be empty/stale — which made a
    /// tap resolve to no tab at all ("works only intermittently"). Positions
    /// past either end still resolve to that end's tab.
    private func hitTest(_ x: CGFloat, barWidth: CGFloat) -> String? {
        guard !items.isEmpty, barWidth > 0 else { return nil }
        let slice = barWidth / CGFloat(items.count)
        let i = min(items.count - 1, max(0, Int(x / slice)))
        return items[i].id
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

    /// Photos-style scrub (iOS 26): touching down lifts/enlarges the glass
    /// pill, which then follows the finger across the tabs (stretching a
    /// little with swipe speed) and settles on the nearest tab on release.
    /// `minimumDistance: 0` keeps a plain tap working: it lands on, and
    /// navigates to, whichever tab it started on.
    private func scrubGesture(barWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .updating($touchActive) { _, state, _ in state = true }
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragStartX = value.location.x
                    if !reduceMotion {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.62)) { pressScale = 1.18 }
                    }
                }
                let id = hitTest(value.location.x, barWidth: barWidth)
                if id != activeID { activeID = id }
                dragIndexFloat = indexFloat(for: value.location.x, barWidth: barWidth)
                if !reduceMotion {
                    // Water-droplet stretch: the faster the swipe, the longer
                    // (and, in the lens below, slimmer) the pill gets.
                    withAnimation(.interactiveSpring(response: 0.16, dampingFraction: 0.7)) {
                        stretchScaleX = 1 + min(1.2, abs(value.velocity.width) / 1200)
                    }
                }
            }
            .onEnded { value in
                let id = hitTest(value.location.x, barWidth: barWidth)
                activeID = id
                finishTouch()
                if let id, let item = items.first(where: { $0.id == id }) {
                    // One selection tick, only when this lands on a DIFFERENT
                    // tab than the screen already showing.
                    if tabID(for: app.screen) != id { Haptics.selection() }
                    item.action()
                }
            }
    }

    private func tabID(for screen: Screen) -> String? {
        switch screen {
        case .home: return "home"
        case .mapExplore: return "map"
        case .notifications: return "notifications"
        case .inbox: return "inbox"
        case .profile: return "profile"
        default: return nil
        }
    }

    /// Ends a touch: hands the highlight back to the tab just chosen and
    /// springs the pill back to rest size. Also run when the system cancels
    /// the gesture (no `onEnded`), so `isDragging` can never get stuck.
    private func finishTouch() {
        dragIndexFloat = nil
        isDragging = false
        dragStartX = nil
        stretchAnchor = .center
        withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
            stretchScaleX = 1
            pressScale = 1
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

    // Continuous "index space" TARGET position for the single glass/
    // highlight shape: the live drag position while a drag is in flight,
    // otherwise wherever `activeIndex` currently rests (a tap, a settle, or
    // a screen change via `syncActiveToScreen()`). Exactly one source of
    // truth for "where should the shape end up" — see this file's real-
    // Liquid-Glass pass doc comment above `dragIndexFloat` for why that
    // matters (it's the fix for the old two-blob approximation's leftover-
    // highlight bug). Motion refinement pass: this is a TARGET now, not what
    // gets rendered directly — `renderIndexFloat` (see its own doc comment
    // above `dragStartX`) is what the shape actually draws at, chasing this
    // value via a spring instead of jumping straight to it.
    private var selectionIndexFloat: CGFloat? {
        dragIndexFloat ?? activeIndex.map(CGFloat.init)
    }

    // Stage 3 (2026-09-27 nav/discovery pass) — extracted out of `body`'s
    // own `ForEach` (a real, confirmed Swift type-checker timeout when
    // this whole modifier chain sat inline there: "unable to type-check
    // this expression in reasonable time"). The on-dock text label is
    // gone; the icon (now filled/outline per selection) is the only
    // visible content, at a 44pt+ tap target via the frame below.
    // `accessibilityLabel` keeps VoiceOver announcing the real
    // destination name.
    /// 1 when the glass pill is exactly over this item, fading to 0 one tab
    /// away.
    private func iconProximity(_ item: Item) -> CGFloat {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return 0 }
        let pill = renderIndexFloat ?? CGFloat(i)
        return max(0, 1 - abs(CGFloat(i) - pill))
    }

    @ViewBuilder
    private func tabItem(_ item: Item) -> some View {
        let isActive = activeID == item.id
        let badgeText: String = item.badgeCapped ? AccountBadges.format(item.badge, cap: item.badgeCap) : String(item.badge)
        ZStack(alignment: .topTrailing) {
            item.icon(app.palette.ink, isActive)
                .frame(width: iconSize, height: iconSize)
                .opacity(isActive ? 1 : 0.72)
                // Icon under the lifted pill swells with it (Photos-style).
                .scaleEffect(1 + (pressScale - 1) * 1.9 * iconProximity(item))
            if item.badge > 0 {
                Text(badgeText)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 14, minHeight: 14)
                    .background(BanbeTheme.alert, in: Capsule())
                    .offset(x: 7, y: -5)
                    .accessibilityIdentifier("tab.\(item.id).badge")
                    .accessibilityLabel(app.T("\(item.badge) mục mới", "\(item.badge) new item(s)"))
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
            // ONE selection shape, period — see the real-Liquid-Glass pass
            // doc comment above `dragIndexFloat` for the bug this structure
            // fixes (the old two-blob approximation's stuck origin-tab
            // highlight). Position is now `renderIndexFloat` — the RENDERED,
            // spring-chasing value (see its own doc comment above), not the
            // raw `selectionIndexFloat` target directly — so the shape
            // visibly travels toward the finger/target instead of jumping to
            // it, while still ultimately settling on the exact same resting
            // position `selectionIndexFloat` would land on. Still a live
            // fraction of `geo.size.width` (never `itemFrames`), so this
            // stays correct through the "+" button appearing/shrinking the
            // row and DockRow's own collapse/expand `scaleEffect`.
            // Selection lens — behind the icons. (Drawn above them the glass
            // is near-opaque on the light theme and hides the icon.) It still
            // grows past the bar's top/bottom while a finger is down, and the
            // icon over it swells with it.
            if let indexFloat = renderIndexFloat {
                let count = max(items.count, 1)
                let tabWidth = geo.size.width / CGFloat(count)
                let clampedIndexFloat = min(CGFloat(count - 1), max(0, indexFloat))
                let center = tabWidth * (clampedIndexFloat + 0.5)
                let shapeWidth = tabWidth * 0.82
                let shapeHeight = barHeight - 14
                let x = min(geo.size.width - shapeWidth / 2, max(shapeWidth / 2, center))

                if #available(iOS 26.0, *), !reduceMotion {
                    // Real Apple Liquid Glass — `Glass.regular.interactive()`
                    // (an interactive glass responds to touch with its own
                    // system-drawn highlight/press feedback) applied via
                    // `.glassEffect(_:in:)`, both real SwiftUICore API
                    // confirmed present in this SDK (see doc comment above).
                    // `GlassEffectContainer` is Apple's documented wrapper
                    // for correct compositing/blending of glass content —
                    // used here even though there's only one shape, per
                    // Apple's own guidance to always host glassEffect
                    // content inside one.
                    //
                    // Honest limitation (per this ticket's own instruction
                    // to state one rather than fake it): this is a single
                    // shape gliding continuously between tabs, not a
                    // droplet/elastic-neck morph. Real `glassEffect`'s fluid
                    // shape-blending (via `glassEffectID`/
                    // `glassEffectUnion`) is designed for MULTIPLE
                    // concurrently-visible glass shapes merging into and
                    // separating from each other — it isn't the right tool
                    // for "one shape sliding along a track," so no such
                    // merge/split geometry is attempted here. What IS real:
                    // genuine system glass material (specular highlight,
                    // refraction, `.interactive()` touch response) instead
                    // of a hand-tinted, blurred capsule standing in for it.
                    // Directional stretch cue (this pass) — `.scaleEffect`
                    // applied ON TOP of the real `glassEffect`-decorated
                    // view below, not a separate shape drawn instead of or
                    // over it: an ordinary SwiftUI transform of the actual
                    // glass view, since real `glassEffect`'s API surface has
                    // no native directional-stretch/morph primitive (see the
                    // `strings`-verification note above `dragStartX`). Order
                    // matters: `.scaleEffect` sits BEFORE `.position()` so it
                    // scales the shape in its own local space (about
                    // `stretchAnchor`) rather than distorting where its
                    // center lands on the bar.
                    GlassEffectContainer {
                        Capsule()
                            .fill(.clear)
                            .frame(width: shapeWidth, height: shapeHeight)
                            .glassEffect(.regular.interactive(), in: Capsule())
                            .scaleEffect(x: stretchScaleX * (1 + (pressScale - 1) * 1.8), y: (1 + (pressScale - 1) * 3.2) / (1 + (stretchScaleX - 1) * 1.6), anchor: .center)
                            .position(x: x, y: barHeight / 2)
                    }
                    .allowsHitTesting(false)
                } else {
                    // Fallback for Reduce Motion and for any OS below the
                    // Liquid Glass minimum (deployment target here is still
                    // iOS 17) — a plain translucent capsule, the same
                    // `dockHighlight`-equivalent styling this bar used
                    // before any of the glass/droplet passes. No bulge, no
                    // blur-as-goo trick: a simple, non-animated-feeling
                    // highlight that never crashes and never renders
                    // nothing.
                    Capsule()
                        .fill(app.palette.ink.opacity(0.12))
                        .frame(width: shapeWidth, height: shapeHeight)
                        .position(x: x, y: barHeight / 2)
                        .allowsHitTesting(false)
                }
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
        .background {
            if #available(iOS 26.0, *), !reduceMotion {
                GlassEffectContainer {
                    Capsule()
                        .fill(.clear)
                        .glassEffect(.regular, in: Capsule())
                }
            } else {
                Capsule().fill(.regularMaterial)
            }
        }
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
        .onAppear {
            syncActiveToScreen()
            renderIndexFloat = selectionIndexFloat
        }
        .onChange(of: app.screen) { _, _ in
            // Stage 3 (2026-09-27 nav/discovery pass) — plain assignment
            // now (no `withAnimation` here): the motion-refinement pass
            // below centralizes ALL of the shape's glide/settle animation
            // in the single `.onChange(of: selectionIndexFloat)` handler,
            // so `activeID` changing here just needs to change; whatever
            // that does to `selectionIndexFloat` is picked up there,
            // exactly once, instead of two overlapping animation
            // transactions fighting over the same view.
            syncActiveToScreen()
        }
        // Motion refinement pass (2026-09-28 follow-up #3) — the ONE place
        // that actually animates `renderIndexFloat` (see its own doc
        // comment above `dragStartX`): fires on every raw target change,
        // whether that's a continuous stream of drag samples or a single
        // discrete jump from a tap/screen-change/settle. Honors Reduce
        // Motion by assigning directly with no animation at all, same as
        // this file's other reduceMotion branches.
        .onChange(of: selectionIndexFloat) { _, newValue in
            guard let newValue else { renderIndexFloat = nil; return }
            if reduceMotion {
                renderIndexFloat = newValue
            } else if isDragging {
                // Tight tracking while the finger is down.
                withAnimation(.interactiveSpring(response: 0.12, dampingFraction: 0.85)) {
                    renderIndexFloat = newValue
                }
            } else {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    renderIndexFloat = newValue
                }
            }
        }
        // System-cancelled touch (no `onEnded`): reset so nothing sticks.
        .onChange(of: touchActive) { _, active in
            if !active && isDragging {
                finishTouch()
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
        // BUG FIX (dock-jump-on-tray-open pass) — this used to be
        // `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)`,
        // which made DockRow greedily fill however much height its
        // container PROPOSES and then self-align `.bottom` within that
        // proposed rectangle. `BottomTabBarOverlay.setDockCreateTrayOpen`
        // grows the hosting window's own frame from a small dock band to
        // full-screen while the tray is open — a real change in the height
        // proposed to this view — and `.bottom`-aligning within a rectangle
        // whose HEIGHT just changed is exactly what visibly shifted the
        // dock upward (see BottomTabBarOverlayRoot's own ZStack below for
        // the other half of this fix: `alignment: .bottom` there anchors
        // DockRow to the ZStack's/window's bottom edge directly instead).
        // Only `maxWidth: .infinity` is kept, so DockRow still spans the
        // window's full width for horizontal centering — height is now
        // purely DockRow's own intrinsic size, never a proposed fill.
        .frame(maxWidth: .infinity)
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
