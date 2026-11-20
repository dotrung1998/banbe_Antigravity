import SwiftUI

// v2.3 Home sections (note 81): Shortlist, live line + Live now, See all fan card, Next up ticket cards.

// MARK: - Shortlist

/// "Near you": every open event Home lists, narrowed by Home's filters (UnifiedDiscovery.nearYou, web twin), four large
/// rows a page at least (more when the screen has room, see Pager.fittedPageSize), soonest first. A short last page
/// ends with an end card. Header, end card and empty state are word for word web's ShortlistV23.jsx.
struct ShortlistV23View: View {
    @EnvironmentObject private var app: AppState
    /// The open Home tab, shown after the title ("Near you · Tonight"); nil = no suffix (the list does not follow the tab).
    let tab: HomeHeroTab?
    /// The tab the end card words itself for: "all" = "Change area" instead of "See all events" (web `endTab`).
    var endTab: HomeHeroTab = .all
    let rows: [V23Row]
    /// The list before the Filters-owned filters (UnifiedDiscovery.nearYou `total`).
    let total: Int
    let filterBadge: Int
    let onFilters: () -> Void
    let onAction: (String) -> Void
    /// What narrows the list, as one chip under the header with × to clear (web `active`). Empty = no chip.
    var activeParts: [String] = []
    var onClearActive: (() -> Void)? = nil

    /// Prototype v2 (note 99): the list is "Near you", always soonest first — the tab's own name is the band above it.
    private var sub: ViEn { ViEn("gần nhất trước", "soonest first") }

    /// Home (unified discovery) pins the heading as a `Section` header under the folded band and lists the rest as its
    /// content; `.whole` is the one-block form.
    enum Part { case whole, header, list }
    var part: Part = .whole
    /// Space above the heading in `.whole` (HomeView puts part of it above its scroll anchor instead).
    var topPadding: CGFloat = 28

    var body: some View {
        switch part {
        case .whole:
            VStack(alignment: .leading, spacing: 0) {
                headerRow.padding(.horizontal, 20).padding(.bottom, 12)
                listBody
            }
            .foregroundStyle(app.palette.ink)
            .padding(.top, topPadding)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home.shortlistSection")
        case .header:
            // The caller puts 18 pt above it; 10 pt inside keeps the `.whole` 28 pt rhythm and some air under the band.
            headerRow
                .foregroundStyle(app.palette.ink)
                .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 12)
        case .list:
            VStack(alignment: .leading, spacing: 0) { listBody }
                .foregroundStyle(app.palette.ink)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("home.shortlistSection")
        }
    }

    private var headerRow: some View {
        let n = rows.count
        return HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                // The open tab beside the title: same size, quieter (ink2), after a small middle dot.
                (Text(app.T("Gần bạn", "Near you"))
                    + (tab.map { Text(" · ").foregroundStyle(app.palette.ink2) + Text(app.T($0.vi, $0.en)).foregroundStyle(app.palette.ink2) } ?? Text("")))
                    .font(.app(size: 19)).accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("home.shortlistTitle")
                Button(action: onFilters) {
                    Text(filterBadge > 0 && total > n
                         ? app.T("\(n) trên \(total) sự kiện · \(sub.vi)", "\(n) of \(total) events · \(sub.en)")
                         : app.T("\(n) sự kiện · \(sub.vi)", "\(n) \(n == 1 ? "event" : "events") · \(sub.en)"))
                        .font(.app(size: 12.5)).foregroundStyle(app.palette.ink2)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.filterSummary")
            }
            Spacer(minLength: 0)
            Button(action: onFilters) {
                Image(systemName: "slider.horizontal.3").font(.app(size: 16))
                    .frame(width: 44, height: 44)
                    .background(app.palette.block, in: Circle())
                    .overlay(alignment: .topTrailing) {
                        if filterBadge > 0 {
                            Text("\(filterBadge)").font(.app(size: 11.5, weight: .bold)).foregroundStyle(app.palette.paper)
                                .frame(minWidth: 18, minHeight: 18).padding(.horizontal, 2)
                                .background(app.palette.ink, in: Capsule())
                                .overlay(Capsule().stroke(app.palette.paper, lineWidth: 2))
                                .offset(x: 2, y: -2)
                                .accessibilityIdentifier("home.filterBadge")
                        }
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(filterBadge > 0 ? app.T("Bộ lọc, đang bật \(filterBadge)", "Filters, \(filterBadge) on") : app.T("Bộ lọc", "Filters"))
            .accessibilityIdentifier("home.filtersButton")
        }
    }

    @ViewBuilder private var listBody: some View {
        let card = ListEnd.shortlistEnd(total: total, shown: rows.count, filtersOn: filterBadge > 0, tab: endTab.rawValue)
        if !activeParts.isEmpty {
            HStack(spacing: 0) {
                Text(activeParts.joined(separator: " · ")).font(.app(size: 13.5, weight: .semibold)).lineLimit(1)
                    .padding(.leading, 14)
                Button(action: { Haptics.selection(); onClearActive?() }) {
                    Image(systemName: "xmark").font(.app(size: 12, weight: .bold))
                        .frame(width: 40, height: 36).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(app.T("Xoá tìm kiếm và bộ lọc", "Clear search and filters"))
                .accessibilityIdentifier("home.activeChip.clear")
            }
            .foregroundStyle(app.palette.paper)
            .frame(minHeight: 36)
            .background(app.palette.ink, in: Capsule())
            .padding(.horizontal, 20).padding(.bottom, 12)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home.activeChip")
        }
        V23Pager(items: rows, key: \.key, listID: "home.shortlist",
                 row: { r in EventRowV23View(row: r, onToggleSave: { app.toggleFavorite(r.key) }) { app.goEvent(r.key) } },
                 end: { v in EndCardView(model: card, variant: v, onAction: onAction) },
                 empty: {
                     // Web twin: the filters decide which empty card it is (ShortlistV23.jsx `filtersOn`).
                     EndCardView(model: filterBadge > 0
                        ? EndCardModel(kind: "empty", eyebrow: ViEn("Bộ lọc", "Filters"),
                                       title: ViEn("Không có sự kiện nào khớp bộ lọc.", "Nothing matches these filters."),
                                       body: ViEn("Xoá bộ lọc để xem lại mọi thứ.", "Clear the filters to see everything again."),
                                       actions: [.init(act: "clear-filters", label: ViEn("Xoá bộ lọc", "Clear filters"), primary: true, testId: "home.shortlistClear")])
                        : EndCardModel(kind: "empty", eyebrow: ViEn("Sự kiện", "Events"),
                                       title: ViEn("Chưa có sự kiện nào.", "Nothing on yet."),
                                       body: ViEn("Duyệt theo loại để tìm thứ đang diễn ra.", "Browse by type to find something on."),
                                       actions: [.init(act: "types", label: ViEn("Duyệt theo loại", "Browse by type"), primary: true, testId: "home.shortlistTypes")]),
                                 variant: .solo, onAction: onAction)
                 })
    }
}

// MARK: - Live line

/// Full motion: a seamless ticker with Live / Paused. Reduced motion: one whole update at a time with when, and
/// ‹ n/N › steps by a dissolve. A tap opens Live now. Updates: `LiveLine.updates` (real data only).
struct LiveLineView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let updates: [LiveLine.Update]
    @Binding var index: Int
    let onOpen: () -> Void
    @State private var paused = false
    @State private var runWidth: CGFloat = 0
    @State private var start = Date()
    @State private var pausedAt: TimeInterval?
    @State private var dotOn = true

    var body: some View {
        if !updates.isEmpty {
            let i = min(index, updates.count - 1)
            HStack(spacing: 2) {
                if reduceMotion { reduced(i) } else { ticker }
            }
            .padding(.leading, 14).padding(.trailing, 4)
            .frame(minHeight: 48)
            .background(app.palette.block, in: Capsule())
            .clipShape(Capsule())
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 20).padding(.top, 16)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(app.T("Đang diễn ra", "Live activity"))
            .accessibilityIdentifier("home.liveLine")
        }
    }

    private var dot: some View {
        Circle().fill(BanbeTheme.alert).frame(width: 7, height: 7)
            .opacity(reduceMotion || paused ? 1 : (dotOn ? 1 : 0.35))
            .animation(reduceMotion || paused ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: dotOn)
            .onAppear { dotOn = false }
            .accessibilityHidden(true)
    }

    private func reduced(_ i: Int) -> some View {
        let cur = updates[i]
        return Group {
            Button(action: onOpen) {
                HStack(spacing: 8) {
                    dot
                    VStack(alignment: .leading, spacing: 0) {
                        Text(cur.text.t(app.isEN)).font(.app(size: 13.5, weight: .semibold)).lineLimit(2)
                        if let w = cur.when { Text(w).font(.app(size: 11.5)).opacity(0.72) }
                    }
                    .id(cur.id)
                    .transition(.opacity)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(app.T("Đang diễn ra, xem mọi cập nhật", "Live activity, see all updates") + ". " + cur.text.t(app.isEN))
            .accessibilityIdentifier("home.liveOpen")
            side("chevron.left", enabled: i > 0, label: app.T("Cập nhật trước", "Previous update"), id: "home.livePrev") {
                withAnimation(.easeOut(duration: 0.2)) { index = LiveLine.step(i, -1, updates.count) }
            }
            Text("\(i + 1)/\(updates.count)").font(.app(size: 12.5, weight: .bold)).monospacedDigit().frame(minWidth: 30)
                .accessibilityIdentifier("home.liveIndex")
            side("chevron.right", enabled: i < updates.count - 1, label: app.T("Cập nhật sau", "Next update"), id: "home.liveNext") {
                withAnimation(.easeOut(duration: 0.2)) { index = LiveLine.step(i, 1, updates.count) }
            }
        }
    }

    private func side(_ symbol: String, enabled: Bool, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.app(size: 14, weight: .medium)).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private var texts: [String] { updates.map { $0.text.t(app.isEN) } }

    private var runRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(texts.enumerated()), id: \.offset) { _, t in
                Text(t).padding(.trailing, 28)
                Text("·").opacity(0.4).padding(.trailing, 28)
            }
        }
        .font(.app(size: 13.5, weight: .medium))
        .lineLimit(1)
        .fixedSize()
    }

    private var ticker: some View {
        let duration = LiveLine.seconds(texts)
        return Group {
            Button(action: onOpen) {
                // The run sits in an overlay so its (long) width never widens the line or the page around it.
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .overlay(alignment: .leading) {
                        TimelineView(.animation(paused: paused)) { ctx in
                            let elapsed = pausedAt ?? ctx.date.timeIntervalSince(start)
                            let w = max(1, runWidth)
                            let x = -CGFloat((elapsed / duration).truncatingRemainder(dividingBy: 1)) * w
                            HStack(spacing: 0) {
                                runRow.background(GeometryReader { g in Color.clear.onAppear { runWidth = g.size.width }
                                    .onChange(of: g.size.width) { _, v in runWidth = v } })
                                runRow
                            }
                            .fixedSize()
                            .offset(x: x)
                        }
                    }
                    .clipped()
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.9), .init(color: .clear, location: 1)],
                                     startPoint: .leading, endPoint: .trailing))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(app.T("Đang diễn ra, xem mọi cập nhật", "Live activity, see all updates"))
            .accessibilityIdentifier("home.liveOpen")
            Button {
                if paused {
                    if let p = pausedAt { start = Date().addingTimeInterval(-p) }
                    pausedAt = nil
                } else {
                    pausedAt = Date().timeIntervalSince(start)
                }
                paused.toggle()
            } label: {
                HStack(spacing: 6) {
                    dot
                    Text(paused ? app.T("Đã dừng", "Paused") : app.T("Trực tiếp", "Live")).font(.app(size: 12.5, weight: .bold))
                    if !paused { Text("❙❙").font(.app(size: 10)).tracking(1).accessibilityHidden(true) }
                }
                .padding(.horizontal, 12).frame(minHeight: 44)
                .background(app.palette.paper, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.leading, 6)
            .accessibilityLabel(paused ? app.T("Tiếp tục cập nhật trực tiếp", "Resume live updates") : app.T("Tạm dừng cập nhật trực tiếp", "Pause live updates"))
            .accessibilityAddTraits(paused ? .isSelected : [])
            .accessibilityIdentifier("home.livePause")
        }
    }
}

/// "Live now": every update of the live line, the one shown on Home marked (Reduced form), each event with Open.
struct LiveNowSheet: View {
    @EnvironmentObject private var app: AppState
    let updates: [LiveLine.Update]
    let shownIndex: Int?
    let onOpen: (String, Int) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.T("Đang diễn ra", "Live now")).font(.app(size: 18, weight: .semibold))
                    Text(app.T("\(updates.count) cập nhật hôm nay", "\(updates.count) \(updates.count == 1 ? "update" : "updates") today"))
                        .font(.app(size: 13)).opacity(0.72)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.app(size: 15, weight: .semibold))
                        .frame(width: 44, height: 44).background(app.palette.ink.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(app.T("Đóng", "Close"))
                .accessibilityIdentifier("liveNow.close")
            }
            .padding(.leading, 20).padding(.trailing, 16).padding(.top, 14).padding(.bottom, 8)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(updates.enumerated()), id: \.element.id) { i, u in
                        let here = shownIndex == i
                        let body = HStack(alignment: .top, spacing: 12) {
                            Circle().fill(i == 0 ? BanbeTheme.alert : app.palette.ink.opacity(0.3)).frame(width: 8, height: 8).padding(.top, 6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(u.text.t(app.isEN)).font(.app(size: 15, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                                let small = [u.when, here ? app.T("đang hiện trên Trang chủ", "showing on Home") : nil].compactMap { $0 }.joined(separator: " · ")
                                if !small.isEmpty { Text(small).font(.app(size: 12.5)).opacity(0.72) }
                            }
                            Spacer(minLength: 0)
                            if u.eventId != nil { Text(app.T("Mở", "Open") + " ›").font(.app(size: 13.5, weight: .semibold)) }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .frame(minHeight: 56)
                        .background(here ? app.palette.block : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        if let id = u.eventId {
                            Button { onOpen(id, i) } label: { body.contentShape(Rectangle()) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("liveNow.open.\(i)")
                        } else {
                            body.accessibilityElement(children: .combine)
                        }
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 24)
            }
        }
        .foregroundStyle(app.palette.ink)
        .presentationDetents([.medium, .large])
        .presentationBackground(app.palette.paper)
        .accessibilityIdentifier("liveNow.sheet")
    }
}

// MARK: - Hero suggestion card

/// A suggestion after a short hero pager (Weekend, All events, Browse by type): the See all card's size, a quiet glass
/// card with the other way to look. Rule and words: ListEnd.heroSuggestions. Web twin: HeroSuggestCard.jsx.
struct HeroSuggestCard: View {
    @EnvironmentObject private var app: AppState
    let model: ListEnd.HeroSuggestion
    let width: CGFloat
    let height: CGFloat
    let onOpen: () -> Void

    var body: some View {
        SwipeSafeButton(action: onOpen) {
            ZStack(alignment: .bottomLeading) {
                Text(app.T("Thử xem", "Try instead").uppercased())
                    .font(.app(size: 11, weight: .semibold)).tracking(1.5)
                    .foregroundStyle(.white.opacity(0.62))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // Owner 2026-11-20: the card's line-art sketch fills the upper area (web HeroLineArt, same drawing).
                HeroLineArt(kind: model.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 28)
                VStack(alignment: .leading, spacing: 6) {
                    Text(app.T(model.title.vi, model.title.en))
                        .font(BanbeTheme.display(26)).lineSpacing(0)
                    Text(app.T(model.detail.vi, model.detail.en))
                        .font(.app(size: 13)).foregroundStyle(.white.opacity(0.78))
                    Image(systemName: "arrow.right").font(.app(size: 16, weight: .medium))
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.14), in: Circle())
                        .padding(.top, 10)
                }
            }
            .padding(20)
            .foregroundStyle(.white)
            .frame(width: width, height: height, alignment: .leading)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(app.T(model.title.vi, model.title.en)). \(app.T(model.detail.vi, model.detail.en))")
        .accessibilityIdentifier("home.hero.suggest.\(model.id)")
    }
}

// MARK: - Hero line art

/// Line-art sketch for the hero end cards: the HeroArt* template vector imagesets, generated from the web's
/// src/lib/heroLineArt.js by scripts/gen-hero-line-art.mjs (228 × 140 at 1:1, so the 1.5 stroke stays 1.5 pt).
/// Decorative, hidden from VoiceOver. Drawn white at 62% over the card's glass, as on web.
struct HeroLineArt: View {
    let kind: String

    private static let kinds: Set<String> = ["tonight", "weekend", "all", "browse", "foryou"]

    var body: some View {
        let k = Self.kinds.contains(kind) ? kind : "all"
        Image("HeroArt" + k.prefix(1).uppercased() + k.dropFirst())
            .renderingMode(.template)
            .resizable()
            .frame(width: 228, height: 140)
            .foregroundStyle(.white.opacity(0.62))
            .accessibilityHidden(true)
    }
}

// MARK: - See all fan card

/// The last card of the Home rail: three photos swing into a fan, the tab's chip arrives and glows gold once, each
/// time the card comes back into view. Reduce Motion: the fan simply rests. A tap opens See all for that tab.
struct SeeAllFanCard: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let photos: [String]
    let label: ViEn
    let count: Int
    /// The tab id (foryou/tonight/weekend/all): its line-art sketch stands in for a fan of fewer than 3 photos.
    var art: String = "all"
    /// For You, signed in: a small "Edit preferences" pill that opens the For You preferences editor.
    var onEditPrefs: (() -> Void)? = nil
    let onOpen: () -> Void
    @State private var t: CGFloat = 1
    @State private var chip: CGFloat = 1
    @State private var glow = false

    private static let gold = Color(red: 0.8, green: 0.62, blue: 0.16)

    var body: some View {
        SwipeSafeButton(action: onOpen) {
            ZStack {
                if sketch {
                    HeroLineArt(kind: art)
                        .offset(y: 8 + (1 - t) * 14)
                        .opacity(Double(t))
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 44)
                }
                ZStack {
                    ForEach(Array(fanPhotos.enumerated()), id: \.offset) { i, src in
                        let n = fanPhotos.count
                        let pos = n == 1 ? 1 : n == 2 ? [0, 2][i] : i
                        photo(src, pos: pos)
                    }
                    HStack(spacing: 4) {
                        Text("★").foregroundStyle(Self.gold)
                        Text(label.t(app.isEN))
                    }
                    .font(.app(size: 12, weight: .semibold))
                    .foregroundStyle(app.palette.ink)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(app.palette.paper, in: Capsule())
                    .overlay(Capsule().stroke(Self.gold.opacity(0.7), lineWidth: 1))
                    .shadow(color: Self.gold.opacity(glow ? 0.5 : 0), radius: glow ? 7 : 0)
                    .offset(y: 62 + (1 - chip) * -22)
                    .opacity(chip)
                    .zIndex(3)
                }
                .offset(y: 128 - 180)
                VStack(spacing: 4) {
                    Text(app.T("Xem cả \(count)", "See all \(count)")).font(.app(size: 22, weight: .light))
                    Text(app.T("sự kiện trong mục này", "events in this tab") + " →").font(.app(size: 13)).opacity(0.8)
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 28)
            }
            .foregroundStyle(.white)
            .frame(width: 268, height: 360)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear(perform: play)
        .accessibilityLabel(app.T("Xem cả \(count) sự kiện trong \(label.vi)", "See all \(count) events in \(label.en)"))
        .accessibilityIdentifier("home.hero.seeAll")
        .overlay(alignment: .topTrailing) {
            if let onEditPrefs {
                SwipeSafeButton(action: onEditPrefs) {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3").font(.app(size: 11, weight: .semibold)).accessibilityHidden(true)
                        Text(app.T("Sửa sở thích", "Edit preferences")).font(.app(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).frame(minHeight: 32)
                    .background(Color.white.opacity(0.12), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
                    .padding(6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(6)
                .accessibilityIdentifier("home.hero.editPrefs")
            }
        }
    }

    /// Fewer than 3 real photos would make a lone or lopsided fan (owner 2026-11-20): draw the tab's sketch instead.
    private var realPhotos: [String] { photos.filter { !$0.isEmpty } }
    private var sketch: Bool { realPhotos.count < 3 }
    private var fanPhotos: [String] { sketch ? [] : Array(realPhotos.prefix(3)) }

    private func photo(_ src: String, pos: Int) -> some View {
        let rest: [(CGFloat, CGFloat, Double)] = [(-58, 8, -8), (0, -6, 0), (58, 8, 8)]
        let from: [(CGFloat, CGFloat, Double)] = [(-140, 10, -2), (0, 46, 0), (140, 10, 2)]
        let r = rest[pos], f = from[pos]
        return ZStack {
            Color(hex: 0x2A2620)
            if !src.isEmpty { CatalogPhoto(path: src, height: 124, width: 96, cornerRadius: 0) }
        }
        .frame(width: 96, height: 124)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 11, y: 6)
        .rotationEffect(.degrees(f.2 + (r.2 - f.2) * Double(t)))
        .offset(x: f.0 + (r.0 - f.0) * t, y: f.1 + (r.1 - f.1) * t)
        .opacity(Double(min(1, t * 1.8)))
        .zIndex(pos == 1 ? 2 : 1)
    }

    private func play() {
        guard !reduceMotion else { t = 1; chip = 1; return }
        var tr = Transaction(); tr.disablesAnimations = true
        withTransaction(tr) { t = 0; chip = 0; glow = false }
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 1.5)) { t = 1 }
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.9).delay(0.9)) { chip = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
            withAnimation(.easeOut(duration: 0.3)) { glow = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation(.easeOut(duration: 0.3)) { glow = false } }
        }
    }
}

// MARK: - Next up

/// One upcoming event of the viewer, shaped for the ticket card.
struct NextUpItem: Identifiable {
    var id: String { g.eventId }
    let g: NextUp.Group
    let name: String
    let img: String
    let kicker: String
    let badge: (weekday: String, day: String, month: String)
    let time: String
    let timeNote: ViEn?
    let mapsURL: URL?
    let status: NextUp.Status
    let chip: ViEn?
    let people: (main: ViEn, note: ViEn?)
}

extension AppState {
    /// Every upcoming ticket of the viewer, one card per event, soonest first, from the bookings Home loads.
    func nextUpItems(now: Date = Date()) -> [NextUpItem] {
        guard isSignedIn else { return [] }
        var info: [String: NextUp.EventInfo] = [:]
        var events: [String: CatalogEvent] = [:]
        for b in paymentBookings where info[b.eventKey] == nil {
            guard let e = resolvedEvent(for: b.eventKey), let start = e.startDate else { continue }
            let startMs = start.timeIntervalSince1970 * 1000
            info[b.eventKey] = NextUp.EventInfo(startMs: startMs, endMs: eventEndDate(e).map { $0.timeIntervalSince1970 * 1000 },
                                                cancelled: e.cancelled)
            events[b.eventKey] = e
        }
        let rows = paymentBookings.map { b in
            (eventId: b.eventKey,
             booking: ReserveBarV23.SeatBooking(id: b.id.uuidString.lowercased(), qty: b.qty, status: b.status, paymentState: b.paymentState.rawValue,
                                                holdExpiresAt: b.holdExpiresAt, verifyDueAt: b.verifyDueAt, createdAt: nil),
             gifted: b.isGifted)
        }
        return NextUp.groups(rows, events: info, now: now).compactMap { g in
            guard let e = events[g.eventId] else { return nil }
            let tz = e.timeZoneID ?? "Asia/Ho_Chi_Minh"
            let when = e.when.components(separatedBy: " ▪︎ ")
            let start = when.count > 1 ? when[1] : ""
            let end = eventEndNote(e, start: start)
            return NextUpItem(
                g: g, name: e.name, img: e.img,
                kicker: [trStatus(e.catDisplay.isEmpty ? e.cat : e.catDisplay), e.location?.area ?? e.locationLabel ?? ""].filter { !$0.isEmpty }.joined(separator: " · "),
                badge: NextUp.dateBadge(g.startMs, tz: tz, english: isEN),
                time: start, timeNote: end, mapsURL: e.mapsURL,
                status: NextUp.status(g, now: now), chip: NextUp.chip(g, now: now, tz: tz), people: NextUp.people(g))
        }
    }

    /// The event's end (note 82), when it has one; nil until the end time is loaded for this event.
    func eventEndDate(_ e: CatalogEvent) -> Date? {
        guard let start = e.startDate, let endTime = e.endTime, let startHM = e.when.components(separatedBy: " ▪︎ ").dropFirst().first else { return nil }
        return EventEnd.endDate(start: start, startTime: String(startHM), endTime: endTime)
    }

    /// "to 22:30", "to 00:30 (+1)", or "open-ended" (note 82).
    func eventEndNote(_ e: CatalogEvent, start: String) -> ViEn? {
        if let end = e.endTime {
            let next = EventEnd.endsNextDay(start, end) ? " (+1)" : ""
            return ViEn("đến \(end)\(next)", "to \(end)\(next)")
        }
        return e.endOpen ? ViEn("chưa có giờ kết thúc", "no end time yet") : nil
    }
}

/// "Next up": the viewer's upcoming tickets as ticket cards. Several: a swipeable track, "1 of 3" and dots.
struct NextUpV23View: View {
    @EnvironmentObject private var app: AppState
    let items: [NextUpItem]
    @State private var current: String?

    private var index: Int { items.firstIndex { $0.id == current } ?? 0 }

    var body: some View {
        let many = items.count > 1
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(app.T("Sắp tới", "Next up")).font(BanbeTheme.display(22)).accessibilityAddTraits(.isHeader)
                if many {
                    Text(app.T("\(index + 1) / \(items.count)", "\(index + 1) of \(items.count)"))
                        .font(.app(size: 13, weight: .semibold)).foregroundStyle(app.palette.ink3)
                        .accessibilityIdentifier("home.nextUp.count")
                }
                Spacer()
                Button { app.goSchedule() } label: {
                    Text(app.T("Lịch", "Schedule")).font(.app(size: 14, weight: .medium)).foregroundStyle(app.palette.ink2).frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.nextUp.schedule")
            }
            .padding(.horizontal, 20)
            if many {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(items) { it in card(it).containerRelativeFrame(.horizontal) { w, _ in w - 64 }.id(it.id) }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, 20, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $current)
                .rootSwipeExclusion("homeNextUp")
                HStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
                        Button { withAnimation { current = it.id } } label: {
                            Capsule().fill(app.palette.ink).frame(width: i == index ? 16 : 6, height: 6).opacity(i == index ? 0.85 : 0.22)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(app.T("Vé \(i + 1)", "Ticket \(i + 1)"))
                        .accessibilityAddTraits(i == index ? .isSelected : [])
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: index)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
            } else if let it = items.first {
                card(it).padding(.horizontal, 20)
            }
        }
        .foregroundStyle(app.palette.ink)
        .padding(.top, 14).padding(.bottom, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.nextUp")
    }

    private func card(_ it: NextUpItem) -> some View {
        let tone = it.status.tone == "moss" ? app.palette.update : app.palette.honey
        return VStack(spacing: 0) {
            SwipeSafeButton { app.goEvent(it.g.eventId) } label: {
                ZStack(alignment: .bottomLeading) {
                    Color(hex: 0x241E17)
                    if !it.img.isEmpty { Color.clear.overlay { CatalogPhoto(path: it.img, cornerRadius: 0) }.clipped() }
                    LinearGradient(stops: [.init(color: .black.opacity(0.30), location: 0), .init(color: .clear, location: 0.34),
                                           .init(color: .black.opacity(0.25), location: 0.55), .init(color: .black.opacity(0.78), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 4) {
                        if !it.kicker.isEmpty { Text(it.kicker.uppercased()).font(.app(size: 11.5, weight: .semibold)).tracking(1.4).opacity(0.88).lineLimit(1) }
                        Text(it.name).font(BanbeTheme.display(26)).lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.bottom, 18)
                }
                .frame(height: 206)
                .overlay(alignment: .topLeading) {
                    VStack(spacing: 2) {
                        Text(it.badge.weekday).font(.app(size: 11, weight: .bold))
                        Text(it.badge.day).font(.app(size: 24, weight: .bold))
                        Text(it.badge.month).font(.app(size: 11, weight: .bold))
                    }
                    .foregroundStyle(Color(red: 0.106, green: 0.098, blue: 0.086))
                    .frame(minWidth: 52).padding(.vertical, 7).padding(.horizontal, 8)
                    .background(Color(red: 0.97, green: 0.96, blue: 0.93).opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(12)
                    .accessibilityIdentifier("home.nextUp.date")
                }
                .overlay(alignment: .topTrailing) {
                    if let chip = it.chip {
                        Label(chip.t(app.isEN), systemImage: "clock").font(.app(size: 13, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 12).frame(height: 32)
                            .background(.ultraThinMaterial.opacity(0.6), in: Capsule())
                            .background(Color.black.opacity(0.4), in: Capsule())
                            .padding(12)
                            .accessibilityIdentifier("home.nextUp.chip")
                    }
                }
                .zoomSource(it.g.eventId)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(it.name)
            .accessibilityAddTraits(.isLink)
            ticketTear
            VStack(spacing: 14) {
                HStack(alignment: .top, spacing: 0) {
                    cell(app.T("Bắt đầu", "Starts"), Text(it.time), it.timeNote?.t(app.isEN), first: true)
                    cell(app.T("Vé", "Tickets"), Text(it.people.main.t(app.isEN)), it.people.note?.t(app.isEN))
                    cell(app.T("Trạng thái", "Status"),
                         Text(Image(systemName: it.status.icon == "check" ? "checkmark" : "clock")) + Text(" " + it.status.text.t(app.isEN)),
                         it.status.note?.t(app.isEN), tone: tone)
                }
                HStack(spacing: 10) {
                    Button { act(it.status.action, it) } label: {
                        Label(it.status.button.t(app.isEN), systemImage: it.status.action == "ticket" ? "qrcode" : "clock")
                            .font(.app(size: 15, weight: .bold)).foregroundStyle(app.palette.paper)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(app.palette.ink, in: Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityIdentifier("home.nextUp.primary")
                    if let url = it.mapsURL {
                        Link(destination: url) {
                            Label(app.T("Chỉ đường", "Directions"), systemImage: "mappin")
                                .font(.app(size: 15, weight: .semibold)).foregroundStyle(app.palette.ink)
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .background(app.palette.surface1, in: Capsule())
                                .overlay(Capsule().stroke(app.palette.ink.opacity(0.06), lineWidth: 1))
                        }
                        .accessibilityIdentifier("home.nextUp.directions")
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 16)
        }
        .background(app.palette.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.nextUp.card.\(it.g.eventId)")
    }

    private var ticketTear: some View {
        HStack(spacing: 0) {
            notch(leading: true)
            Rectangle().fill(.clear).frame(height: 1.5)
                .overlay(Rectangle().stroke(app.palette.ink.opacity(0.18), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])).frame(height: 0.1))
                .padding(.horizontal, 4)
            notch(leading: false)
        }
        .frame(height: 18).padding(.vertical, -9).zIndex(2)
        .accessibilityHidden(true)
    }

    private func notch(leading: Bool) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: leading ? 0 : 9, bottomLeadingRadius: leading ? 0 : 9,
                                           bottomTrailingRadius: leading ? 9 : 0, topTrailingRadius: leading ? 9 : 0)
        return shape.fill(app.palette.paper).overlay(shape.fill(Color.black.opacity(0.07)))
            .overlay(shape.fill(LinearGradient(colors: [.black.opacity(0.22), .clear], startPoint: .top, endPoint: .center)))
            .clipShape(shape)
            .frame(width: 10, height: 18)
    }

    private func cell(_ label: String, _ value: Text, _ note: String?, first: Bool = false, tone: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.app(size: 11, weight: .bold)).tracking(1.3).foregroundStyle(app.palette.ink3)
            value.font(.app(size: 15, weight: .medium)).foregroundStyle(tone ?? app.palette.ink).lineLimit(1)
            if let note { Text(note).font(.app(size: 12.5)).foregroundStyle(app.palette.ink2).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, first ? 0 : 12).padding(.trailing, first ? 10 : 0)
        .overlay(alignment: .leading) { if !first { Rectangle().fill(app.palette.ink.opacity(0.12)).frame(width: 1) } }
        .accessibilityElement(children: .combine)
    }

    private func act(_ action: String, _ it: NextUpItem) {
        guard let id = UUID(uuidString: it.g.primaryId) else { return app.goEvent(it.g.eventId) }
        switch action {
        case "pay": app.openPaymentDetails(id, back: .home)
        default: Task { await app.openBookingConfirmed(bookingID: id, eventKey: it.g.eventId, back: .home) }
        }
    }
}
