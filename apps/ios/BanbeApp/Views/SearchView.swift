import SwiftUI

// Search screen (note 50) — replaces "the magnifier opens Map". Web twin: src/screens/Search.jsx (/search).
// Empty query: recent searches (this device only), categories, trending (Banbe Pulse).
// Typing: live results from the ONE shared matcher (Lib/Search.swift — the same documents Map searches),
// grouped Events · Hosts · Areas, each with its count. "See on map" carries the query to Map.
// Search never counts toward the streak (note 36).
struct SearchView: View {
    @EnvironmentObject private var app: AppState
    /// Shown over Home (RootView) instead of as its own screen.
    let isOverlay: Bool
    init(isOverlay: Bool = false) { self.isOverlay = isOverlay }

    @State private var focused = false
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
        return (real + demo).compactMap { e in
            let start = app.discoveryStart(for: e, now: now)
            if let start, now.timeIntervalSince(start) > Self.endedAfter { return nil }
            return Doc(event: e, startsAt: start, doc: SearchMatch.buildDoc(for: e))
        }
    }

    private var query: String { app.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        let all = docs
        let q = query
        let eventHits = q.isEmpty ? [] : all.filter { SearchMatch.matches(doc: $0.doc, query: q) }
        let hosts = hostHits(all, q)
        let areas = areaHits(q)
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if q.isEmpty { idle } else { results(eventHits, hosts, areas) }
                }
                .padding(.bottom, 60)
            }
            .scrollDismissesKeyboard(.interactively)
            .opacity(atHomeBar ? 0 : 1)
            // As an overlay the results drop in from the top (and lift away on close).
            .offset(y: isOverlay && atHomeBar ? -28 : 0)
        }
        .foregroundStyle(app.palette.ink)
        // As an overlay the paper fades in over the live Home instead of a whole new page appearing (no white flash).
        .background(app.palette.paper.ignoresSafeArea().opacity(isOverlay && atHomeBar ? 0 : 1))
        .hidesDock("search")
        .overlay {
            // UI tests look for the Search "screen" whether it is an overlay or a screen.
            if isOverlay { Color.clear.frame(width: 0, height: 0).accessibilityIdentifier("screen.search") }
        }
        .task {
            if app.discoveryEvents.isEmpty { await app.loadDiscoveryEvents() }
            if app.pulseDaily.isEmpty { await app.loadPulse(period: .daily) }
        }
        .onAppear {
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
    }

    /// True until the glide from Home's search bar has started: the field is drawn where Home's bar was, at its width.
    private var entering: Bool { !arrived && app.searchEntranceFrom != nil && !reduceMotion }
    /// The field sits over Home's bar: before the entrance glide, and during the exit glide.
    private var atHomeBar: Bool { entering || leaving }

    /// Back: when Search came from Home, the field glides back down onto Home's bar (the reverse of the entrance),
    /// then Home simply appears under it.
    private func close() {
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
        HStack(spacing: atHomeBar ? 0 : 10) {
            Button {
                focused = false
                close()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(app.palette.ink.opacity(0.07), in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // While entering, the back button takes no width, so the field starts as wide as Home's bar.
            .frame(width: atHomeBar ? 0 : nil)
            .opacity(atHomeBar ? 0 : 1)
            .clipped()
            .accessibilityLabel(app.T("Quay lại", "Back"))
            .accessibilityIdentifier("search.back")
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .semibold)).opacity(0.6)
                FocusableTextField(text: $app.searchQuery, isFirstResponder: $focused,
                                   placeholder: app.T("Tìm sự kiện, host, khu vực, vibe…", "Search events, hosts, areas, vibes…"),
                                   font: .systemFont(ofSize: 15))
                    .frame(height: 44)
                    .accessibilityLabel(app.T("Tìm kiếm", "Search"))
                    .accessibilityIdentifier("search.input")
                if !app.searchQuery.isEmpty {
                    Button { app.searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 15)).opacity(0.45)
                            .frame(width: 32, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(app.T("Xoá", "Clear"))
                }
            }
            .padding(.horizontal, 14)
            .background { Color.clear.nativeGlassCapsule(interactive: false) }
            // Entrance: starts over Home's search bar and glides up into the header as the back button slides in.
            .offset(y: atHomeBar ? entranceOffsetY : 0)
        }
        .padding(.horizontal, atHomeBar ? 20 : 16).padding(.top, 8).padding(.bottom, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(app.palette.rule).frame(height: 1).opacity(atHomeBar ? 0 : 1) }
        .onChange(of: focused) { was, now in if was && !now { commit() } }
    }

    // MARK: Idle (empty query)

    private func groupTitle(_ text: String, count: Int? = nil, id: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(text).font(BanbeTheme.display(16)).accessibilityAddTraits(.isHeader)
            if let count { Text("\(count)").font(.system(size: 12.5)).opacity(0.6) }
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 10)
        .modifier(OptionalIdentifier(identifier: id))
    }

    private func chip(_ title: String, icon: String? = nil, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 13)) }
                Text(title).lineLimit(1)
            }
            .font(.system(size: 13.5))
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
                    .font(.system(size: 12.5)).opacity(0.6).buttonStyle(.plain)
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
                        Text("\(i + 1)").font(.system(size: 14, weight: .bold)).monospacedDigit().opacity(0.5).frame(width: 22, alignment: .leading)
                        Text(p.eventName).font(.system(size: 14.5)).lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).opacity(0.4)
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

    private func commit() {
        recent = RecentSearches.push(recent, app.searchQuery)
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
                    .font(.system(size: 13)).opacity(0.65)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24).padding(.vertical, 36)
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
                                Text(priceLabel(d.event)).font(.system(size: 13, weight: .bold)).lineLimit(1).fixedSize()
                            }
                            Text([app.discoveryWhenLabel(d.startsAt, timeZone: d.event.eventTimeZone), d.event.locationLabel ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.system(size: 12)).opacity(0.65).lineLimit(1)
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
                .font(.system(size: 13.5, weight: .semibold))
                .padding(.horizontal, 16).frame(minHeight: 40)
                .overlay(Capsule().strokeBorder(app.palette.rule, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20).padding(.vertical, 18)
        .accessibilityIdentifier("search.seeOnMap")
    }

    private func resultRow(icon: String?, initial: String?, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Group {
                if let icon { Image(systemName: icon).font(.system(size: 17)) }
                else { Text(initial ?? "?").font(.system(size: 16, weight: .bold)) }
            }
            .frame(width: 40, height: 40)
            .background(app.palette.ink.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: icon == nil ? 20 : BanbeTheme.Radius.tile, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 14.5, weight: .semibold)).lineLimit(1)
                Text(subtitle).font(.system(size: 12)).opacity(0.6)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).opacity(0.4)
        }
        .padding(.horizontal, 20).padding(.vertical, 6)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}
