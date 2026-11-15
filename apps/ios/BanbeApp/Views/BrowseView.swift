import SwiftUI

// Browse by type / See all (v2.3, note 81, switch home_v23). Web twin: src/screens/Browse.jsx. One screen for both:
// "Browse by type" lists the whole catalogue, "See all" one Home tab with type chips counted inside that tab. Under the
// title a deck of host faces (a tap lists the hosts, a host opens their real profile). The magnifier turns the title
// into a search field. Its own Filters (When, Price, Seats). Four rows a page with the swipe signs, then an end card.
// Rules: Lib/V23Rules.swift (BrowseRules, Pager, ListEnd).

extension AppState {
    func openBrowse(type: String = "all", scope: String = "all", keep: Bool = false) {
        let t = type.isEmpty ? "all" : type, sc = scope.isEmpty ? "all" : scope
        let same = keep && browseType == t && browseScope == sc
        browseType = t
        browseScope = sc
        if !same { browseQuery = ""; browseFilters = .default }
        browseShowTypes = false
        homeFilterSheetOpen = false
        screen = .browse
    }

    func backFromBrowse() { screen = .home }

    /// The whole Home tab in its own order (For You ranked, else soonest), before Home's filters; open events only
    /// (not cancelled, not started more than an hour ago). Web twin: `tabItems` in Home.jsx.
    func v23TabItems(_ tab: HomeHeroTab, items: [HomeDiscovery.Item], byKey: [String: CatalogEvent],
                     forYou: [ForYouMatch], now: Date) -> [HomeDiscovery.Item] {
        func open(_ it: HomeDiscovery.Item) -> Bool {
            guard byKey[it.key]?.cancelled == false, let start = it.startsAt else { return false }
            return start >= now.addingTimeInterval(-3600)
        }
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

    /// The Browse scope's entries (the same discovery items Home uses, so there is no second filter path) with the
    /// words search reads and the real host.
    func browseEntries(now: Date = Date()) -> (entries: [BrowseRules.Entry], byKey: [String: CatalogEvent]) {
        let feed = self.feed
        let scores = pulseScores
        let items = feed.map { discoveryItem(for: $0, now: now, scores: scores) }
        let byKey = Dictionary(feed.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let base: [HomeDiscovery.Item]
        if let tab = HomeHeroTab(rawValue: browseScope) {
            base = v23TabItems(tab, items: items, byKey: byKey, forYou: forYouMatches, now: now)
        } else {
            base = HomeDiscovery.apply(items, .default, now: now).filter { byKey[$0.key]?.cancelled == false }
        }
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
    @State private var finding = false
    @State private var hostsOpen = false
    @State private var filtersOpen = false
    @FocusState private var searchFocused: Bool

    private var tabLabel: ViEn? { HomeHeroTab(rawValue: app.browseScope).map { ViEn($0.vi, $0.en) } }

    var body: some View {
        let now = Date()
        let (entries, byKey) = app.browseEntries(now: now)
        let counts = BrowseRules.typeCounts(entries)
        let effType = app.browseType != "all" && (counts[app.browseType] ?? 0) == 0 ? "all" : app.browseType
        let chips = EventTypes.categoryDefs().filter { (counts[$0.key] ?? 0) > 0 }.sorted { (counts[$0.key] ?? 0) > (counts[$1.key] ?? 0) }
        let result = BrowseRules.list(entries, type: effType, query: app.browseQuery, filters: app.browseFilters, now: now)
        let hosts = BrowseRules.hosts(BrowseRules.list(entries, type: effType, query: "", filters: .default, now: now).list)
        let rows = result.list.compactMap { en in byKey[en.key].map { app.v23Row($0, item: en.item, now: now) } }
        let typeName = chips.first { $0.key == effType }.map { ViEn($0.vi, $0.en) } ?? HomeDiscovery.categories.first { $0.key == effType }.map { ViEn($0.vi, $0.en) }
        let others = chips.filter { $0.key != effType }.map { ListEnd.OtherType(key: $0.key, name: ViEn($0.vi, $0.en), count: counts[$0.key] ?? 0) }
        let card = ListEnd.browseEnd(type: effType, typeName: effType == "all" ? nil : typeName, count: result.list.count,
                                     hidden: result.hidden, query: app.browseQuery, others: others)
        let titleText = (effType != "all" ? typeName?.t(app.isEN) : nil) ?? tabLabel?.t(app.isEN) ?? app.T("Mọi sự kiện", "All events")
        let kicker = tabLabel.map { app.T("Xem tất cả · \($0.vi)", "See all · \($0.en)") } ?? app.T("Duyệt theo loại", "Browse by type")
        let q = app.browseQuery.trimmingCharacters(in: .whitespaces)
        let navTitle = !q.isEmpty ? "“\(q)” · \(titleText)" : (tabLabel != nil && effType != "all" ? "\(tabLabel!.t(app.isEN)) · \(titleText)" : titleText)
        let nFilters = BrowseRules.filterCount(app.browseFilters)
        // In the type grid the header describes the whole scope (the tiles carry their own per-type counts).
        let headCount = app.browseShowTypes ? entries.count : result.list.count

        VStack(spacing: 0) {
            nav(navTitle)
            viewSwitch
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(kicker.uppercased()).font(.app(size: 11, weight: .bold)).tracking(1.1).opacity(0.72)
                            Text(titleText).font(.app(size: 30)).tracking(-0.6).padding(.top, 4).padding(.bottom, 10)
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityIdentifier("browse.title")
                            HostDeckView(hosts: hosts) { hostsOpen = true }
                            Text([app.T("\(headCount) sự kiện", "\(headCount) \(headCount == 1 ? "event" : "events")"),
                                  app.area == LocationHierarchy.allID ? nil : app.currentAreaLabel].compactMap { $0 }.joined(separator: " · "))
                                .font(.app(size: 13)).opacity(0.72).padding(.top, 6)
                        }
                        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 8)
                        if app.browseShowTypes {
                            typeGrid(chips, counts: counts)
                        } else {
                            if !chips.isEmpty { typeChips(chips, counts: counts, total: entries.count, selected: effType) }
                            HStack {
                                (Text("\(result.list.count)").bold() + Text(" " + app.T("sự kiện", result.list.count == 1 ? "event" : "events")))
                                    .font(.app(size: 14))
                                    .accessibilityIdentifier("browse.count")
                                Spacer()
                                filtersButton(nFilters)
                            }
                            .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 12)
                            .id("browse.listTop")
                            V23Pager(items: rows, key: \.key, listID: "browse.list", hints: true,
                                     row: { r in EventRowV23View(row: r, idPrefix: "browse.event") { app.goEvent(r.key) } },
                                     end: { v in EndCardView(model: card, variant: v) { onEnd($0, proxy: proxy) } },
                                     empty: { EndCardView(model: emptyCard(hidden: result.hidden), variant: .solo) { onEnd($0, proxy: proxy) } })
                        }
                        Color.clear.frame(height: 120)
                    }
                    .foregroundStyle(app.palette.ink)
                }
                .scrollDismissesKeyboard(.immediately)
            }
        }
        .background(app.palette.paper.ignoresSafeArea())
        .sheet(isPresented: $hostsOpen) {
            HostListSheet(hosts: hosts, title: titleText, onPick: { id in
                hostsOpen = false
                app.openOrganizerProfile(organizerID: id, back: .browse)
            }, onClose: { hostsOpen = false })
            .environmentObject(app)
        }
        .sheet(isPresented: $filtersOpen) {
            NavigationStack {
                HomeFilterSheet(items: BrowseRules.list(entries, type: effType, query: app.browseQuery, filters: .default, now: now).list.map(\.item),
                                now: now, onClose: { filtersOpen = false },
                                mapFilters: BrowseRules.browseFilters(app.browseFilters),
                                onApplyMap: { app.browseFilters = BrowseRules.browseFilters($0) },
                                browseTitle: app.T("Lọc \(titleText)", "Filter \(titleText)"))
            }
            .environmentObject(app)
            .presentationDetents([.large])
        }
        .accessibilityIdentifier("browse.screen")
    }

    // MARK: Events | By type

    /// The screen's two views, in the type chips' own look: the scoped list (Events), or the same scope as its type
    /// grid (By type). Copy follows note 57 (no dash or semicolon between ideas).
    private var viewSwitch: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                viewChip(app.T("Sự kiện", "Events"), key: "events", on: !app.browseShowTypes) { app.browseShowTypes = false }
                viewChip(app.T("Theo loại", "By type"), key: "types", on: app.browseShowTypes) { app.browseShowTypes = true }
            }
            .padding(.horizontal, 20).padding(.top, 10)
        }
        .rootSwipeExclusion("browseViewSwitch")
        .accessibilityIdentifier("browse.viewSwitch")
    }

    private func viewChip(_ title: String, key: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button { Haptics.selection(); action() } label: {
            Text(title).font(.app(size: 14, weight: .semibold))
                .foregroundStyle(on ? app.palette.paper : app.palette.ink)
                .padding(.horizontal, 16).frame(minHeight: 44)
                .background(on ? app.palette.ink : .clear, in: Capsule())
                .overlay(Capsule().stroke(on ? .clear : app.palette.rule, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("browse.view.\(key)")
    }

    private func eventCount(_ n: Int) -> String {
        app.isEN ? "\(n) \(n == 1 ? "event" : "events")" : "\(n) sự kiện"
    }

    /// Every type with an event in this scope, most events first, in Home's Browse by type tiles. A tile opens the
    /// scoped list for that type, the same step the type chips take.
    @ViewBuilder
    private func typeGrid(_ chips: [(key: String, vi: String, en: String)], counts: [String: Int]) -> some View {
        if chips.isEmpty {
            Text(app.T("Chưa có gì ở đây.", "Nothing here yet."))
                .font(.app(size: 14)).opacity(0.72)
                .padding(.horizontal, 20).padding(.top, 18)
                .accessibilityIdentifier("browse.typeGrid.empty")
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4, alignment: .top), count: 3), spacing: 4) {
                ForEach(chips, id: \.key) { (d: (key: String, vi: String, en: String)) in
                    Button {
                        Haptics.selection()
                        app.browseType = d.key
                        app.browseShowTypes = false
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: CategoryGlyph.symbol(d.key)).font(.app(size: 24, weight: .light)).frame(width: 52, height: 52)
                            Text(app.T(d.vi, d.en)).font(.app(size: 13)).lineLimit(1).minimumScaleFactor(0.8)
                            Text(eventCount(counts[d.key] ?? 0)).font(.app(size: 11.5)).opacity(0.64).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14).padding(.bottom, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("browse.grid.\(d.key)")
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 20).padding(.top, 10)
            .accessibilityIdentifier("browse.typeGrid")
        }
    }

    // MARK: parts

    private func nav(_ title: String) -> some View {
        HStack(spacing: 8) {
            circle("chevron.left", label: app.T("Về Trang chủ", "Back to Home"), id: "browse.back") { app.backFromBrowse() }
            if finding {
                TextField(app.T("Tìm trong các sự kiện này", "Search these events"), text: $app.browseQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($searchFocused)
                    .onSubmit { finding = false }
                    .font(.app(size: 16))
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(app.palette.field, in: Capsule())
                    .overlay(Capsule().stroke(app.palette.rule, lineWidth: 1))
                    .accessibilityIdentifier("browse.searchInput")
            } else {
                Text(title).font(.app(size: 16, weight: .semibold)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("browse.navTitle")
            }
            circle(finding ? "xmark" : "magnifyingglass",
                   label: finding ? app.T("Xoá tìm kiếm", "Clear search") : app.T("Tìm trong các sự kiện này", "Search these events"),
                   id: "browse.search") {
                if finding { app.browseQuery = ""; finding = false } else { finding = true; DispatchQueue.main.async { searchFocused = true } }
            }
            circle("map", label: app.T("Xem trên bản đồ", "See on the map"), id: "browse.map") { app.goMapExploreFromHome() }
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 8)
        .background(app.palette.paper)
        .overlay(alignment: .bottom) { Rectangle().fill(app.palette.rule).frame(height: 1) }
    }

    private func circle(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.app(size: 16, weight: .medium))
                .frame(width: 44, height: 44)
                .background(app.palette.ink.opacity(0.07), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private func typeChips(_ chips: [(key: String, vi: String, en: String)], counts: [String: Int], total: Int, selected: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(key: "all", title: app.T("Tất cả", "All"), n: total, on: selected == "all")
                ForEach(chips, id: \.key) { (d: (key: String, vi: String, en: String)) in chip(key: d.key, title: app.T(d.vi, d.en), n: counts[d.key] ?? 0, on: selected == d.key) }
            }
            .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 10)
        }
        .rootSwipeExclusion("browseTypeChips")
        .accessibilityIdentifier("browse.typeChips")
    }

    private func chip(key: String, title: String, n: Int, on: Bool) -> some View {
        Button { Haptics.selection(); app.browseType = key } label: {
            HStack(spacing: 6) {
                if key != "all" { Image(systemName: CategoryGlyph.symbol(key)).font(.app(size: 13)) }
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

    private func filtersButton(_ n: Int) -> some View {
        Button { filtersOpen = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3").font(.app(size: 15))
                Text(app.T("Bộ lọc", "Filters")).font(.app(size: 14, weight: .semibold))
                if n > 0 {
                    Text("\(n)").font(.app(size: 12, weight: .bold)).foregroundStyle(app.palette.paper)
                        .frame(minWidth: 20, minHeight: 20).padding(.horizontal, 3).background(app.palette.ink, in: Capsule())
                }
            }
            .padding(.horizontal, 14).frame(minHeight: 44)
            .background(app.palette.block, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(n > 0 ? app.T("Bộ lọc, đang bật \(n)", "Filters, \(n) on") : app.T("Bộ lọc", "Filters"))
        .accessibilityIdentifier("browse.filtersButton")
    }

    private func emptyCard(hidden: Int) -> EndCardModel {
        let q = app.browseQuery.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            return EndCardModel(kind: "empty", eyebrow: ViEn("Tìm kiếm", "Search"),
                                title: ViEn("Không có sự kiện nào khớp “\(q)”.", "No events match “\(q)”."),
                                body: ViEn("Thử tên khác, một khu vực hoặc một loại sự kiện.", "Try another name, an area or a type."),
                                actions: [.init(act: "clear-search", label: ViEn("Xoá tìm kiếm", "Clear search"), primary: true, testId: "browse.emptyClear")])
        }
        if hidden > 0 {
            return EndCardModel(kind: "empty", eyebrow: ViEn("Bộ lọc", "Filters"),
                                title: ViEn("Không có sự kiện nào khớp bộ lọc.", "None of these match your filters."),
                                body: ViEn("Xoá bộ lọc để xem lại mọi thứ.", "Clear the filters to see everything again."),
                                actions: [.init(act: "clear-filters", label: ViEn("Xoá bộ lọc", "Clear filters"), primary: true, testId: "browse.emptyClear")])
        }
        return EndCardModel(kind: "empty", eyebrow: ViEn("Sắp có", "Coming up"), title: ViEn("Chưa có gì ở đây.", "Nothing here yet."),
                            body: ViEn("Sự kiện mới sẽ hiện ở đây khi chủ nhà đăng.", "New events show up here when hosts post them."), actions: [])
    }

    private func onEnd(_ act: String, proxy: ScrollViewProxy) {
        switch act {
        case "clear-filters": app.browseFilters = .default
        case "clear-search": app.browseQuery = ""; finding = false
        case "map": app.goMapExploreFromHome()
        case "host": app.goCreate()
        default:
            if act.hasPrefix("type:") {
                app.browseType = String(act.dropFirst(5))
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { proxy.scrollTo("browse.listTop", anchor: .top) }
            }
        }
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

/// Four overlapping host faces, then +N, with "A, B and 16 more hosts". Turns over one face every few seconds (never
/// with Reduce Motion). A tap opens the searchable host list.
struct HostDeckView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let hosts: [BrowseRules.Host]
    let onOpen: () -> Void
    @State private var order: [BrowseRules.Host] = []

    var body: some View {
        if !hosts.isEmpty {
            let deck = BrowseRules.deckFaces(order.isEmpty ? hosts : order)
            let line = BrowseRules.deckLine(hosts)
            Button(action: onOpen) {
                HStack(spacing: 12) {
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
                    VStack(alignment: .leading, spacing: 0) {
                        Text(line.names.t(app.isEN)).font(.app(size: 14, weight: .semibold)).lineLimit(1)
                        if !line.more.en.isEmpty { Text(line.more.t(app.isEN)).font(.app(size: 12.5)).opacity(0.72) }
                    }
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
