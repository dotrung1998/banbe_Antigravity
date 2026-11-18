import SwiftUI

// Note 99 (switch `unified_discovery`): Home's pieces of the shared search / type / time / filters, plus Search's
// Filters row. Only rendered while `app.unifiedDiscoveryEnabled`; with the switch off nothing here is used. Web twins:
// the state bar, type tiles, type sheet and map banner in src/screens/Home.jsx, the Filters row in Search.jsx.

@MainActor
enum UnifiedText {
    static func events(_ app: AppState, _ n: Int) -> String {
        app.T("\(n) sự kiện", n == 1 ? "1 event" : "\(n) events")
    }

    static func typeName(_ app: AppState, _ key: String) -> String {
        HomeDiscovery.categories.first { $0.key == key }.map { app.T($0.vi, $0.en) } ?? key
    }

    /// "Dưới 400k" / "Under 400k", "Miễn phí", "Từ 100k", or nil when no price filter is on.
    static func price(_ app: AppState, _ f: HomeDiscovery.Filters) -> String? {
        if f.free { return app.T("Miễn phí", "Free") }
        if let hi = f.priceMax {
            let v = EventMarket.formatMoneyShort(hi, currency: f.priceCurrency)
            if let lo = f.priceMin { return "\(EventMarket.formatMoneyShort(lo, currency: f.priceCurrency))–\(v)" }
            return app.T("Dưới \(v)", "Under \(v)")
        }
        if let lo = f.priceMin { return app.T("Từ \(EventMarket.formatMoneyShort(lo, currency: f.priceCurrency))", "From \(EventMarket.formatMoneyShort(lo, currency: f.priceCurrency))") }
        return nil
    }

    /// The parts the Filters button owns, in reading order: type, price, seats, almost full, sort.
    static func filterParts(_ app: AppState, _ f: HomeDiscovery.Filters, sort: String) -> [String] {
        var p: [String] = []
        if let c = f.cats.first { p.append(typeName(app, c)) }
        if let pr = price(app, f) { p.append(pr) }
        if f.seatsLeft { p.append(app.T("Còn chỗ", "Seats left")) }
        if f.almostFull { p.append(app.T("Sắp hết chỗ", "Almost full")) }
        if !f.typeFilters.isEmpty { p.append(app.T("\(f.typeFilters.count) chi tiết", "\(f.typeFilters.count) details")) }
        if sort != "soonest", let s = HomeDiscovery.sortLabels[sort] { p.append(app.T(s.vi, s.en)) }
        return p
    }

    static func time(_ app: AppState, _ date: String) -> String? {
        guard date != "any" else { return nil }
        return HomeDiscovery.dateLabels[date].map { app.T($0.vi, $0.en) }
    }
}

// MARK: - State bar (under the live line)

/// "“query” · Type · Price · Tonight · N events", an ink Map pill and × (clears query and filters, keeps the time).
struct UnifiedStateBar: View {
    @EnvironmentObject private var app: AppState
    let count: Int
    let onMap: () -> Void
    let onClear: () -> Void

    var body: some View {
        let q = app.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let f = app.homeFilters
        let parts = (q.isEmpty ? [] : ["“\(q)”"]) + UnifiedText.filterParts(app, f, sort: app.homeSort)
            + [UnifiedText.time(app, f.date)].compactMap { $0 }
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.app(size: 13, weight: .semibold)).foregroundStyle(app.palette.clay)
                .accessibilityHidden(true)
            (Text(parts.joined(separator: " · ")).font(.app(size: 13, weight: .semibold))
             + Text(" · " + UnifiedText.events(app, count)).font(.app(size: 13)).foregroundColor(app.palette.ink2))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: { Haptics.selection(); onMap() }) {
                Text(app.T("Bản đồ", "Map"))
                    .font(.app(size: 13, weight: .semibold))
                    .padding(.horizontal, 12).frame(height: 32)
                    .foregroundStyle(app.palette.paper)
                    .background(app.palette.ink, in: Capsule())
                    .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(app.T("Xem trên bản đồ", "See on the map"))
            .accessibilityIdentifier("home.state.map")
            Button(action: { Haptics.selection(); onClear() }) {
                Image(systemName: "xmark").font(.app(size: 13, weight: .bold))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(app.T("Xoá tìm kiếm và bộ lọc", "Clear search and filters"))
            .accessibilityIdentifier("home.state.clear")
        }
        .foregroundStyle(app.palette.ink)
        .padding(.leading, 14).padding(.trailing, 2)
        .background(app.palette.block, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 20).padding(.top, 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.stateBar")
    }
}

// MARK: - Browse by type (filters Home in place)

struct UnifiedBrowseSection: View {
    @EnvironmentObject private var app: AppState
    /// Events per type for the current search, time and price ("all" = every type).
    let counts: [String: Int]
    let onToggle: (String) -> Void
    let onClear: () -> Void
    let onOpenSheet: () -> Void

    private var selected: String? { app.homeFilters.cats.first }

    var body: some View {
        let keys = EventTypes.keys
        let tiles = UnifiedDiscovery.topTypes(counts, keys: keys)
        let picked = UnifiedDiscovery.pickedTileType(selected, tiles: tiles)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(app.T("Duyệt theo loại", "Browse by type"))
                    .font(BanbeTheme.display(19))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if selected != nil {
                    Button(action: { Haptics.selection(); onClear() }) {
                        (Text(app.T("Xem tất cả ", "See all ")) + Text("\(counts["all"] ?? 0)").bold())
                            .font(.app(size: 14, weight: .semibold)).frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.browse.all")
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .top), count: 3), spacing: 6) {
                ForEach(tiles, id: \.self) { k in
                    let n = counts[k] ?? 0
                    tile(glyph: CategoryGlyph.symbol(k), title: UnifiedText.typeName(app, k), sub: UnifiedText.events(app, n),
                         on: selected == k, zero: n == 0, dashed: false, id: "home.browse.\(k)") { onToggle(k) }
                }
                if let picked {
                    tile(glyph: CategoryGlyph.symbol(picked), title: UnifiedText.typeName(app, picked),
                         sub: UnifiedText.events(app, counts[picked] ?? 0) + app.T(" · đổi", " · change"),
                         on: true, zero: false, dashed: false, id: "home.browse.picked", action: onOpenSheet)
                        .accessibilityHint(app.T("Đổi loại", "Change the type"))
                } else {
                    tile(glyph: "magnifyingglass", title: app.T("Tất cả loại", "All types"),
                         sub: app.T("\(keys.count) loại", "\(keys.count) types"),
                         on: false, zero: false, dashed: true, id: "home.browse.find", action: onOpenSheet)
                }
            }
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 20).padding(.top, 28)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.browse")
        .tourTarget("tour.home.browse")
    }

    private func tile(glyph: String, title: String, sub: String, on: Bool, zero: Bool, dashed: Bool, id: String,
                      action: @escaping () -> Void) -> some View {
        SwipeSafeButton(action: action) {
            VStack(spacing: 4) {
                Image(systemName: glyph)
                    .font(.app(size: 22, weight: .light))
                    .foregroundStyle(on ? app.palette.paper : app.palette.ink)
                    .frame(width: 52, height: 52)
                    .background(on ? app.palette.ink : Color.clear, in: Circle())
                    .overlay {
                        if dashed { Circle().strokeBorder(app.palette.ink3, style: StrokeStyle(lineWidth: 1, dash: [3, 3])) }
                    }
                Text(title).font(.app(size: 13, weight: on ? .semibold : .regular)).lineLimit(1).minimumScaleFactor(0.8)
                Text(sub).font(.app(size: 11.5)).opacity(0.64).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12).padding(.bottom, 10)
            .background(on ? app.palette.block : Color.clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(zero && !on ? 0.5 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}

// MARK: - Type sheet ("All types")

struct UnifiedTypeSheet: View {
    @EnvironmentObject private var app: AppState
    let counts: [String: Int]
    let selected: String?
    let onPick: (String) -> Void
    @State private var query = ""

    var body: some View {
        let keys = UnifiedDiscovery.typeSheetOrder(counts, keys: EventTypes.keys, nameOf: { UnifiedText.typeName(app, $0) }, query: query)
        VStack(spacing: 0) {
            Text(app.T("Tất cả loại", "All types")).font(BanbeTheme.display(19)).padding(.top, 18).padding(.bottom, 10)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").opacity(0.6).accessibilityHidden(true)
                TextField(app.T("Tìm một loại", "Find a type"), text: $query)
                    .font(.app(size: 15))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("home.typeSheet.search")
            }
            .padding(.horizontal, 14).frame(height: 44)
            .background(app.palette.ink.opacity(0.05), in: Capsule())
            .padding(.horizontal, 16).padding(.bottom, 8)
            ScrollView {
                LazyVStack(spacing: 0) {
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        row(key: "all", glyph: "square.grid.2x2", name: app.T("Tất cả loại", "All types"),
                            n: counts["all"] ?? 0, on: selected == nil, dim: false)
                    }
                    ForEach(keys, id: \.self) { k in
                        let n = counts[k] ?? 0
                        row(key: k, glyph: CategoryGlyph.symbol(k), name: UnifiedText.typeName(app, k), n: n, on: selected == k, dim: n == 0)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .foregroundStyle(app.palette.ink)
        .background(app.palette.paper.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("home.typeSheet")
    }

    private func row(key: String, glyph: String, name: String, n: Int, on: Bool, dim: Bool) -> some View {
        Button { Haptics.selection(); onPick(key) } label: {
            HStack(spacing: 14) {
                Image(systemName: glyph).font(.app(size: 17, weight: .light)).frame(width: 36, height: 36)
                    .background(app.palette.ink.opacity(0.06), in: Circle())
                Text(name).font(.app(size: 15, weight: on ? .semibold : .regular))
                Spacer(minLength: 8)
                Text("\(n)").font(.app(size: 13)).monospacedDigit().opacity(0.6)
                Image(systemName: "checkmark").font(.app(size: 14, weight: .bold)).opacity(on ? 1 : 0).accessibilityHidden(true)
            }
            .padding(.horizontal, 20).frame(minHeight: 52)
            .opacity(dim && !on ? 0.45 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name), \(UnifiedText.events(app, n))")
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("home.typeSheet.\(key)")
    }
}

// MARK: - Map banner (under the Shortlist)

struct UnifiedMapBanner: View {
    @EnvironmentObject private var app: AppState
    let count: Int
    let onOpen: () -> Void

    var body: some View {
        SwipeSafeButton(action: { Haptics.selection(); onOpen() }) {
            HStack(spacing: 14) {
                mapArt.frame(width: 64, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.T("Xem trên bản đồ", "See on the map")).font(.app(size: 15, weight: .semibold))
                    Text(UnifiedText.events(app, count) + app.T(" · cùng kết quả", " · same results"))
                        .font(.app(size: 12.5)).foregroundStyle(app.palette.ink2)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.right").font(.app(size: 14, weight: .bold))
                    .foregroundStyle(app.palette.paper)
                    .frame(width: 40, height: 40)
                    .background(app.palette.ink, in: Circle())
            }
            .padding(10)
            .background(app.palette.block, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 20).padding(.top, 16)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("home.mapBanner")
    }

    /// A few streets and pins drawn in place of a map tile (no network).
    private var mapArt: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(app.palette.surface2))
            var roads = Path()
            roads.move(to: CGPoint(x: 0, y: size.height * 0.62)); roads.addLine(to: CGPoint(x: size.width, y: size.height * 0.38))
            roads.move(to: CGPoint(x: size.width * 0.35, y: 0)); roads.addLine(to: CGPoint(x: size.width * 0.55, y: size.height))
            ctx.stroke(roads, with: .color(app.palette.paper), lineWidth: 4)
            for p in [CGPoint(x: 0.25, y: 0.35), CGPoint(x: 0.7, y: 0.6), CGPoint(x: 0.55, y: 0.25)] {
                let r = CGRect(x: p.x * size.width - 4, y: p.y * size.height - 4, width: 8, height: 8)
                ctx.fill(Path(ellipseIn: r), with: .color(app.palette.clay))
            }
        }
    }
}

// MARK: - Search: the Filters row

struct UnifiedSearchFilterRow: View {
    @EnvironmentObject private var app: AppState
    let onOpen: () -> Void

    var body: some View {
        let parts = UnifiedText.filterParts(app, app.homeFilters, sort: app.homeSort)
        let time = UnifiedText.time(app, app.homeFilters.date) ?? app.T("Mọi lúc", "Any time")
        Button(action: { Haptics.selection(); onOpen() }) {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3").font(.app(size: 15, weight: .semibold)).accessibilityHidden(true)
                Group {
                    if parts.isEmpty {
                        Text(app.T("Bộ lọc", "Filters")).font(.app(size: 14, weight: .semibold))
                            + Text(app.T(" · loại, giá, sắp xếp · \(time)", " · type, price, sort · \(time)")).font(.app(size: 13)).foregroundColor(app.palette.ink2)
                    } else {
                        Text(app.T("Bộ lọc: ", "Filters: ")).font(.app(size: 14, weight: .semibold))
                            + Text(parts.joined(separator: " · ")).font(.app(size: 14))
                            + Text(" · \(time)").font(.app(size: 13)).foregroundColor(app.palette.ink2)
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                if !parts.isEmpty {
                    Text("\(parts.count)").font(.app(size: 11.5, weight: .bold)).monospacedDigit()
                        .foregroundStyle(app.palette.paper)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(app.palette.clay, in: Capsule())
                }
                Image(systemName: "chevron.right").font(.app(size: 12, weight: .semibold)).opacity(0.45).accessibilityHidden(true)
            }
            .padding(.horizontal, 14).frame(minHeight: 48)
            .background(app.palette.block, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 20).padding(.top, 12)
        .accessibilityValue(parts.isEmpty ? app.T("Không bật", "None on") : parts.joined(separator: ", "))
        .accessibilityIdentifier("search.filters")
    }
}
