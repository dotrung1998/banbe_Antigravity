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
struct HomeCategoryRow: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(HomeDiscovery.categories, id: \.key) { c in
                    let cats = app.homeFilters.cats
                    let active = c.key == "all" ? cats.isEmpty : cats.contains(c.key)
                    SwipeSafeButton {
                        if !active { Haptics.selection() }
                        app.pickFilter(c.key)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: CategoryGlyph.symbol(c.key))
                                .font(.system(size: 20, weight: .regular))
                                .foregroundStyle(active ? app.palette.paper : app.palette.ink)
                                .frame(width: 52, height: 52)
                                .background(active ? app.palette.ink.opacity(0.9) : app.palette.ink.opacity(0.06),
                                            in: RoundedRectangle(cornerRadius: BanbeTheme.Radius.tile, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: BanbeTheme.Radius.tile, style: .continuous)
                                        .strokeBorder(app.palette.ink.opacity(active ? 0 : 0.06), lineWidth: 1)
                                }
                                .shadow(color: .black.opacity(active ? 0.18 : 0), radius: 3, y: 2)
                            Text(app.T(c.vi, c.en))
                                .font(.system(size: 11.5, weight: active ? .semibold : .medium))
                                .lineLimit(1).fixedSize()
                                .opacity(active ? 1 : 0.8)
                        }
                        .frame(width: 64)
                        .foregroundStyle(app.palette.ink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(app.T(c.vi, c.en))
                    .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
                    // Same ids as the old text chips (UI tests filter by category through these).
                    .accessibilityIdentifier("filter.\(c.key)")
                    .animation(.easeOut(duration: 0.15), value: active)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12).padding(.bottom, 4)
        }
        .rootSwipeExclusion("homeCategories")
    }
}

/// Full-width search entry. The placeholder says what you can actually search for.
struct HomeSearchBar: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        SwipeSafeButton {
            Haptics.light()
            app.openSearch(from: app.homeSearchBarFrame)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .opacity(0.7)
                Text(app.T("Tìm sự kiện, host, khu vực, vibe…", "Search events, hosts, areas, vibes…"))
                    .font(.system(size: 14.5))
                    .opacity(0.6)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background { Color.clear.nativeGlassCapsule(interactive: true) }
            .contentShape(Capsule())
        }
        // Where the bar is on screen, so Search can start its own field right here (the glide-up entrance).
        .background(GeometryReader { g in
            Color.clear
                .onAppear { app.homeSearchBarFrame = g.frame(in: .global) }
                .onChange(of: g.frame(in: .global)) { _, f in app.homeSearchBarFrame = f }
        })
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.T("Tìm sự kiện, host, khu vực", "Search events, hosts, areas"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("home.searchBar")
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

    var body: some View {
        if path.isEmpty {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(app.palette.field)
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

    var body: some View {
        SwipeSafeButton { app.goEvent(model.key) } label: {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear
                    .aspectRatio(16.0 / 10.0, contentMode: .fit)
                    .overlay {
                        DiscoveryPhoto(path: model.img, radius: BanbeTheme.Radius.card).zoomSource(model.key)
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
                if let going = model.fill.going, !model.cancelled {
                    Text(app.T("\(going) người sẽ đến", "\(going) going"))
                        .font(.system(size: 11.5))
                        .opacity(0.6)
                        .padding(.top, 3)
                        .accessibilityIdentifier("home.card.going")
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 20)
            .padding(.bottom, 22)
        }
        .buttonStyle(.plain)
        // `card.<key>` sits on the photo ONLY (UI tests open events through it, so it must match exactly one element):
        // set on the whole button it would overwrite the Save / badge identifiers inside, and on the name as well it
        // would match twice.
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
