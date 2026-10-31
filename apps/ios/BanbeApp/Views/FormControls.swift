import SwiftUI

// Low-friction form controls (note 48). One shared copy of the pieces that
// were re-implemented privately per screen: a selectable chip, a −/+ count
// stepper and a named-step progress bar. Visual language matches the
// previous private copies (EventPreferencesViews `chip()`, ReserveView
// `stepper()`, OnboardingFlowViews `OnboardingTopBar`) so adopting them is
// not a redesign.

/// A selectable capsule. Selection is shown by fill + weight + the
/// `.isSelected` trait, never colour alone.
struct ChoiceChip: View {
    let title: String
    let selected: Bool
    var compact = false
    var identifier: String? = nil
    let action: () -> Void

    @EnvironmentObject private var app: AppState

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Text(title)
                .font(.system(size: compact ? 11.5 : 13, weight: selected ? .semibold : .regular))
                .multilineTextAlignment(.leading)
                .padding(.horizontal, compact ? 10 : 14).padding(.vertical, compact ? 6 : 9)
                .foregroundStyle(selected ? app.palette.paper : app.palette.ink)
                .background(selected ? app.palette.ink : app.palette.field, in: Capsule())
                .overlay(Capsule().stroke(app.palette.rule, lineWidth: selected ? 0 : 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .modifier(OptionalIdentifier(identifier: identifier))
    }
}

/// −/+ stepper for small counts (tickets, seats, days). The ends dim at the
/// limits; VoiceOver gets a single adjustable element instead of two buttons.
struct CountStepper: View {
    let value: Int
    let range: ClosedRange<Int>
    var step = 1
    /// Spoken unit, e.g. "seats". Optional.
    var unit: String? = nil
    var identifier: String? = nil
    let onChange: (Int) -> Void

    @EnvironmentObject private var app: AppState

    init(value: Int, range: ClosedRange<Int>, step: Int = 1, unit: String? = nil,
         identifier: String? = nil, onChange: @escaping (Int) -> Void) {
        self.value = value
        self.range = range
        self.step = step
        self.unit = unit
        self.identifier = identifier
        self.onChange = onChange
    }

    /// Binding convenience for plain `Int` state.
    init(value: Binding<Int>, range: ClosedRange<Int>, step: Int = 1, unit: String? = nil,
         identifier: String? = nil) {
        self.init(value: value.wrappedValue, range: range, step: step, unit: unit,
                  identifier: identifier) { value.wrappedValue = $0 }
    }

    private var canDecrement: Bool { value - step >= range.lowerBound }
    private var canIncrement: Bool { value + step <= range.upperBound }

    var body: some View {
        HStack(spacing: 8) {
            button("−", enabled: canDecrement) { onChange(max(range.lowerBound, value - step)) }
            Text("\(value)")
                .font(BanbeTheme.display(18))
                .monospacedDigit()
                .frame(minWidth: 28)
            button("+", enabled: canIncrement) { onChange(min(range.upperBound, value + step)) }
        }
        .foregroundStyle(app.palette.ink)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(unit.map { "\(value) \($0)" } ?? "\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if canIncrement { onChange(value + step) }
            case .decrement: if canDecrement { onChange(value - step) }
            @unknown default: break
            }
        }
        .modifier(OptionalIdentifier(identifier: identifier))
    }

    private func button(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { if enabled { Haptics.selection(); action() } }) {
            Text(symbol)
                .font(.system(size: 18))
                .frame(width: 36, height: 36)
                .foregroundStyle(enabled ? app.palette.ink : app.palette.ink.opacity(0.3))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(app.palette.rule, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Pure progress maths, kept out of the view so it is unit-testable.
enum StepProgressModel {
    /// Fraction complete: steps strictly before `current` count as done.
    /// `current == steps` means everything is done.
    static func fraction(current: Int, total: Int) -> Double {
        guard total > 0 else { return 0 }
        return Double(min(max(current, 0), total)) / Double(total)
    }

    static func percent(current: Int, total: Int) -> Int {
        Int((fraction(current: current, total: total) * 100).rounded())
    }
}

/// Named-step progress ("Account ✓ · Interests · Picks · Settings").
/// Goal-gradient rule (note 48): callers pass a `current` that already counts
/// what the person has done (e.g. account creation), so it never opens at 0%.
struct StepProgress: View {
    let steps: [String]
    /// Index of the step in progress; earlier steps render as done.
    let current: Int
    /// Per-step done flags for forms filled in any order (overrides the
    /// "everything before `current` is done" rule when set).
    var completed: [Bool]? = nil
    /// Optional encouraging line shown beside the percentage ring.
    var message: String? = nil
    var showsPercent = true
    var identifier: String? = nil
    /// When set, step labels become buttons (e.g. scroll to a form section).
    var onSelect: ((Int) -> Void)? = nil

    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Note 66: steps that just turned done pop once (none under Reduce Motion). Web: `.bb-step-pop`.
    @State private var popped: Set<Int> = []

    private var doneCount: Int { completed.map { $0.filter { $0 }.count } ?? current }
    private var percent: Int { StepProgressModel.percent(current: doneCount, total: steps.count) }
    private func isDone(_ index: Int) -> Bool {
        if let completed { return completed.indices.contains(index) && completed[index] }
        return index < current
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsPercent || message != nil {
                // One line, one type size (owner, 2026-10-21): the old linear
                // bar is gone; the percentage sits inside a small ring instead.
                HStack(alignment: .center, spacing: 10) {
                    if let message {
                        Text(message)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(app.palette.ink)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    if showsPercent { percentRing }
                }
            }
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, title in
                    stepLabel(index: index, title: title)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: onSelect == nil ? .ignore : .contain)
        .accessibilityLabel(accessibilitySummary)
        .onChange(of: completed ?? []) { previous, now in
            guard !reduceMotion, previous.count == now.count else { return }
            let fresh = Set(now.indices.filter { now[$0] && !previous[$0] })
            guard !fresh.isEmpty else { return }
            withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { popped = fresh }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 180_000_000)
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { popped = [] }
            }
        }
        .modifier(OptionalIdentifier(identifier: identifier))
    }

    /// The percentage inside a thin ring that fills as steps get done.
    private var percentRing: some View {
        let fraction = StepProgressModel.fraction(current: doneCount, total: steps.count)
        return ZStack {
            Circle().stroke(app.palette.ink.opacity(0.12), lineWidth: 3)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(app.palette.ink, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(percent)%")
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(app.palette.ink)
                .padding(4)
        }
        .frame(width: 44, height: 44)
        .animation(Motion.animation(.easeOut(duration: 0.25), reduce: reduceMotion), value: doneCount)
    }

    private var accessibilitySummary: String {
        let name = steps.indices.contains(current) ? steps[current] : (steps.last ?? "")
        let position = min(current + 1, steps.count)
        return app.T("Bước \(position) trên \(steps.count): \(name), xong \(percent)%",
                     "Step \(position) of \(steps.count): \(name), \(percent)% complete")
    }

    /// One column: a numbered circle (a check once done) on a connector line
    /// that runs through the column, so circles and labels always align.
    @ViewBuilder
    private func stepLabel(index: Int, title: String) -> some View {
        let done = isDone(index)
        let active = index == current
        let lineColor: (Bool) -> Color = { $0 ? app.palette.ink : app.palette.ink.opacity(0.14) }
        let content = VStack(spacing: 6) {
            ZStack {
                HStack(spacing: 0) {
                    Rectangle().fill(index == 0 ? .clear : lineColor(isDone(index - 1)))
                    Rectangle().fill(index == steps.count - 1 ? .clear : lineColor(done))
                }
                .frame(height: 2)
                ZStack {
                    Circle()
                        .fill(done || active ? app.palette.ink : app.palette.paper)
                    Circle()
                        .stroke(done || active ? Color.clear : app.palette.ink.opacity(0.25), lineWidth: 1.5)
                    if done && !active {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(app.palette.paper)
                    } else {
                        Text("\(index + 1)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(done || active ? app.palette.paper : app.palette.ink.opacity(0.6))
                    }
                }
                .frame(width: 28, height: 28)
                .scaleEffect(popped.contains(index) ? 1.12 : 1)
                // The step you're on gets a halo; a finished current step keeps its number.
                .overlay(Circle().stroke(app.palette.ink.opacity(active ? 0.22 : 0), lineWidth: 4).padding(-4))
                .overlay(alignment: .topTrailing) {
                    if done && active {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(app.palette.ink, app.palette.paper)
                            .offset(x: 5, y: -5)
                    }
                }
            }
            Text(title)
                .font(.system(size: 11, weight: active ? .semibold : .regular))
                .foregroundStyle(app.palette.ink.opacity(active || done ? 1 : 0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        if let onSelect {
            Button { onSelect(index) } label: { content.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityLabel(done ? app.T("\(title), xong", "\(title), done") : title)
                .accessibilityAddTraits(active ? .isSelected : [])
        } else {
            content
        }
    }
}

/// Short warm line for a progress bar, by fraction done. Localised.
enum ProgressEncouragement {
    static func line(remaining: Int, T: (String, String) -> String) -> String {
        switch remaining {
        case ...0: return T("Xong rồi!", "All done!")
        case 1: return T("Còn 1 bước nữa thôi", "Just 1 step to go")
        default: return T("Tốt lắm, còn \(remaining) bước", "Nice, \(remaining) steps to go")
        }
    }
}

struct OptionalIdentifier: ViewModifier {
    let identifier: String?
    func body(content: Content) -> some View {
        if let identifier { content.accessibilityIdentifier(identifier) } else { content }
    }
}

/// The booking journey "Event ✓ → Hold → Pay → Ticket" (note 48). Reaching
/// Reserve already completed step 1, so the bar never opens at 0%.
struct BookingJourneyProgress: View {
    /// 1 = holding, 2 = paying, 3 = waiting for the ticket, 4 = done.
    let current: Int

    @EnvironmentObject private var app: AppState

    var body: some View {
        StepProgress(
            steps: [app.T("Sự kiện", "Event"), app.T("Giữ chỗ", "Hold"),
                    app.T("Thanh toán", "Pay"), app.T("Vé", "Ticket")],
            current: current,
            message: ProgressEncouragement.line(remaining: 4 - current, T: app.T),
            identifier: "booking.journey"
        )
    }
}

/// Editable list of short options as removable chips plus an "Add" field —
/// replaces typing comma-separated text (note 48).
struct OptionChipsEditor: View {
    @Binding var options: [String]
    let placeholder: String
    var identifier: String = "optionChips"

    @EnvironmentObject private var app: AppState
    @State private var draft = ""

    private func add() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !options.contains(value) else { draft = ""; return }
        options.append(value)
        draft = ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !options.isEmpty {
                FlowRow(spacing: 6) {
                    ForEach(options, id: \.self) { option in
                        Button {
                            options.removeAll { $0 == option }
                        } label: {
                            HStack(spacing: 4) {
                                Text(option).font(.system(size: 12.5))
                                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).accessibilityHidden(true)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .foregroundStyle(app.palette.ink)
                            .background(app.palette.field, in: Capsule())
                            .overlay(Capsule().stroke(app.palette.rule, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option)
                        .accessibilityHint(app.T("Chạm để xoá", "Tap to remove"))
                    }
                }
            }
            HStack(spacing: 8) {
                TextField(placeholder, text: $draft)
                    .font(.system(size: 13))
                    .submitLabel(.done)
                    .onSubmit(add)
                    .padding(10)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(app.palette.rule))
                    .accessibilityIdentifier("\(identifier).field")
                Button(app.T("Thêm", "Add"), action: add)
                    .font(.system(size: 13, weight: .semibold))
                    .buttonStyle(.plain)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("\(identifier).add")
            }
        }
    }
}

// MARK: - Long text (note 69)

/// Note 69: long-text fields in Create event are at least twice the height of a one-line field (Event name), and each
/// has an Expand button that opens the whole text in a sheet with Clear all.
enum LongText {
    /// A one-line Create field: 15pt padding top and bottom around a 16pt line.
    static let singleLineHeight: CGFloat = 52
    /// The whole box, padding included.
    static let minBoxHeight: CGFloat = singleLineHeight * 2
}

/// The small "expand" control in a long field's label row.
struct ExpandFieldButton: View {
    @EnvironmentObject private var app: AppState
    let fieldName: String
    var identifier: String? = nil
    let action: () -> Void

    var body: some View {
        Button { Haptics.light(); action() } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(app.palette.ink2)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(app.T("Mở rộng \(fieldName)", "Expand \(fieldName)"))
        .accessibilityIdentifier(identifier ?? "expand")
    }
}

/// The whole text of one long field, full screen: Done, a live count, and Clear all (confirmed, so one stray tap never
/// wipes a write-up). Edits the same binding as the field, so nothing needs saving.
struct LongTextSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    let title: String
    @Binding var text: String
    /// nil = no cap (the description has none on the server); the count is still shown.
    var limit: Int? = nil
    var placeholder: String = ""
    /// The introduction's chosen look, so the sheet shows the text the way guests will.
    var font: Font = .system(size: 17)
    var color: Color? = nil
    @State private var confirmClear = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder).font(font).foregroundStyle(app.palette.ink3)
                        .padding(.horizontal, 21).padding(.vertical, 16)
                        .accessibilityHidden(true)
                }
                TextEditor(text: $text)
                    .font(font)
                    .foregroundStyle(color ?? app.palette.ink)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .focused($focused)
                    .accessibilityLabel(title)
                    .accessibilityIdentifier("longText.editor")
                    .onChange(of: text) { _, v in if let limit, v.count > limit { text = String(v.prefix(limit)) } }
            }
            .background(app.palette.paper)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(app.T("Xong", "Done")) { dismiss() }
                        .accessibilityIdentifier("longText.done")
                }
                // Top bar, not the bottom bar: with the keyboard up a bottom toolbar is hidden under it.
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .destructive) { confirmClear = true } label: {
                        Text(app.T("Xoá hết", "Clear all"))
                    }
                    .disabled(text.isEmpty)
                    .accessibilityIdentifier("longText.clearAll")
                }
            }
            // The count rides above the keyboard (a safe-area inset moves with it).
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Spacer()
                    Text(limit.map { "\(text.count)/\($0)" } ?? "\(text.count)").font(.footnote).monospacedDigit()
                        .foregroundStyle(limit.map { text.count >= $0 } == true ? BanbeTheme.alert : app.palette.ink2)
                        .accessibilityLabel(limit.map { app.T("\(text.count) trên \($0) ký tự", "\(text.count) of \($0) characters") }
                                            ?? app.T("\(text.count) ký tự", "\(text.count) characters"))
                }
                .padding(.horizontal, 20).padding(.vertical, 8)
                .background(app.palette.paper)
            }
            .confirmationDialog(app.T("Xoá toàn bộ nội dung?", "Clear all text?"), isPresented: $confirmClear, titleVisibility: .visible) {
                Button(app.T("Xoá hết", "Clear all"), role: .destructive) { text = ""; focused = true }
                    .accessibilityIdentifier("longText.clearConfirm")
                Button(app.T("Huỷ", "Cancel"), role: .cancel) {}
            }
        }
        .onAppear { focused = true }
    }
}

// MARK: - Introduction style (note 69, migration 207)

/// The introduction's whole-text look: one of four fonts and one of five theme colours (so it reads in light and dark).
/// Stored as details.intro_font / intro_color; "sans" + "ink" are the defaults and are not stored.
enum IntroStyle {
    static func font(_ key: String?, size: CGFloat = 16) -> Font {
        switch key {
        case "serif": return .system(size: size, design: .serif)
        case "rounded": return .system(size: size, design: .rounded)
        case "mono": return .system(size: size, design: .monospaced)
        default: return .system(size: size)
        }
    }

    static func color(_ key: String?, _ palette: Palette) -> Color {
        switch key {
        case "ink2": return palette.ink2
        case "clay": return palette.clay
        case "honey": return palette.honey
        case "alert": return BanbeTheme.alert
        default: return palette.ink
        }
    }

    static func fontName(_ key: String, _ T: (String, String) -> String) -> String {
        switch key {
        case "serif": return T("Có chân", "Serif")
        case "rounded": return T("Tròn", "Rounded")
        case "mono": return T("Đơn cách", "Mono")
        default: return T("Mặc định", "Default")
        }
    }

    static func colorName(_ key: String, _ T: (String, String) -> String) -> String {
        switch key {
        case "ink2": return T("Xám", "Grey")
        case "clay": return T("Đất nung", "Clay")
        case "honey": return T("Mật ong", "Honey")
        case "alert": return T("Đỏ", "Red")
        default: return T("Mặc định", "Default")
        }
    }
}

/// Font chips and colour swatches under the introduction field.
struct IntroStylePicker: View {
    @EnvironmentObject private var app: AppState
    @Binding var font: String
    @Binding var color: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(app.T("Kiểu chữ", "Text style")).font(.system(size: 13, weight: .semibold))
            HStack(spacing: 8) {
                ForEach(EventTypes.introFonts, id: \.self) { key in
                    let on = font == key
                    Button { Haptics.selection(); font = key } label: {
                        Text("Aa").font(IntroStyle.font(key, size: 17).weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(on ? app.palette.paper : app.palette.ink)
                            .background(on ? app.palette.ink : app.palette.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(on ? .clear : app.palette.rule, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(IntroStyle.fontName(key, app.T))
                    .accessibilityAddTraits(on ? [.isSelected] : [])
                    .accessibilityIdentifier("create.introFont.\(key)")
                }
            }
            HStack(spacing: 12) {
                ForEach(EventTypes.introColors, id: \.self) { key in
                    let on = color == key
                    Button { Haptics.selection(); color = key } label: {
                        Circle().fill(IntroStyle.color(key, app.palette))
                            .frame(width: 30, height: 30)
                            .overlay(Circle().stroke(app.palette.rule, lineWidth: 1))
                            .padding(4)
                            .overlay(Circle().stroke(on ? app.palette.ink : .clear, lineWidth: 2))
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(IntroStyle.colorName(key, app.T))
                    .accessibilityAddTraits(on ? [.isSelected] : [])
                    .accessibilityIdentifier("create.introColor.\(key)")
                }
            }
        }
        .foregroundStyle(app.palette.ink)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("create.introStyle")
    }
}

// MARK: - Sub-step bar (note 69)

/// The nested progress inside one Create step (Basics, Tickets). Deliberately unlike `StepProgress`: no ring, no
/// percentage, small 26pt dots on a thin track, filled clay for the current part, a ✓ for done parts, and only the
/// current part's name under the bar, so it reads as "inside this step", not as more steps.
struct SubStepBar: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let stepTitle: String
    let titles: [String]
    let current: Int
    let done: [Bool]
    var identifier: String = "create.substeps"
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                ForEach(titles.indices, id: \.self) { i in
                    if i > 0 {
                        Rectangle()
                            .fill(i <= current ? app.palette.clay : app.palette.rule)
                            .frame(height: 2)
                            .frame(maxWidth: .infinity)
                    }
                    dot(i)
                }
            }
            HStack(spacing: 6) {
                Text(app.T("Phần \(current + 1)/\(titles.count)", "Part \(current + 1) of \(titles.count)"))
                    .font(.caption.weight(.semibold)).foregroundStyle(app.palette.ink2)
                Text(titles.indices.contains(current) ? titles[current] : "").font(.subheadline.weight(.semibold))
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(app.palette.blockInset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(Motion.animation(.easeInOut(duration: 0.2), reduce: reduceMotion), value: current)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private func dot(_ i: Int) -> some View {
        let isCurrent = i == current
        let isDone = done.indices.contains(i) && done[i]
        return Button { Haptics.selection(); onSelect(i) } label: {
            ZStack {
                Circle()
                    .fill(isCurrent ? app.palette.clay : (isDone ? app.palette.ink : Color.clear))
                    .overlay(Circle().stroke(isCurrent || isDone ? Color.clear : app.palette.ink3, lineWidth: 1.5))
                if isDone && !isCurrent {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(app.palette.paper)
                } else {
                    Text("\(i + 1)").font(.system(size: 12, weight: .bold)).monospacedDigit()
                        .foregroundStyle(isCurrent ? app.palette.paper : app.palette.ink2)
                }
            }
            .frame(width: 26, height: 26)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -9)
        .accessibilityLabel(app.T("\(stepTitle), phần \(i + 1) trên \(titles.count), \(titles[i])",
                                  "\(stepTitle), part \(i + 1) of \(titles.count), \(titles[i])"))
        .accessibilityValue(isDone ? app.T("Xong", "Done") : "")
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
        .accessibilityIdentifier("\(identifier).\(i)")
    }
}
