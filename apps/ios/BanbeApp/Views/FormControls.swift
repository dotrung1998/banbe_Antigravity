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
