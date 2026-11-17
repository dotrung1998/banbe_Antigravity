import Foundation

// v2.3 rules shared by Home, Browse by type and Event Detail (note 81, switch home_v23). Line-for-line ports of the web's
// pure modules so both platforms say and decide the same things:
//   Pager        <- src/lib/pager.js            ListEnd   <- src/lib/listEnd.js (+ browseEnd from browse.js)
//   BrowseRules  <- src/lib/browse.js           LiveLine  <- src/lib/liveLine.js
// Tests: BanbeAppTests/V23RulesTests.swift (shared tests/fixtures/pager.json + the web unit cases). Change both together.
// Copy is a ViEn pair (note 57: no dash or semicolon between ideas).

/// One string in both languages; `t(app.lang == "en")` picks.
struct ViEn: Equatable, Hashable {
    let vi: String
    let en: String
    init(_ vi: String, _ en: String) { self.vi = vi; self.en = en }
    func t(_ english: Bool) -> String { english ? en : vi }
}

// MARK: - Pager

enum Pager {
    static let pageSize = 4
    /// Tallest page: past this a page stops reading as one screen and the pager is lost below the fold.
    static let maxPageSize = 8
    /// The arrows, page numbers and "5–8 of 18" line under the track (44 pt numbers + padding + range), with 4 pt air.
    static let navHeight: CGFloat = 71

    /// How many rows fit below the list's top edge, so the rows AND the pager are on screen without scrolling.
    /// `available` is the height from the list's top to the bottom of the window. Never fewer than the classic four
    /// and never more than `maxPageSize` (same rule as the web's fittedPageSize in src/lib/pager.js).
    static func fittedPageSize(available: CGFloat, rowHeight: CGFloat = 92, nav: CGFloat = navHeight,
                               smallest: Int = pageSize, largest: Int = maxPageSize) -> Int {
        guard available.isFinite, available > 0, rowHeight > 0 else { return smallest }
        let fits = Int(((available - nav) / rowHeight).rounded(.down))
        return Swift.max(smallest, Swift.min(largest, fits))
    }

    static func paginate<T>(_ list: [T], size: Int = pageSize) -> [[T]] {
        stride(from: 0, to: list.count, by: size).map { Array(list[$0..<min($0 + size, list.count)]) }
    }

    static func clampPage(_ i: Int, _ pageCount: Int) -> Int { max(0, min(max(0, pageCount - 1), i)) }

    /// "5–8 of 18" / "5–8 trên 18" ("9 of 9" for one row). Ranges keep their en dash.
    static func rangeText(sizes: [Int], page: Int, english: Bool) -> String {
        guard !sizes.isEmpty else { return "" }
        let total = sizes.reduce(0, +)
        let idx = clampPage(page, sizes.count)
        let first = idx * (sizes.first ?? pageSize) + 1
        let last = first + sizes[idx] - 1
        let span = first == last ? "\(first)" : "\(first)–\(last)"
        return english ? "\(span) of \(total)" : "\(span) trên \(total)"
    }

    enum EndVariant: String { case solo, slim, mid, fill }

    /// The end card fills the hole a short last page leaves: room = rows missing on the last page.
    static func endCardRoom(sizes: [Int], size: Int = pageSize) -> (room: Int, variant: EndVariant?) {
        guard let lastCount = sizes.last else { return (0, nil) }
        let room = size - lastCount
        guard room > 0 else { return (0, nil) }
        if sizes.count == 1 { return (room, .solo) }
        return (room, room == 1 ? .slim : room == 2 ? .mid : .fill)
    }

    /// At most `max` page numbers, always containing the current page.
    static func pageWindow(_ page: Int, _ pageCount: Int, max m: Int = 5) -> [Int] {
        if pageCount <= m { return Array(0..<pageCount) }
        let start = max(0, min(pageCount - m, clampPage(page, pageCount) - m / 2))
        return Array(start..<(start + m))
    }

    static func showNav(pageCount: Int) -> Bool { pageCount > 1 }

    /// The page nearest to a scroll offset (the track decides).
    static func pageAt(offset: CGFloat, pageWidth: CGFloat, pageCount: Int) -> Int {
        pageWidth > 0 ? clampPage(Int((offset / pageWidth).rounded()), pageCount) : 0
    }
}

// MARK: - End cards

struct EndCardModel: Equatable {
    struct Action: Equatable { let act: String; let label: ViEn; var primary = false; var testId: String? = nil }
    let kind: String
    let eyebrow: ViEn?
    let title: ViEn
    let body: ViEn?
    let actions: [Action]

    /// One row of room: the title and the primary action only.
    var slimmed: EndCardModel {
        EndCardModel(kind: kind, eyebrow: eyebrow, title: title, body: nil, actions: Array(actions.filter(\.primary).prefix(1)))
    }
}

enum ListEnd {
    /// Home Shortlist end card. total = the tab's events before Home's filters, shown = after.
    static func shortlistEnd(tab: String, tabLabel: ViEn, total: Int, shown: Int, filtersOn: Bool) -> EndCardModel {
        let hidden = max(0, total - shown)
        if filtersOn && hidden > 0 {
            return EndCardModel(
                kind: "filters",
                eyebrow: ViEn("Đang hiện \(shown) trên \(total)", "\(shown) of \(total) shown"),
                title: hidden == 1 ? ViEn("Còn 1 sự kiện nằm ngay ngoài bộ lọc.", "1 more is just outside your filters.")
                    : ViEn("Còn \(hidden) sự kiện nằm ngay ngoài bộ lọc.", "\(hidden) more are just outside your filters."),
                body: ViEn("Nới một bộ lọc là chúng quay lại, mọi thứ khác giữ nguyên.", "Loosen one and they come straight back, nothing else changes."),
                actions: [.init(act: "clear-filters", label: ViEn("Hiện cả \(total)", "Show all \(total)"), primary: true),
                          .init(act: "types", label: ViEn("Duyệt theo loại", "Browse by type"))])
        }
        return EndCardModel(
            kind: "end",
            eyebrow: ViEn("Hết mục \(tabLabel.vi)", "End of \(tabLabel.en)"),
            title: tab == "tonight" ? ViEn("Tối nay chỉ có vậy. Chỗ đẹp hết trước.", "That’s tonight. The good seats go first.")
                : ViEn("Bạn đã xem hết các gợi ý.", "You’ve seen every pick."),
            body: ViEn("Duyệt theo loại hoặc mở bản đồ để xem thêm quanh bạn.", "Browse by type or open the map to see more around you."),
            actions: [.init(act: "types", label: ViEn("Duyệt mọi loại", "Browse every type"), primary: true),
                      .init(act: "map", label: ViEn("Mở bản đồ", "Open the map"))])
    }

    struct OtherType: Equatable { let key: String; let name: ViEn; let count: Int }

    /// End card for a Browse list (no "Notify me": no backend).
    static func browseEnd(type: String, typeName: ViEn?, count n: Int, hidden: Int, query: String, others: [OtherType]) -> EndCardModel {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty && hidden > 0 {
            return EndCardModel(
                kind: "filters",
                eyebrow: ViEn("Đang hiện \(n) trên \(n + hidden)", "\(n) of \(n + hidden) shown"),
                title: hidden == 1 ? ViEn("Còn 1 sự kiện nằm ngay ngoài bộ lọc.", "1 more is just outside your filters.")
                    : ViEn("Còn \(hidden) sự kiện nằm ngay ngoài bộ lọc.", "\(hidden) more are just outside your filters."),
                body: ViEn("Nới một bộ lọc là chúng quay lại, mọi thứ khác giữ nguyên.", "Loosen one and they come straight back, nothing else changes."),
                actions: [.init(act: "clear-filters", label: ViEn("Hiện cả \(n + hidden)", "Show all \(n + hidden)"), primary: true)])
        }
        if !q.isEmpty {
            var acts: [EndCardModel.Action] = [.init(act: "clear-search", label: ViEn("Xoá tìm kiếm", "Clear search"), primary: true)]
            if type != "all" { acts.append(.init(act: "type:all", label: ViEn("Tìm mọi loại", "Search every type"))) }
            return EndCardModel(
                kind: "search",
                eyebrow: ViEn("\(n) kết quả cho “\(q)”", "\(n) \(n == 1 ? "match" : "matches") for “\(q)”"),
                title: ViEn("Chưa đúng ý? Thử tên host, khu vực hoặc món ăn.", "Not quite it? Try a host, an area or a dish."),
                body: type == "all" ? ViEn("Tìm theo tên sự kiện, host, khu vực và loại.", "Search reads titles, hosts, areas and types.")
                    : ViEn("Bạn đang tìm trong \(typeName?.vi ?? "").", "You are searching \(typeName?.en ?? "") only."),
                actions: acts)
        }
        if type == "all" {
            return EndCardModel(
                kind: "all",
                eyebrow: ViEn("Hết danh sách", "That’s the whole list"),
                title: ViEn("Không còn gì để cuộn. Vẫn còn điều để bắt đầu.", "Nothing left to scroll. Something left to start."),
                body: ViEn("Những buổi hay nhất ở đây bắt đầu từ một host và vài chiếc ghế. Buổi tiếp theo có thể là của bạn.",
                           "The best nights here began with one host and a few chairs. The next one could be yours."),
                actions: [.init(act: "host", label: ViEn("Tổ chức một buổi", "Host a night"), primary: true),
                          .init(act: "map", label: ViEn("Mở bản đồ", "Open the map"))])
        }
        let name = typeName ?? ViEn("", "")
        let top = others.first
        var acts = others.prefix(2).enumerated().map { i, o in
            EndCardModel.Action(act: "type:\(o.key)", label: ViEn("\(o.name.vi) · \(o.count)", "\(o.name.en) · \(o.count)"), primary: i == 0)
        }
        acts.append(.init(act: "type:all", label: ViEn("Mọi loại", "All types"), primary: others.isEmpty))
        return EndCardModel(
            kind: "type",
            eyebrow: ViEn("Mọi \(name.vi.lowercased()) đang mở", "Every \(name.en.lowercased()) on now"),
            title: top.map { ViEn("Vẫn tò mò? \($0.name.vi) có \($0.count) sự kiện.", "Still curious? \($0.name.en) has \($0.count) on.") }
                ?? ViEn("Loại này chỉ có vậy.", "That’s all for this type."),
            body: ViEn("Cùng khu phố, một kiểu buổi tối khác.", "Same neighbourhoods, a different kind of night."),
            actions: acts)
    }
}

// MARK: - Browse by type / See all

enum BrowseRules {
    static let scopes = ["all", "foryou", "tonight", "weekend"]
    static let deckShown = 4

    /// What the Browse list needs per event: Home's discovery item plus the words search reads and the host.
    struct Entry: Equatable {
        var item: HomeDiscovery.Item
        var name: String
        var area: String
        var catDisplay: String
        var organizerId: String?
        var organizerName: String
        var avatarURL: URL?
        var key: String { item.key }
    }

    struct Host: Equatable, Identifiable {
        let id: String
        var name: String
        var avatarURL: URL?
        var events: [String]
    }

    /// Events of one type ("all" = every type); an event's second category counts too.
    static func ofType(_ entries: [Entry], _ type: String) -> [Entry] {
        type == "all" ? entries : entries.filter { $0.item.catKeys.contains(type) }
    }

    static func typeCounts(_ entries: [Entry]) -> [String: Int] {
        var out: [String: Int] = [:]
        for e in entries { for k in Set(e.item.catKeys) { out[k, default: 0] += 1 } }
        return out
    }

    /// Accent-insensitive: "bep nho" finds "Bếp Nhỏ". Every word must match somewhere.
    static func matches(_ e: Entry, _ q: String) -> Bool {
        let needle = MapDiscovery.foldText(q)
        guard !needle.isEmpty else { return true }
        let hay = MapDiscovery.foldText([e.name, e.organizerName, e.area, e.catDisplay].filter { !$0.isEmpty }.joined(separator: " "))
        return needle.split(separator: " ").allSatisfy { hay.contains($0) }
    }

    /// Browse's own filters: Home's shape with type and category parts switched off.
    static func browseFilters(_ f: HomeDiscovery.Filters) -> HomeDiscovery.Filters {
        var x = f
        x.cats = []
        x.typeFilters = []
        return x
    }

    static func filterCount(_ f: HomeDiscovery.Filters) -> Int {
        let x = browseFilters(f)
        var n = 0
        if x.date != "any" { n += 1 }
        if x.free || x.priceMin != nil || x.priceMax != nil { n += 1 }
        if x.seatsLeft { n += 1 }
        if x.almostFull { n += 1 }
        return n
    }

    /// scope entries → type → search → Browse's own filters. `hidden` = how many the filters hide.
    static func list(_ entries: [Entry], type: String, query: String, filters: HomeDiscovery.Filters, now: Date) -> (list: [Entry], searched: Int, hidden: Int) {
        let searched = ofType(entries, type).filter { matches($0, query) }
        let kept = Set(HomeDiscovery.apply(searched.map(\.item), browseFilters(filters), now: now).map(\.key))
        let list = searched.filter { kept.contains($0.key) }
        return (list, searched.count, searched.count - list.count)
    }

    /// Real hosts of these events, busiest first, then by name.
    static func hosts(_ entries: [Entry]) -> [Host] {
        var order: [String] = []
        var map: [String: Host] = [:]
        for e in entries {
            guard let id = e.organizerId, !id.isEmpty else { continue }
            if map[id] == nil { map[id] = Host(id: id, name: e.organizerName, avatarURL: e.avatarURL, events: []); order.append(id) }
            map[id]?.events.append(e.key)
            if map[id]?.avatarURL == nil, let u = e.avatarURL { map[id]?.avatarURL = u }
        }
        return order.compactMap { map[$0] }.sorted {
            $0.events.count != $1.events.count ? $0.events.count > $1.events.count
                : $0.name.compare($1.name, locale: Locale(identifier: "vi")) == .orderedAscending
        }
    }

    /// "AEIE Studios, Bàn Dài" + "and 16 more hosts".
    static func deckLine(_ hosts: [Host]) -> (names: ViEn, more: ViEn) {
        guard !hosts.isEmpty else { return (ViEn("Chưa có host", "No hosts yet"), ViEn("", "")) }
        let names = hosts.prefix(2).map(\.name).joined(separator: ", ")
        let rest = hosts.count - min(2, hosts.count)
        if rest > 0 { return (ViEn(names, names), ViEn("và \(rest) host khác", "and \(rest) more \(rest == 1 ? "host" : "hosts")")) }
        if hosts.count == 1 { return (ViEn(names, names), ViEn("tổ chức mọi sự kiện ở đây", "hosts every event here")) }
        return (ViEn(names, names), ViEn("tổ chức các sự kiện này", "host these events"))
    }

    static func deckFaces(_ hosts: [Host], shown: Int = deckShown) -> (faces: [Host], more: Int) {
        (Array(hosts.prefix(shown)), max(0, hosts.count - shown))
    }

    static func rotate(_ hosts: [Host]) -> [Host] { hosts.count > 1 ? Array(hosts.dropFirst()) + [hosts[0]] : hosts }

    /// Stable tint index per host name for the monogram fallback (same hash as the web).
    static func tintIndex(_ name: String, _ n: Int) -> Int {
        var h: UInt32 = 0
        for scalar in name.unicodeScalars { h = h &* 31 &+ scalar.value }
        return n > 0 ? Int(h % UInt32(n)) : 0
    }

    static func filterHosts(_ hosts: [Host], _ q: String) -> [Host] {
        let needle = MapDiscovery.foldText(q)
        return needle.isEmpty ? hosts : hosts.filter { MapDiscovery.foldText($0.name).contains(needle) }
    }
}

// MARK: - Live line

enum LiveLine {
    static let maxUpdates = 8
    static let fewSeats = 5

    struct PulseItem: Equatable { let eventId: String; let eventName: String; let organizerName: String; let bookingCount: Int }
    struct Facts: Equatable { let seatsLeft: Int?; let when: String }
    struct Update: Equatable, Identifiable { let id: String; let eventId: String?; let kind: String; let text: ViEn; let when: String? }

    static func updates(pulse: [PulseItem], lookup: (String) -> Facts?, tonight: Int, weekend: Int, max m: Int = maxUpdates) -> [Update] {
        var out: [Update] = []
        if tonight > 0 {
            out.append(Update(id: "sum-tonight", eventId: nil, kind: "summary",
                              text: tonight == 1 ? ViEn("1 sự kiện diễn ra tối nay", "1 event on tonight") : ViEn("\(tonight) sự kiện diễn ra tối nay", "\(tonight) events on tonight"), when: nil))
        } else if weekend > 0 {
            out.append(Update(id: "sum-weekend", eventId: nil, kind: "summary",
                              text: weekend == 1 ? ViEn("1 sự kiện cuối tuần này", "1 event this weekend") : ViEn("\(weekend) sự kiện cuối tuần này", "\(weekend) events this weekend"), when: nil))
        }
        for p in pulse {
            if out.count >= m { break }
            let name = p.eventName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !p.eventId.isEmpty, let facts = lookup(p.eventId) else { continue }
            let text: ViEn
            let kind: String
            if let s = facts.seatsLeft, s > 0, s <= fewSeats {
                kind = "seats"
                text = s == 1 ? ViEn("Chỉ còn 1 chỗ ở \(name)", "Only 1 seat left at \(name)") : ViEn("Chỉ còn \(s) chỗ ở \(name)", "Only \(s) seats left at \(name)")
            } else if p.bookingCount > 0 {
                kind = "booked"
                let b = p.bookingCount
                text = b == 1 ? ViEn("1 lượt đặt \(name) hôm nay", "1 booking for \(name) today") : ViEn("\(b) lượt đặt \(name) hôm nay", "\(b) bookings for \(name) today")
            } else {
                kind = "trending"
                let raw = p.organizerName.trimmingCharacters(in: .whitespacesAndNewlines)
                let host = !raw.isEmpty && MapDiscovery.foldText(raw) != MapDiscovery.foldText(name) ? raw : nil
                text = host.map { ViEn("\(name) của \($0) đang được quan tâm", "\(name) by \($0) is getting attention") }
                    ?? ViEn("\(name) đang được quan tâm", "\(name) is getting attention")
            }
            out.append(Update(id: "ev-\(p.eventId)", eventId: p.eventId, kind: kind, text: text, when: facts.when.isEmpty ? nil : facts.when))
        }
        return out
    }

    /// One pass of the ticker at a fixed reading speed.
    static func seconds(_ texts: [String]) -> Double {
        let chars = texts.reduce(0) { $0 + $1.count + 5 }
        return Double(max(16, Int((Double(chars) * 0.26).rounded())))
    }

    static func step(_ i: Int, _ dir: Int, _ n: Int) -> Int { max(0, min(max(0, n - 1), i + dir)) }
}
