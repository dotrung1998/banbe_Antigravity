import SwiftUI

// "Recipe for success" sheet + compact meter + per-field insight (note 50). Lists the 10 ingredients from
// Lib/EventRecipe.swift, each with what to do, why (naming its evidence: "Based on N similar events" or
// "General banbe tip") and a Fix button that jumps to the step. Informational only: it never blocks
// submitting. Web twin: src/screens/sheets/RecipeSheet.jsx (+ CreateEvent.jsx `Insight` / `PriceMarket`).

private func recipeMark(_ status: EventRecipe.Status) -> String {
    switch status { case .good: return "✓"; case .improve: return "◐"; case .missing: return "○" }
}

/// "Recipe 7/10 ━━━━━ See tips ›" under the step bar.
struct RecipeMeter: View {
    @EnvironmentObject private var app: AppState
    let checks: [EventRecipe.Check]
    let onOpen: () -> Void

    var body: some View {
        let score = EventRecipe.score(checks)
        Button(action: onOpen) {
            HStack(spacing: 10) {
                Text(app.T("Công thức", "Recipe") + " \(score.good)/\(score.total)")
                    .font(.system(size: 12.5, weight: .bold)).lineLimit(1).fixedSize()
                HStack(spacing: 3) {
                    ForEach(checks) { c in
                        Capsule()
                            .fill(c.status == .good ? app.palette.ink.opacity(0.85)
                                  : c.status == .improve ? app.palette.honey : app.palette.ink.opacity(0.15))
                            .frame(height: 5)
                    }
                }
                .accessibilityHidden(true)
                Text(app.T("Xem gợi ý", "See tips") + " ›")
                    .font(.system(size: 12, weight: .semibold)).opacity(0.7).lineLimit(1).fixedSize()
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .overlay(Capsule().strokeBorder(app.palette.rule, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.T("Công thức thành công: \(score.good) trên \(score.total). Xem gợi ý",
                                  "Recipe for success: \(score.good) of \(score.total). See tips"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("create.recipeMeter")
    }
}

/// Inline list used by the sheet and by the Review step. Missing first, then improve, then good.
struct RecipeList: View {
    @EnvironmentObject private var app: AppState
    let checks: [EventRecipe.Check]
    var compact = false
    let onFix: ((EventRecipe.Check) -> Void)?

    private var sorted: [EventRecipe.Check] {
        let order: [EventRecipe.Status: Int] = [.missing: 0, .improve: 1, .good: 2]
        return checks.enumerated()
            .sorted { (order[$0.element.status] ?? 0, $0.offset) < (order[$1.element.status] ?? 0, $1.offset) }
            .map(\.element)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(sorted) { c in
                let copy = EventRecipe.copy(c, app.T)
                HStack(alignment: .top, spacing: 12) {
                    Text(recipeMark(c.status))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(c.status == .good ? app.palette.paper : c.status == .improve ? app.palette.honey : app.palette.ink)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(c.status == .good ? app.palette.ink.opacity(0.85) : .clear))
                        .overlay(Circle().strokeBorder(c.status == .good ? .clear : (c.status == .improve ? app.palette.honey : app.palette.ink.opacity(0.3)), lineWidth: 1.5))
                        .accessibilityLabel(c.status == .good ? app.T("Đã ổn", "Done")
                                            : c.status == .improve ? app.T("Nên cải thiện", "Could improve") : app.T("Còn thiếu", "Missing"))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(copy.title).font(.system(size: 14, weight: .semibold))
                        if !compact || c.status != .good {
                            Text(copy.detail).font(.system(size: 12.5)).opacity(0.72).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                    if c.status != .good, let onFix {
                        Button { onFix(c) } label: {
                            Text(app.T("Sửa", "Fix"))
                                .font(.system(size: 12.5, weight: .semibold))
                                .padding(.horizontal, 12).frame(minHeight: 32)
                                .overlay(Capsule().strokeBorder(app.palette.rule, lineWidth: 1))
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(app.T("Sửa: ", "Fix: ") + copy.title)
                        .accessibilityIdentifier("recipe.fix.\(c.id)")
                    }
                }
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) { Rectangle().fill(app.palette.rule).frame(height: 1) }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("recipe.\(c.id)")
            }
        }
        .foregroundStyle(app.palette.ink)
    }
}

struct RecipeSheet: View {
    @EnvironmentObject private var app: AppState
    let checks: [EventRecipe.Check]
    let hasData: Bool
    let n: Int?
    let onFix: (EventRecipe.Check) -> Void
    let onClose: () -> Void

    var body: some View {
        let score = EventRecipe.score(checks)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(app.T("Công thức thành công", "Recipe for success")).font(BanbeTheme.display(19))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                            .frame(width: 34, height: 34)
                            .background(app.palette.ink.opacity(0.07), in: Circle())
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(app.T("Đóng", "Close"))
                    .accessibilityIdentifier("create.recipe.close")
                }
                Text(app.T("\(score.good)/\(score.total) thành phần đã ổn.", "\(score.good) of \(score.total) ingredients in place.")
                     + " " + (hasData
                              ? app.T("Số liệu từ \(n ?? 0) sự kiện tương tự trên banbe.", "Numbers come from \(n ?? 0) similar events on banbe.")
                              : app.T("Chưa đủ sự kiện tương tự để so sánh — đây là mẹo chung.", "Not enough similar events to compare yet — these are general tips."))
                     + " " + app.T("Không bắt buộc để gửi.", "Never required to submit."))
                    .font(.system(size: 12.5)).opacity(0.7)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 10)
            .overlay(alignment: .bottom) { Rectangle().fill(app.palette.rule).frame(height: 1) }
            ScrollView {
                RecipeList(checks: checks) { c in onClose(); onFix(c) }
                    .padding(.horizontal, 22).padding(.bottom, 28)
            }
        }
        .foregroundStyle(app.palette.ink)
        .background(app.palette.paper.ignoresSafeArea())
        .presentationDetents([.fraction(0.86), .large])
        .presentationDragIndicator(.visible)
        .hidesDock("recipeSheet")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("create.recipeSheet")
    }
}

/// One insight line per field (the video's "busier" caveat): the line is short; the evidence and the full
/// reasoning sit behind "Why?". A data line only appears when the benchmark slice exists; otherwise the
/// recipe's general tip (no numbers), and nothing at all when the ingredient is fine and there's no data.
struct RecipeInsight: View {
    @EnvironmentObject private var app: AppState
    let check: EventRecipe.Check?
    var line: String? = nil
    let identifier: String
    @State private var open = false

    var body: some View {
        if let check {
            let copy = EventRecipe.copy(check, app.T)
            if let text = line ?? (check.status != .good ? copy.title : nil) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(check.status == .good ? "✓" : "✦")
                            .foregroundStyle(check.status == .good ? app.palette.ink : app.palette.honey)
                            .accessibilityHidden(true)
                        Text(text).opacity(0.85).fixedSize(horizontal: false, vertical: true)
                        Button(app.T("Vì sao?", "Why?")) { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } }
                            .font(.system(size: 12.5, weight: .semibold))
                            .underline()
                            .opacity(0.75)
                            .buttonStyle(.plain)
                            .accessibilityValue(open ? app.T("Đang mở", "Expanded") : "")
                    }
                    if open {
                        Text(copy.detail).opacity(0.7).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(.system(size: 12.5))
                .foregroundStyle(app.palette.ink)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(identifier)
            }
        }
    }
}

/// Price histogram of similar events (get_host_benchmarks) with this event's own price marked — the market
/// behind the decision, same idea as the Home filter's histogram. It is also the price slider (owner, 2026-10-21):
/// drag the clay knob (or tap the track) to set the price; quick picks and the typed field stay in sync through
/// `app.createPrice`. Web twin: `PriceMarket` in src/screens/CreateEvent.jsx.
struct PriceMarketView: View {
    @EnvironmentObject private var app: AppState
    let price: HostBenchmarks.Price
    let mine: Int
    let catLabel: String
    var onChange: ((Int) -> Void)? = nil
    @State private var dragging = false

    private static let knob: CGFloat = 26
    private var unset: Bool { mine <= 0 }
    /// Without a price the knob rests (dimmed) on the median.
    private var value: Int {
        unset ? EventRecipe.fractionToPrice(EventRecipe.priceToFraction(Int(price.median ?? price.min ?? 0), price) ?? 0.5, price) : mine
    }
    private var fraction: Double { EventRecipe.priceToFraction(value, price) ?? 0.5 }

    /// Which side of p25 / median / p75 a price falls on; a light tick each time a drag crosses one.
    private func band(_ v: Int) -> Int {
        [price.p25, price.median, price.p75].compactMap { $0 }.filter { Double(v) >= $0 }.count
    }

    private func set(_ v: Int) {
        guard v != mine else { return }
        if !unset, band(v) != band(mine) { Haptics.selection() }
        onChange?(v)
    }

    var body: some View {
        let counts = price.histogram ?? []
        let peak = max(counts.max() ?? 1, 1)
        let k = Self.knob
        VStack(alignment: .leading, spacing: 6) {
            Text(app.T("\(catLabel) · trung vị \(EventRecipe.formatVndShort(price.median)) · \(price.n ?? 0) sự kiện",
                       "\(catLabel) · median \(EventRecipe.formatVndShort(price.median)) · \(price.n ?? 0) events"))
                .font(.system(size: 12)).opacity(0.8)
            GeometryReader { geo in
                let track = max(geo.size.width - k, 1)
                let x = k / 2 + track * fraction
                ZStack(alignment: .topLeading) {
                    // Bars up to the chosen price are filled in: the part of the market you are priced against.
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(Array(counts.enumerated()), id: \.offset) { i, c in
                            let reached = !unset && (Double(i) + 0.5) / Double(max(counts.count, 1)) <= fraction
                            RoundedRectangle(cornerRadius: 3)
                                .fill(reached ? app.palette.clay.opacity(0.55) : app.palette.ink.opacity(0.2))
                                .frame(height: max(44 * 0.06, 44 * CGFloat(c) / CGFloat(peak)))
                        }
                    }
                    .frame(height: 44, alignment: .bottom)
                    .padding(.horizontal, k / 2)
                    .padding(.top, 8)
                    // Track under the bars, then the marker line from the bars down into the knob.
                    Capsule().fill(app.palette.ink.opacity(0.18))
                        .frame(width: track, height: 3)
                        .offset(x: k / 2, y: 8 + 44 + 14)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(unset ? app.palette.ink.opacity(0.3) : app.palette.clay)
                        .frame(width: 2, height: 58)
                        .offset(x: x - 1, y: 4)
                        .accessibilityIdentifier("create.priceMarker")
                    ZStack {
                        Circle().fill(app.palette.clay)
                        Circle().stroke(app.palette.paper, lineWidth: 2)
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left")
                            Image(systemName: "chevron.right")
                        }
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.white)
                    }
                    .frame(width: k, height: k)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                    .scaleEffect(dragging ? 1.12 : 1)
                    .opacity(unset && !dragging ? 0.55 : 1)
                    .offset(x: x - k / 2, y: 8 + 44 + 14 - k / 2 + 1.5)
                    if dragging {
                        Text(EventRecipe.formatVndShort(value))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(app.palette.paper)
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(app.palette.ink, in: Capsule())
                            .fixedSize()
                            .alignmentGuide(.leading) { $0.width / 2 }
                            .offset(x: x, y: -18)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: geo.size.width, height: 8 + 44 + 14 + k / 2 + 4, alignment: .topLeading)
                // Tapping the bars jumps the price there; a vertical swipe over them still scrolls the page.
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { loc in
                    set(EventRecipe.fractionToPrice(Double((loc.x - k / 2) / track), price))
                }
                // Dragging happens on the knob's row only, so the page keeps scrolling when a finger lands on the bars.
                .overlay(alignment: .bottomLeading) {
                    Color.clear
                        .frame(width: geo.size.width, height: k + 14)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                                .onChanged { g in
                                    if !dragging { withAnimation(.easeOut(duration: 0.12)) { dragging = true } }
                                    set(EventRecipe.fractionToPrice(Double((g.location.x - k / 2) / track), price))
                                }
                                .onEnded { _ in withAnimation(.easeOut(duration: 0.15)) { dragging = false } }
                        )
                }
            }
            .frame(height: 8 + 44 + 14 + Self.knob / 2 + 4)
            .accessibilityElement()
            .accessibilityLabel(app.T("Giá vé", "Ticket price"))
            .accessibilityValue(unset ? app.T("Chưa chọn", "Not set") : EventRecipe.formatVndShort(value))
            .accessibilityHint(app.T("Vuốt lên hoặc xuống để đổi giá", "Swipe up or down to change the price"))
            .accessibilityAdjustableAction { direction in
                let s = EventRecipe.priceSliderStep
                switch direction {
                case .increment: set(min(value + s, Int(price.max ?? Double(value + s))))
                case .decrement: set(max(value - s, Int(price.min ?? 0)))
                @unknown default: break
                }
            }
            .accessibilityIdentifier("create.priceSlider")
            HStack {
                Text(EventRecipe.formatVndShort(price.min))
                Spacer()
                Text(app.T("‹ Kéo để chọn giá ›", "‹ Drag to set your price ›")).fontWeight(.semibold)
                Spacer()
                Text(EventRecipe.formatVndShort(price.max))
            }
            .font(.system(size: 11)).opacity(0.6)
            .accessibilityHidden(true)
        }
        .foregroundStyle(app.palette.ink)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("create.priceMarket")
    }
}
