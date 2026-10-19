import SwiftUI

// Home filter sheet (note 50) — the "level D" filter from the "4 levels" video, adapted to events:
// - a sheet OVER the results (never a full page, never one page per filter), every filter in one scroll;
// - pills (no steppers) for every discrete choice, and EVERY pill shows its count before you tap it,
//   computed with all your other filters applied;
// - a price histogram behind the range, with a context line that follows the other filters
//   ("Music · median 250k · 12 of 41 events");
// - a CTA that says exactly what you'll get ("Show 23 events"), or which single filter to relax.
// Edits a local draft; nothing changes on Home until the CTA is pressed. Web twin: HomeFilterSheet.jsx.
struct HomeFilterSheet: View {
    @EnvironmentObject private var app: AppState
    let items: [HomeDiscovery.Item]
    let now: Date
    let onClose: () -> Void

    @State private var draft = HomeDiscovery.Filters.default
    @State private var draftSort = "soonest"
    @State private var forTwo = false
    @State private var seeded = false
    @State private var datePickerOpen = false
    /// The location picker slides up OVER this sheet; this sheet (and its draft) stays alive underneath.
    @State private var areaOpen = false
    @State private var pickedDate = Date()

    private static let priceStep = 50_000
    private typealias D = HomeDiscovery

    private var canSortNearest: Bool { app.located == true && app.userCoords != nil }
    private var areaLabel: String? { app.area == LocationHierarchy.allID ? nil : app.currentAreaLabel }

    var body: some View {
        let resultCount = D.apply(items, draft, now: now).count
        let hints = resultCount == 0 ? D.relaxationHints(items, draft, now: now, limit: 1) : []
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    whenSection
                    priceSection
                    categorySection
                    seatsSection
                    locationSection
                    sortSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            Divider().overlay(app.palette.rule)
            VStack(spacing: 8) {
                InkButton(title: ctaTitle(resultCount, hints.first), cornerRadius: 999) {
                    if resultCount > 0 {
                        app.homeFilters = draft
                        app.homeSort = draftSort
                        onClose()
                    } else if let hint = hints.first {
                        draft = hint.filters
                    }
                }
                .accessibilityIdentifier("home.filter.apply")
                .accessibilityValue("\(resultCount)")
                Text(app.T("trên tổng \(items.count) sự kiện", "out of \(items.count) events"))
                    .font(.system(size: 11.5)).opacity(0.55)
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 18)
        }
        .foregroundStyle(app.palette.ink)
        .background(app.palette.paper.ignoresSafeArea())
        .onAppear {
            guard !seeded else { return }
            seeded = true
            draft = app.homeFilters
            draftSort = app.homeSort
        }
        .sheet(isPresented: $areaOpen) {
            LocationPickerSheet(isPresented: $areaOpen, doneMode: true)
                .environmentObject(app)
        }
        .presentationDetents([.fraction(0.88), .large])
        .presentationDragIndicator(.visible)
        .hidesDock("homeFilterSheet")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.filterSheet")
    }

    private func ctaTitle(_ n: Int, _ hint: D.RelaxHint?) -> String {
        if n > 0 { return app.T("Xem \(n) sự kiện", "Show \(n) event\(n == 1 ? "" : "s")") }
        if let hint, let l = D.relaxLabels[hint.id] {
            return app.T("Không có sự kiện · thử \(l.vi)", "No events · try \(l.en)")
        }
        return app.T("Không có sự kiện", "No events")
    }

    private var header: some View {
        HStack {
            Button(app.T("Đặt lại", "Reset")) {
                Haptics.selection()
                draft = .default
                draftSort = "soonest"
            }
            .font(.system(size: 14))
            .opacity(0.75)
            .frame(minWidth: 44, minHeight: 44)
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.filter.reset")
            Spacer()
            Text(app.T("Bộ lọc", "Filters")).font(BanbeTheme.display(17)).accessibilityAddTraits(.isHeader)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(app.palette.ink.opacity(0.07), in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(app.T("Đóng", "Close"))
            .accessibilityIdentifier("home.filter.close")
        }
        .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 4)
        .overlay(alignment: .bottom) { Rectangle().fill(app.palette.rule).frame(height: 1) }
    }

    // MARK: Pieces

    private func pill(_ title: String, active: Bool, count: Int? = nil, disabled: Bool = false, icon: String? = nil,
                      id: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 13)) }
                Text(title)
                if let count {
                    Text("\(count)").font(.system(size: 12)).monospacedDigit().opacity(0.65)
                }
            }
            .font(.system(size: 13.5, weight: active ? .semibold : .medium))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(minHeight: 38)
            .foregroundStyle(active ? app.palette.paper : app.palette.ink)
            .background(active ? app.palette.ink.opacity(0.9) : Color.clear, in: Capsule())
            .overlay(Capsule().strokeBorder(active ? Color.clear : app.palette.rule, lineWidth: 1))
            .opacity(disabled && !active ? 0.4 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled && !active)
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    private func section<Content: View, Right: View>(_ title: String, @ViewBuilder right: () -> Right,
                                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(BanbeTheme.display(17)).accessibilityAddTraits(.isHeader)
                Spacer()
                right()
            }
            content()
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(app.palette.rule).frame(height: 1) }
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        section(title, right: { EmptyView() }, content: content)
    }

    // MARK: When

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = AppState.vietnamTimeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var whenSection: some View {
        let counts = D.optionCounts(items, draft, .date, options: D.dateOptions, now: now)
        let picked = draft.date.hasPrefix("on:")
        return section(app.T("Khi nào", "When")) {
            FlowRow(spacing: 8) {
                ForEach(D.dateOptions, id: \.self) { opt in
                    let label = D.dateLabels[opt] ?? (opt, opt)
                    pill(app.T(label.vi, label.en), active: draft.date == opt, count: opt == "any" ? nil : counts[opt],
                         disabled: opt != "any" && counts[opt] == 0, id: "home.filter.date.\(opt)") { draft.date = opt }
                }
                pill(picked ? pickedLabel : app.T("Chọn ngày", "Pick a date"), active: picked, icon: "calendar",
                     id: "home.filter.date.pick") { datePickerOpen.toggle() }
            }
            if datePickerOpen {
                DatePicker("", selection: $pickedDate, in: Calendar.current.startOfDay(for: now)..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .environment(\.timeZone, AppState.vietnamTimeZone)
                    .tint(app.palette.ink)
                    .onChange(of: pickedDate) { _, d in
                        draft.date = "on:" + Self.isoDay.string(from: d)
                        datePickerOpen = false
                    }
            }
        }
    }

    private var pickedLabel: String {
        let parts = draft.date.dropFirst(3).split(separator: "-")
        return parts.count == 3 ? "\(parts[2])/\(parts[1])" : app.T("Chọn ngày", "Pick a date")
    }

    // MARK: Price

    private var priceSection: some View {
        // Market behind the price control: everything that passes the OTHER filters.
        var others = draft
        others.priceMin = nil; others.priceMax = nil; others.free = false
        let market = D.apply(items, others, now: now).compactMap(\.priceVnd)
        let paid = market.filter { $0 > 0 }
        let hist = D.priceHistogram(market, buckets: 14)
        let paidMedian = D.median(paid.map(Double.init))
        let step = Self.priceStep
        let sliderMax = hist.map { Int((Double($0.max) / Double(step)).rounded(.up)) * step } ?? 0
        let lo = draft.priceMin ?? 0
        let hi = draft.priceMax ?? sliderMax
        let loIdx = D.bucketIndex(hist, price: lo) ?? 0
        let hiIdx = D.bucketIndex(hist, price: hi) ?? 0
        let inRange = paid.filter { $0 >= lo && $0 <= hi }.count
        let freeCount = D.optionCounts(items, draft, .free, now: now)["true"] ?? 0
        let catLabel: String? = draft.cats.count == 1
            ? D.categories.first(where: { $0.key == draft.cats[0] }).map { app.T($0.vi, $0.en) } : nil
        let contextLine = [catLabel, areaLabel,
                           paidMedian.map { app.T("trung vị \(shown(Int($0)))", "median \(shown(Int($0)))") }]
            .compactMap { $0 }.joined(separator: " · ")
        return section(app.T("Giá", "Price"), right: {
            Button {
                forTwo.toggle()
            } label: {
                Text((forTwo ? "✓ " : "") + app.T("Giá cho 2 người", "Price for 2"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .opacity(forTwo ? 1 : 0.6)
                    .frame(minHeight: 32)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(forTwo ? .isSelected : [])
            .accessibilityIdentifier("home.filter.forTwo")
        }) {
            if let hist {
                (Text(contextLine.isEmpty ? "" : contextLine + " · ")
                 + Text(app.T("\(inRange) / \(paid.count) sự kiện", "\(inRange) of \(paid.count) events")).bold())
                    .font(.system(size: 12.5))
                    .opacity(0.75)
                    .accessibilityIdentifier("home.filter.priceContext")
                let peak = max(hist.counts.max() ?? 1, 1)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(hist.counts.enumerated()), id: \.offset) { i, c in
                        let on = !draft.free && i >= loIdx && i <= hiIdx
                        RoundedRectangle(cornerRadius: 3)
                            .fill(app.palette.ink.opacity(on ? 0.85 : 0.16))
                            .frame(height: max(56 * 0.06, 56 * CGFloat(c) / CGFloat(peak)))
                    }
                }
                .frame(height: 56, alignment: .bottom)
                .accessibilityHidden(true)
                PriceRangeSlider(low: lo, high: hi, maxValue: sliderMax, step: step, label: shown) { newLo, newHi in
                    draft.priceMin = newLo > 0 ? newLo : nil
                    draft.priceMax = newHi < sliderMax ? newHi : nil
                    draft.free = false
                }
                HStack {
                    Text(lo > 0 ? shown(lo) : app.T("Miễn phí", "Free"))
                    Spacer()
                    Text(draft.priceMax != nil ? shown(hi) : "\(shown(sliderMax))+")
                }
                .font(.system(size: 12.5, weight: .semibold))
            } else {
                Text(app.T("Chưa có sự kiện trả phí nào khớp.", "No paid events match yet."))
                    .font(.system(size: 12.5)).opacity(0.6)
            }
            pill(app.T("Chỉ miễn phí", "Free only"), active: draft.free, count: freeCount, disabled: freeCount == 0,
                 id: "home.filter.free") {
                draft.free.toggle(); draft.priceMin = nil; draft.priceMax = nil
            }
        }
    }

    private func shown(_ v: Int) -> String { EventRecipe.formatVndShort(forTwo ? v * 2 : v) }

    // MARK: Category / seats / location / sort

    private var categorySection: some View {
        let keys = D.categories.map(\.key).filter { $0 != "all" }
        let counts = D.optionCounts(items, draft, .cats, options: keys, now: now)
        return section(app.T("Danh mục", "Category")) {
            FlowRow(spacing: 8) {
                ForEach(D.categories.filter { $0.key != "all" }, id: \.key) { c in
                    let on = draft.cats.contains(c.key)
                    pill(app.T(c.vi, c.en), active: on, count: counts[c.key], disabled: !on && counts[c.key] == 0,
                         icon: CategoryGlyph.symbol(c.key), id: "home.filter.cat.\(c.key)") {
                        if on { draft.cats.removeAll { $0 == c.key } } else { draft.cats.append(c.key) }
                    }
                }
            }
        }
    }

    private var seatsSection: some View {
        let seats = D.optionCounts(items, draft, .seatsLeft, now: now)["true"] ?? 0
        let almost = D.optionCounts(items, draft, .almostFull, now: now)["true"] ?? 0
        return section(app.T("Chỗ ngồi", "Seats")) {
            FlowRow(spacing: 8) {
                pill(app.T("Còn chỗ", "Seats left"), active: draft.seatsLeft, count: seats, id: "home.filter.seatsLeft") {
                    draft.seatsLeft.toggle()
                }
                pill(app.T("Sắp hết chỗ", "Almost full"), active: draft.almostFull, count: almost,
                     disabled: almost == 0, id: "home.filter.almostFull") { draft.almostFull.toggle() }
            }
        }
    }

    private var locationSection: some View {
        section(app.T("Khu vực", "Location")) {
            Button { Haptics.selection(); areaOpen = true } label: {
                HStack {
                    Text(areaLabel ?? app.T("Mọi nơi", "Everywhere"))
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).opacity(0.5)
                }
                .font(.system(size: 14))
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 44)
                .overlay(RoundedRectangle(cornerRadius: BanbeTheme.Radius.tile, style: .continuous).strokeBorder(app.palette.rule))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.filter.area")
        }
    }

    private var sortSection: some View {
        section(app.T("Sắp xếp", "Sort by")) {
            FlowRow(spacing: 8) {
                ForEach(D.sortModes, id: \.self) { m in
                    let label = D.sortLabels[m] ?? (m, m)
                    pill(app.T(label.vi, label.en), active: draftSort == m, disabled: m == "nearest" && !canSortNearest,
                         id: "home.sort.\(m)") { draftSort = m }
                }
            }
            if !canSortNearest {
                Text(app.T("Bật vị trí để sắp xếp theo khoảng cách.", "Turn on location to sort by distance."))
                    .font(.system(size: 11.5)).opacity(0.6)
            }
        }
    }
}

/// Two-thumb range over [0, maxValue] in `step` increments. Each thumb is its own adjustable element.
struct PriceRangeSlider: View {
    @EnvironmentObject private var app: AppState
    let low: Int
    let high: Int
    let maxValue: Int
    let step: Int
    let label: (Int) -> String
    let onChange: (Int, Int) -> Void

    private let thumb: CGFloat = 26

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width - thumb, 1)
            let x: (Int) -> CGFloat = { v in maxValue > 0 ? CGFloat(v) / CGFloat(maxValue) * width : 0 }
            let value: (CGFloat) -> Int = { px in
                guard maxValue > 0 else { return 0 }
                let raw = Double(min(max(px, 0), width) / width) * Double(maxValue)
                return min(maxValue, Int((raw / Double(step)).rounded()) * step)
            }
            ZStack(alignment: .leading) {
                Capsule().fill(app.palette.ink.opacity(0.14)).frame(height: 4).padding(.horizontal, thumb / 2)
                Capsule().fill(app.palette.ink.opacity(0.85))
                    .frame(width: max(x(high) - x(low), 0), height: 4)
                    .offset(x: thumb / 2 + x(low))
                thumbView
                    .offset(x: x(low))
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("priceRange")).onChanged { g in
                        onChange(min(value(g.location.x - thumb / 2), high), high)
                    })
                    .accessibilityElement()
                    .accessibilityLabel(app.T("Giá thấp nhất", "Minimum price"))
                    .accessibilityValue(label(low))
                    .accessibilityAdjustableAction { dir in
                        let next = dir == .increment ? min(low + step, high) : max(low - step, 0)
                        onChange(next, high)
                    }
                    .accessibilityIdentifier("home.filter.priceMin")
                thumbView
                    .offset(x: x(high))
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("priceRange")).onChanged { g in
                        onChange(low, max(value(g.location.x - thumb / 2), low))
                    })
                    .accessibilityElement()
                    .accessibilityLabel(app.T("Giá cao nhất", "Maximum price"))
                    .accessibilityValue(label(high))
                    .accessibilityAdjustableAction { dir in
                        let next = dir == .increment ? min(high + step, maxValue) : max(high - step, low)
                        onChange(low, next)
                    }
                    .accessibilityIdentifier("home.filter.priceMax")
            }
            .coordinateSpace(name: "priceRange")
        }
        .frame(height: 30)
    }

    private var thumbView: some View {
        Circle()
            .fill(app.palette.paper)
            .overlay(Circle().strokeBorder(app.palette.ink.opacity(0.85), lineWidth: 2))
            .frame(width: thumb, height: thumb)
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            .contentShape(Circle().inset(by: -8))
    }
}
