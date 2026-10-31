import SwiftUI

// Home discovery building blocks (note 50): category glyph row, search bar, event card (photo on top,
// details underneath), compact list row, the "Next up" reminder banner and the weekend rail card.
// Web twins: src/components/home/HomeDiscoveryParts.jsx.
//
// Card rule from the "4 levels" video (staff variant): the name and numbers come OFF the photo so every
// card reads the same whatever the host uploaded. On the photo: only small badges (date, Save, Almost full).

/// Everything one card / row shows, computed once by HomeView from the shared discovery item.
struct DiscoveryCardModel: Identifiable, Equatable {
    var id: String { key }
    let key: String
    let name: String
    let img: String
    let dateBadge: String
    let priceLabel: String
    let isFree: Bool
    let metaLine: String
    let fill: HomeDiscovery.FillBadge
    let cancelled: Bool
    let going: Bool
    /// best | popular | nil
    let label: String?
    /// What kind of evening it is (event type profiles), e.g. "Bàn 8 người · Có món chay · BYO"; nil when none.
    var typeLine: String? = nil
}

/// Line-style category glyphs. SF Symbols at one weight stand in for the web's hand-drawn SVG set
/// (same meaning per key; the create flow already uses these symbols).
enum CategoryGlyph {
    static func symbol(_ key: String) -> String {
        switch key {
        case "supper": return "fork.knife"
        case "fashion": return "tshirt"
        case "gallery": return "photo.artframe"
        case "music": return "music.note"
        case "popup": return "storefront"
        default: return "square.grid.2x2"
        }
    }
}

/// Quiet tinted rounded-square tiles; they stay out of the way of the event photos below.
/// Category tiles. `keys` is the row (All first, then categories with events in the area, most first;
/// HomeDiscovery.categoryRowKeys) and `counts` what tapping each one would show. "Show all" opens every category A–Z.
struct HomeCategoryRow: View {
    @EnvironmentObject private var app: AppState
    var keys: [String] = HomeDiscovery.categories.map(\.key)
    var counts: [String: Int]? = nil
    var onShowAll: (() -> Void)? = nil
    /// Simple Shell: the slim version (vertical padding cut to 8); the tiles, counts and end padding are unchanged.
    var compact = false
    // Today's sizes at the default text size, growing with Dynamic Type; labels wrap instead of clipping.
    @ScaledMetric(relativeTo: .caption) private var labelSize: CGFloat = 11.5
    @ScaledMetric(relativeTo: .caption) private var columnWidth: CGFloat = 60
    @ScaledMetric(relativeTo: .caption) private var tileSize: CGFloat = 48

    private func tile(_ symbol: String, active: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 19, weight: .regular))
            .foregroundStyle(active ? app.palette.paper : app.palette.ink)
            .frame(width: tileSize, height: tileSize)
            .background(active ? app.palette.ink.opacity(0.9) : app.palette.ink.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: BanbeTheme.Radius.tile, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: BanbeTheme.Radius.tile, style: .continuous)
                    .strokeBorder(app.palette.ink.opacity(active ? 0 : 0.06), lineWidth: 1)
            }
            .shadow(color: .black.opacity(active ? 0.18 : 0), radius: 3, y: 2)
    }

    var body: some View {
        let byKey = Dictionary(uniqueKeysWithValues: HomeDiscovery.categories.map { ($0.key, $0) })
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 2) {
                ForEach(keys, id: \.self) { key in
                    if let c = byKey[key] {
                        let cats = app.homeFilters.cats
                        let active = c.key == "all" ? cats.isEmpty : cats.contains(c.key)
                        let n = counts?[c.key]
                        SwipeSafeButton {
                            if !active { Haptics.selection() }
                            app.pickFilter(c.key)
                        } label: {
                            VStack(spacing: 4) {
                                tile(CategoryGlyph.symbol(c.key), active: active)
                                Text(app.T(c.vi, c.en))
                                    .font(.system(size: labelSize, weight: active ? .semibold : .medium))
                                    .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.85)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .opacity(active ? 1 : 0.8)
                                if let n {
                                    Text("\(n)").font(.system(size: labelSize - 0.5)).monospacedDigit().opacity(0.55)
                                        .accessibilityIdentifier("home.categoryCount.\(c.key)")
                                }
                            }
                            .frame(width: columnWidth)
                            .foregroundStyle(app.palette.ink)
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(n.map { app.T("\(c.vi), \($0) sự kiện", "\(c.en), \($0) events") } ?? app.T(c.vi, c.en))
                        .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
                        // Same ids as the old text chips (UI tests filter by category through these).
                        .accessibilityIdentifier("filter.\(c.key)")
                        .animation(.easeOut(duration: 0.15), value: active)
                    }
                }
                if let onShowAll {
                    SwipeSafeButton { onShowAll() } label: {
                        VStack(spacing: 4) {
                            tile("ellipsis", active: false)
                            Text(app.T("Xem tất cả", "Show all"))
                                .font(.system(size: labelSize, weight: .medium))
                                .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.85)
                                .fixedSize(horizontal: false, vertical: true)
                                .opacity(0.8)
                        }
                        .frame(width: columnWidth)
                        .foregroundStyle(app.palette.ink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(app.T("Xem tất cả danh mục", "Show all categories"))
                    .accessibilityIdentifier("home.category.showAll")
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, compact ? 8 : 12).padding(.bottom, compact ? 0 : 4)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .rootSwipeExclusion("homeCategories")
    }
}

/// Every category A–Z with what tapping it would show in the current area. Zero ones stay visible, dimmed.
struct HomeCategorySheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    let counts: [String: Int]

    var body: some View {
        let byKey = Dictionary(uniqueKeysWithValues: HomeDiscovery.categories.map { ($0.key, $0) })
        let keys = HomeDiscovery.categorySheetKeys(EventTypes.categoryDefs(), lang: app.isEN ? "en" : "vi")
        NavigationStack {
            List(keys, id: \.self) { key in
                if let c = byKey[key] {
                    let n = counts[key] ?? 0
                    let active = app.homeFilters.cats.contains(key)
                    Button {
                        Haptics.selection()
                        app.pickFilter(key)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: CategoryGlyph.symbol(key)).font(.system(size: 18))
                                .frame(width: 40, height: 40)
                                .background(app.palette.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: BanbeTheme.Radius.tile, style: .continuous))
                            Text(app.T(c.vi, c.en)).font(.body.weight(active ? .semibold : .regular))
                            Spacer()
                            Text("\(n)").font(.subheadline).monospacedDigit().opacity(0.7)
                            if active { Image(systemName: "checkmark").font(.subheadline.weight(.semibold)) }
                        }
                        .foregroundStyle(app.palette.ink)
                        .opacity(n == 0 ? 0.45 : 1)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(app.T("\(c.vi), \(n) sự kiện", "\(c.en), \(n) events"))
                    .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
                    .accessibilityIdentifier("home.categorySheet.\(key)")
                }
            }
            .listStyle(.plain)
            .navigationTitle(app.T("Tất cả danh mục", "All categories"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(app.T("Đóng", "Close"))
                        .accessibilityIdentifier("home.categorySheet.close")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .hidesDock("home.categorySheet")  // the dock window would otherwise float over the list (note 45)
        .accessibilityIdentifier("home.categorySheet")
    }
}

/// Full-width search entry. The placeholder says what you can actually search for.
struct HomeSearchBar: View {
    @EnvironmentObject private var app: AppState
    /// Simple Shell (note 66): "Find events near D1" (the area folded in). nil = today's placeholder.
    var placeholder: String? = nil
    /// Room kept free on the trailing edge for a control laid over the bar (Simple Shell's area button).
    var trailingInset: CGFloat = 0

    var body: some View {
        SwipeSafeButton {
            Haptics.light()
            app.openSearch(from: app.homeSearchBarFrame)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .opacity(0.7)
                Text(placeholder ?? app.T("Tìm sự kiện, host, khu vực, vibe…", "Search events, hosts, areas, vibes…"))
                    .font(.system(size: 14.5))
                    .opacity(0.6)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(app.palette.ink)
            .padding(.leading, 16)
            .padding(.trailing, 16 + trailingInset)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background { Color.clear.nativeGlassCapsule(interactive: true) }
            .contentShape(Capsule())
        }
        // Hidden while the Search overlay is open: its own field IS this bar, lifted into its header (and set back
        // down here on close), so there is never a second copy showing through.
        .opacity(app.searchOverlayOpen ? 0 : 1)
        // Where the bar is on screen, so Search can start its own field right here (the glide-up entrance).
        .background(GeometryReader { g in
            Color.clear
                .onAppear { app.homeSearchBarFrame = g.frame(in: .global) }
                .onChange(of: g.frame(in: .global)) { _, f in app.homeSearchBarFrame = f }
        })
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(placeholder ?? app.T("Tìm sự kiện, host, khu vực", "Search events, hosts, areas"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("home.searchBar")
        .tourTarget("tour.home.search")
    }
}

/// Photo with an honest "No photo yet" placeholder (never a stock photo standing in for a real one).
private struct DiscoveryPhoto: View {
    @EnvironmentObject private var app: AppState
    let path: String
    var width: CGFloat? = nil
    var height: CGFloat? = nil
    let radius: CGFloat
    var compact = false
    /// Note 71: the empty slot inside a polaroid uses `palette.matSlot` (`field` equals the dark mat).
    var inPolaroid = false

    var body: some View {
        if path.isEmpty {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(inPolaroid ? app.palette.matSlot : app.palette.field)
                .frame(width: width, height: height)
                .frame(maxWidth: width == nil ? .infinity : nil, maxHeight: height == nil ? .infinity : nil)
                .overlay {
                    if compact {
                        Image(systemName: "photo").font(.system(size: 18)).opacity(0.35)
                    } else {
                        Text(app.T("Chưa có ảnh", "No photo yet")).font(.system(size: 12)).opacity(0.55)
                    }
                }
                .foregroundStyle(app.palette.ink)
                .accessibilityLabel(app.T("Chưa có ảnh", "No photo yet"))
        } else {
            CatalogPhoto(path: path, height: height, width: width, cornerRadius: radius)
                .frame(maxHeight: height == nil ? .infinity : nil)
        }
    }
}

private struct FillStatusChip: View {
    @EnvironmentObject private var app: AppState
    let model: DiscoveryCardModel

    var body: some View {
        if model.cancelled {
            PhotoChip(text: app.T("Đã hủy", "Cancelled"), background: BanbeTheme.Chip.cancelled)
        } else if model.fill.soldOut {
            PhotoChip(text: app.T("Hết chỗ", "Sold out"), background: BanbeTheme.Chip.past)
        } else if model.fill.almostFull, let left = model.fill.left {
            PhotoChip(text: app.T("Sắp hết · còn \(left)", "Almost full · \(left) left"), background: BanbeTheme.Chip.hold)
                .accessibilityIdentifier("home.card.almostFull")
        } else if model.going {
            PhotoChip(text: app.T("Bạn sẽ đến", "You're going"), background: BanbeTheme.Chip.going)
        }
    }
}

/// The card: photo (16:10) with only small badges on it, the details underneath.
struct DiscoveryCard: View {
    @EnvironmentObject private var app: AppState
    let model: DiscoveryCardModel

    /// Simple Shell follow-up (plan item 5): with the switch on the card is a block (`palette.block` fill, 12pt
    /// padding under the photo, card radius) so it reads as one object on paper. OFF: today's unfilled card.
    private var filled: Bool { app.simpleShellEnabled }
    /// Calm Pass phase 3 (switch `polaroid_cards`, migration 208, note 71): the photo is inset 8pt in a `mat` frame
    /// (hairline + soft ink-tinted shadow in light, the surface step alone in dark) with the caption below it. No
    /// rotation, tape or stickers, so long Vietnamese titles and large text behave as on the plain card. Wins over
    /// `filled`. Web twin: HomeDiscoveryParts.jsx `polaroid`.
    private var polaroid: Bool { app.polaroidCardsEnabled }
    private var framed: Bool { polaroid || filled }
    private static let polaroidInset: CGFloat = 8
    private static let polaroidPhotoRadius: CGFloat = 8

    var body: some View {
        SwipeSafeButton { app.goEvent(model.key) } label: {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear
                    .aspectRatio(16.0 / 10.0, contentMode: .fit)
                    .overlay {
                        DiscoveryPhoto(path: model.img, radius: polaroid ? Self.polaroidPhotoRadius : BanbeTheme.Radius.card, inPolaroid: polaroid).zoomSource(model.key)
                            .accessibilityIdentifier("card.\(model.key)")
                    }
                    .overlay(alignment: .topLeading) {
                        if !model.dateBadge.isEmpty {
                            PhotoChip(text: model.dateBadge, background: app.palette.paper.opacity(0.62), foreground: app.palette.ink)
                                .padding(10)
                                .accessibilityIdentifier("home.card.date")
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        let saved = app.isSaved(model.key)
                        SwipeSafeButton { app.toggleFavorite(model.key) } label: {
                            PhotoChip(text: saved ? app.T("Đã lưu", "Saved") : app.T("Lưu", "Save"),
                                      background: saved ? BanbeTheme.Chip.going : app.palette.paper.opacity(0.62),
                                      foreground: saved ? .white : app.palette.ink)
                                .padding(10)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(saved ? .isSelected : [])
                        .accessibilityIdentifier("home.save.\(model.key)")
                    }
                    .overlay(alignment: .bottomLeading) { FillStatusChip(model: model).padding(10) }

                details
                    .padding(.horizontal, polaroid ? 4 : filled ? 12 : 0)
                    .padding(.bottom, polaroid ? 4 : filled ? 12 : 0)
            }
            .padding(polaroid ? Self.polaroidInset : 0)
            .background {
                let shape = RoundedRectangle(cornerRadius: BanbeTheme.Radius.card, style: .continuous)
                if polaroid {
                    shape.fill(app.palette.mat)
                        .overlay(shape.strokeBorder(app.palette.divider, lineWidth: 1))
                        // Light only (mat is 1.04:1 on paper); dark separates by the surface step.
                        .shadow(color: app.isDark ? .clear : Color(hex: 0x1B1916).opacity(0.10), radius: 4, y: 2)
                } else if filled {
                    shape.fill(app.palette.block)
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 20)
            .padding(.bottom, framed ? 16 : 22)
        }
        .buttonStyle(.plain)
        // `card.<key>` sits on the photo ONLY (UI tests open events through it, so it must match exactly one element):
        // set on the whole button it would overwrite the Save / badge identifiers inside, and on the name as well it
        // would match twice.
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let label = model.label {
                HStack(spacing: 5) {
                    Text(label == "best" ? "★" : "✦").foregroundStyle(app.palette.honey).accessibilityHidden(true)
                    Text(label == "best" ? app.T("Hợp với bạn nhất", "Best match for you") : app.T("Nổi bật tuần này", "Popular this week"))
                }
                .font(.system(size: 11, weight: .bold))
                .kerning(0.6)
                .textCase(.uppercase)
                .padding(.top, 10)
                .accessibilityIdentifier("home.card.label.\(label)")
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(model.name)
                    .font(BanbeTheme.display(18))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(model.priceLabel)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(model.isFree ? app.palette.honey : app.palette.ink)
                    .lineLimit(1).fixedSize()
            }
            .padding(.top, model.label == nil ? 10 : 4)
            if !model.metaLine.isEmpty {
                Text(model.metaLine)
                    .font(.system(size: 12.5))
                    .opacity(0.68)
                    .lineLimit(1)
                    .padding(.top, 3)
            }
            if let typeLine = model.typeLine {
                Text(typeLine)
                    .font(.system(size: 12.5))
                    .opacity(0.8)
                    .lineLimit(1)
                    .padding(.top, 3)
                    .accessibilityIdentifier("home.card.typeLine")
            }
            if let going = model.fill.going, !model.cancelled {
                Text(app.T("\(going) người sẽ đến", "\(going) going"))
                    .font(.system(size: 11.5))
                    .opacity(0.6)
                    .padding(.top, 3)
                    .accessibilityIdentifier("home.card.going")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Compact row for comparing quickly. 72pt thumbnail: big enough to recognise, not to crowd.
struct DiscoveryRow: View {
    @EnvironmentObject private var app: AppState
    let model: DiscoveryCardModel

    var body: some View {
        SwipeSafeButton { app.goEvent(model.key) } label: {
            HStack(alignment: .center, spacing: 12) {
                DiscoveryPhoto(path: model.img, width: 72, height: 72, radius: BanbeTheme.Radius.thumb, compact: true)
                    .zoomSource(model.key)
                    .accessibilityIdentifier("card.\(model.key)")
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(model.name).font(BanbeTheme.display(15.5)).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(model.priceLabel)
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(model.isFree ? app.palette.honey : app.palette.ink)
                            .lineLimit(1).fixedSize()
                    }
                    Text([model.dateBadge, model.metaLine].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 12)).opacity(0.68).lineLimit(1)
                    if let typeLine = model.typeLine {
                        Text(typeLine).font(.system(size: 12)).opacity(0.8).lineLimit(1)
                    }
                    if model.cancelled || model.fill.soldOut || model.fill.almostFull {
                        Text(model.cancelled ? app.T("Đã hủy", "Cancelled")
                             : model.fill.soldOut ? app.T("Hết chỗ", "Sold out")
                             : app.T("Sắp hết · còn \(model.fill.left ?? 0)", "Almost full · \(model.fill.left ?? 0) left"))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(model.cancelled ? BanbeTheme.alert : app.palette.honey)
                    }
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
        .buttonStyle(.plain)
    }
}

/// Shown only while the note-37 reminder rule fires (24h before → 12h after start) for a confirmed ticket.
struct NextUpBanner: View {
    @EnvironmentObject private var app: AppState
    let event: CatalogEvent
    let phase: EventReminder.Phase
    let haloTrigger: Int

    var body: some View {
        SwipeSafeButton { app.goEvent(event.key) } label: {
            HStack(spacing: 12) {
                DiscoveryPhoto(path: event.img, width: 52, height: 52, radius: BanbeTheme.Radius.thumb, compact: true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill").font(.system(size: 9)).accessibilityHidden(true)
                        Text(phase == .live ? app.T("Đang diễn ra", "Happening now") : app.T("Sắp diễn ra", "Starting soon"))
                    }
                    .font(.system(size: 10.5, weight: .bold))
                    .kerning(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(app.palette.honey)
                    Text(event.name).font(BanbeTheme.display(15.5)).lineLimit(1)
                    let when = app.trStatus(event.when)
                    if !when.isEmpty { Text(when).font(.system(size: 12)).opacity(0.7).lineLimit(1) }
                }
                Spacer(minLength: 0)
                Text(app.T("Xem vé", "Your ticket") + " ›")
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1).fixedSize()
            }
            .foregroundStyle(app.palette.ink)
            .padding(10)
            .background(app.palette.field.opacity(0.7), in: RoundedRectangle(cornerRadius: BanbeTheme.Radius.card, style: .continuous))
            .overlay { EventReminderHalo(trigger: haloTrigger, cornerRadius: BanbeTheme.Radius.card) }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .accessibilityIdentifier("home.eventReminder")
    }
}

/// "This weekend" rail card. Real live events only; seats come from the real fill, never `seats_remaining`.
struct WeekendRailCard: View {
    @EnvironmentObject private var app: AppState
    let event: CatalogEvent

    var body: some View {
        let fill = app.eventFill[event.key].map { HomeDiscovery.fillBadge(booked: $0.booked, capacity: $0.capacity) }
        let soldOut = fill?.soldOut ?? false
        SwipeSafeButton { app.goEvent(event.key) } label: {
            VStack(alignment: .leading, spacing: 0) {
                DiscoveryPhoto(path: event.img, width: 168, height: 110, radius: BanbeTheme.Radius.thumb)
                    .overlay(alignment: .topTrailing) {
                        let saved = app.isSaved(event.key)
                        SwipeSafeButton { app.toggleFavorite(event.key) } label: {
                            PhotoChip(text: saved ? app.T("Đã lưu", "Saved") : app.T("Lưu", "Save"),
                                      background: saved ? BanbeTheme.Chip.going : app.palette.paper.opacity(0.62),
                                      foreground: saved ? .white : app.palette.ink)
                                .scaleEffect(0.86, anchor: .topTrailing)
                                .padding(6)
                        }
                        .buttonStyle(.plain)
                    }
                    .overlay(alignment: .bottomLeading) {
                        if soldOut {
                            PhotoChip(text: app.T("Hết chỗ", "Sold out"), background: BanbeTheme.Chip.cancelled)
                                .scaleEffect(0.86, anchor: .bottomLeading)
                                .padding(6)
                        }
                    }
                Text(event.name).font(BanbeTheme.display(14)).lineLimit(1).padding(.top, 7)
                Text([app.trStatus(event.when), event.locationLabel ?? ""].filter { !$0.isEmpty }.joined(separator: " ▪︎ "))
                    .font(.system(size: 11)).lineLimit(1).padding(.top, 2)
                HStack {
                    Text(event.priceVnd > 0 ? app.trStatus(event.price) : app.T("Miễn phí", "Free"))
                    Spacer(minLength: 4)
                    if let left = fill?.left, !soldOut { Text(app.T("\(left) chỗ trống", "\(left) left")) }
                }
                .font(.system(size: 11)).padding(.top, 1)
            }
            .frame(width: 168, alignment: .leading)
            .foregroundStyle(app.palette.ink)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("weekend.\(event.key)")
    }
}
