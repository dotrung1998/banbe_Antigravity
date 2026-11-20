import SwiftUI
import UIKit

// Home from the v5 prototype (note 80), shown with the Simple Shell on Going out. Web twin:
// src/components/home/HomeShellV5.jsx. A pinned paper app bar (wordmark, the area chip as its middle, search / Map /
// quick settings, and the tabs as its second row) sits above one dark photo hero that holds the date kicker and the
// snap card rail; below it come Browse (types with counts + Find a type) and By type (one photo row per type).
// Pure views over lists HomeView already builds: no fetching and no filters of its own.

/// The goer tabs of the hero. The Hosting tab is separate (`HomeHeroSection.hosting`): it is the host view of `app.homeView`.
enum HomeHeroTab: String, CaseIterable {
    /// `all` = every open event, any type and date, soonest first (no For You ranking, no time window). Order = the tab row.
    case foryou, tonight, weekend, all
    var vi: String {
        switch self { case .foryou: "Dành cho bạn"; case .tonight: "Tối nay"; case .weekend: "Cuối tuần"; case .all: "Tất cả" }
    }
    var en: String {
        switch self { case .foryou: "For You"; case .tonight: "Tonight"; case .weekend: "Weekend"; case .all: "All events" }
    }
    /// The tabs Browse shows (web `SCOPES`): All events is Browse's own "Browse by type" scope there, not a fifth tab.
    static let browseTabs: [HomeHeroTab] = [.foryou, .tonight, .weekend]
}

private enum HeroColor {
    static let night = Color(hex: 0x16140F)
    static let badgeFill = Color(hex: 0xF7F4EC).opacity(0.85)
    static let badgeInk = Color(hex: 0x1B1916)
}

/// The first For You card is the tour's "your picks" target (`tour.home.forYou`).
private struct HeroFirstCardTourTarget: ViewModifier {
    let isFirst: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if isFirst { content.tourTarget("tour.home.forYou") } else { content }
    }
}

/// The band folds to ONE row once the feed is really moving (owner 2026-11-22: "when I scroll down, hide the tabs").
/// The tabs are the hero's own context, so they leave with it — but the view pill that replaces the area chip in the
/// middle always names the open view and lists the others, Hosting (the separate host view) included, plus the area, so
/// switching stays one tap away. Hysteresis: folds past 72 pt, unfolds only back at the very top, so it never flaps
/// mid-scroll. Web twin: `compact` in HomeShellV5.jsx (same thresholds).
final class HomeHeaderCompact: ObservableObject {
    static let shared = HomeHeaderCompact()
    @Published private(set) var isCompact = false
    /// Bumped when a scroll gesture begins. The band's native menus (area, view) rebuild on a new identity, which
    /// dismisses them — a SwiftUI `Menu` has no `isPresented` binding, so a menu opened from the pinned band used to
    /// stay on screen while the reader scrolled the feed under it (owner 2026-11-23, the two screenshots). One rebuild
    /// per gesture, on its rising edge, so normal scrolling costs nothing.
    @Published private(set) var menuGeneration = 0
    private var lastOffsetY: CGFloat?
    private var scrolling = false
    private var idleTask: DispatchWorkItem?

    func update(offsetY: CGFloat) {
        noteScroll(offsetY)
        let next = isCompact ? offsetY > 24 : offsetY > 72
        guard next != isCompact else { return }
        if UIAccessibility.isReduceMotionEnabled {
            isCompact = next
        } else {
            withAnimation(.easeInOut(duration: 0.24)) { isCompact = next }
        }
    }

    /// A new scroll gesture (a movement after a quiet moment) closes any band menu; a pause of 200 ms ends the gesture.
    private func noteScroll(_ y: CGFloat) {
        defer { lastOffsetY = y }
        guard let last = lastOffsetY, abs(y - last) > 0.5 else { return }
        if !scrolling {
            scrolling = true
            menuGeneration &+= 1
        }
        idleTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.scrolling = false }
        idleTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: task)
    }

    func reset() {
        guard isCompact else { return }
        if UIAccessibility.isReduceMotionEnabled {
            isCompact = false
        } else {
            withAnimation(.easeInOut(duration: 0.24)) { isCompact = false }
        }
    }
}

/// One 40 pt circle in a screen's top bar (owner 2026-11-18): the same glyph size, fill, hairline and hit target on Home
/// and Browse, so the top-right cluster is one control in one place across the two screens and only fades, never moves,
/// when the screen changes. Search is the clay accent; Map and the settings gear are ink. The gear is the same
/// `gearshape.fill` badge Quick settings wears inside the sheet.
struct HeaderCircleButton: View {
    @EnvironmentObject private var app: AppState
    let system: String
    let label: String
    let id: String
    var accent: Bool = false
    /// Search only: publishes where this circle is, so Search can start its own field right here (the glide entrance).
    var measureFrame: Bool = false
    let action: () -> Void

    var body: some View {
        let button = SwipeSafeButton(action: { Haptics.light(); action() }) {
            Image(systemName: system)
                .font(.app(size: 16, weight: .medium))
                .foregroundStyle(accent ? app.palette.clay : app.palette.ink)
                .frame(width: 40, height: 40)
                .background(app.palette.ink.opacity(0.05), in: Circle())
                .overlay(Circle().strokeBorder(app.palette.divider, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
        return button.background {
            if measureFrame {
                GeometryReader { g in
                    Color.clear
                        .onAppear { app.homeSearchBarFrame = g.frame(in: .global) }
                        .onChange(of: g.frame(in: .global)) { _, f in app.homeSearchBarFrame = f }
                }
            }
        }
    }
}

/// The account's face wherever the app offers a way into Account (the dock, Quick settings, the Account screens): the
/// real profile photo, initials when there is none, and the person glyph for a guest. One clay disc and one paper ring.
struct AccountAvatarView: View {
    @EnvironmentObject private var app: AppState
    var size: CGFloat = 40
    /// The white 1.5 pt edge. The Simple Shell dock turns it off and draws its own 2 pt ring outside the face.
    var ringed: Bool = true

    private var avatarURL: URL? { app.user?.avatarURL.flatMap { URL(string: $0) } }

    /// The disc's own content when there is no usable photo: initials, or the guest glyph. Also the placeholder while
    /// the photo loads and the fallback if it fails (expired URL, offline), so the disc is never blank.
    @ViewBuilder private var fallback: some View {
        if app.isSignedIn {
            Text(BottomTabBar.initials(app.displayName)).font(.app(size: size * 0.33, weight: .bold))
                .foregroundStyle(.white)
        } else {
            Image(systemName: "person").font(.app(size: size * 0.4, weight: .regular))
                .foregroundStyle(.white)
        }
    }

    var body: some View {
        ZStack {
            if let avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .background(app.palette.clay, in: Circle())
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white.opacity(ringed ? 0.9 : 0), lineWidth: 1.5))
    }
}

/// Home's app bar (owner 2026-11-22): ONE paper band, two rows, the same shape at rest and scrolled. It is pinned at the
/// top of the feed and keeps its own room in the hero, so nothing slides under it at rest and the tabs can never be cut
/// by it — the complaint about the floating band. Web twin: the `.bb-home-head*` block in src/index.css.
struct HomeHeroPinnedHeader: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var compact = HomeHeaderCompact.shared
    /// The goer tab; Hosting is the other Home view (`hosting` below), selected the same way it is in the hero.
    @Binding var tab: HomeHeroTab
    let onSearchLocations: () -> Void
    let onAvatar: () -> Void
    @Binding var height: CGFloat

    /// The band at rest: 58 pt of controls + 44 pt of tabs. Folded, only the 58 pt bar is left.
    static let fallbackHeight: CGFloat = 102
    static let barHeight: CGFloat = 58

    /// The wordmark artwork's own aspect (1206 × 544 px). Its box carries a transparent margin, so the drawn mark is
    /// narrower than the box.
    private static let wordmarkAspect: CGFloat = 1206.0 / 544.0

    /// True while Home shows the Hosting view: the same band, with the Hosting tab selected instead of a goer tab.
    private var hosting: Bool { app.simpleShellEnabled && app.effectiveHomeView == .host }

    /// The area label the band shows ("Everywhere" when no area is chosen).
    private var areaText: String {
        app.area == LocationHierarchy.allID ? app.T("Mọi nơi", "Everywhere") : app.currentAreaLabel
    }

    /// The open view's name, for the folded band's pill.
    private var viewTitle: String { hosting ? app.T("Tổ chức", "Hosting") : app.T(tab.vi, tab.en) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                mark
                Spacer(minLength: 6)
                // One middle, two states: the area chip while the tabs show, the view + area pill once they fold away.
                // Both carry the menu-generation id, so starting to scroll rebuilds them and closes an open menu.
                ZStack {
                    areaButton
                        .id(compact.menuGeneration)
                        .opacity(compact.isCompact ? 0 : 1)
                        .allowsHitTesting(!compact.isCompact)
                        .accessibilityHidden(compact.isCompact)
                    viewPill
                        .id(compact.menuGeneration)
                        .opacity(compact.isCompact ? 1 : 0)
                        .allowsHitTesting(compact.isCompact)
                        .accessibilityHidden(!compact.isCompact)
                }
                .frame(maxWidth: 160)
                Spacer(minLength: 6)
                controls
            }
            .padding(.horizontal, 16)
            .frame(height: Self.barHeight)
            .tourTarget("tour.home.search")
            tabsRow
                .frame(height: compact.isCompact ? 0 : 44)
                .opacity(compact.isCompact ? 0 : 1)
                .clipped()
                .accessibilityHidden(compact.isCompact)
        }
        .frame(maxWidth: .infinity)
        // Paper from the very top: the band IS the screen's edge now, so the status-bar strip above it is paper too
        // (it used to be the night hero showing through).
        .background(app.palette.paper.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) { Rectangle().fill(app.palette.divider).frame(height: 1) }
        .onAppear { height = heightForState }
        .onChange(of: compact.isCompact) { _, _ in
            // The hero's spacer animates with the band, so the feed takes back the 44 pt as the tabs fold in.
            withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .easeInOut(duration: 0.24)) { height = heightForState }
        }
        // Bottom edge of the pinned header: the tour keeps spotlighted sections below it.
        .tourTarget("tour.home.headerBottom")
    }

    /// What the band occupies in the hero's layout for the current state.
    private var heightForState: CGFloat { compact.isCompact ? Self.barHeight : Self.fallbackHeight }

    /// The wordmark in the theme's logo ink. Its box is 30 pt tall (the artwork's own aspect), which draws a ~23 pt
    /// mark — the size the design research's bars use, and small enough to leave the area chip the band's middle.
    @ViewBuilder private var mark: some View {
        if let image = UIImage(named: BanbeLogo.Kind.wordmark.rawValue) {
            Image(uiImage: image)
                .renderingMode(.template).resizable().scaledToFit()
                .foregroundStyle(app.palette.ink)
                .frame(width: 30 * Self.wordmarkAspect, height: 30, alignment: .leading)
                .accessibilityLabel("banbe")
                .accessibilityIdentifier("home.title")
        } else {
            Text("banbe").font(BanbeTheme.display(24)).foregroundStyle(app.palette.ink)
                .accessibilityIdentifier("home.title")
        }
    }

    // MARK: area / controls

    /// The area chip is the band's middle while the tabs show (owner 2026-11-22): one quiet capsule between the brand
    /// and the three controls, its label truncating rather than pushing either side.
    private var areaButton: some View {
        let place = app.area == LocationHierarchy.allID ? nil : app.currentAreaLabel
        return Menu {
            AreaMenuOptions { onSearchLocations() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "mappin").font(.app(size: 12, weight: .medium)).opacity(0.7)
                Text(areaText).font(.app(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: 150, alignment: .leading)
                    .accessibilityIdentifier("header.area.label")
                Text("▾").font(.app(size: 9)).opacity(0.45)
            }
            .foregroundStyle(place == nil ? app.palette.ink3 : app.palette.ink)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(app.palette.ink.opacity(0.05), in: Capsule())
            .overlay(Capsule().strokeBorder(app.palette.divider, lineWidth: 1))
            .contentShape(Capsule())
        }
        .accessibilityLabel(app.T("Khu vực: \(areaText). Đổi khu vực", "Area: \(areaText). Change area"))
        .accessibilityIdentifier("header.area")
    }

    /// The folded band's view pill (owner 2026-11-22): the open view over the area, opening every view — Hosting, the
    /// separate host view, included — plus the area picker. It replaces the area chip while the tabs are folded, so the
    /// bar always says where you are and how to move.
    private var viewPill: some View {
        Menu {
            ForEach(HomeHeroTab.allCases.filter { $0 != .foryou || app.hasForYouPrefs }, id: \.self) { t in
                Button {
                    // From the folded band's pill every view except Hosting keeps the scroll position (owner 2026-11-19).
                    selectGoerTab(t, keepScroll: true)
                } label: {
                    if !hosting && tab == t {
                        Label(app.T(t.vi, t.en), systemImage: "checkmark")
                    } else {
                        Text(app.T(t.vi, t.en))
                    }
                }
            }
            if app.isSignedIn {
                Divider()
                Button {
                    openHosting()
                } label: {
                    if hosting {
                        Label(app.T("Tổ chức", "Hosting"), systemImage: "checkmark")
                    } else {
                        Label(app.T("Tổ chức · chế độ host", "Hosting · host view"), systemImage: "briefcase")
                    }
                }
            }
            Divider()
            Menu {
                AreaMenuOptions { onSearchLocations() }
            } label: {
                Label(app.T("Khu vực: \(areaText)", "Area: \(areaText)"), systemImage: "mappin.and.ellipse")
            }
        } label: {
            VStack(spacing: 1) {
                Text(viewTitle).font(.app(size: 17, weight: .semibold)).foregroundStyle(app.palette.linkBlue).lineLimit(1)
                HStack(spacing: 3) {
                    Image(systemName: "mappin").font(.app(size: 9))
                    Text(areaText).font(.app(size: 10.5, weight: .medium)).lineLimit(1)
                }
                .foregroundStyle(app.palette.ink3)
            }
            .frame(maxWidth: 150)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(app.palette.ink.opacity(0.05), in: Capsule())
            .overlay(Capsule().strokeBorder(app.palette.divider, lineWidth: 1))
            .contentShape(Capsule())
        }
        .accessibilityLabel(app.T("Xem: \(viewTitle). Khu vực: \(areaText). Đổi", "View: \(viewTitle). Area: \(areaText). Change"))
        .accessibilityIdentifier("header.view")
    }

    /// Search, Map, quick settings: three equal 40 pt circles — the cluster the owner asked for, with the area between
    /// the brand and it instead of inside a field. The settings gear (not the avatar) opens Quick settings, and it is the
    /// same badge the sheet itself shows over the account row.
    private var controls: some View {
        HStack(spacing: 8) {
            HeaderCircleButton(system: "magnifyingglass", label: app.T("Tìm sự kiện", "Search events"), id: "home.searchBar",
                               accent: true, measureFrame: true) {
                app.openSearch(from: app.homeSearchBarFrame)
            }
            // Note 99: a clay dot while a search is narrowing Home (the query outlives the Search screen).
            .overlay(alignment: .topTrailing) {
                if app.unifiedDiscoveryEnabled && !app.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Circle().fill(app.palette.clay).frame(width: 9, height: 9)
                        .overlay(Circle().stroke(app.palette.paper, lineWidth: 1.5))
                        .offset(x: 1, y: -1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            HeaderCircleButton(system: "map", label: app.T("Bản đồ", "Map"), id: "home.mapButton") {
                app.goMapExploreFromHome()
            }
            if app.unifiedDiscoveryEnabled {
                HeaderCircleButton(system: "gearshape.fill", label: app.T("Cài đặt nhanh", "Quick settings"), id: "home.quickButton") {
                    onAvatar()
                }
            } else {
                // Note 99: the gear only exists with unified discovery (the account is the dock's slot there); otherwise the face.
                SwipeSafeButton {
                    Haptics.light()
                    onAvatar()
                } label: {
                    AccountAvatarView(size: 40).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(app.T("Tài khoản", "Account"))
                .accessibilityIdentifier("home.avatarButton")
            }
        }
    }

    // MARK: tabs

    /// The band's second row (owner 2026-11-22): the goer tabs and Hosting, pinned with the bar. Because they live in
    /// the band, a tab can never be half-cut by it — the flaw in the screenshot that started this pass. This is the
    /// web's `home-hero-tabs` / `home-hero-tab-*`.
    private var tabsRow: some View {
        ViewThatFits(in: .horizontal) {
            tabsStack(spacing: 18).padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                tabsStack(spacing: 18).padding(.horizontal, 16)
            }
        }
        .frame(height: 44)
        .rootSwipeExclusion("homeHeroTabs")
        .accessibilityElement(children: .contain)
        .tourTarget("tour.home.tonight")
    }

    private func tabsStack(spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(HomeHeroTab.allCases.filter { $0 != .foryou || app.hasForYouPrefs }, id: \.self) { t in
                tabButton(title: app.T(t.vi, t.en), selected: !hosting && tab == t, id: "home.hero.tab.\(t.rawValue)") {
                    selectGoerTab(t)
                }
            }
            if app.isSignedIn {
                tabButton(title: app.T("Tổ chức", "Hosting"), selected: hosting, id: "home.hero.tab.hosting") { openHosting() }
                    .tourTarget("tour.home.hosting")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A goer tab: from Hosting it also returns Home to the Going out view (tab and mode stay in sync). Either way the
    /// feed goes back to the top — including when the tab tapped is the one already open: from the folded band the pick
    /// can happen far down the page, and re-choosing the current view is never a dead tap (owner 2026-11-23).
    private func selectGoerTab(_ t: HomeHeroTab, keepScroll: Bool = false) {
        if hosting {
            Haptics.selection()
            tab = t
            app.homeView = .goer
            HomeMode.stored = app.homeView
        } else if tab != t {
            Haptics.selection()
            tab = t
        }
        if !keepScroll { app.resetHomeScrollToTop() }
    }

    private func tabButton(title: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        SwipeSafeButton(action: action) {
            Text(title)
                .font(.app(size: 15.5, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? app.palette.ink : app.palette.ink3)
                .lineLimit(1).fixedSize()
                .frame(minHeight: 44)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(selected ? app.palette.ink : Color.clear).frame(height: 2)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier(id)
    }

    private func openHosting() {
        if HomeMode.hostSegmentLocked(organizerMode: app.isSignedIn && app.organizerMode) {
            Haptics.light()
            app.startHosting(land: .home)
            return
        }
        Haptics.selection()
        app.homeView = .host
        HomeMode.stored = app.homeView
        app.resetHomeScrollToTop()
    }
}

/// The hero: blurred photo of the card in view, header, search, tabs, card rail with a trailing "See all".
struct HomeHeroSection: View {
    @EnvironmentObject private var app: AppState
    @Binding var tab: HomeHeroTab
    let lists: [HomeHeroTab: [DiscoveryCardModel]]
    let onSeeAll: (HomeHeroTab) -> Void
    /// "Search locations…" in the area menu (HomeView owns that sheet).
    let onSearchLocations: () -> Void
    /// The gear's tap: opens the quick-settings sheet (HomeView owns it).
    let onAvatar: () -> Void
    /// Height of the pinned header above (measured by HomeView), left empty at the top of the hero.
    var headerHeight: CGFloat = HomeHeroPinnedHeader.fallbackHeight
    /// v2.3 (note 81): every tab's size; non-nil turns the rail's last card into the See all fan card.
    var v23Counts: [HomeHeroTab: Int]? = nil
    /// How many events Weekend and All events hold under Home's area and filters, for the short pager's suggestion cards
    /// (web `lists.totals`). Empty = no cards.
    var suggestTotals: [HomeHeroTab: Int] = [:]
    /// Note 99 (unified_discovery): "Browse all events" scrolls Home to the Near you list instead of opening Browse; nil = open Browse.
    var onBrowseAll: (() -> Void)? = nil
    /// True while Home shows the Hosting view (organizer mode on + `app.homeView == .host`): the same hero without the card rail.
    /// Derived from app state here (never passed in), so the hero tab and the content below can never disagree.
    private var hosting: Bool { app.simpleShellEnabled && app.effectiveHomeView == .host }

    @State private var current: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let cardWidth: CGFloat = 268
    private static let cardHeight: CGFloat = 360

    private var list: [DiscoveryCardModel] { hosting ? [] : (lists[tab] ?? []) }
    private var currentCard: DiscoveryCardModel? {
        list.first { $0.key == current } ?? list.first
    }
    private var currentIndex: Int { list.firstIndex { $0.key == current } ?? 0 }
    /// The dash lit under the rail: the rail's end card ("See all") is the last page, so it lights the last dash.
    private var dashIndex: Int {
        if list.isEmpty { return currentIndex }
        if current == "home.hero.seeAll" { return list.count }
        if let i = suggestions.firstIndex(where: { "home.hero.suggest.\($0.id)" == current }) { return list.count + 1 + i }
        return currentIndex
    }
    /// A short pager (1 or 2 events) offers other ways to look after the See all card: Weekend, All events, Browse by
    /// type. The rule and the words are shared with web (ListEnd.heroSuggestions, tests/fixtures/list-end.json).
    private var suggestions: [ListEnd.HeroSuggestion] {
        guard !hosting, !list.isEmpty else { return [] }
        return ListEnd.heroSuggestions(tab: tab.rawValue, shown: list.count, weekend: suggestTotals[.weekend] ?? 0, all: suggestTotals[.all] ?? 0)
    }
    private func openSuggestion(_ c: ListEnd.HeroSuggestion) {
        Haptics.selection()
        if c.kind == "tab", let t = c.tab.flatMap(HomeHeroTab.init(rawValue:)) {
            tab = t   // in place: the rail swaps, the page does not scroll
        } else if app.unifiedDiscoveryEnabled, let onBrowseAll {
            onBrowseAll()
        } else {
            app.openBrowse(type: "all", scope: "all")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The band (brand, area, controls and the tabs) is pinned by HomeView (`HomeHeroPinnedHeader`); this keeps
            // its room, so the rail starts exactly under the tabs.
            Color.clear.frame(height: headerHeight)
            dateKicker
            if hosting {
                Color.clear.frame(height: 16)
            } else {
                rail
                dots
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The photo reaches past the hero's own top edge, so nothing seams under the paper band.
        .background { backdrop.padding(.top, -240) }
        .foregroundStyle(.white)
        .onChange(of: tab) { _, _ in current = list.first?.key }
        .accessibilityIdentifier("home.hero")
    }

    /// The date is the hero's kicker now (the band keeps one row): small, tracked, quiet, over the photo.
    private var dateKicker: some View {
        let f = DateFormatter()
        f.locale = Locale(identifier: app.isEN ? "en_GB" : "vi_VN")
        f.dateFormat = "EEEE d MMMM"
        return Text(f.string(from: Date()).uppercased())
            .font(.app(size: 11, weight: .semibold))
            .tracking(1.4)
            .foregroundStyle(.white.opacity(0.58))
            // The same 24 pt the rail's cards start on: the kicker used to sit flush against the screen edge.
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .accessibilityIdentifier("home.date")
    }

    // MARK: backdrop

    private var backdrop: some View {
        Color.clear.overlay {
            ZStack {
                HeroColor.night
                if let path = currentCard?.img, !path.isEmpty {
                    CatalogPhoto(path: path, cornerRadius: 0)
                        .scaleEffect(1.1)
                        .blur(radius: 18)
                        .saturation(0.9)
                        .overlay(Color.black.opacity(0.55))
                        .transition(.opacity)
                }
            }
            .animation(Motion.fade(.easeInOut(duration: 0.4), reduce: reduceMotion), value: currentCard?.key)
        }
        .clipped()
        .accessibilityHidden(true)
    }

    // MARK: rail

    @ViewBuilder private var rail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(list.enumerated()), id: \.element.key) { i, card in
                    heroCard(card)
                        .modifier(HeroFirstCardTourTarget(isFirst: i == 0 && tab == .foryou))
                        .opacity(i == currentIndex ? 1 : 0.6)
                        .animation(Motion.fade(.easeOut(duration: 0.3), reduce: reduceMotion), value: currentIndex)
                        .id(card.key)
                }
                if !list.isEmpty {
                    seeAllCard.id("home.hero.seeAll")
                    ForEach(suggestions, id: \.id) { c in
                        HeroSuggestCard(model: c, width: Self.cardWidth, height: Self.cardHeight) { openSuggestion(c) }
                            .id("home.hero.suggest.\(c.id)")
                    }
                }
                if list.isEmpty {
                    emptyCard
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, 24, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $current)
        .padding(.top, 20)
        .tourTarget("tour.home.rail")
        .rootSwipeExclusion("homeHeroRail")
        .accessibilityIdentifier("home.hero.rail")
    }

    private func heroCard(_ m: DiscoveryCardModel) -> some View {
        SwipeSafeButton { app.goEvent(m.key) } label: {
            ZStack(alignment: .bottomLeading) {
                Color(hex: 0x2A2620)
                if !m.img.isEmpty {
                    Color.clear.overlay {
                        CatalogPhoto(path: m.img, cornerRadius: 0)
                    }
                    .clipped()
                }
                LinearGradient(stops: [.init(color: .black.opacity(0.25), location: 0), .init(color: .black.opacity(0), location: 0.3),
                                       .init(color: .black.opacity(0.05), location: 0.5), .init(color: .black.opacity(0.78), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 6) {
                    if !m.metaLine.isEmpty {
                        Text(m.metaLine.uppercased())
                            .font(.app(size: 11)).tracking(1.3).opacity(0.85).lineLimit(1)
                    }
                    Text(m.name)
                        .font(.app(size: 26, weight: .light)).lineLimit(3).minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Text(m.priceLabel)
                        Spacer(minLength: 0)
                        if let left = m.fill.left { Text(app.T("Còn \(left) chỗ", "\(left) left")) }
                    }
                    .font(.app(size: 13)).opacity(0.9).lineLimit(1)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: Self.cardWidth, height: Self.cardHeight)
            // The cover grows out of (and shrinks back into) this card, not the screen's centre.
            .zoomSource(m.key)
            .overlay(alignment: .top) {
                HStack {
                    if !m.dateBadge.isEmpty { badge(m.dateBadge.uppercased()) }
                    Spacer(minLength: 0)
                    badge(app.isSaved(m.key) ? app.T("ĐÃ LƯU", "SAVED") : app.T("LƯU", "SAVE"))
                }
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(m.name), \(m.priceLabel)")
        .accessibilityIdentifier("home.hero.card.\(m.key)")
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.app(size: 11.5, weight: .bold)).tracking(0.2)
            .foregroundStyle(HeroColor.badgeInk)
            .padding(.horizontal, 10).frame(height: 28)
            .background(HeroColor.badgeFill, in: Capsule())
    }

    @ViewBuilder private var seeAllCard: some View {
        if let counts = v23Counts {
            SeeAllFanCard(photos: list.map(\.img), label: ViEn(tab.vi, tab.en), count: counts[tab] ?? list.count,
                          art: tab.rawValue,
                          // For You, signed in: "Edit preferences" opens the same For You editor as everywhere else.
                          onEditPrefs: tab == .foryou && app.isSignedIn ? { app.openEventPreferences(returnTo: .home) } : nil) { onSeeAll(tab) }
        } else {
            classicSeeAllCard
        }
    }

    private var classicSeeAllCard: some View {
        SwipeSafeButton { onSeeAll(tab) } label: {
            VStack(spacing: 10) {
                Text("→").font(.app(size: 26))
                Text(app.T("Xem tất cả", "See all")).font(.app(size: 15))
            }
            .foregroundStyle(.white)
            .frame(width: Self.cardWidth, height: Self.cardHeight)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.hero.seeAll")
    }

    /// True when an area or any filter narrows Home (so an empty rail may just mean "too narrow").
    private var areaActive: Bool { app.area != LocationHierarchy.allID }
    private var otherFiltersActive: Bool { app.homeFilters != .default || app.filterForYou }

    /// The empty tab is a real card in the hero (owner 2026-11-19: "looks better and more premium"): the rail's full
    /// width and the hero card's height and corner, a tonal surface (with a blurred cover of what the primary action
    /// leads to, when there is one), a tracked kicker, a serif headline, one line on what is next, ONE primary pill and
    /// the other ways out as quiet links. Which actions appear, and what each does, is unchanged from note 97.
    /// Web twin: the `home-hero-empty` card in HomeShellV5.jsx.
    private var emptyCard: some View {
        let icon: String, text: String, cta: String, headline: String
        let action: () -> Void
        let place = app.currentAreaLabel
        let narrowed = areaActive || otherFiltersActive
        // The weekend rail is built with the same area and filters (only the date differs), so `lists` already knows
        // whether "See this weekend" leads anywhere (owner 2026-11-18). Web twin: `weekendHasEvents` in HomeShellV5.jsx.
        let weekendList = lists[.weekend] ?? []
        let weekendHasEvents = !weekendList.isEmpty
        let browseAll: () -> Void = {
            Haptics.selection()
            if app.unifiedDiscoveryEnabled, let onBrowseAll { onBrowseAll() } else { app.openBrowse(type: "all", scope: "all") }
        }
        switch tab {
        case .foryou:
            icon = "sparkles"
            headline = narrowed ? app.T("Chưa có gợi ý ở đây.", "No picks here yet.")
                                : app.T("Gợi ý của bạn bắt đầu từ đây.", "Your picks start here.")
            if areaActive {
                text = app.T("Chưa có gợi ý ở \(place). Thử đổi khu vực hoặc bỏ bớt bộ lọc.",
                             "No picks in \(place). Try another area or fewer filters.")
            } else if otherFiltersActive {
                text = app.T("Bộ lọc đang ẩn mọi gợi ý. Bỏ bớt bộ lọc để xem thêm.", "Your filters hide every pick. Clear them to see more.")
            } else {
                text = app.T("Chưa có gợi ý. Trả lời vài câu hỏi để chúng tôi chọn sự kiện hợp với bạn.",
                             "No picks yet. Answer a few questions and we will pick events that fit you.")
            }
            cta = app.T("Đặt sở thích", "Set your preferences")
            action = { Haptics.selection(); app.openEventPreferences() }
        case .tonight:
            icon = "moon.stars"
            headline = app.T("Đêm nay yên ắng.", "A quiet night.")
            let base = areaActive ? app.T("Tối nay chưa có sự kiện nào ở \(place).", "Nothing on tonight in \(place).")
                                  : app.T("Tối nay chưa có sự kiện nào.", "Nothing on tonight.")
            if weekendHasEvents {
                // A real number when it is known: the rail is capped (4 or 5), so a full rail only knows "at least".
                let cap = app.homeV23Enabled ? 4 : 5
                var n: Int? = nil
                if weekendList.count < cap {
                    n = weekendList.count
                } else if !narrowed, let total = v23Counts?[.weekend] {
                    n = max(total, weekendList.count)
                }
                let next = n.map { n in app.T("Cuối tuần này có \(n) sự kiện.", "\(n) \(n == 1 ? "event" : "events") this weekend.") }
                    ?? app.T("Cuối tuần này vẫn có sự kiện.", "The weekend has more.")
                text = base + " " + next
                cta = app.T("Xem cuối tuần", "See this weekend")
                action = { Haptics.selection(); tab = .weekend }
            } else {
                // An empty Tonight must not send people to an empty Weekend and then a second "Browse all events".
                text = base + " " + app.T("Cuối tuần này cũng chưa có gì.", "The weekend is quiet too.")
                cta = app.T("Xem tất cả sự kiện", "Browse all events")
                action = browseAll
            }
        case .weekend:
            icon = "calendar"
            headline = app.T("Cuối tuần yên ắng.", "A quiet weekend.")
            text = areaActive ? app.T("Cuối tuần này chưa có sự kiện nào ở \(place).", "Nothing on this weekend in \(place).")
                              : app.T("Cuối tuần này chưa có sự kiện nào.", "Nothing on this weekend.")
            // Browse all events opens the every-event list, never the By type section on Home (owner 2026-11-18).
            cta = app.T("Xem tất cả sự kiện", "Browse all events")
            action = browseAll
        case .all:
            icon = "calendar"
            headline = app.T("Chưa có gì ở đây.", "Nothing here yet.")
            text = areaActive ? app.T("Chưa có sự kiện nào ở \(place).", "No events in \(place) yet.")
                              : app.T("Chưa có sự kiện nào đang mở.", "No open events yet.")
            cta = app.T("Mở bản đồ", "Open the map")
            action = { Haptics.selection(); app.goMapExploreFromHome() }
        }
        // Narrowed by an area or filters: "Change area" leads; the original action drops to the second/third slot.
        let changeArea = narrowed && areaActive
        let clear: (label: String, run: () -> Void)? = {
            guard narrowed else { return nil }
            if otherFiltersActive {
                return (app.T("Bỏ bộ lọc", "Clear filters"), {
                    Haptics.selection()
                    app.setHomeFilters(.default)
                    app.filterForYou = false
                })
            }
            // Only the area narrows: show every event in it, as the real every-event list (not Home's By type rows).
            return (app.T("Xem mọi sự kiện ở \(place)", "Show all events in \(place)"), browseAll)
        }()
        let showPrefsLink = tab == .foryou && narrowed && !app.hasForYouMatches
        let primary: HeroEmptyCard.Action
        var links: [HeroEmptyCard.Action] = []
        if changeArea {
            primary = .init(title: app.T("Đổi khu vực", "Change area"), id: "home.hero.empty.area") {
                Haptics.selection()
                onSearchLocations()
            }
            if let clear { links.append(.init(title: clear.label, id: "home.hero.empty.clear", run: clear.run)) }
            if tab != .foryou || showPrefsLink { links.append(.init(title: cta, id: "home.hero.empty.cta", run: action)) }
        } else {
            primary = .init(title: cta, id: "home.hero.empty.cta", run: action)
            if let clear { links.append(.init(title: clear.label, id: "home.hero.empty.clear", run: clear.run)) }
            // When "See this weekend" does lead somewhere, Browse all events stays one tap away as well.
            if tab == .tonight, weekendHasEvents {
                links.append(.init(title: app.T("Xem tất cả sự kiện", "Browse all events"), id: "home.hero.empty.more", run: browseAll))
            }
        }
        let kicker = app.T(tab == .weekend ? "Cuối tuần này" : (tab == .all ? "Tất cả sự kiện" : tab.vi),
                           tab == .weekend ? "This weekend" : (tab == .all ? "All events" : tab.en))
            + (areaActive ? " · \(place)" : "")
        return HeroEmptyCard(icon: icon, kicker: kicker, headline: headline, support: text, primary: primary, links: links,
                             // The covers of what the primary action leads to (Tonight → this weekend), never made up.
                             photos: tab == .tonight && weekendHasEvents && !changeArea ? weekendList.map(\.img).filter { !$0.isEmpty } : [],
                             minHeight: Self.cardHeight)
            // The rail holds nothing else, so the card takes the rail's whole width (inside its 24 pt margins).
            .containerRelativeFrame(.horizontal)
            .id("home.hero.empty.\(tab.rawValue)")
    }

    private var dots: some View {
        HStack(spacing: 6) {
            // One dash per card plus one for the end card and one per suggestion card.
            ForEach(0..<(list.isEmpty ? 0 : list.count + 1 + suggestions.count), id: \.self) { i in
                Capsule()
                    .fill(i == dashIndex ? Color.white : Color.white.opacity(0.32))
                    .frame(width: i == dashIndex ? 30 : 20, height: 3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18).padding(.bottom, 22)
        .animation(Motion.fade(.easeOut(duration: 0.2), reduce: reduceMotion), value: dashIndex)
        .accessibilityHidden(true)
    }
}

/// "Browse": the most-stocked types with counts (up to 5) and a "Find a type" tile that opens the A-Z sheet.
struct HomeBrowseSection: View {
    @EnvironmentObject private var app: AppState
    /// Event counts per category key ("all" ignored).
    let counts: [String: Int]
    let onPick: (String) -> Void
    let onFind: () -> Void
    /// v2.3 (note 81): "Browse by type" with "See all N" (every live event); the tiles open the Browse screen.
    var seeAllTotal: Int? = nil

    private static let maxTiles = 5

    private var top: [(key: String, n: Int)] {
        let order = Dictionary(uniqueKeysWithValues: EventTypes.keys.enumerated().map { ($1, $0) })
        return counts.filter { $0.key != "all" && $0.value > 0 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : (order[$0.key] ?? 0) < (order[$1.key] ?? 0) }
            .prefix(Self.maxTiles).map { (key: $0.key, n: $0.value) }
    }

    private func events(_ n: Int) -> String { app.isEN ? "\(n) \(n == 1 ? "event" : "events")" : "\(n) sự kiện" }

    var body: some View {
        if !top.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(seeAllTotal != nil ? app.T("Duyệt theo loại", "Browse by type") : app.T("Khám phá", "Browse"))
                        .font(BanbeTheme.display(19))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    if let total = seeAllTotal {
                        Button(action: onFind) {
                            (Text(app.T("Xem tất cả ", "See all ")) + Text("\(total)").bold())
                                .font(.app(size: 14, weight: .semibold)).frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("home.browse.all")
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4, alignment: .top), count: 3), spacing: 4) {
                    ForEach(top, id: \.key) { t in
                        tile(symbol: CategoryGlyph.symbol(t.key), title: typeName(t.key), sub: events(t.n), id: "home.browse.\(t.key)") { onPick(t.key) }
                    }
                    tile(symbol: "magnifyingglass", title: app.T("Tìm một loại", "Find a type"),
                         sub: app.T("\(EventTypes.categoryDefs().count) loại", "\(EventTypes.categoryDefs().count) types"), id: "home.browse.find", action: onFind)
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 20).padding(.top, 28)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home.browse")
            .tourTarget("tour.home.browse")
        }
    }

    private func typeName(_ key: String) -> String {
        HomeDiscovery.categories.first { $0.key == key }.map { app.T($0.vi, $0.en) } ?? key
    }

    private func tile(symbol: String, title: String, sub: String, id: String, action: @escaping () -> Void) -> some View {
        SwipeSafeButton(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.app(size: 24, weight: .light))
                    .frame(width: 52, height: 52)
                Text(title).font(.app(size: 13)).lineLimit(1).minimumScaleFactor(0.8)
                Text(sub).font(.app(size: 11.5)).opacity(0.64).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 14).padding(.bottom, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }
}

/// "By type": a Filters button + one-line summary, then one horizontal photo row per type (most events first;
/// a type with no event is not shown).
struct HomeByTypeSections: View {
    @EnvironmentObject private var app: AppState
    /// (category key, cards) already ordered, at most 12 cards per row.
    let sections: [(key: String, cards: [DiscoveryCardModel])]
    let summary: String
    let onFilters: () -> Void
    let onPick: (String) -> Void

    /// Group the shown cards by their first category, biggest group first, 12 per row (web twin: `sections`).
    static func sections(shown: [HomeDiscovery.Item], cards: [DiscoveryCardModel]) -> [(key: String, cards: [DiscoveryCardModel])] {
        let byKey = Dictionary(cards.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        var order: [String] = []
        var groups: [String: [DiscoveryCardModel]] = [:]
        for it in shown {
            guard let card = byKey[it.key] else { continue }
            let k = it.catKeys.first ?? "other"
            if groups[k] == nil { order.append(k) }
            groups[k, default: []].append(card)
        }
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return order.sorted { (groups[$0]?.count ?? 0) != (groups[$1]?.count ?? 0) ? (groups[$0]?.count ?? 0) > (groups[$1]?.count ?? 0) : (rank[$0] ?? 0) < (rank[$1] ?? 0) }
            .map { (key: $0, cards: Array((groups[$0] ?? []).prefix(12))) }
    }

    private func typeName(_ key: String) -> String {
        HomeDiscovery.categories.first { $0.key == key }.map { app.T($0.vi, $0.en) } ?? key
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(app.T("Theo loại", "By type"))
                        .font(BanbeTheme.display(19))
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    SwipeSafeButton(action: onFilters) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.app(size: 16, weight: .regular))
                            .frame(width: 38, height: 38)
                            .background(app.palette.block, in: Circle())
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(app.T("Bộ lọc", "Filters"))
                    .accessibilityIdentifier("home.filtersButton")
                }
                SwipeSafeButton(action: onFilters) {
                    Text(summary)
                        .font(.app(size: 13)).opacity(0.72).lineLimit(1)
                        .padding(.bottom, 3)
                        .overlay(alignment: .bottom) { Rectangle().fill(app.palette.divider).frame(height: 1) }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.filterSummary")
                .tourTarget("tour.home.filters")
            }
            .padding(.horizontal, 20).padding(.top, 28)
            if sections.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.T("Chưa có gì khớp", "Nothing matches yet")).font(.app(size: 17))
                    Text(app.T("Bộ lọc đang ẩn mọi sự kiện. Nới rộng để xem thêm.", "Your filters hide every event. Widen them to see more."))
                        .font(.app(size: 14)).opacity(0.7)
                }
                .padding(.horizontal, 20).padding(.top, 24)
                .accessibilityIdentifier("home.byType.empty")
            }
            ForEach(sections, id: \.key) { section in
                row(section)
            }
        }
        .foregroundStyle(app.palette.ink)
    }

    private func row(_ s: (key: String, cards: [DiscoveryCardModel])) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SwipeSafeButton { onPick(s.key) } label: {
                HStack(spacing: 12) {
                    Image(systemName: CategoryGlyph.symbol(s.key)).font(.app(size: 17, weight: .regular)).frame(width: 22)
                    Text(typeName(s.key)).font(.app(size: 17, weight: .semibold))
                    Text("\(s.cards.count)").font(.app(size: 14)).opacity(0.64)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.app(size: 12, weight: .semibold)).opacity(0.5)
                }
                .padding(.horizontal, 20)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.type.\(s.key)")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(s.cards) { card in typeCard(card) }
                }
                .padding(.horizontal, 20)
            }
            .rootSwipeExclusion("homeType.\(s.key)")
        }
        .padding(.top, 14)
    }

    private func typeCard(_ m: DiscoveryCardModel) -> some View {
        SwipeSafeButton { app.goEvent(m.key) } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    app.palette.block
                    if !m.img.isEmpty { Color.clear.overlay { CatalogPhoto(path: m.img, cornerRadius: 0) }.clipped() }
                }
                .frame(width: 168, height: 204)
                .overlay(alignment: .topLeading) {
                    if !m.dateBadge.isEmpty {
                        Text(m.dateBadge.uppercased())
                            .font(.app(size: 11.5, weight: .bold))
                            .foregroundStyle(HeroColor.badgeInk)
                            .padding(.horizontal, 10).frame(height: 26)
                            .background(Color(hex: 0xF7F4EC).opacity(0.9), in: Capsule())
                            .padding(8)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if m.fill.soldOut {
                        Text(app.T("HẾT CHỖ", "SOLD OUT"))
                            .font(.app(size: 11.5, weight: .bold))
                            .foregroundStyle(BanbeTheme.onAlert)
                            .padding(.horizontal, 12).frame(height: 26)
                            .background(BanbeTheme.alert, in: Capsule())
                            .padding(8)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(m.name)
                    .font(.app(size: 15)).lineLimit(2).multilineTextAlignment(.leading)
                    .padding(.top, 10)
                Text([m.metaLine, m.priceLabel].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.app(size: 12)).opacity(0.64).lineLimit(1)
                    .padding(.top, 3)
            }
            .frame(width: 168, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(m.name), \(m.priceLabel)")
        .accessibilityIdentifier("home.event.\(m.key)")
    }
}

// MARK: - Empty hero tab

/// The card an empty hero tab shows (owner 2026-11-19). Pure view: the copy and the actions come from
/// `HomeHeroSection.emptyCard`. Always on the dark hero, so the colours are the hero's own (light and dark theme alike).
/// Fades and rises once on appear (none under Reduce Motion); every size follows Dynamic Type and the card grows past
/// the hero card's height rather than clipping long Vietnamese copy.
struct HeroEmptyCard: View {
    struct Action {
        let title: String
        let id: String
        let run: () -> Void
    }

    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    let icon: String
    let kicker: String
    let headline: String
    let support: String
    let primary: Action
    let links: [Action]
    let photos: [String]
    let minHeight: CGFloat

    @ScaledMetric(relativeTo: .caption) private var kickerSize: CGFloat = 11
    @ScaledMetric(relativeTo: .title) private var headSize: CGFloat = 30
    @ScaledMetric(relativeTo: .subheadline) private var bodySize: CGFloat = 15
    @ScaledMetric(relativeTo: .body) private var buttonSize: CGFloat = 15
    @State private var shown = false

    private static let paper = Color(hex: 0xF7F4EC)
    private static let ink = Color(hex: 0x1B1916)
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 16, style: .continuous) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: kickerSize + 2, weight: .medium))
                Text(kicker.uppercased())
                    .font(.app(size: kickerSize, weight: .semibold)).tracking(1.5).lineLimit(2)
            }
            .foregroundStyle(.white.opacity(0.72))
            Spacer(minLength: 18)
            if !photos.isEmpty, !typeSize.isAccessibilitySize {
                fan.padding(.bottom, 22).accessibilityHidden(true)
            }
            Text(headline)
                .font(V23Style.serif(headSize)).tracking(-0.6)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(support)
                .font(.app(size: bodySize)).lineSpacing(2)
                .foregroundStyle(.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            SwipeSafeButton(action: primary.run) {
                HStack(spacing: 8) {
                    Text(primary.title).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "arrow.right").font(.system(size: buttonSize - 2, weight: .semibold)).accessibilityHidden(true)
                }
                .font(.app(size: buttonSize, weight: .semibold))
                .foregroundStyle(Self.ink)
                .padding(.horizontal, 20).padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Self.paper, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(primary.id)
            .padding(.top, 20)
            if !links.isEmpty {
                // Side by side when they fit, stacked otherwise (long Vietnamese labels, large text).
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 20) { linkButtons }.frame(maxWidth: .infinity)
                    VStack(spacing: 0) { linkButtons }.frame(maxWidth: .infinity)
                }
                .padding(.top, 6)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, links.isEmpty ? 20 : 8)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background { surface }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 14)
        .onAppear {
            guard !shown else { return }
            if reduceMotion { shown = true } else { withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.6)) { shown = true } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.hero.empty")
    }

    @ViewBuilder private var linkButtons: some View {
        ForEach(links, id: \.id) { link in
            SwipeSafeButton(action: link.run) {
                Text(link.title)
                    .font(.app(size: buttonSize - 1, weight: .medium))
                    .underline(true, color: .white.opacity(0.35))
                    .foregroundStyle(.white.opacity(0.86))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(link.id)
        }
    }

    /// A tonal night surface with a faint clay glow; with covers, the first one blurred and dimmed under it.
    private var surface: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x302A22), Color(hex: 0x1A1813)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let cover = photos.first {
                Color.clear.overlay {
                    CatalogPhoto(path: cover, cornerRadius: 0).scaleEffect(1.3).blur(radius: 26).saturation(0.85)
                }
                .clipped()
                .opacity(0.5)
            }
            RadialGradient(colors: [app.palette.clay.opacity(0.32), .clear], center: .topTrailing, startRadius: 0, endRadius: 280)
            LinearGradient(stops: [.init(color: .black.opacity(0.12), location: 0), .init(color: .clear, location: 0.3),
                                   .init(color: .black.opacity(0.55), location: 1)], startPoint: .top, endPoint: .bottom)
        }
        .accessibilityHidden(true)
    }

    /// Up to three covers of where the primary action leads, stacked like the See all card's fan.
    private var fan: some View {
        let covers = Array(photos.prefix(3))
        return ZStack(alignment: .leading) {
            ForEach(Array(covers.enumerated()), id: \.offset) { i, src in
                ZStack {
                    Color(hex: 0x2A2620)
                    CatalogPhoto(path: src, height: 84, width: 64, cornerRadius: 0)
                }
                .frame(width: 64, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                .rotationEffect(.degrees([-6.0, 2.0, 8.0][i]))
                .offset(x: CGFloat(i) * 38, y: [4.0, -2.0, 5.0][i])
                .zIndex(Double(3 - i))
            }
        }
        .frame(width: 64 + CGFloat(max(0, covers.count - 1)) * 38 + 12, height: 96, alignment: .leading)
    }
}
