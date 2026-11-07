import SwiftUI
import UIKit

/// Onboarding Version 3 overlay (note 64). Web twin: src/components/tour/OnboardingTour.jsx.
///
/// Hosted in the dock's always-on-top window (BottomTabBarOverlayRoot), the one place that is above BOTH the main
/// window (Home, Account) and the dock itself, so it can spotlight either. While it shows, that window takes every
/// touch (`BottomTabBarOverlay.setTourActive`) and RootView hides the real app from VoiceOver, so the highlighted
/// control is only ever a picture: nothing underneath can be pressed.
struct OnboardingTourOverlay: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var tour = OnboardingTourController.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var titleFocused: Bool

    private static let pad: CGFloat = 6
    private static let waitSeconds: Double = 1.5

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let step = tour.current
            let rect = step.flatMap { tour.frames[$0.target] }.flatMap { visible($0, in: size) }
            ZStack(alignment: .topLeading) {
                scrim(size: size, hole: rect)
                if let rect {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(app.palette.clay, lineWidth: 2)
                        .shadow(color: app.palette.clay.opacity(0.35), radius: 6)
                        .frame(width: rect.width + Self.pad * 2, height: rect.height + Self.pad * 2)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                if let step {
                    card(step, size: size, rect: rect)
                }
            }
            .animation(reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.28), value: rect)
        }
        .ignoresSafeArea()
        .accessibilityIdentifier("tour.overlay")
        .task(id: tour.index) { await settleStep() }
        .onChange(of: app.screen) { _, s in
            // A deep link or anything else that leaves the tour's screens ends it (no marker).
            if s != .home && s != .profile { app.abortOnboardingTour() }
        }
        .onChange(of: app.userID) { _, uid in if uid == nil { app.abortOnboardingTour() } }
        .onChange(of: app.onboardingFlowActive || app.needsPreferencesOnboarding || app.needsSettingsOnboarding) { _, up in
            if up { app.abortOnboardingTour() }
        }
    }

    /// Go to the step's screen, give its target a moment to appear, otherwise skip it.
    private func settleStep() async {
        app.showTourStepScreen()
        titleFocused = false
        let deadline = Date().addingTimeInterval(Self.waitSeconds)
        while Date() < deadline {
            if let step = tour.current, let r = tour.frames[step.target], visibleRect(r) { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
            if Task.isCancelled { return }
        }
        if let step = tour.current, tour.frames[step.target].map(visibleRect) != true {
            if !tour.skipMissing() { app.endOnboardingTour(completed: true) }
            return
        }
        titleFocused = true
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    private func visibleRect(_ r: CGRect) -> Bool {
        let screen = UIScreen.main.bounds
        return r.width > 0 && r.height > 0 && r.maxY > 0 && r.minY < screen.height
    }

    private func visible(_ r: CGRect, in size: CGSize) -> CGRect? {
        r.width > 0 && r.height > 0 && r.maxY > 0 && r.minY < size.height ? r : nil
    }

    private func scrim(size: CGSize, hole: CGRect?) -> some View {
        Path { p in
            p.addRect(CGRect(origin: .zero, size: size))
            if let hole {
                p.addRoundedRect(in: hole.insetBy(dx: -Self.pad, dy: -Self.pad), cornerSize: CGSize(width: 16, height: 16), style: .continuous)
            }
        }
        .fill(Color(red: 20 / 255, green: 18 / 255, blue: 14 / 255).opacity(0.58), style: FillStyle(eoFill: true))
        .contentShape(Rectangle()) // swallows every touch, including inside the cut-out
        .onTapGesture {}
        .accessibilityHidden(true)
    }

    @ViewBuilder private func card(_ step: TourStep, size: CGSize, rect: CGRect?) -> some View {
        let n = tour.steps.count
        let width = min(340, size.width - 32)
        let copy = app.lang == "en" ? step.en : step.vi
        let title = copy.title
        VStack(alignment: .leading, spacing: 0) {
            Text(app.T("Bước \(tour.index + 1)/\(n)", "Step \(tour.index + 1) of \(n)"))
                .font(.system(size: 12, weight: .semibold)).opacity(0.6)
                .accessibilityHidden(true)
            Text(title)
                .font(BanbeTheme.display(20)).padding(.top, 4)
                .accessibilityLabel(app.T("Bước \(tour.index + 1)/\(n): \(title)", "Step \(tour.index + 1) of \(n): \(title)"))
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)
                .accessibilityIdentifier("tour.title")
            Text(copy.body)
                .font(.system(size: 14)).padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("tour.body")
            stepStrip(n: n).padding(.top, 12)
            HStack(spacing: 8) {
                Button(app.T("Bỏ qua", "Skip")) { app.endOnboardingTour(completed: true) }
                    .font(.system(size: 14, weight: .semibold)).opacity(0.75)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("tour.skip")
                Spacer(minLength: 0)
                Button(app.T("Quay lại", "Back")) { tour.back() }
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 16).frame(minHeight: 44)
                    .background(app.palette.field, in: Capsule())
                    .overlay(Capsule().stroke(app.palette.rule, lineWidth: 1))
                    .disabled(tour.isFirst).opacity(tour.isFirst ? 0.4 : 1)
                    .accessibilityIdentifier("tour.back")
                Button(tour.isLast ? app.T("Xong", "Done") : app.T("Tiếp", "Next")) {
                    if !tour.next() { app.endOnboardingTour(completed: true) }
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(app.palette.paper)
                .padding(.horizontal, 18).frame(minHeight: 44)
                .background(app.palette.ink, in: Capsule())
                .accessibilityIdentifier("tour.next")
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
        }
        .foregroundStyle(app.palette.ink)
        .padding(16)
        .frame(width: width, alignment: .leading)
        .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 22, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("tour.card")
        .accessibilityAction(.escape) { app.endOnboardingTour(completed: true) }
        .position(cardCenter(width: width, size: size, rect: rect, below: step.below))
    }

    private func stepStrip(n: Int) -> some View {
        // Wraps on narrow screens / large text: a flow of 32pt numbers, every one directly selectable.
        let columns = [GridItem(.adaptive(minimum: 36), spacing: 6, alignment: .leading)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(Array(tour.steps.enumerated()), id: \.element.id) { i, st in
                let current = i == tour.index
                let missing = tour.missing.contains(i)
                Button { tour.goTo(i) } label: {
                    Text("\(i + 1)")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 32, height: 32)
                        .foregroundStyle(current ? app.palette.paper : app.palette.ink)
                        .background(current ? app.palette.ink : app.palette.field, in: Circle())
                        .overlay(Circle().stroke(app.palette.rule, lineWidth: current ? 0 : 1))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(missing).opacity(missing ? 0.35 : 1)
                .accessibilityLabel(app.T("Bước \(i + 1)/\(n): \(st.short.vi)", "Step \(i + 1) of \(n): \(st.short.en)"))
                .accessibilityAddTraits(current ? [.isSelected] : [])
                .accessibilityIdentifier("tour.step.\(i + 1)")
            }
        }
    }

    private func cardCenter(width: CGFloat, size: CGSize, rect: CGRect?, below: Bool) -> CGPoint {
        let estimatedHeight: CGFloat = 230
        let x: CGFloat
        let y: CGFloat
        if let rect {
            x = min(max(16 + width / 2, rect.midX), size.width - 16 - width / 2)
            let placeBelow = below ? rect.maxY < size.height * 0.62 : rect.minY < size.height * 0.38
            if placeBelow {
                y = min(rect.maxY + Self.pad + 12 + estimatedHeight / 2, size.height - estimatedHeight / 2 - 24)
            } else {
                y = max(rect.minY - Self.pad - 12 - estimatedHeight / 2, estimatedHeight / 2 + 50)
            }
        } else {
            x = size.width / 2
            y = size.height * 0.4
        }
        return CGPoint(x: x, y: y)
    }
}
