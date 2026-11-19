import SwiftUI

// Search screen (note 50) — replaces "the magnifier opens Map". Web twin: src/screens/Search.jsx (/search).
// Empty query: recent searches (this device only), categories, trending (Banbe Pulse).
// Typing: live results from the ONE shared matcher (Lib/Search.swift — the same documents Map searches),
// grouped Events · Hosts · Areas, each with its count. "See on map" carries the query to Map.
// Search never counts toward the streak (note 36).
struct SearchView: View {
    @State private var categorySheetOpen = false
    /// Note 99: the shared Filters sheet opened from Search's Filters row.
    @State private var udFilterSheetOpen = false
    @EnvironmentObject private var app: AppState
    /// Shown over Home (RootView) instead of as its own screen.
    let isOverlay: Bool
    /// Prototype v2 (note 99): the unified bottom sheet — its own grabber, in-sheet field and Xong, no shared bar.
    let unifiedSheet: Bool
    init(isOverlay: Bool = false, unifiedSheet: Bool = false) {
        self.isOverlay = isOverlay
        self.unifiedSheet = unifiedSheet
    }
    @FocusState private var sheetFocused: Bool
    /// Note 99: the sheet's field edits this local text; `app.searchQuery` follows debounced, so a keystroke does not
    /// re-render Home and the Map underneath.
    @State private var text = ""
    @State private var pushTask: Task<Void, Never>?

    /// The persistent bar's focus (the field itself lives in RootView, see PersistentSearchBar).
    private var focused: Bool {
        get { app.searchBarFocused }
        nonmutating set { app.searchBarFocused = newValue }
    }
    /// Entrance from Home's search bar: false = the field still sits where Home's bar was, true = in the header.
    @State private var arrived = false
    /// Exit back to Home: the field glides down onto Home's search bar before the screen switches.
    @State private var leaving = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var recent: [String] = RecentSearches.load()

    private static let endedAfter: TimeInterval = 12 * 3600 // note 38: a live row 12h past its start is over

    private struct Doc: Identifiable {
        var id: String { event.key }
        let event: CatalogEvent
        let startsAt: Date?
        let doc: String
    }

    private struct HostHit: Identifiable {
        var id: String { key }
        let key: String
        let name: String
        var organizerID: String?
        var count: Int
    }

    /// One searchable list: real public events + the demo catalogue, upcoming only, same doc builder as Map.
    private var docs: [Doc] {
        let now = Date()
        let real = app.discoveryEvents.filter(\.isOpen)
        let realKeys = Set(real.map(\.key))
        let demo = EventCatalog.all.filter { !realKeys.contains($0.key) && !$0.inviteOnly }.map(app.withLive).filter(\.isOpen)
        // Note 99 (owner): in unified mode the sheet promises "Same results as the map", so it lists only events the
        // Map can plot (a loaded Map row with lat/lng; `CatalogEvent.key` == `MapEventRow.id`). Until the Map rows are
        // known the current list stays (no empty flash); the `.task` below loads them.
        let plottable: [String: MapDiscovery.Point]? = app.unifiedDiscoveryEnabled && app.mapEventsKnown ? app.mapPlottablePoints : nil
        return (real + demo).compactMap { e in
            if let plottable, plottable[e.key] == nil { return nil }
            let start = app.discoveryStart(for: e, now: now)
            if let start, now.timeIntervalSince(start) > Self.endedAfter { return nil }
            return Doc(event: e, startsAt: start, doc: SearchMatch.buildDoc(for: e))
        }
    }

    private var liveText: String { unifiedSheet ? text : app.searchQuery }
    private var query: String { liveText.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Sets the query; in the sheet it also flushes to `app.searchQuery` right away (clear, recent chip, submit, CTA).
    private func setText(_ s: String) {
        if unifiedSheet { text = s; pushTask?.cancel(); pushTask = nil; app.searchQuery = s } else { app.searchQuery = s }
    }
    /// Debounced write of the typed text (~150 ms).
    private func schedulePush() {
        pushTask?.cancel()
        pushTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            app.searchQuery = text
            pushTask = nil
        }
    }

    /// Note 99: Home's filters + time + sort over the query's hits (the same `HomeDiscovery.apply` Home renders with).
    private func udNarrowed(_ hits: [Doc]) -> [Doc] {
        let now = Date()
        let items = hits.map { app.discoveryItem(for: $0.event, now: now) }
        var kept = HomeDiscovery.apply(items, app.homeFilters, now: now)
        if app.homeSort != "soonest" { kept = HomeDiscovery.sort(kept, mode: app.homeSort) }
        let byKey = Dictionary(hits.map { ($0.event.key, $0) }, uniquingKeysWith: { a, _ in a })
        return kept.compactMap { byKey[$0.key] }
    }

    /// The Filters sheet counts over what the query found (everything when there is no query yet).
    private func udSheetItems(_ all: [Doc], _ q: String) -> [HomeDiscovery.Item] {
        let now = Date()
        let base = q.isEmpty ? all : all.filter { SearchMatch.matches(doc: $0.doc, query: q) }
        return base.map { app.discoveryItem(for: $0.event, now: now) }
    }

    var body: some View {
        let all = docs
        let q = query
        let queryHits = q.isEmpty ? [] : all.filter { SearchMatch.matches(doc: $0.doc, query: q) }
        // Note 99 (unified_discovery): results also respect the shared filters and time.
        let eventHits = app.unifiedDiscoveryEnabled ? udNarrowed(queryHits) : queryHits
        // Note 99: host/area groups are unused in unified mode, so they are not computed there.
        let hosts = app.unifiedDiscoveryEnabled ? [] : hostHits(all, q)
        let areas = app.unifiedDiscoveryEnabled ? [] : areaHits(q)
        let uHits = app.unifiedDiscoveryEnabled ? (q.isEmpty ? udNarrowed(all) : eventHits) : []
        VStack(spacing: 0) {
            if unifiedSheet { unifiedSheetHeader } else { header }
            // Note 99: the source chips stay pinned under the field while the body scrolls.
            if app.unifiedDiscoveryEnabled { unifiedSourceChips }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if app.unifiedDiscoveryEnabled { unifiedRecent(q) }
                    if app.unifiedDiscoveryEnabled { UnifiedSearchFilterRow(onOpen: { udFilterSheetOpen = true }) }
                    if app.unifiedDiscoveryEnabled {
                        unifiedResults(uHits)
                    } else if q.isEmpty { idle } else { results(eventHits, hosts, areas) }
                }
                .padding(.bottom, app.unifiedDiscoveryEnabled ? 120 : 60)   // note 99: room under the pinned CTA
            }
            .scrollDismissesKeyboard(.interactively)
            .opacity(atHomeBar ? 0 : 1)
            // As an overlay the results drop in from the top (and lift away on close).
            .offset(y: isOverlay && atHomeBar ? -28 : 0)
        }
        .overlay(alignment: .bottom) {
            // Note 99: the "See on the map · N" CTA is pinned 30 pt above the sheet's bottom, results scroll beneath.
            if app.unifiedDiscoveryEnabled && !uHits.isEmpty { unifiedMapCTA(uHits, q: q).padding(.bottom, 30) }
        }
        .foregroundStyle(app.palette.ink)
        // As an overlay the paper fades in over the live Home instead of a whole new page appearing (no white flash).
        .background(app.palette.paper.ignoresSafeArea().opacity(isOverlay && atHomeBar ? 0 : 1))
        // Note 99: the sheet registers with the dock at the moment it opens (RootView), not on appear.
        .background { if !unifiedSheet { Color.clear.hidesDock("search") } }
        .onChange(of: text) { _, _ in if unifiedSheet { schedulePush() } }
        .onChange(of: app.searchQuery) { _, v in
            // Changed from outside (Clear filters, another screen): adopt it unless a typed value is still pending.
            if unifiedSheet, pushTask == nil, v != text { text = v }
        }
        .onDisappear { if unifiedSheet { pushTask?.cancel(); pushTask = nil; if app.searchQuery != text { app.searchQuery = text } } }
        .task(id: unifiedSheet) {
            // The keyboard waits for the sheet's slide-up to finish.
            guard unifiedSheet else { return }
            try? await Task.sleep(for: .milliseconds(350))
            sheetFocused = true
        }
        .onChange(of: atHomeBar) { _, v in app.searchBarAtHome = v }
        .onDisappear { if app.searchBarHandlers?.owner == "search" { app.searchBarHandlers = nil } }
        .onChange(of: app.lang) { _, _ in registerSearchBar() }
        .overlay {
            // UI tests look for the Search "screen" whether it is an overlay or a screen.
            if isOverlay { Color.clear.frame(width: 0, height: 0).accessibilityIdentifier("screen.search") }
        }
        .task {
            // Note 99: Search opened before the Map was visited: load the Map rows the unified list is limited to.
            if app.unifiedDiscoveryEnabled && !app.mapEventsKnown { await app.loadMapEvents() }
        }
        .task {
            if app.discoveryEvents.isEmpty { await app.loadDiscoveryEvents() }
            if app.pulseDaily.isEmpty { await app.loadPulse(period: .daily) }
        }
        .onAppear {
            guard !unifiedSheet else { text = app.searchQuery; return }
            registerSearchBar()
            guard entering else { focused = app.searchQuery.isEmpty; return }
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) { arrived = true }
            }
            // The keyboard comes up once the field has (nearly) landed, not on top of the glide.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                app.searchEntranceFrom = nil
                focused = app.searchQuery.isEmpty
            }
        }
        .sheet(isPresented: $udFilterSheetOpen) {
            HomeFilterSheet(items: udSheetItems(all, q), now: Date(), onClose: { udFilterSheetOpen = false })
                .environmentObject(app)
        }
        .sheet(isPresented: $categorySheetOpen) {
            HomeCategorySheet(counts: [:], selected: [], onPick: { key in
                app.pickFilter(key)
                app.goHome()
            })
            .environmentObject(app)
        }
        // The prototype's sheet surface: 28 pt corners, our own 38 × 5 grabber (the system one is hidden).
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(28)
        .presentationBackground(app.palette.paper)
    }

    /// Prototype v2's sheet header: grabber, the 48 pt in-sheet field (clay magnifier, clay focus border, its own
    /// clear button) and Xong.
    private var unifiedSheetHeader: some View {
        VStack(spacing: 10) {
            Capsule().fill(app.palette.ink.opacity(0.18)).frame(width: 38, height: 5)
                .accessibilityHidden(true)
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.app(size: 16, weight: .medium))
                        .foregroundStyle(app.palette.clay).accessibilityHidden(true)
                    TextField(app.T("Tìm sự kiện, host, khu vực, vibe…", "Search events, hosts, areas, vibes…"), text: $text)
                        .font(.app(size: 15))
                        .focused($sheetFocused)
                        .submitLabel(.search)
                        .onSubmit { commit() }
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("search.sheet.field")
                    if !text.isEmpty {
                        Button {
                            setText("")
                            sheetFocused = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.app(size: 15)).foregroundStyle(app.palette.ink3)
                                .frame(width: 32, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(app.T("Xoá tìm kiếm", "Clear search"))
                        .accessibilityIdentifier("search.sheet.clear")
                    }
                }
                .padding(.horizontal, 14).frame(height: 48)
                .background(app.palette.surface2, in: Capsule())
                .overlay(Capsule().strokeBorder(sheetFocused ? app.palette.clay : .clear, lineWidth: 1.5))
                Button {
                    commit()
                    sheetFocused = false
                    app.unifiedSearchOpen = false
                } label: {
                    Text(app.T("Xong", "Done")).font(.app(size: 15, weight: .semibold))
                        .frame(minWidth: 44, minHeight: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("search.sheet.done")
            }
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 6)
    }

    /// True until the glide from Home's search bar has started: the field is drawn where Home's bar was, at its width.
    private var entering: Bool { !arrived && app.searchEntranceFrom != nil && !reduceMotion }
    /// The field sits over Home's bar: before the entrance glide, and during the exit glide.
    private var atHomeBar: Bool { entering || leaving }

    /// Back: when Search came from Home, the field glides back down onto Home's bar (the reverse of the entrance),
    /// then Home simply appears under it.
    private func close() {
        if unifiedSheet { commit(); app.unifiedSearchOpen = false; return }
        if isOverlay {
            guard !leaving else { return }
            let frame = app.homeSearchBarFrame
            guard !reduceMotion, frame.width > 0 else { app.searchOverlayOpen = false; return }
            app.searchEntranceFrom = frame
            withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) { leaving = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                app.searchOverlayOpen = false
                app.searchEntranceFrom = nil
            }
            return
        }
        let frame = app.homeSearchBarFrame
        guard !reduceMotion, app.searchBackScreen == .home, frame.width > 0, !leaving else { app.goBack(); return }
        app.searchEntranceFrom = frame
        withAnimation(.spring(response: 0.36, dampingFraction: 0.9)) { leaving = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            app.searchClosingToHome = true
            app.goBack()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                app.searchClosingToHome = false
                app.searchEntranceFrom = nil
            }
        }
    }
    private var topInset: CGFloat {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.keyWindow?.safeAreaInsets.top ?? 0
    }
    /// How far below its resting place (8pt under the safe-area top, 44pt tall) the field starts: Home's bar's own
    /// position (46pt tall), so the field begins exactly over it.
    private var entranceOffsetY: CGFloat {
        guard let from = app.searchEntranceFrom else { return 0 }
        return from.minY + 1 - (topInset + 8)
    }

    private var header: some View {
        // The field, back button and clear button are the persistent bar (RootView); this keeps its room.
        Color.clear.frame(height: 44).allowsHitTesting(false)
        .padding(.horizontal, atHomeBar ? 20 : 16).padding(.top, 8).padding(.bottom, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(app.palette.rule).frame(height: 1).opacity(atHomeBar ? 0 : 1) }
        .onChange(of: focused) { was, now in if was && !now { commit() } }
    }

    // MARK: Unified discovery (prototype v2)

    /// "Từ Trang chủ" / "Từ Bản đồ" + "Trang chủ + Bản đồ" source chips (note 99: pinned under the field).
    private var unifiedSourceChips: some View {
        let fromMap = app.screen == .mapExplore
        return HStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: fromMap ? "map" : "house").font(.app(size: 11, weight: .semibold)).accessibilityHidden(true)
                Text(fromMap ? app.T("Từ Bản đồ", "From the Map") : app.T("Từ Trang chủ", "From Home")).font(.app(size: 11.5, weight: .semibold))
            }
            .padding(.horizontal, 10).frame(height: 26)
            .background(app.palette.block, in: Capsule())
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.2.circlepath").font(.app(size: 11, weight: .semibold)).accessibilityHidden(true)
                Text(app.T("Trang chủ + Bản đồ", "Home + Map")).font(.app(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(app.palette.ink2)
            .padding(.horizontal, 10).frame(height: 26)
            .overlay(Capsule().strokeBorder(app.palette.rule, lineWidth: 1))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 6)
        .accessibilityIdentifier("search.meta")
    }

    /// Recent searches while no query is typed.
    @ViewBuilder
    private func unifiedRecent(_ q: String) -> some View {
        if !recent.isEmpty && q.isEmpty {
            Text(app.T("Gần đây", "Recent").uppercased())
                .font(.app(size: 11, weight: .semibold)).tracking(1.4).foregroundStyle(app.palette.ink3)
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 8)
            FlowRow(spacing: 8) {
                ForEach(recent, id: \.self) { r in
                    Button { setText(r) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "clock").font(.app(size: 13)).opacity(0.55).accessibilityHidden(true)
                            Text(r).font(.app(size: 14, weight: .medium)).lineLimit(1)
                        }
                        .padding(.horizontal, 14).frame(height: 38)
                        .background(app.palette.surface2, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("search.recent")
                }
            }
            .padding(.horizontal, 20)
        }
    }

    /// The SAME result set the Map shows: one `EventRowV23` per event, the shared filters already applied, a results
    /// head and a "See on the map · N" CTA. No host/area groups and no trending block in this mode.
    @ViewBuilder
    private func unifiedResults(_ hits: [Doc]) -> some View {
        let q = query
        let now = Date()
        let rows = hits.map { d in (d.event.key, app.v23Row(d.event, item: app.discoveryItem(for: d.event, now: now))) }
        LazyVStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(q.isEmpty
                     ? app.T("\(rows.count) sự kiện", "\(rows.count) \(rows.count == 1 ? "event" : "events")")
                     : app.T("\(rows.count) kết quả cho “\(q)”", "\(rows.count) result\(rows.count == 1 ? "" : "s") for “\(q)”"))
                    .font(BanbeTheme.display(19))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    Circle().fill(app.palette.update).frame(width: 6, height: 6).accessibilityHidden(true)
                    Text(app.T("Cùng kết quả với bản đồ", "Same results as the map"))
                        .font(.app(size: 12)).foregroundStyle(app.palette.ink3).lineLimit(1)
                }
            }
            .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 12)

            ForEach(rows, id: \.0) { key, row in
                EventRowV23View(row: row, idPrefix: "search.event",
                                onToggleSave: { app.toggleFavorite(key) },
                                onOpen: { commit(); focused = false; app.goEvent(key) })
            }

            if rows.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(app.T("Tìm kiếm", "Search").uppercased())
                        .font(.app(size: 11, weight: .semibold)).tracking(1.4).foregroundStyle(app.palette.ink3)
                    Text(app.T("Không có sự kiện nào khớp.", "Nothing matches.")).font(.app(size: 16, weight: .medium))
                    Text(q.isEmpty
                         ? app.T("Thử bớt bộ lọc, hoặc chọn Mọi lúc.", "Try fewer filters, or pick Any time.")
                         : app.T("Không có gì khớp “\(q)”. Thử một từ khác hoặc bỏ bộ lọc.", "Nothing matches “\(q)”. Try another word or drop the filters."))
                        .font(.app(size: 13)).foregroundStyle(app.palette.ink2).fixedSize(horizontal: false, vertical: true)
                    Button {
                        setText("")
                        app.homeFilters = .default
                        app.homeSort = "soonest"
                    } label: {
                        Text(app.T("Xoá bộ lọc", "Clear filters"))
                            .font(.app(size: 14, weight: .semibold)).foregroundStyle(app.palette.paper)
                            .padding(.horizontal, 16).frame(minHeight: 40)
                            .background(app.palette.ink, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                    .accessibilityIdentifier("search.empty.clearFilters")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(app.palette.block, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 20)
                .accessibilityIdentifier("search.empty")
            }

        }
        .padding(.bottom, 24)
    }

    /// The pinned "See on the map · N" CTA (note 99).
    private func unifiedMapCTA(_ hits: [Doc], q: String) -> some View {
        let count = hits.count
        return Button {
            commit()
            focused = false
            // Note 99: the Map frames these N results when any lies outside its committed area (MapExploreView
            // `applyFitRequest`), so its "List · N" equals N.
            if app.mapEventsKnown {
                let pts = hits.compactMap { app.mapPlottablePoints[$0.event.key] }
                app.mapFitRequest = pts.isEmpty ? nil : AppState.MapFitRequest(points: pts)
            }
            // Over the Map the sheet just closes: the map already shows these results.
            if app.screen == .mapExplore { app.unifiedSearchOpen = false } else { app.seeSearchOnMap(q) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "map").font(.app(size: 17, weight: .semibold)).accessibilityHidden(true)
                Text(app.T("Xem trên bản đồ", "See on the map")).font(.app(size: 15.5, weight: .semibold))
                Text("\(count)").font(.app(size: 12)).monospacedDigit()
                    .padding(.horizontal, 7).frame(minWidth: 24, minHeight: 24)
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
            }
            .foregroundStyle(app.palette.paper)
            // Owner 2026-11-19: the pill hugs its label (centred), not the sheet's full width.
            .padding(.horizontal, 24)
            .frame(minHeight: 54)
            .background(app.palette.ink, in: Capsule())
            .shadow(color: .black.opacity(0.24), radius: 13, y: 6)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .accessibilityIdentifier("search.seeOnMap")
    }

    // MARK: Idle (empty query)

    private func groupTitle(_ text: String, count: Int? = nil, id: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(text).font(BanbeTheme.display(16)).accessibilityAddTraits(.isHeader)
            if let count { Text("\(count)").font(.app(size: 12.5)).opacity(0.6) }
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 10)
        .modifier(OptionalIdentifier(identifier: id))
    }

    private func chip(_ title: String, icon: String? = nil, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.app(size: 13)) }
                Text(title).lineLimit(1)
            }
            .font(.app(size: 13.5))
            .padding(.horizontal, 14).frame(minHeight: 36)
            .overlay(Capsule().strokeBorder(app.palette.rule, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    @ViewBuilder
    private var idle: some View {
        if !recent.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text(app.T("Tìm gần đây", "Recent")).font(BanbeTheme.display(16))
                Spacer()
                Button(app.T("Xoá", "Clear")) { recent = []; RecentSearches.save([]) }
                    .font(.app(size: 12.5)).opacity(0.6).buttonStyle(.plain)
                    .accessibilityIdentifier("search.recent.clear")
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 10)
            FlowRow(spacing: 8) {
                ForEach(recent, id: \.self) { r in chip(r, id: "search.recent") { app.searchQuery = r } }
            }
            .padding(.horizontal, 20)
        }
        groupTitle(app.T("Danh mục", "Categories"))
        FlowRow(spacing: 8) {
            ForEach(HomeDiscovery.categories.filter { $0.key != "all" }, id: \.key) { c in
                chip(app.T(c.vi, c.en), icon: CategoryGlyph.symbol(c.key), id: "search.cat.\(c.key)") {
                    app.pickFilter(c.key)
                    app.goHome()
                }
            }
        }
        .padding(.horizontal, 20)
        if !app.pulseDaily.isEmpty {
            groupTitle(app.T("Đang được quan tâm", "Trending today")).padding(.top, 4)
            ForEach(Array(app.pulseDaily.prefix(5).enumerated()), id: \.element.id) { i, p in
                Button { app.goEvent(p.eventId) } label: {
                    HStack(spacing: 12) {
                        Text("\(i + 1)").font(.app(size: 14, weight: .bold)).monospacedDigit().opacity(0.5).frame(width: 22, alignment: .leading)
                        Text(p.eventName).font(.app(size: 14.5)).lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.app(size: 12, weight: .semibold)).opacity(0.4)
                    }
                    .padding(.horizontal, 20).frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("search.trending")
            }
        }
    }

    // MARK: Results

    private func hostHits(_ all: [Doc], _ q: String) -> [HostHit] {
        guard !q.isEmpty else { return [] }
        var byName: [String: HostHit] = [:]
        var order: [String] = []
        for d in all {
            let name = d.event.orgName.isEmpty ? d.event.hostShort : d.event.orgName
            guard !name.isEmpty, SearchMatch.matches(doc: SearchMatch.normalize(name), query: q) else { continue }
            let k = SearchMatch.normalize(name)
            if var cur = byName[k] {
                cur.count += 1
                if cur.organizerID == nil { cur.organizerID = d.event.organizerId }
                byName[k] = cur
            } else {
                byName[k] = HostHit(key: k, name: name, organizerID: d.event.organizerId, count: 1)
                order.append(k)
            }
        }
        // Most upcoming events first; ties keep first-seen order.
        return order.enumerated().compactMap { i, k in byName[k].map { ($0, i) } }
            .sorted { $0.0.count != $1.0.count ? $0.0.count > $1.0.count : $0.1 < $1.1 }
            .prefix(5).map(\.0)
    }

    private func areaHits(_ q: String) -> [LocationNode] {
        guard !q.isEmpty else { return [] }
        return Array(LocationHierarchy.flatten(app.locationTree).filter { node in
            node.openCount > 0
                && SearchMatch.matches(doc: SearchMatch.normalize(LocationHierarchy.label(node, T: app.T) + " " + node.raw), query: q)
        }.prefix(5))
    }

    private func registerSearchBar() {
        guard !unifiedSheet else { return }
        app.searchBarAtHome = atHomeBar
        app.searchBarHandlers = SearchBarHandlers(
            owner: "search",
            placeholder: app.T("Tìm sự kiện, host, khu vực, vibe…", "Search events, hosts, areas, vibes…"),
            back: { focused = false; close() },
            submit: { commit() })
    }

    private func commit() {
        if unifiedSheet { pushTask?.cancel(); pushTask = nil; app.searchQuery = text }   // note 99: flush on submit
        recent = RecentSearches.push(recent, liveText)
        RecentSearches.save(recent)
    }

    private func priceLabel(_ e: CatalogEvent) -> String {
        if AppState.catalogKeys.contains(e.key) { return app.trStatus(e.price) }
        return e.priceVnd > 0 ? EventMarket.formatMoney(e.priceVnd, currency: e.currency) : app.T("Miễn phí", "Free")
    }

    @ViewBuilder
    private func results(_ events: [Doc], _ hosts: [HostHit], _ areas: [LocationNode]) -> some View {
        let total = events.count + hosts.count + areas.count
        if total == 0 {
            VStack(spacing: 6) {
                Text(app.T("Không có kết quả cho \"\(query)\"", "Nothing for \"\(query)\"")).font(BanbeTheme.display(17))
                Text(app.T("Thử một từ ngắn hơn, tên khu vực, hoặc một danh mục.", "Try a shorter word, an area, or a category."))
                    .font(.app(size: 13)).foregroundStyle(app.palette.ink2)
                // Calm Pass phase 2: a way forward instead of a dead end. Categories are the real list, not suggestions.
                HStack(spacing: 8) {
                    Button { app.pickFilter("all"); app.goHome() } label: {
                        InlineEmptyState<EmptyView>.actionLabel(app.T("Xem tất cả sự kiện", "See all events"), systemImage: "sparkles", palette: app.palette)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("search.empty.all")
                    Button { app.searchQuery = "" } label: {
                        InlineEmptyState<EmptyView>.actionLabel(app.T("Xoá tìm kiếm", "Clear search"), systemImage: "xmark", palette: app.palette)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("search.empty.clear")
                }
                .padding(.top, 10)
                FlowRow(spacing: 8) {
                    ForEach(HomeDiscovery.categories.filter { $0.key != "all" }.prefix(4), id: \.key) { c in
                        chip(app.T(c.vi, c.en), icon: CategoryGlyph.symbol(c.key), id: "search.empty.cat.\(c.key)") {
                            app.pickFilter(c.key)
                            app.goHome()
                        }
                    }
                    chip(app.T("Tất cả danh mục", "Show all"), icon: "square.grid.2x2", id: "search.empty.cat.showAll") {
                        categorySheetOpen = true
                    }
                }
                .padding(.top, 12)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 4)
            .accessibilityIdentifier("search.empty")
        }
        if !events.isEmpty {
            groupTitle(app.T("Sự kiện", "Events"), count: events.count, id: "search.group.events")
            ForEach(events.prefix(30)) { d in
                SwipeSafeButton {
                    commit()
                    focused = false
                    app.goEvent(d.event.key)
                } label: {
                    HStack(spacing: 12) {
                        Group {
                            if d.event.img.isEmpty {
                                RoundedRectangle(cornerRadius: BanbeTheme.Radius.thumb, style: .continuous)
                                    .fill(app.palette.ink.opacity(0.08)).frame(width: 56, height: 56)
                            } else {
                                CatalogPhoto(path: d.event.img, height: 56, width: 56, cornerRadius: BanbeTheme.Radius.thumb)
                            }
                        }
                        .zoomSource(d.event.key)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(d.event.name).font(BanbeTheme.display(15)).lineLimit(1)
                                Spacer(minLength: 0)
                                Text(priceLabel(d.event)).font(.app(size: 13, weight: .bold)).lineLimit(1).fixedSize()
                            }
                            Text([app.discoveryWhenLabel(d.startsAt, timeZone: d.event.eventTimeZone), d.event.locationLabel ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.app(size: 12)).opacity(0.65).lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 20).padding(.bottom, 12)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("search.event.\(d.event.key)")
            }
        }
        if !hosts.isEmpty {
            groupTitle(app.T("Host", "Hosts"), count: hosts.count, id: "search.group.hosts")
            ForEach(hosts) { h in
                Button {
                    commit()
                    focused = false
                    if let id = h.organizerID { app.openOrganizerProfile(organizerID: id, back: isOverlay ? .home : .search) } else { app.searchQuery = h.name }
                } label: {
                    resultRow(icon: nil, initial: String(h.name.prefix(1)).uppercased(), title: h.name,
                              subtitle: app.T("\(h.count) sự kiện sắp tới", "\(h.count) upcoming event\(h.count == 1 ? "" : "s")"))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("search.host")
            }
        }
        if !areas.isEmpty {
            groupTitle(app.T("Khu vực", "Areas"), count: areas.count, id: "search.group.areas")
            ForEach(areas) { n in
                Button {
                    commit()
                    focused = false
                    app.pickArea(n.id)
                    app.goHome()
                } label: {
                    resultRow(icon: "mappin.and.ellipse", initial: nil, title: LocationHierarchy.label(n, T: app.T),
                              subtitle: app.T("\(n.openCount) sự kiện", "\(n.openCount) event\(n.openCount == 1 ? "" : "s")"))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("search.area")
            }
        }
        Button {
            commit()
            focused = false
            app.seeSearchOnMap(query)
        } label: {
            Text(app.T("Xem trên bản đồ", "See on map") + " ›")
                .font(.app(size: 13.5, weight: .semibold))
                .padding(.horizontal, 16).frame(minHeight: 40)
                .overlay(Capsule().strokeBorder(app.palette.rule, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 18)
        .accessibilityIdentifier("search.seeOnMap")
    }

    private func resultRow(icon: String?, initial: String?, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Group {
                if let icon { Image(systemName: icon).font(.app(size: 17)) }
                else { Text(initial ?? "?").font(.app(size: 16, weight: .bold)) }
            }
            .frame(width: 40, height: 40)
            .background(app.palette.ink.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: icon == nil ? 20 : BanbeTheme.Radius.tile, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.app(size: 14.5, weight: .semibold)).lineLimit(1)
                Text(subtitle).font(.app(size: 12)).opacity(0.6)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.app(size: 12, weight: .semibold)).opacity(0.4)
        }
        .padding(.horizontal, 20).padding(.vertical, 6)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}
