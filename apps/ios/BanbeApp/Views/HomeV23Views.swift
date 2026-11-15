import SwiftUI

// v2.3 Home pieces (note 81, switch home_v23 on top of simple_shell). Web twins: src/components/list/{Pager,EndCard,
// EventRowV23}.jsx, src/components/home/{ShortlistV23,LiveLine,SeeAllFanCard,NextUpV23}.jsx, sheets/LiveNowSheet.jsx.
// Pure rules: Lib/V23Rules.swift, Lib/V23EventRules.swift.

// MARK: - Row

/// One v2.3 event row: kicker (type · when), title, place or status, the price centred on the row.
struct V23Row: Identifiable, Equatable {
    struct Status: Equatable { let alert: Bool; let text: String }
    var id: String { key }
    let key: String
    let name: String
    let img: String
    let kicker: String
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
                      kicker: [type, when].filter { !$0.isEmpty }.joined(separator: " · "),
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
                    Text(row.kicker.uppercased()).font(.app(size: 11, weight: .bold)).tracking(0.66).opacity(0.72).lineLimit(1)
                    Text(row.name).font(BanbeTheme.display(16)).lineLimit(1)
                    Group {
                        if let s = row.status {
                            Text(s.text).fontWeight(.semibold).foregroundStyle(s.alert ? BanbeTheme.alert : app.palette.honey)
                        } else {
                            Text(row.place).opacity(0.72)
                        }
                    }
                    .font(.app(size: 12.5)).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(row.priceLabel).font(.app(size: 14, weight: .bold)).lineLimit(1)
                    .foregroundStyle(row.isFree ? app.palette.honey : app.palette.ink)
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

/// The prototype's end card: dashed paper card, faint honey glow, three clay dots, eyebrow, serif line, body, actions.
struct EndCardView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: EndCardModel
    let variant: Pager.EndVariant
    let onAction: (String) -> Void
    @State private var shown = false
    @State private var bob = false

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
                VStack(spacing: 0) {
                    if variant != .mid { dots.padding(.bottom, 12) }
                    if let e = c.eyebrow {
                        Text(e.t(app.isEN).uppercased()).font(.app(size: 11, weight: .bold)).tracking(1.4).foregroundStyle(app.palette.ink3)
                    }
                    Text(c.title.t(app.isEN)).font(V23Style.serif(variant == .mid ? 19 : 22)).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, variant == .mid ? 6 : 8).padding(.bottom, variant == .mid ? 0 : 8)
                    if let b = c.body, variant != .mid {
                        Text(b.t(app.isEN)).font(.app(size: 13)).lineSpacing(3).foregroundStyle(app.palette.ink2).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    FlowRow(spacing: 8) { ForEach(c.actions, id: \.act) { button($0) } }
                        .padding(.top, variant == .mid ? 12 : 16)
                }
                .frame(maxWidth: .infinity, maxHeight: variant == .solo ? nil : .infinity)
                .padding(.horizontal, 20).padding(.vertical, variant == .mid ? 16 : 22)
            }
        }
        .foregroundStyle(app.palette.ink)
        .background(RadialGradient(colors: [app.palette.honey.opacity(0.09), .clear], center: .top, startRadius: 0, endRadius: 260), in: shape)
        .overlay(shape.strokeBorder(app.palette.ink.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .padding(.horizontal, 20).padding(.top, variant == .slim ? 2 : 6).padding(.bottom, 14)
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 14)
        .scaleEffect(shown ? 1 : 0.98)
        .onAppear {
            guard !reduceMotion else { shown = true; return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.18)) { shown = true }
            withAnimation(.easeInOut(duration: 0.4).delay(0.6).repeatCount(4, autoreverses: true)) { bob = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("list.endCard.\(model.kind)")
    }

    private var dots: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(app.palette.clay).opacity([0.35, 0.65, 1][i]).frame(width: 5, height: 5)
                    .offset(y: bob && !reduceMotion ? -4 : 0)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.4).delay(0.6 + Double(i) * 0.16).repeatCount(4, autoreverses: true), value: bob)
            }
        }
        .accessibilityHidden(true)
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
/// drive the same track; one ink under the numbers slides to the new number; "5–8 of 18" says where you are. A short
/// last page ends with an end card sized to the missing rows. `hints` (Browse / See all): slim edge tabs, a one-time
/// nudge, darkening while the list is swiped, and a "Swipe to see more" cue until the first turn.
struct V23Pager<Item, Row: View, End: View, Empty: View>: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var inkSpace

    let items: [Item]
    let key: (Item) -> String
    /// Remembers this list's page for the session (per list and content).
    let listID: String
    var hints = false
    var rowHeight: CGFloat = EventRowV23View.height
    @ViewBuilder let row: (Item) -> Row
    let end: (Pager.EndVariant) -> End
    @ViewBuilder let empty: () -> Empty

    @MainActor private static var savedPages: [String: Int] { get { V23PagerMemory.pages } set { V23PagerMemory.pages = newValue } }
    @State private var page: Int?
    @State private var turned = false
    @State private var swiping = false
    @State private var nudge = false
    @State private var nudgeX: CGFloat = 0

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
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $page)
                .scrollDisabled(!nav)
                .modifier(SwipePhase(swiping: $swiping))
                .overlay { if hints && nav { edgeTabs(p.count) } }
                .rootSwipeExclusion("v23Pager.\(listID)")
                if hints && nav {
                    HStack(spacing: 8) { Text(app.T("Vuốt để xem thêm", "Swipe to see more")); Text("⟶") }
                        .font(.app(size: 12.5)).opacity(turned ? 0 : 0.6)
                        .animation(.easeOut(duration: 0.4), value: turned)
                        .padding(.top, 4)
                        .accessibilityHidden(true)
                }
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
                if hints && !UserDefaults.standard.bool(forKey: V23PagerMemory.nudgeKey) {
                    UserDefaults.standard.set(true, forKey: V23PagerMemory.nudgeKey)
                    nudge = true
                    runNudge()
                }
            }
            .onChange(of: signature) { _, sig in
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { page = Pager.clampPage(Self.savedPages[sig] ?? 0, pages.count) }
            }
            .onChange(of: page) { old, new in
                if let new { Self.savedPages[signature] = new }
                if old != nil && old != new { turned = true; Haptics.selection() }
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
            HStack(spacing: 2) {
                ForEach(Pager.pageWindow(current, count), id: \.self) { i in
                    let on = i == current
                    Button { go(i) } label: {
                        Text("\(i + 1)").font(.app(size: 14, weight: .semibold))
                            .foregroundStyle(on ? app.palette.paper : app.palette.ink)
                            .frame(minWidth: 44, minHeight: 44)
                            .background {
                                if on { Capsule().fill(app.palette.ink).frame(height: 32).matchedGeometryEffect(id: "ink", in: inkSpace) }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(app.T("Trang \(i + 1)", "Page \(i + 1)"))
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("\(listID).page.\(i + 1)")
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.46, dampingFraction: 0.78), value: current)
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

    /// Slim tabs at the edges (18 pt, clear of the prices). Both darken while the list is swiped.
    private func edgeTabs(_ count: Int) -> some View {
        HStack {
            if current > 0 {
                tab("‹", leading: true, label: app.T("Trang trước", "Previous page"), id: "\(listID).hintPrev") { go(current - 1) }
                    .opacity(swiping ? 1 : 0.6)
            }
            Spacer(minLength: 0)
            if current < count - 1 {
                tab("›", leading: false, label: app.T("Trang sau", "Next page"), id: "\(listID).hintNext") { go(current + 1) }
                    .offset(x: nudgeX)
            }
        }
        .animation(.easeOut(duration: swiping ? 0.12 : 0.6), value: swiping)
    }

    private func tab(_ glyph: String, leading: Bool, label: String, id: String, action: @escaping () -> Void) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: leading ? 0 : 10, bottomLeadingRadius: leading ? 0 : 10,
                                           bottomTrailingRadius: leading ? 10 : 0, topTrailingRadius: leading ? 10 : 0)
        return Button(action: action) {
            Text(glyph).font(.app(size: 15))
                .frame(width: 18, height: 56)
                .background(app.palette.ink.opacity(swiping ? 0.22 : 0.08), in: shape)
                .frame(width: 30, height: 64, alignment: leading ? .leading : .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    /// The one-time nudge toward the next page (never with Reduce Motion).
    private func runNudge() {
        guard !reduceMotion else { return }
        let steps: [(Double, CGFloat)] = [(0.8, -6), (1.08, 0), (1.36, -4), (1.64, 0)]
        for (t, x) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { withAnimation(.easeInOut(duration: 0.28)) { nudgeX = x } }
        }
    }
}

/// Session memory for the pagers (their pages) and the one-time nudge key.
@MainActor enum V23PagerMemory {
    static var pages: [String: Int] = [:]
    static let nudgeKey = "banbe.v23.pagerNudgeSeen"
}

/// Pairs an item with a stable id for ForEach without making `Item` Identifiable.
private struct Keyed<T> { let keyID: String; let value: T }

/// True while the list is being swiped (iOS 18's scroll phase; earlier systems keep the tabs still).
private struct SwipePhase: ViewModifier {
    @Binding var swiping: Bool
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollPhaseChange { _, phase in
                let moving = phase == .interacting || phase == .decelerating || phase == .tracking
                if moving != swiping { swiping = moving }
            }
        } else {
            content
        }
    }
}
