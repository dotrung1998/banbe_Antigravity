import SwiftUI

// See all / Browse by type (v2.3, notes 81, 85, 86, 88 and 90, switch home_v23). Web twin: src/screens/Browse.jsx. One
// route family, one kind of screen: a list of events.
// · scope "all" is Browse by type: the whole catalogue as a LIST, never a grid (note 88). Every event at once, with the
//   type chips narrowing it in place; "All" widens it back. The nav row says "Browse by type", a picked type is the
//   30px content heading with its own count line.
// · a scope is See all for one Home tab, with Home's same three tabs right under the nav so the reader switches tab in
//   place (note 85), type chips counted inside that tab, then the list.
// Browse by type is the row's FOURTH TAB (note 90), alongside For You, Tonight and Weekend: it opens the every-event
// list in place, and its tab row keeps the tab it came from as context. Back always leaves Browse for Home in one step
// (owner 2026-11-18): Home and Browse are one tab, so Back never steps through Browse's own tabs to get home.
// Under the nav a deck of host faces: a tap lists the hosts, a host opens their real profile. The magnifier opens the
// same search screen Home's does. Its own Filters (Location, When, Price, Seats). Four rows a page with the swipe signs,
// then an end card. Rules: Lib/V23Rules.swift (BrowseRules, Pager, ListEnd).

extension AppState {
    func openBrowse(type: String = "all", scope: String = "all", keep: Bool = false) {
        let t = type.isEmpty ? "all" : type, sc = scope.isEmpty ? "all" : scope
        let same = keep && browseType == t && browseScope == sc
        browseType = t
        browseScope = sc
        if !same { browseQuery = ""; browseFilters = .default }
        homeFilterSheetOpen = false
        // Home and Browse share one top bar, so they cross-fade rather than slide past each other (RootView).
        dockTabSwitch = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.dockTabSwitch = false }
        screen = .browse
    }

    /// Back leaves Browse for Home, always (owner 2026-11-18): Home and Browse are one tab, so Back returns to the Home
    /// screen in one step instead of stepping back through Browse's own scope tabs.
    func backFromBrowse() {
        // The same quick cross-fade: the shared top-right cluster stays exactly where it is.
        dockTabSwitch = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.dockTabSwitch = false }
        screen = .home
    }

    /// Browse by type from inside one tab's See all: it opens the whole catalogue as one list of every event.
    func browseOpenTypes() {
        browseScope = "all"
        browseType = "all"
        browseQuery = ""
        browseFilters = .default
    }

    /// See all carries Home's three tabs (note 85), so the reader switches tab in place. The tab is what changes: its
    /// search and its own filters start clean (the same reset `openBrowse` takes), and the type survives only where the
    /// new tab still has events of it.
    func browseSwitchScope(_ scope: String) {
        let sc = scope.isEmpty ? "all" : scope
        guard sc != browseScope else { return }
        let counts = browseTypeCounts(scope: sc)
        browseScope = sc
        browseQuery = ""
        browseFilters = .default
        if browseType != "all" && (counts[browseType] ?? 0) == 0 { browseType = "all" }
    }

    /// A type chip (note 88: "All" is every event, so the list widens in place; there is no grid in between).
    func browsePickType(_ key: String) {
        browseType = key.isEmpty ? "all" : key
    }

    /// The whole Home tab in its own order (For You ranked, else soonest), before Home's filters; open events only
    /// (not cancelled, not started more than an hour ago). Web twin: `tabItems` in Home.jsx.
    func v23TabItems(_ tab: HomeHeroTab, items: [HomeDiscovery.Item], byKey: [String: CatalogEvent],
                     forYou: [ForYouMatch], now: Date) -> [HomeDiscovery.Item] {
        // One "still on" rule with web's tabItems (UnifiedDiscovery.isOpenItem: not cancelled, a start, not past its end).
        func open(_ it: HomeDiscovery.Item) -> Bool { byKey[it.key]?.cancelled == false && UnifiedDiscovery.isOpenItem(it, now: now) }
        switch tab {
        case .tonight, .weekend:
            var f = HomeDiscovery.Filters.default
            f.date = tab == .tonight ? "today" : "weekend"
            return HomeDiscovery.apply(items, f, now: now).filter(open)
        case .foryou:
            let byItem = Dictionary(items.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
            let ranked = forYou.compactMap { byItem[$0.key] }.filter(open)
            if !ranked.isEmpty { return ranked }
            return HomeDiscovery.apply(items, .default, now: now).filter(open)
        }
    }

    /// The scope's discovery items in the scope's own order, before Browse's search and its own filters. "all" = the
    /// whole catalogue Home lists, open events only (not cancelled, not started more than an hour ago).
    func browseBaseItems(scope: String, now: Date) -> [HomeDiscovery.Item] {
        let scores = pulseScores
        let items = feed.map { discoveryItem(for: $0, now: now, scores: scores) }
        let byKey = Dictionary(feed.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        if let tab = HomeHeroTab(rawValue: scope) {
            return v23TabItems(tab, items: items, byKey: byKey, forYou: forYouMatches, now: now)
        }
        return HomeDiscovery.apply(items, .default, now: now).filter { byKey[$0.key]?.cancelled == false }
    }

    /// How many events each type has in that scope (an event's second category counts too): the type chips, the tiles
    /// and the scope switch's keep-or-drop rule all read this one count.
    func browseTypeCounts(scope: String, now: Date = Date()) -> [String: Int] {
        var out: [String: Int] = [:]
        for it in browseBaseItems(scope: scope, now: now) { for k in Set(it.catKeys) { out[k, default: 0] += 1 } }
        return out
    }

    /// The Browse scope's entries (the same discovery items Home uses, so there is no second filter path) with the
    /// words search reads and the real host.
    func browseEntries(now: Date = Date()) -> (entries: [BrowseRules.Entry], byKey: [String: CatalogEvent]) {
        let feed = self.feed
        let byKey = Dictionary(feed.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let base = browseBaseItems(scope: browseScope, now: now)
        let entries: [BrowseRules.Entry] = base.compactMap { (it: HomeDiscovery.Item) -> BrowseRules.Entry? in
            guard let e = byKey[it.key] else { return nil }
            let real = realEventsByID[it.key] ?? nil
            let orgID = e.organizerId ?? eventOrganizerID[e.key] ?? real?.organizerId
            let stats = orgID.flatMap { organizerStats[$0] }
            let name = e.orgName.isEmpty ? (real?.orgName ?? e.hostShort) : e.orgName
            return BrowseRules.Entry(item: it, name: e.name, area: e.locationLabel ?? e.location?.area ?? "",
                                     catDisplay: trStatus(e.catDisplay.isEmpty ? e.cat : e.catDisplay),
                                     // A host without a name is not shown as a face (no "·" in the deck).
                                     organizerId: name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : orgID, organizerName: name,
                                     avatarURL: MediaURLs.organizerAvatar(path: stats?.avatarPath, r2Ref: stats?.avatarR2Ref, variant: .thumb))
        }
        return (entries, byKey)
    }
}

struct BrowseView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// One route for all five Browse sheets. A single `.sheet(item:)` cannot present two at once, so a host-deck tap
    /// and a filter tap in the same run loop resolve to one route instead of fighting over separate modifiers.
    private enum SheetRoute: String, Identifiable, Equatable {
        case hosts, filters, area, types, quick
        var id: String { rawValue }
    }
    @State private var sheetRoute: SheetRoute? = nil
    /// Bumped when the reader taps the scope tab or type chip they are already on: the list goes back to its top
    /// (owner 2026-11-23 — re-choosing the current option is never a dead tap after scrolling).
    @State private var browseTopToken = 0

    private var tabLabel: ViEn? { HomeHeroTab(rawValue: app.browseScope).map { ViEn($0.vi, $0.en) } }
    /// The location picker still takes a Bool binding; it is backed by the one route so Done or a swipe clears it.
    private var areaSheetPresented: Binding<Bool> {
        Binding(get: { sheetRoute == .area }, set: { shown in if !shown { sheetRoute = nil } })
    }

    var body: some View {
        let now = Date()
        let (entries, byKey) = app.browseEntries(now: now)
        let counts = BrowseRules.typeCounts(entries)
        let typeDefs = EventTypes.categoryDefs()
        // A type the catalogue does not have falls back to the whole list; every real type keeps its list even while it
        // has nothing on, so a zero-count tile opens an honest empty list instead of bouncing back to the grid (note 87).
        let known = typeDefs.contains { $0.key == app.browseType }
        let effType = (app.browseType != "all" && !known) ? "all" : app.browseType
        let chips = typeDefs.filter { (counts[$0.key] ?? 0) > 0 }.sorted { (counts[$0.key] ?? 0) > (counts[$1.key] ?? 0) }
        // No grid (note 88): Browse by type IS the list of every event, and the type chips narrow it in place.
        let result = BrowseRules.list(entries, type: effType, query: app.browseQuery, filters: app.browseFilters, now: now)
        let hosts: [BrowseRules.Host] =
            BrowseRules.hosts(BrowseRules.list(entries, type: effType, query: "", filters: .default, now: now).list)
        let rows = result.list.compactMap { en in byKey[en.key].map { app.v23Row($0, item: en.item, now: now) } }
        let typeName = chips.first { $0.key == effType }.map { ViEn($0.vi, $0.en) } ?? HomeDiscovery.categories.first { $0.key == effType }.map { ViEn($0.vi, $0.en) }
        let others = chips.filter { $0.key != effType }.map { ListEnd.OtherType(key: $0.key, name: ViEn($0.vi, $0.en), count: counts[$0.key] ?? 0) }
        let card = ListEnd.browseEnd(type: effType, typeName: effType == "all" ? nil : typeName, count: result.list.count,
                                     hidden: result.hidden, others: others)
        let titleText = (effType != "all" ? typeName?.t(app.isEN) : nil) ?? tabLabel?.t(app.isEN) ?? app.T("Duyệt theo loại", "Browse by type")
        // Area lives in its own two pills; the filter badge counts only what the filter sheet's Reset can clear.
        let nFilters = BrowseRules.filterCount(app.browseFilters)

        VStack(spacing: 0) {
            // The tab row closes the header now that it shows on every Browse screen (note 90).
            nav
            scopeTabs
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // The screen's title, under the tabs (note 91): the same 30px line and count as a picked type's
                        // heading, so a tab names what it holds instead of leaving the top of the page to the host deck.
                        // One heading row and one filter row (the Browse list pass): the hosts' faces sit beside the
                        // title and Filters closes the chip row, where each used to take a row of its own and push
                        // the first event almost halfway down the screen.
                        listHead(titleText, count: result.list.count, hosts: hosts, now: now)
                            .id("browse.listTop")
                        areaScope
                        HStack(spacing: 0) {
                            if !chips.isEmpty || app.browseScope != "all" { typeChips(chips, counts: counts, total: entries.count, selected: effType) }
                            else { Spacer(minLength: 0) }
                            typeButton.padding(.leading, 8)
                            filtersButton(nFilters).padding(.leading, 8).padding(.trailing, 20)
                        }
                        .padding(.top, 12).padding(.bottom, 14)
                        V23Pager(items: rows, key: \.key, listID: "browse.list",
                                 row: { r in EventRowV23View(row: r, idPrefix: "browse.event", onToggleSave: { app.toggleFavorite(r.key) }) { app.goEvent(r.key) } },
                                 end: { v in EndCardView(model: card, variant: v) { onEnd($0, proxy: proxy) } },
                                 empty: { EndCardView(model: emptyCard(hidden: result.hidden), variant: .solo) { onEnd($0, proxy: proxy) } })
                        Color.clear.frame(height: 120)
                    }
                    .foregroundStyle(app.palette.ink)
                }
                .scrollDismissesKeyboard(.immediately)
                .onChange(of: browseTopToken) { _, _ in
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { proxy.scrollTo("browse.listTop", anchor: .top) }
                }
            }
        }
        .background(app.palette.paper.ignoresSafeArea())
        // A new area is a new list: return to the heading and its count instead of staying at a scroll position that
        // belonged to the old area.
        .onChange(of: app.area) { _, _ in browseTopToken += 1 }
        .sheet(item: $sheetRoute) { route in
            switch route {
            case .hosts:
                HostListSheet(hosts: hosts, title: titleText, onPick: { id in
                    sheetRoute = nil
                    app.openOrganizerProfile(organizerID: id, back: .browse)
                }, onClose: { sheetRoute = nil })
                .environmentObject(app)
            case .filters:
                NavigationStack {
                    HomeFilterSheet(items: BrowseRules.list(entries, type: effType, query: app.browseQuery, filters: .default, now: now).list.map(\.item),
                                    now: now, onClose: { sheetRoute = nil },
                                    mapFilters: BrowseRules.browseFilters(app.browseFilters),
                                    onApplyMap: { app.browseFilters = BrowseRules.browseFilters($0) },
                                    browseTitle: app.T("Lọc \(titleText)", "Filter \(titleText)"))
                }
                .environmentObject(app)
                .presentationDetents([.large])
            case .area:
                LocationPickerSheet(isPresented: areaSheetPresented, doneMode: true)
                    .environmentObject(app)
            case .types:
                BrowseTypePicker(counts: counts, total: entries.count, selected: effType,
                                 onPick: { key in
                                     app.browsePickType(key)
                                     sheetRoute = nil
                                     browseTopToken += 1
                                 }, onClose: { sheetRoute = nil })
                    .environmentObject(app)
            case .quick:
                // The same Quick settings panel Home's gear opens (owner 2026-11-18).
                QuickSheetView(onClose: { sheetRoute = nil })
                    .environmentObject(app)
            }
        }
        .accessibilityIdentifier("browse.screen")
    }

    // MARK: Home's tabs

    /// Home's three tabs and Browse by type. Text over a rule, never a pill, so this row can't be mistaken for the
    /// type chips' filter row below it. The fourth tab (note 90) opens the whole catalogue's list in place; the row
    /// shows on every Browse screen, with the tab selected on the every-event list. Back always goes Home (owner
    /// 2026-11-18), so the tab it came from only keeps its context, it is never a Back destination.
    private var scopeTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(HomeHeroTab.allCases, id: \.self) { t in
                    let on = app.browseScope == t.rawValue
                    Button {
                        // Re-tapping the open tab returns to the top of its list instead of doing nothing.
                        guard !on else { Haptics.light(); browseTopToken += 1; return }
                        Haptics.selection()
                        app.browseSwitchScope(t.rawValue)
                    } label: {
                        tabLabel(t.vi, t.en, on: on)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
                    .accessibilityIdentifier("browse.scope.\(t.rawValue)")
                }
                Button {
                    guard app.browseScope != "all" else { Haptics.light(); browseTopToken += 1; return }
                    Haptics.selection()
                    app.browseOpenTypes()
                } label: {
                    tabLabel(app.T("Duyệt theo loại", "Browse by type"), on: app.browseScope == "all")
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(app.browseScope == "all" ? [.isSelected, .isButton] : .isButton)
                .accessibilityIdentifier("browse.scope.all")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
        }
        .rootSwipeExclusion("browseScopeTabs")
        .overlay(alignment: .bottom) { Rectangle().fill(app.palette.rule).frame(height: 1) }
        .accessibilityIdentifier("browse.scopeTabs")
    }

    /// One tab's label: 16pt so all four fit a phone's width, the open one in full ink over its own rule.
    private func tabLabel(_ vi: String, _ en: String? = nil, on: Bool) -> some View {
        Text(en.map { app.T(vi, $0) } ?? vi)
            .font(.app(size: 16, weight: on ? .medium : .regular))
            .foregroundStyle(app.palette.ink.opacity(on ? 1 : 0.55))
            .lineLimit(1).fixedSize()
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) { Rectangle().fill(on ? app.palette.ink : Color.clear).frame(height: 2) }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }

    private func eventCount(_ n: Int) -> String {
        app.isEN ? "\(n) \(n == 1 ? "event" : "events")" : "\(n) sự kiện"
    }

    /// The screen's own title, under the tabs (note 91): a picked type's name, else the open tab's, else "Browse by
    /// type". Under it one line that says what the list holds — the weekend's or tonight's real dates on those tabs,
    /// then the count and the area. The hosts' faces sit on the same row and open the host list.
    private func listHead(_ title: String, count n: Int, hosts: [BrowseRules.Host], now: Date) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.app(size: 30)).tracking(-0.6).lineLimit(1).minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("browse.title")
                Text([BrowseDates.label(scope: app.browseScope, now: now, english: app.isEN), eventCount(n),
                      app.area == LocationHierarchy.allID ? nil : app.currentAreaLabel].compactMap { $0 }.joined(separator: " · "))
                    .font(.app(size: 13)).opacity(0.72).padding(.top, 6)
                    .accessibilityIdentifier("browse.scopeCount")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !hosts.isEmpty { HostDeckView(hosts: hosts) { sheetRoute = .hosts } }
        }
        .padding(.horizontal, 20).padding(.top, 18)
    }

    // MARK: parts

    /// Always Home now (owner 2026-11-18): Home and Browse are one tab, so Back never loops through Browse's own tabs.
    private var backLabel: String { app.T("Về Trang chủ", "Back to Home") }

    /// One row, the same 58 pt bar and 16 pt edges as Home's (owner 2026-11-18): the top-right cluster is the same three
    /// controls, in the same place, with the same styling on both screens, so moving between Home and Browse never
    /// shifts or restyles it — the screens cross-fade underneath it. Search opens the same search Home's magnifier
    /// does; the gear opens the same Quick settings sheet Home's gear does.
    private var nav: some View {
        HStack(spacing: 8) {
            HeaderCircleButton(system: "chevron.left", label: backLabel, id: "browse.back") { app.backFromBrowse() }
            Spacer(minLength: 0)
            HeaderCircleButton(system: "magnifyingglass", label: app.T("Tìm sự kiện", "Search events"), id: "browse.search",
                               accent: true, measureFrame: true) {
                app.openSearch(from: app.homeSearchBarFrame)
            }
            HeaderCircleButton(system: "map", label: app.T("Bản đồ", "Map"), id: "browse.map") { app.goMapExploreFromHome() }
            HeaderCircleButton(system: "gearshape.fill", label: app.T("Cài đặt nhanh", "Quick settings"), id: "browse.quick") {
                sheetRoute = .quick
            }
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 16)
        .frame(height: 58)
        .background(app.palette.paper)
        .accessibilityIdentifier("browse.nav")
    }

    // MARK: Area scope / type picker

    /// Browse opens on the area the reader came from and offers the two choices explicitly: stay in this area, or
    /// widen to every area. The filter sheet keeps the full picker for a specific area.
    private var areaScope: some View {
        let active = app.area != LocationHierarchy.allID
        return HStack(spacing: 8) {
            Button { Haptics.selection(); sheetRoute = .area } label: {
                areaPill(active ? app.currentAreaLabel : app.T("Chọn khu vực", "Choose area"), active: active, icon: "mappin")
            }
            .buttonStyle(.plain)
            // Each pill hugs its own words (web twin: inline-flex). Without this the row's spare width is handed to
            // one flexible button, which is what stretched "All areas" into a long dark bar.
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityAddTraits(active ? .isSelected : [])
            .accessibilityIdentifier("browse.area.current")

            Button {
                Haptics.selection()
                // Re-choosing the option already on is never a dead tap (note 96).
                if active { browseTopToken += 1 } else { app.pickArea(LocationHierarchy.allID) }
            } label: {
                areaPill(app.T("Tất cả khu vực", "All areas"), active: !active)
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityAddTraits(!active ? .isSelected : [])
            .accessibilityIdentifier("browse.area.all")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.top, 10)
        .accessibilityIdentifier("browse.areaScope")
    }

    private func areaPill(_ title: String, active: Bool, icon: String? = nil) -> some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).font(.app(size: 12, weight: .medium)) }
            // The label cap keeps a long area name from pushing the second pill off a 375 pt-wide phone.
            Text(title).font(.app(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: 150, alignment: .leading)
        }
        .foregroundStyle(active ? app.palette.paper : app.palette.ink)
        .padding(.horizontal, 13).frame(minHeight: 40)
        .background(active ? app.palette.ink : Color.clear, in: Capsule())
        .overlay(Capsule().strokeBorder(active ? Color.clear : app.palette.rule, lineWidth: 1))
        .contentShape(Capsule())
    }

    /// The type chips scroll horizontally; this button opens the whole list so a type that is off-screen is still one
    /// tap away, with its glyph and count.
    private var typeButton: some View {
        Button { Haptics.selection(); sheetRoute = .types } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.2x2").font(.app(size: 14, weight: .medium))
                Text(app.T("Loại", "Type")).font(.app(size: 13.5, weight: .semibold))
                Image(systemName: "chevron.down").font(.app(size: 9, weight: .semibold)).opacity(0.55)
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 12).frame(height: 40)
            .background(app.palette.ink.opacity(0.07), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(app.T("Chọn loại sự kiện", "Choose event type"))
        .accessibilityIdentifier("browse.typeButton")
    }

    private func typeChips(_ chips: [(key: String, vi: String, en: String)], counts: [String: Int], total: Int, selected: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(key: "all", title: app.T("Tất cả", "All"), n: total, on: selected == "all")
                ForEach(chips, id: \.key) { (d: (key: String, vi: String, en: String)) in chip(key: d.key, title: app.T(d.vi, d.en), n: counts[d.key] ?? 0, on: selected == d.key) }
            }
            .padding(.leading, 20).padding(.trailing, 16)
        }
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.93), .init(color: .clear, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
        .rootSwipeExclusion("browseTypeChips")
        .accessibilityIdentifier("browse.typeChips")
    }

    private func chip(key: String, title: String, n: Int, on: Bool) -> some View {
        Button {
            Haptics.selection()
            // Re-tapping the open chip returns to the top of its list instead of doing nothing.
            if on { browseTopToken += 1 } else { app.browsePickType(key) }
        } label: {
            HStack(spacing: 6) {
                if key != "all" { Image(systemName: CategoryGlyph.symbol(key)).font(.app(size: 14)) }
                Text(title).font(.app(size: 14, weight: .semibold))
                Text("\(n)").font(.app(size: 14, weight: .medium)).monospacedDigit().opacity(0.7)
            }
            .foregroundStyle(on ? app.palette.paper : app.palette.ink)
            .padding(.horizontal, 14).frame(minHeight: 44)
            .background(on ? app.palette.ink : .clear, in: Capsule())
            .overlay(Capsule().stroke(on ? .clear : app.palette.rule, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("browse.type.\(key)")
    }

    /// Filters closes the chip row: an icon the size of the nav circles, with the number of filters on as a badge.
    private func filtersButton(_ n: Int) -> some View {
        Button { sheetRoute = .filters } label: {
            Image(systemName: "slider.horizontal.3").font(.app(size: 16, weight: .medium))
                .frame(width: 40, height: 40)
                .background(app.palette.ink.opacity(0.07), in: Circle())
                .overlay(alignment: .topTrailing) {
                    if n > 0 {
                        Text("\(n)").font(.app(size: 11, weight: .bold)).monospacedDigit().foregroundStyle(app.palette.paper)
                            .frame(minWidth: 18, minHeight: 18).padding(.horizontal, 2).background(app.palette.ink, in: Capsule())
                            .overlay(Capsule().stroke(app.palette.paper, lineWidth: 2))
                            .offset(x: 4, y: -4)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(n > 0 ? app.T("Bộ lọc, đang bật \(n)", "Filters, \(n) on") : app.T("Bộ lọc", "Filters"))
        .accessibilityIdentifier("browse.filtersButton")
    }

    private func emptyCard(hidden: Int) -> EndCardModel {
        if hidden > 0 {
            return EndCardModel(kind: "empty", eyebrow: ViEn("Bộ lọc", "Filters"),
                                title: ViEn("Không có sự kiện nào khớp bộ lọc.", "None of these match your filters."),
                                body: ViEn("Xoá bộ lọc để xem lại mọi thứ.", "Clear the filters to see everything again."),
                                actions: [.init(act: "clear-filters", label: ViEn("Xoá bộ lọc", "Clear filters"), primary: true, testId: "browse.emptyClear")])
        }
        // An empty list is never a dead end (note 91): the card offers the next real step — another area, another tab,
        // the whole catalogue, the map, hosting — the same way the end cards do. An area with nothing on gets "All areas"
        // first, so the reader is not stuck in a narrower area.
        let areaAll: EndCardModel.Action? = app.area == LocationHierarchy.allID ? nil
            : .init(act: "area:all", label: ViEn("Xem mọi khu vực", "All areas"), primary: true, testId: "browse.emptyAllAreas")
        func withArea(_ list: [EndCardModel.Action]) -> [EndCardModel.Action] {
            guard let areaAll = areaAll else { return list }
            return [areaAll] + list.map { item in
                var next = item
                next.primary = false
                return next
            }
        }
        let actions: [EndCardModel.Action]
        if app.browseScope == "all" {
            actions = withArea(app.browseType != "all"
                ? [.init(act: "type:all", label: ViEn("Xem mọi loại", "See every type"), primary: true),
                   .init(act: "map", label: ViEn("Mở bản đồ", "Open the map"))]
                : [.init(act: "map", label: ViEn("Mở bản đồ", "Open the map"), primary: true),
                   .init(act: "host", label: ViEn("Tổ chức một buổi", "Host a night"))])
        } else if app.browseScope == "weekend" {
            actions = withArea([.init(act: "type:all", label: ViEn("Xem mọi loại", "See every type"), primary: true),
                                .init(act: "map", label: ViEn("Mở bản đồ", "Open the map"))])
        } else {
            actions = withArea([.init(act: "scope:weekend", label: ViEn("Xem cuối tuần", "See this weekend"), primary: true),
                                .init(act: "browse-types", label: ViEn("Duyệt theo loại", "Browse by type")),
                                .init(act: "map", label: ViEn("Mở bản đồ", "Open the map"))])
        }
        return EndCardModel(kind: "empty", eyebrow: ViEn("Sắp có", "Coming up"), title: ViEn("Chưa có gì ở đây.", "Nothing here yet."),
                            body: ViEn("Sự kiện mới sẽ hiện ở đây khi chủ nhà đăng. Trong lúc chờ, thử một chỗ khác.",
                                       "New events show up here when hosts post them. Meanwhile, try somewhere else."),
                            actions: actions)
    }

    private func onEnd(_ act: String, proxy: ScrollViewProxy) {
        switch act {
        case "clear-filters": app.browseFilters = .default
        case "area:all": app.pickArea(LocationHierarchy.allID)
        case "map": app.goMapExploreFromHome()
        // The same Start hosting path the dock "+" and Home's locked Hosting use (web twin: startHosting({ land: 'home' })):
        // guest -> sign-in prompt, organizer mode off -> the start-hosting invitation, on -> Home > Hosting.
        case "host": app.startHosting()
        case "browse-types": app.browseOpenTypes()
        default:
            if act.hasPrefix("type:") {
                app.browsePickType(String(act.dropFirst(5)))
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { proxy.scrollTo("browse.listTop", anchor: .top) }
            } else if act.hasPrefix("scope:") {
                app.browseSwitchScope(String(act.dropFirst(6)))
            }
        }
    }
}

// MARK: - Dates under the title

/// What a tab's dates really are, for the line under its title: the weekend's days (the same Friday 17:00 to Sunday
/// window the Weekend tab filters on), today's date for Tonight, nothing for the other lists.
enum BrowseDates {
    static func label(scope: String, now: Date, english: Bool, offsetMin: Int = HomeDiscovery.defaultOffsetMin) -> String? {
        let option = scope == "weekend" ? "weekend" : scope == "tonight" ? "today" : nil
        guard let option, let w = HomeDiscovery.dateWindow(option, now: now, offsetMin: offsetMin) else { return nil }
        let zone = TimeZone(secondsFromGMT: offsetMin * 60) ?? .current
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        let last = w.end.addingTimeInterval(-1)
        func text(_ d: Date, _ format: String) -> String {
            let f = DateFormatter()
            f.calendar = cal; f.timeZone = zone
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = format
            return f.string(from: d)
        }
        // Vietnamese days the way the rows write them: T2 … T7, CN.
        func vi(_ d: Date) -> String {
            let c = cal.dateComponents([.weekday, .day, .month], from: d)
            return "\(["CN", "T2", "T3", "T4", "T5", "T6", "T7"][((c.weekday ?? 1) - 1) % 7]) \(c.day ?? 0)/\(c.month ?? 0)"
        }
        let oneDay = cal.isDate(w.start, inSameDayAs: last)
        if !english { return oneDay ? vi(last) : vi(w.start) + " – " + vi(last) }
        if oneDay { return text(last, "EEE d MMM") }
        let sameMonth = cal.component(.month, from: w.start) == cal.component(.month, from: last)
        return text(w.start, sameMonth ? "EEE d" : "EEE d MMM") + " – " + text(last, "EEE d MMM")
    }
}

// MARK: - Host deck + list

/// A host's face: their real photo, else a monogram on a theme tint.
struct HostFace: View {
    @EnvironmentObject private var app: AppState
    let host: BrowseRules.Host
    var size: CGFloat = 34
    var ring: Color? = nil

    var body: some View {
        let tints = [app.palette.clay, app.palette.update, app.palette.honey, app.palette.plum]
        ZStack {
            Circle().fill(tints[BrowseRules.tintIndex(host.name, tints.count)])
            if let url = host.avatarURL {
                RemoteImage(path: url.absoluteString, maxPixel: size * 3)
            } else {
                Text(String(host.name.trimmingCharacters(in: .whitespaces).first ?? "·").uppercased())
                    .font(.app(size: size * 0.42, weight: .bold)).foregroundStyle(app.palette.paper)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(ring ?? app.palette.paper, lineWidth: ring == .clear ? 0 : 2))
        .accessibilityHidden(true)
    }
}

/// Overlapping host faces, then +N, beside the list's title. Turns over one face every few seconds (never with
/// Reduce Motion). A tap opens the searchable host list, which is where the names are.
struct HostDeckView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let hosts: [BrowseRules.Host]
    let onOpen: () -> Void
    @State private var order: [BrowseRules.Host] = []

    var body: some View {
        if !hosts.isEmpty {
            let deck = BrowseRules.deckFaces(order.isEmpty ? hosts : order, shown: 3)
            Button(action: onOpen) {
                HStack(spacing: 0) {
                    HStack(spacing: -10) {
                        ForEach(Array(deck.faces.enumerated()), id: \.element.id) { i, h in
                            HostFace(host: h).zIndex(Double(deck.faces.count - i))
                        }
                        if deck.more > 0 {
                            Text("+\(deck.more)").font(.app(size: 12.5, weight: .bold))
                                .padding(.horizontal, 8).frame(minWidth: 34, minHeight: 34)
                                .background(app.palette.block, in: Capsule())
                                .overlay(Capsule().stroke(app.palette.paper, lineWidth: 2))
                        }
                    }
                    .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.6), value: order.map(\.id))
                }
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(app.T("Xem cả \(hosts.count) host", "See all \(hosts.count) \(hosts.count == 1 ? "host" : "hosts")"))
            .accessibilityIdentifier("browse.hostDeck")
            .onAppear { order = hosts }
            .onChange(of: hosts.map(\.id)) { _, _ in order = hosts }
            .task(id: hosts.map(\.id)) {
                guard !reduceMotion, hosts.count > 1 else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 3_200_000_000)
                    if Task.isCancelled { break }
                    order = BrowseRules.rotate(order.isEmpty ? hosts : order)
                }
            }
        }
    }
}

/// All the hosts of a Browse list: searchable by name (accent-insensitive), each with how many of these events they
/// host. A tap opens the real host profile; its Back returns to Browse.
struct HostListSheet: View {
    @EnvironmentObject private var app: AppState
    let hosts: [BrowseRules.Host]
    let title: String
    let onPick: (String) -> Void
    let onClose: () -> Void
    @State private var q = ""

    var body: some View {
        let rows = BrowseRules.filterHosts(hosts, q)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.T("\(hosts.count) host", "\(hosts.count) \(hosts.count == 1 ? "host" : "hosts")")).font(.app(size: 18, weight: .semibold))
                    Text(title).font(.app(size: 13)).opacity(0.72)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.app(size: 15, weight: .semibold))
                        .frame(width: 44, height: 44).background(app.palette.ink.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(app.T("Đóng", "Close"))
                .accessibilityIdentifier("hostList.close")
            }
            .padding(.leading, 20).padding(.trailing, 16).padding(.top, 14).padding(.bottom, 6)
            TextField(app.T("Tìm host theo tên", "Search hosts by name"), text: $q)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .font(.app(size: 15))
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(app.palette.field, in: Capsule())
                .overlay(Capsule().stroke(app.palette.rule, lineWidth: 1))
                .padding(.horizontal, 20).padding(.vertical, 6)
                .accessibilityIdentifier("hostList.search")
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(rows) { h in
                        Button { onPick(h.id) } label: {
                            HStack(spacing: 12) {
                                HostFace(host: h, size: 40, ring: .clear)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(h.name).font(.app(size: 15, weight: .semibold)).lineLimit(1)
                                    Text(app.T("\(h.events.count) sự kiện ở đây", "\(h.events.count) \(h.events.count == 1 ? "event" : "events") here"))
                                        .font(.app(size: 12.5)).opacity(0.72)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.app(size: 12)).opacity(0.5)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 6).frame(minHeight: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("hostList.row.\(h.id)")
                    }
                    if rows.isEmpty {
                        Text(app.T("Không có host nào tên “\(q.trimmingCharacters(in: .whitespaces))”.", "No host called “\(q.trimmingCharacters(in: .whitespaces))”."))
                            .font(.app(size: 14)).opacity(0.72).padding(.horizontal, 12).padding(.vertical, 18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 24)
            }
        }
        .foregroundStyle(app.palette.ink)
        .presentationDetents([.large])
        .presentationBackground(app.palette.paper)
        .accessibilityIdentifier("hostList.sheet")
    }
}

/// Every type in the catalogue, with its glyph and live count: the reliable way to change type when the horizontal
/// chip strip has scrolled a choice off-screen. Zero-count types stay listed (muted) because picking one still opens
/// its honest empty list (note 87).
private struct BrowseTypePicker: View {
    @EnvironmentObject private var app: AppState
    let counts: [String: Int]
    let total: Int
    let selected: String
    let onPick: (String) -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    row(key: "all", title: app.T("Tất cả", "All"), n: total)
                    ForEach(EventTypes.categoryDefs(), id: \.key) { d in
                        row(key: d.key, title: app.T(d.vi, d.en), n: counts[d.key] ?? 0)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
            }
            .background(app.palette.paper.ignoresSafeArea())
            .navigationTitle(app.T("Loại sự kiện", "Event type"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.app(size: 15, weight: .semibold))
                    }
                    .accessibilityLabel(app.T("Đóng", "Close"))
                    .accessibilityIdentifier("browse.typeClose")
                }
            }
        }
        .tint(app.palette.ink)
        .foregroundStyle(app.palette.ink)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(app.palette.paper)
        .accessibilityIdentifier("browse.typeSheet")
    }

    private func row(key: String, title: String, n: Int) -> some View {
        let on = selected == key
        return Button {
            Haptics.selection()
            onPick(key)
        } label: {
            HStack(spacing: 12) {
                Group {
                    if key == "all" { Image(systemName: "square.grid.2x2") }
                    else { Image(systemName: CategoryGlyph.symbol(key)) }
                }
                .font(.app(size: 16))
                .frame(width: 22)
                Text(title).font(.app(size: 16))
                Spacer(minLength: 8)
                Text("\(n)").font(.app(size: 13)).monospacedDigit().opacity(0.6)
                Image(systemName: "checkmark").font(.app(size: 14, weight: .semibold)).opacity(on ? 1 : 0)
            }
            .foregroundStyle(app.palette.ink.opacity(key != "all" && n == 0 ? 0.55 : 1))
            .frame(minHeight: 52)
            .overlay(alignment: .bottom) { Rectangle().fill(app.palette.rule).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("browse.typeOption.\(key)")
    }
}
