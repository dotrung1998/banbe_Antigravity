import SwiftUI
import UIKit

// Home from the v5 prototype (note 80), shown with the Simple Shell on Going out. Web twin:
// src/components/home/HomeShellV5.jsx. A pinned paper app bar (wordmark, the area chip as its middle, search / Map /
// account, and the tabs as its second row) sits above one dark photo hero that holds the date kicker and the snap card
// rail; below it come Browse (types with counts + Find a type) and By type (one photo row per type).
// Pure views over lists HomeView already builds: no fetching and no filters of its own.

/// The goer tabs of the hero. The Hosting tab is separate (`HomeHeroSection.hosting`): it is the host view of `app.homeView`.
enum HomeHeroTab: String, CaseIterable {
    case foryou, tonight, weekend
    var vi: String { self == .foryou ? "Dành cho bạn" : (self == .tonight ? "Tối nay" : "Cuối tuần") }
    var en: String { self == .foryou ? "For You" : (self == .tonight ? "Tonight" : "Weekend") }
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

/// Home's app bar (owner 2026-11-22): ONE paper band, two rows, the same shape at rest and scrolled. It is pinned at the
/// top of the feed and keeps its own room in the hero, so nothing slides under it at rest and the tabs can never be cut
/// by it — the complaint about the floating band. Web twin: the `.bb-home-head*` block in src/index.css.
struct HomeHeroPinnedHeader: View {
    @EnvironmentObject private var app: AppState
    /// The goer tab; Hosting is the other Home view (`hosting` below), selected the same way it is in the hero.
    @Binding var tab: HomeHeroTab
    let onSearchLocations: () -> Void
    let onAvatar: () -> Void
    @Binding var height: CGFloat

    /// The band's own height: 58 pt of controls + 44 pt of tabs. Everything inside is static — no morph, no ramp.
    static let fallbackHeight: CGFloat = 102

    /// The wordmark artwork's own aspect (1206 × 544 px). Its box carries a transparent margin, so the drawn mark is
    /// narrower than the box.
    private static let wordmarkAspect: CGFloat = 1206.0 / 544.0

    /// True while Home shows the Hosting view: the same band, with the Hosting tab selected instead of a goer tab.
    private var hosting: Bool { app.simpleShellEnabled && app.effectiveHomeView == .host }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                mark
                Spacer(minLength: 6)
                areaButton
                Spacer(minLength: 6)
                controls
            }
            .padding(.horizontal, 16)
            .frame(height: 58)
            .tourTarget("tour.home.search")
            tabsRow
        }
        .frame(maxWidth: .infinity)
        // Paper from the very top: the band IS the screen's edge now, so the status-bar strip above it is paper too
        // (it used to be the night hero showing through).
        .background(app.palette.paper.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) { Rectangle().fill(app.palette.divider).frame(height: 1) }
        .background(GeometryReader { g in
            Color.clear
                .onAppear { height = g.size.height }
                .onChange(of: g.size.height) { _, h in height = h }
        })
        // Bottom edge of the pinned header: the tour keeps spotlighted sections below it.
        .tourTarget("tour.home.headerBottom")
    }

    /// The wordmark in the theme's logo ink. Its box is 30 pt tall (the artwork's own aspect), which draws a ~23 pt
    /// mark — the size the design research's bars use, and small enough to leave the area chip the band's middle.
    @ViewBuilder private var mark: some View {
        if let image = UIImage(named: BanbeLogo.Kind.wordmark.rawValue) {
            Image(uiImage: image)
                .renderingMode(.template).resizable().scaledToFit()
                .foregroundStyle(app.palette.logo)
                .frame(width: 30 * Self.wordmarkAspect, height: 30, alignment: .leading)
                .accessibilityLabel("banbe")
                .accessibilityIdentifier("home.title")
        } else {
            Text("banbe").font(BanbeTheme.display(24)).foregroundStyle(app.palette.logo)
                .accessibilityIdentifier("home.title")
        }
    }

    /// Initials in a clay disc (a person glyph for a guest). Opens Account.
    private func avatarButton(size: CGFloat) -> some View {
        SwipeSafeButton {
            Haptics.light()
            onAvatar()
        } label: {
            Group {
                if app.isSignedIn {
                    Text(BottomTabBar.initials(app.displayName)).font(.app(size: size * 0.33, weight: .bold))
                } else {
                    Image(systemName: "person").font(.app(size: size * 0.4, weight: .regular))
                }
            }
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(app.palette.clay, in: Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(app.T("Tài khoản", "Account"))
        .accessibilityIdentifier("home.avatarButton")
    }

    // MARK: area / controls

    /// The area chip is the band's middle (owner 2026-11-22): one quiet capsule between the brand and the three
    /// controls, its label truncating rather than pushing either side.
    private var areaButton: some View {
        let place = app.area == LocationHierarchy.allID ? nil : app.currentAreaLabel
        let areaText = place ?? app.T("Mọi nơi", "Everywhere")
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

    /// Search, Map, account: three equal 40 pt circles — the cluster the owner asked for, with the area between the
    /// brand and it instead of inside a field.
    private var controls: some View {
        HStack(spacing: 8) {
            roundButton(system: "magnifyingglass", label: app.T("Tìm sự kiện", "Search events"), id: "home.searchBar",
                        accent: true, measureFrame: true) {
                Haptics.light()
                app.openSearch(from: app.homeSearchBarFrame)
            }
            roundButton(system: "map", label: app.T("Bản đồ", "Map"), id: "home.mapButton") {
                Haptics.light()
                app.goMapExploreFromHome()
            }
            avatarButton(size: 40)
        }
    }

    private func roundButton(system: String, label: String, id: String, accent: Bool = false,
                             measureFrame: Bool = false, action: @escaping () -> Void) -> some View {
        let button = SwipeSafeButton(action: action) {
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
        // Where the search circle is on screen, so Search can start its own field right here (the glide entrance).
        if measureFrame {
            return button.background(GeometryReader { g in
                Color.clear
                    .onAppear { app.homeSearchBarFrame = g.frame(in: .global) }
                    .onChange(of: g.frame(in: .global)) { _, f in app.homeSearchBarFrame = f }
            })
        }
        return button
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
            ForEach(HomeHeroTab.allCases, id: \.self) { t in
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

    /// A goer tab: from Hosting it also returns Home to the Going out view (tab and mode stay in sync).
    private func selectGoerTab(_ t: HomeHeroTab) {
        if hosting {
            Haptics.selection()
            tab = t
            app.homeView = .goer
            HomeMode.stored = app.homeView
            app.resetHomeScrollToTop()
        } else if tab != t {
            Haptics.selection()
            tab = t
        }
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
    /// Avatar tap: opens the quick-settings sheet (HomeView owns it).
    let onAvatar: () -> Void
    /// Height of the pinned header above (measured by HomeView), left empty at the top of the hero.
    var headerHeight: CGFloat = HomeHeroPinnedHeader.fallbackHeight
    /// v2.3 (note 81): every tab's size; non-nil turns the rail's last card into the See all fan card.
    var v23Counts: [HomeHeroTab: Int]? = nil
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
            SeeAllFanCard(photos: list.map(\.img), label: ViEn(tab.vi, tab.en), count: counts[tab] ?? list.count) { onSeeAll(tab) }
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

    /// Same card-sized slot and visual language as a rail card, with one primary action that guides the person on.
    /// When an area or filter is active it explains that and offers to change the area / clear the filters first.
    private var emptyCard: some View {
        let icon: String, text: String, cta: String
        let action: () -> Void
        let place = app.currentAreaLabel
        let narrowed = areaActive || otherFiltersActive
        switch tab {
        case .foryou:
            icon = "sparkles"
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
            text = areaActive ? app.T("Tối nay chưa có sự kiện nào ở \(place).", "Nothing on tonight in \(place).")
                              : app.T("Tối nay chưa có sự kiện nào.", "Nothing on tonight.")
            cta = app.T("Xem cuối tuần", "See this weekend")
            action = { Haptics.selection(); tab = .weekend }
        case .weekend:
            icon = "calendar"
            text = areaActive ? app.T("Cuối tuần này chưa có sự kiện nào ở \(place).", "Nothing on this weekend in \(place).")
                              : app.T("Cuối tuần này chưa có sự kiện nào.", "Nothing on this weekend.")
            cta = app.T("Xem tất cả sự kiện", "Browse all events")
            action = {
                Haptics.selection()
                var f = app.homeFilters
                f.date = "any"
                app.setHomeFilters(f)
                app.homeBrowseScrollRequest = UUID()
            }
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
            // Only the area narrows: show every event in it (the Browse list below).
            return (app.T("Xem mọi sự kiện ở \(place)", "Show all events in \(place)"), {
                Haptics.selection()
                app.homeBrowseScrollRequest = UUID()
            })
        }()
        let showPrefsLink = tab == .foryou && narrowed && !app.hasForYouMatches
        func pill(_ title: String, id: String, primary: Bool, run: @escaping () -> Void) -> some View {
            SwipeSafeButton(action: run) {
                Text(title)
                    .font(.app(size: 15, weight: .semibold)).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.85)
                    .foregroundStyle(primary ? HeroColor.badgeInk : .white)
                    .padding(.horizontal, 18).frame(maxWidth: .infinity, minHeight: 44)
                    .background(primary ? HeroColor.badgeFill : Color.white.opacity(0.14), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(primary ? 0 : 0.3), lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(id)
        }
        return VStack(spacing: 12) {
            Image(systemName: icon).font(.app(size: 28, weight: .light))
            Text(text)
                .font(.app(size: 15)).multilineTextAlignment(.center).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            if changeArea {
                pill(app.T("Đổi khu vực", "Change area"), id: "home.hero.empty.area", primary: true) {
                    Haptics.selection()
                    onSearchLocations()
                }
                if let clear { pill(clear.label, id: "home.hero.empty.clear", primary: false, run: clear.run) }
                if tab == .foryou {
                    if showPrefsLink {
                        SwipeSafeButton(action: action) {
                            Text(cta).font(.app(size: 14)).underline().frame(minHeight: 36).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("home.hero.empty.cta")
                    }
                } else {
                    SwipeSafeButton(action: action) {
                        Text(cta).font(.app(size: 14)).underline().frame(minHeight: 36).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.hero.empty.cta")
                }
            } else {
                pill(cta, id: "home.hero.empty.cta", primary: true, run: action)
                if let clear { pill(clear.label, id: "home.hero.empty.clear", primary: false, run: clear.run) }
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(width: Self.cardWidth, height: Self.cardHeight)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.hero.empty")
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(Array(list.enumerated()), id: \.element.key) { i, _ in
                Capsule()
                    .fill(i == currentIndex ? Color.white : Color.white.opacity(0.32))
                    .frame(width: i == currentIndex ? 30 : 20, height: 3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18).padding(.bottom, 22)
        .animation(Motion.fade(.easeOut(duration: 0.2), reduce: reduceMotion), value: currentIndex)
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
