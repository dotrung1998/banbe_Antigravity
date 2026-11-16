import SwiftUI

// v2.3 Home pieces (note 81, switch home_v23 on top of simple_shell). Web twins: src/components/list/{Pager,EndCard,
// EventRowV23}.jsx, src/components/home/{ShortlistV23,LiveLine,SeeAllFanCard,NextUpV23}.jsx, sheets/LiveNowSheet.jsx.
// Pure rules: Lib/V23Rules.swift, Lib/V23EventRules.swift.

// MARK: - Row

/// One v2.3 event row: when · type, title, then place or status with the price at the end of that line.
struct V23Row: Identifiable, Equatable {
    struct Status: Equatable { let alert: Bool; let text: String }
    var id: String { key }
    let key: String
    let name: String
    let img: String
    /// "T6 27/11 · 19:00": first on the top line and in full ink, so it is never the part that is cut.
    let when: String
    let type: String
    let place: String
    let priceLabel: String
    let isFree: Bool
    let status: Status?
}

extension AppState {
    /// The type's own name (event type profiles) in the reader's language, else the catalogue's label.
    func v23TypeName(_ key: String?) -> String? {
        guard let key else { return nil }
        return HomeDiscovery.categories.first { $0.key == key }.map { T($0.vi, $0.en) }
    }

    func v23Row(_ e: CatalogEvent, item it: HomeDiscovery.Item, now: Date = Date()) -> V23Row {
        var fill = HomeDiscovery.fillBadge(booked: it.booked, capacity: it.capacity)
        if e.soldOut && fill.left == nil { fill.soldOut = true }
        let soldOut = it.soldOut || fill.soldOut
        let type = v23TypeName(it.catKeys.first) ?? trStatus(e.catDisplay.isEmpty ? e.cat : e.catDisplay)
        let when = discoveryDateBadge(it.startsAt, now: now, timeZone: e.eventTimeZone)
        let area = e.locationLabel ?? e.location?.area
        let km = it.distanceKm.map { String(format: "%.1f", $0).replacingOccurrences(of: ".", with: ",") + " km" }
        let status: V23Row.Status? = e.cancelled ? .init(alert: true, text: T("Đã huỷ", "Cancelled"))
            : soldOut ? .init(alert: true, text: T("Hết chỗ", "Sold out"))
            : fill.almostFull ? .init(alert: false, text: T("Sắp hết · còn \(fill.left ?? 0) chỗ", "Almost full · \(fill.left ?? 0) left"))
            : nil
        return V23Row(key: e.key, name: e.name, img: e.img,
                      when: when, type: type,
                      place: [area, km].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                      priceLabel: it.priceVnd == 0 ? T("Miễn phí", "Free") : trStatus(e.price),
                      isFree: it.priceVnd == 0, status: status)
    }
}

struct EventRowV23View: View {
    static let height: CGFloat = 92
    @EnvironmentObject private var app: AppState
    let row: V23Row
    var idPrefix = "home.event"
    let onOpen: () -> Void

    var body: some View {
        SwipeSafeButton(action: onOpen) {
            HStack(spacing: 12) {
                CatalogPhoto(path: row.img, height: 80, width: 80, cornerRadius: BanbeTheme.Radius.thumb)
                    .zoomSource(row.key)
                VStack(alignment: .leading, spacing: 3) {
                    // Each line owns the full width beside the photo, so nothing is cut at phone width. When leads
                    // the top line in full ink; if the line ever runs out it is the type that is cut, and the chips
                    // already say the type. The price closes the third line (it used to stand in its own column
                    // beside all three, which is what cut the time off) and still lines up down the list.
                    (Text(row.when.uppercased())
                     + Text((row.when.isEmpty || row.type.isEmpty ? "" : " · ") + row.type.uppercased())
                        .foregroundColor(app.palette.ink.opacity(0.72)))
                        .font(.app(size: 11, weight: .bold)).tracking(0.66).lineLimit(1)
                    Text(row.name).font(BanbeTheme.display(16)).lineLimit(1)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Group {
                            if let s = row.status {
                                Text(s.text).fontWeight(.semibold).foregroundStyle(s.alert ? BanbeTheme.alert : app.palette.honey)
                            } else {
                                Text(row.place).opacity(0.72)
                            }
                        }
                        .font(.app(size: 12.5)).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if !row.priceLabel.isEmpty {
                            Text(row.priceLabel).font(.app(size: 14, weight: .semibold)).monospacedDigit().lineLimit(1)
                                .foregroundStyle(row.isFree ? app.palette.honey : app.palette.ink)
                                .layoutPriority(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 20).padding(.bottom, 12)
            .frame(height: Self.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isLink)
        .accessibilityIdentifier("\(idPrefix).\(row.key)")
    }
}

// MARK: - End card

/// The end card: a quiet block that closes the list — eyebrow, serif line, body, actions, all on the leading edge
/// like the rows above it. It used to be a dashed outline with three bobbing dots: the outline read as a placeholder
/// and the dots as a second page indicator, right above the real one.
struct EndCardView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: EndCardModel
    let variant: Pager.EndVariant
    let onAction: (String) -> Void
    @State private var shown = false

    private var c: EndCardModel { variant == .slim ? model.slimmed : model }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 22, style: .continuous) }

    var body: some View {
        Group {
            if variant == .slim {
                HStack(spacing: 12) {
                    Text(c.title.t(app.isEN)).font(V23Style.serif(16.5)).frame(maxWidth: .infinity, alignment: .leading)
                    if let a = c.actions.first { button(a) }
                }
                .padding(.leading, 18).padding(.trailing, 12).padding(.vertical, 12)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if let e = c.eyebrow {
                        Text(e.t(app.isEN).uppercased()).font(.app(size: 11, weight: .bold)).tracking(1.4).foregroundStyle(app.palette.ink3)
                    }
                    Text(c.title.t(app.isEN)).font(V23Style.serif(variant == .mid ? 19 : 22))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, variant == .mid ? 6 : 8).padding(.bottom, variant == .mid ? 0 : 6)
                    if let b = c.body, variant != .mid {
                        Text(b.t(app.isEN)).font(.app(size: 13)).lineSpacing(3).foregroundStyle(app.palette.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    FlowRow(spacing: 8) { ForEach(c.actions, id: \.act) { button($0) } }
                        .padding(.top, variant == .mid ? 12 : 16)
                }
                .frame(maxWidth: .infinity, maxHeight: variant == .solo ? nil : .infinity, alignment: .topLeading)
                .padding(.horizontal, 20).padding(.vertical, variant == .mid ? 16 : 20)
            }
        }
        .foregroundStyle(app.palette.ink)
        .background(app.palette.block, in: shape)
        .padding(.horizontal, 20).padding(.top, variant == .slim ? 2 : 6).padding(.bottom, 14)
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 14)
        .onAppear {
            guard !reduceMotion else { shown = true; return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.18)) { shown = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("list.endCard.\(model.kind)")
    }

    private func button(_ a: EndCardModel.Action) -> some View {
        Button { onAction(a.act) } label: {
            Text(a.label.t(app.isEN)).font(.app(size: 13.5, weight: .semibold)).lineLimit(1)
                .foregroundStyle(a.primary ? app.palette.paper : app.palette.ink)
                .padding(.horizontal, 16).frame(minHeight: 44)
                .background(a.primary ? app.palette.ink : .clear, in: Capsule())
                .overlay(Capsule().stroke(a.primary ? .clear : app.palette.rule, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityIdentifier(a.testId.map { "list.\($0)" } ?? "list.end.\(a.act)")
    }
}

// MARK: - Pager

/// One pager for every v2.3 list: four large rows a page on their own horizontal track; the arrows and page numbers
/// drive the same track; "5–8 of 18" says where you are. A short last page ends with an end card sized to the missing
/// rows. The ink under the numbers is a drop that FOLLOWS the swipe: it reads the track's live scroll position, so it
/// leaves with the finger, stretches between two numbers and settles on the new one (it used to wait for the page to
/// land, which read as lag). The numbers, arrows and range are the only paging signs: the edge tabs, the one-time
/// nudge and the "Swipe to see more" line said the same thing three more times and are gone.
struct V23Pager<Item, Row: View, End: View, Empty: View>: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let items: [Item]
    let key: (Item) -> String
    /// Remembers this list's page for the session (per list and content).
    let listID: String
    var rowHeight: CGFloat = EventRowV23View.height
    @ViewBuilder let row: (Item) -> Row
    let end: (Pager.EndVariant) -> End
    @ViewBuilder let empty: () -> Empty

    @MainActor private static var savedPages: [String: Int] { get { V23PagerMemory.pages } set { V23PagerMemory.pages = newValue } }
    @State private var page: Int?
    /// The track's live position in pages. A reference the pager itself does not observe, so a swipe redraws the
    /// numbers only, never the rows.
    @State private var progress = PagerProgress()

    private var pages: [[Item]] { Pager.paginate(items) }
    private var signature: String { "\(listID)|" + items.map(key).joined(separator: "|") }
    private var current: Int { Pager.clampPage(page ?? 0, pages.count) }

    var body: some View {
        if pages.isEmpty {
            empty().accessibilityIdentifier("\(listID).empty")
        } else {
            let p = pages
            let room = Pager.endCardRoom(sizes: p.map(\.count))
            let nav = Pager.showNav(pageCount: p.count)
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 0) {
                        ForEach(p.indices, id: \.self) { i in
                            VStack(spacing: 0) {
                                ForEach(p[i].map { Keyed(keyID: key($0), value: $0) }, id: \.keyID) { it in row(it.value) }
                                if i == p.count - 1, let v = room.variant {
                                    end(v)
                                        .frame(minHeight: v == .solo ? nil : CGFloat(room.room) * rowHeight, alignment: .top)
                                        .frame(maxHeight: v == .solo ? nil : .infinity)
                                }
                            }
                            .frame(height: nav ? CGFloat(Pager.pageSize) * rowHeight : nil, alignment: .top)
                            .containerRelativeFrame(.horizontal)
                            .accessibilityHidden(i != current)
                            .id(i)
                        }
                    }
                    .scrollTargetLayout()
                    .background { if #unavailable(iOS 18.0) { LegacyTrackProbe(progress: progress, pageCount: p.count) } }
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $page)
                .scrollDisabled(!nav)
                .modifier(TrackProgress(progress: progress))
                .rootSwipeExclusion("v23Pager.\(listID)")
                if nav { numbers(p.count).padding(.top, 6) }
                if nav {
                    Text(Pager.rangeText(sizes: p.map(\.count), page: current, english: app.isEN))
                        .font(.app(size: 12.5)).opacity(0.72).padding(.top, 2)
                        .accessibilityIdentifier("\(listID).range")
                }
            }
            .foregroundStyle(app.palette.ink)
            .onAppear {
                if page == nil { page = Pager.clampPage(Self.savedPages[signature] ?? 0, p.count) }
                progress.value = CGFloat(current)
            }
            .onChange(of: signature) { _, sig in
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { page = Pager.clampPage(Self.savedPages[sig] ?? 0, pages.count) }
                progress.value = CGFloat(current)
            }
            .onChange(of: page) { old, new in
                if let new { Self.savedPages[signature] = new }
                if old != nil && old != new { Haptics.selection() }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(listID)
        }
    }

    private func go(_ i: Int) {
        let next = Pager.clampPage(i, pages.count)
        withAnimation(reduceMotion ? nil : .spring(response: 0.44, dampingFraction: 0.9)) { page = next }
    }

    private func numbers(_ count: Int) -> some View {
        HStack(spacing: 2) {
            navButton("chevron.left", enabled: current > 0, label: app.T("Trang trước", "Previous page"), id: "\(listID).prev") { go(current - 1) }
            PagerDrop(progress: progress, window: Pager.pageWindow(current, count), current: current, listID: listID, go: go)
            navButton("chevron.right", enabled: current < count - 1, label: app.T("Trang sau", "Next page"), id: "\(listID).next") { go(current + 1) }
        }
        .padding(.horizontal, 20)
    }

    private func navButton(_ symbol: String, enabled: Bool, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.app(size: 16, weight: .medium)).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

/// Where the pager's track is, in pages (1.5 = halfway from the second page to the third).
@MainActor final class PagerProgress: ObservableObject {
    @Published var value: CGFloat = 0
}

/// The page numbers with the drop under the open one. Two layers: the numbers in ink, and the same numbers in paper
/// on ink, cut to the drop's shape — so a number turns light exactly where the drop covers it, mid-swipe included.
/// The drop's leading edge runs ahead and its trailing edge lags, which is the stretch. Flat ink, no gloss: it is the
/// only object on these screens that moves like liquid, it does not also need to shine. Reduce Motion: no stretch,
/// the drop steps from number to number.
private struct PagerDrop: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var progress: PagerProgress
    let window: [Int]
    let current: Int
    let listID: String
    let go: (Int) -> Void

    private static var cell: CGFloat { 44 }
    private static var inset: CGFloat { 3 }

    var body: some View {
        let edges = PagerDropRules.edges(progress: progress.value, first: window.first ?? 0, count: window.count, still: reduceMotion)
        let left = edges.trail * Self.cell + Self.inset
        let width = (edges.lead - edges.trail) * Self.cell + Self.cell - 2 * Self.inset
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                ForEach(window, id: \.self) { i in
                    Button { go(i) } label: {
                        Text("\(i + 1)").font(.app(size: 14, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(app.palette.ink)
                            .frame(width: Self.cell, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(app.T("Trang \(i + 1)", "Page \(i + 1)"))
                    .accessibilityAddTraits(i == current ? .isSelected : [])
                    .accessibilityIdentifier("\(listID).page.\(i + 1)")
                }
            }
            HStack(spacing: 0) {
                ForEach(window, id: \.self) { i in
                    Text("\(i + 1)").font(.app(size: 14, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(app.palette.paper)
                        .frame(width: Self.cell, height: 44)
                }
            }
            .background(app.palette.ink)
            .mask(alignment: .leading) {
                Capsule().frame(width: max(width, 0), height: 32).offset(x: left)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// The drop's two edges, in cells from the first number shown: at rest both sit on the open page; between pages the
/// leading edge eases out (runs ahead) and the trailing edge eases in (lags), so the drop is longest mid-swipe.
enum PagerDropRules {
    static func edges(progress: CGFloat, first: Int, count: Int, still: Bool) -> (trail: CGFloat, lead: CGFloat) {
        guard count > 0 else { return (0, 0) }
        let rel = min(max(progress - CGFloat(first), 0), CGFloat(count - 1))
        if still { let r = rel.rounded(); return (r, r) }
        let base = rel.rounded(.down), f = rel - base
        return (base + f * f, base + 1 - (1 - f) * (1 - f))
    }
}

/// Reports the track's position (iOS 18: the scroll view's own geometry).
private struct TrackProgress: ViewModifier {
    let progress: PagerProgress
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { g in
                g.containerSize.width > 0 ? g.contentOffset.x / g.containerSize.width : 0
            } action: { _, new in
                progress.value = new
            }
        } else {
            content
        }
    }
}

/// iOS 17: the same position, read from where the track's content sits inside its scroll view.
private struct LegacyTrackProbe: View {
    let progress: PagerProgress
    let pageCount: Int
    var body: some View {
        GeometryReader { geo in
            let pageWidth = geo.size.width / CGFloat(max(pageCount, 1))
            let x = pageWidth > 0 ? -geo.frame(in: .scrollView).minX / pageWidth : 0
            Color.clear.onChange(of: x) { _, new in progress.value = new }
        }
    }
}

/// Session memory for the pagers (their pages).
@MainActor enum V23PagerMemory {
    static var pages: [String: Int] = [:]
}

/// Pairs an item with a stable id for ForEach without making `Item` Identifiable.
private struct Keyed<T> { let keyID: String; let value: T }
