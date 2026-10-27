import SwiftUI
import UIKit

/// "Do it, then ✓" button (note 64). Web twin: src/components/ui/AsyncSuccessButton.jsx.
/// State model: `AsyncActionState` (Lib/AsyncAction.swift).
///
/// - `run` performs the real work and returns an `AsyncActionResult`. Only that result can show the ✓.
/// - While pending the button morphs into a circle on its own axis and an arc spins.
/// - On success the arc finishes its current turn, a ✓ appears, success is announced to VoiceOver, then
///   `onSuccessAnimationComplete` runs exactly once. That is where a caller navigates or presents.
/// - On failure the shape and label come back and the caller's own error text shows.
/// - Reduce Motion: no morph, no spin, a short crossfade (same state timing).
struct AsyncSuccessButton: View {
    enum Role { case primary, secondary, destructive }

    let title: String
    var role: Role = .primary
    var enabled = true
    /// Spoken while pending (e.g. "Logging in…"). nil = the title.
    var pendingLabel: String? = nil
    /// Spoken when the ✓ shows (e.g. "Signed in"). nil = no announcement (an intermediate step).
    var successLabel: String? = nil
    /// "Stay and update" saves: after the ✓ the button returns to its label.
    var resetAfterSuccess = false
    var identifier: String
    let run: () async -> AsyncActionResult
    var onSuccessAnimationComplete: (() -> Void)? = nil
    var onPhaseChange: ((AsyncActionPhase) -> Void)? = nil

    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var state = AsyncActionState()
    @State private var spinStart = Date()
    @State private var showCheck = false

    private static let height: CGFloat = 50
    private static let turn: TimeInterval = 0.8

    private var morphed: Bool { !reduceMotion && state.phase != .idle && state.phase != .failure }
    /// The "not yet" look applies only while idle: a caller's own busy flag flipping `enabled` mid-request must not
    /// grey out the morphing circle.
    private var looksEnabled: Bool { enabled || state.phase != .idle }

    var body: some View {
        Button(action: activate) {
            ZStack {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .opacity(state.phase == .idle || state.phase == .failure ? 1 : 0)
                if state.phase == .pending || (state.phase == .success && !showCheck) {
                    spinner.transition(.opacity)
                }
                if showCheck {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: morphed ? Self.height : .infinity, minHeight: Self.height, maxHeight: Self.height)
            .background(background, in: RoundedRectangle(cornerRadius: morphed ? Self.height / 2 : 18, style: .continuous))
            .overlay {
                if role == .secondary {
                    RoundedRectangle(cornerRadius: morphed ? Self.height / 2 : 18, style: .continuous)
                        .stroke(app.palette.rule, lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .frame(maxWidth: .infinity) // keeps the circle on the original axis and the layout from jumping
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.86), value: state.phase)
        .animation(.easeOut(duration: 0.2), value: showCheck)
        .disabled(!enabled && state.phase == .idle)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(state.phase.isLocked ? .updatesFrequently : [])
        .accessibilityIdentifier(identifier)
        .onChange(of: state.phase) { _, phase in onPhaseChange?(phase) }
    }

    @ViewBuilder private var spinner: some View {
        if reduceMotion || UITestFixture.isActive {
            // Still under Reduce Motion, and under UI tests (XCUITest waits for an idle app, note 63).
            arc(angle: .degrees(-90))
        } else {
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSince(spinStart)
                arc(angle: .degrees(t / Self.turn * 360 - 90))
            }
        }
    }

    private func arc(angle: Angle) -> some View {
        ZStack {
            Circle().stroke(foreground.opacity(0.25), lineWidth: 2.4)
            Circle().trim(from: 0, to: 0.28)
                .stroke(foreground, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .rotationEffect(angle)
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }

    private var background: Color {
        switch role {
        case .primary: return looksEnabled ? app.palette.ink : app.palette.ink.opacity(0.16)
        case .secondary: return app.palette.field
        case .destructive: return BanbeTheme.alert
        }
    }

    private var foreground: Color {
        switch role {
        case .primary: return looksEnabled ? app.palette.paper : app.palette.ink
        case .secondary: return app.palette.ink
        case .destructive: return BanbeTheme.onAlert
        }
    }

    private var accessibilityValue: String {
        switch state.phase {
        case .pending: return pendingLabel ?? app.T("Đang xử lý", "Working")
        case .success, .completed: return successLabel ?? ""
        default: return ""
        }
    }

    private func activate() {
        guard enabled, !state.phase.isLocked else { return }
        state = state.reduce(.start)
        spinStart = Date()
        showCheck = false
        if let pendingLabel { UIAccessibility.post(notification: .announcement, argument: pendingLabel) }
        Task { @MainActor in
            let result = await run()
            state = state.reduce(.resolve(ok: result.ok, error: result.error))
            if result.ok { await finishSuccess() } else { state = state.reduce(.reset) }
        }
    }

    @MainActor private func finishSuccess() async {
        // Let the arc finish the turn it is on, then draw the ✓.
        if !reduceMotion && !UITestFixture.isActive {
            let elapsed = Date().timeIntervalSince(spinStart)
            let rest = Self.turn - elapsed.truncatingRemainder(dividingBy: Self.turn)
            try? await Task.sleep(nanoseconds: UInt64(rest * 1_000_000_000))
        }
        showCheck = true
        Haptics.success()
        if let successLabel { UIAccessibility.post(notification: .announcement, argument: successLabel) }
        try? await Task.sleep(nanoseconds: UInt64((reduceMotion ? 0.15 : 0.36) * 1_000_000_000))
        let before = state
        state = state.reduce(.animDone)
        if state.fired && !before.fired { onSuccessAnimationComplete?() }
        if resetAfterSuccess {
            try? await Task.sleep(nanoseconds: 700_000_000)
            showCheck = false
            state = state.reduce(.reset)
        }
    }
}
