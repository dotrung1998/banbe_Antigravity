import SwiftUI
import UIKit

/// Tour overlay (note 64), forward-only chapters since onboarding v5 (note 80). Web twin (still the 8-step jumpable
/// version): src/components/tour/OnboardingTour.jsx.
///
/// Hosted in the dock's always-on-top window (BottomTabBarOverlayRoot), the one place that is above BOTH the main
/// window (Home, Account) and the dock itself, so it can spotlight either. While it shows, that window takes every
/// touch (`BottomTabBarOverlay.setTourActive`) and RootView hides the real app from VoiceOver, so the highlighted
/// control is only ever a picture: nothing underneath can be pressed. A "do it" step runs the control's own action
/// from here (`AppState.performTourDoIt`) when the person taps inside the highlight.
///
/// No Back and no jumpable step numbers: the progress bar only shows where you are. Stopping happens at a chapter
/// break or with End tour.
struct OnboardingTourOverlay: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var tour = OnboardingTourController.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var titleFocused: Bool
    @State private var ringPulse = false

    private static let pad: CGFloat = 6
    private static let waitSeconds: Double = 1.5

    /// Looping motion holds still under UI tests: XCUITest waits for an idle app (note 63).
    private static var loopsMotion: Bool {
        #if DEBUG
        if UITestFixture.isActive { return false }
        #endif
        return true
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let onStep = tour.phase == .step
            let step = onStep ? tour.current : nil
            let rect = step.flatMap { tour.frames[$0.target] }.flatMap { visible($0, in: size) }
            ZStack(alignment: .topLeading) {
                scrim(size: size, hole: rect)
                if let rect {
                    let ring = RoundedRectangle(cornerRadius: 16, style: .continuous)
                    ring
                        .stroke(app.palette.clay, lineWidth: 2)
                        .shadow(color: app.palette.clay.opacity(0.35), radius: 6)
                        .frame(width: rect.width + Self.pad * 2, height: rect.height + Self.pad * 2)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    if tour.doIt != nil && !reduceMotion && Self.loopsMotion {
                        // The "tap here" ring: grows and fades on a loop (held still under UI tests and Reduce Motion).
                        ring
                            .stroke(Color.white, lineWidth: 2)
                            .frame(width: rect.width + Self.pad * 2 + 12, height: rect.height + Self.pad * 2 + 12)
                            .scaleEffect(ringPulse ? 1.12 : 1)
                            .opacity(ringPulse ? 0 : 0.9)
                            .position(x: rect.midX, y: rect.midY)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                            .onAppear {
                                ringPulse = false
                                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { ringPulse = true }
                            }
                    }
                }
                if let step {
                    card(step, size: size, rect: rect)
                }
                if tour.phase == .chapterDone { chapterBreak(size: size) }
                if tour.phase == .finished { finishSheet(size: size) }
            }
            .animation(reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.28), value: rect)
            .animation(reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.32), value: tour.phase)
        }
        .ignoresSafeArea()
        .accessibilityIdentifier("tour.overlay")
        .task(id: "\(tour.index).\(tour.phase)") { await settleStep() }
        .onChange(of: app.screen) { _, s in
            // A deep link or anything else that leaves the tour's screens ends it (no marker).
            if s != .home && s != .profile { app.abortOnboardingTour() }
        }
        .onChange(of: app.userID) { _, uid in if uid == nil { app.abortOnboardingTour() } }
        .onChange(of: app.onboardingFlowActive || app.needsPreferencesOnboarding || app.needsSettingsOnboarding) { _, up in
            if up { app.abortOnboardingTour() }
        }
    }

    /// Go to the step's screen, give its target a moment to appear, otherwise skip it (forward only).
    private func settleStep() async {
        titleFocused = false
        guard tour.phase == .step else {
            UIAccessibility.post(notification: .screenChanged, argument: nil)
            return
        }
        app.showTourStepScreen()
        let deadline = Date().addingTimeInterval(Self.waitSeconds)
        while Date() < deadline {
            if let step = tour.current, let r = tour.frames[step.target], visibleRect(r) { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
            if Task.isCancelled { return }
        }
        if let step = tour.current, tour.frames[step.target].map(visibleRect) != true {
            tour.skipMissing()
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
        let cutout = hole?.insetBy(dx: -Self.pad, dy: -Self.pad)
        return Path { p in
            p.addRect(CGRect(origin: .zero, size: size))
            if let cutout {
                p.addRoundedRect(in: cutout, cornerSize: CGSize(width: 16, height: 16), style: .continuous)
            }
        }
        .fill(Color(red: 20 / 255, green: 18 / 255, blue: 14 / 255).opacity(0.62), style: FillStyle(eoFill: true))
        .contentShape(Rectangle()) // swallows every touch, including inside the cut-out
        .onTapGesture { location in
            // Only a "do it" step reacts, and only to a tap inside its highlight.
            if tour.doIt != nil, let cutout, cutout.contains(location) { app.performTourDoIt() }
        }
        .accessibilityHidden(true)
    }

    // MARK: step card

    @ViewBuilder private func card(_ step: TourStep, size: CGSize, rect: CGRect?) -> some View {
        let width = min(360, size.width - 24)
        let text = stepCopy(step)
        let chapter = tour.chapter
        let chapterName = chapter.map { app.T($0.name.vi, $0.name.en) } ?? ""
        let stepInChapter = chapter.map { tour.index - $0.range.lowerBound + 1 } ?? tour.index + 1
        let chapterSteps = chapter?.range.count ?? tour.steps.count
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(app.T("Chương \(tour.chapterIndex + 1)/\(tour.chapters.count) · \(chapterName)",
                           "Chapter \(tour.chapterIndex + 1) of \(tour.chapters.count) · \(chapterName)").uppercased())
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(app.T("\(stepInChapter)/\(chapterSteps)", "\(stepInChapter) of \(chapterSteps)"))
                    .fixedSize()
            }
            .font(.system(size: 11, weight: .semibold)).tracking(0.8)
            .foregroundStyle(app.palette.ink.opacity(0.6))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("tour.chapter")
            Text(text.title)
                .font(BanbeTheme.display(22)).padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)
                .accessibilityIdentifier("tour.title")
            Text(text.body)
                .font(.system(size: 14)).lineSpacing(2).padding(.top, 6)
                .foregroundStyle(app.palette.ink.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("tour.body")
            HStack(spacing: 8) {
                if let doIt = tour.doIt {
                    // Also a real button, so VoiceOver (which can't reach the highlight) can do the step too.
                    Button { app.performTourDoIt() } label: {
                        Label(app.T("\(doIt.vi) để tiếp tục", "\(doIt.en) to continue"), systemImage: "arrow.up.forward")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("tour.doIt")
                } else {
                    Button { tour.next() } label: {
                        Text(tour.isLastInChapter ? app.T("Xong chương này", "Finish chapter") : app.T("Tiếp", "Next"))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(app.palette.paper)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(app.palette.ink, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .accessibilityIdentifier("tour.next")
                }
                Button(app.T("Kết thúc", "End tour")) { app.endOnboardingTour(completed: true) }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(app.palette.ink.opacity(0.7))
                    .padding(.horizontal, 8).frame(minHeight: 44)
                    .fixedSize()
                    .accessibilityIdentifier("tour.end")
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
            progressBars.padding(.top, 12)
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 14)
        .frame(width: width, alignment: .leading)
        .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 22, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("tour.card")
        .accessibilityAction(.escape) { app.endOnboardingTour(completed: true) }
        .position(cardCenter(width: width, size: size, rect: rect, below: step.below))
    }

    private func stepCopy(_ step: TourStep) -> (title: String, body: String) {
        if step.id == "account.organizerMode" && app.organizerMode && !app.simpleShellEnabled {
            let on = OnboardingTourContent.hostingOnCopy
            return app.isEN ? on.en : on.vi
        }
        return app.isEN ? step.en : step.vi
    }

    /// One thin bar per step, a gap between chapters. Read-only: it shows where you are, it can't be used to jump.
    private var progressBars: some View {
        let total = tour.steps.count
        return HStack(spacing: 3) {
            ForEach(Array(tour.steps.indices), id: \.self) { i in
                Capsule()
                    .fill(i <= tour.index ? app.palette.ink : app.palette.rule)
                    .frame(height: 3)
                    .padding(.leading, tour.chapters.contains { $0.range.lowerBound == i && i > 0 } ? 7 : 0)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(app.T("Tiến độ: bước \(tour.position)/\(total)", "Tour progress, step \(tour.position) of \(total)"))
        .accessibilityIdentifier("tour.progress")
    }

    private func cardCenter(width: CGFloat, size: CGSize, rect: CGRect?, below: Bool) -> CGPoint {
        let estimatedHeight: CGFloat = 240
        let x: CGFloat
        let y: CGFloat
        if let rect {
            x = min(max(12 + width / 2, rect.midX), size.width - 12 - width / 2)
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

    // MARK: sheets

    private func bottomSheet<Content: View>(size: CGSize, id: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 0) {
                Capsule().fill(app.palette.ink.opacity(0.2)).frame(width: 36, height: 5)
                    .frame(maxWidth: .infinity).padding(.bottom, 12)
                    .accessibilityHidden(true)
                content()
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(app.palette.paper, in: UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityIdentifier(id)
        }
        .frame(width: size.width, height: size.height)
        .transition(reduceMotion ? .opacity : .move(edge: .bottom))
    }

    private func sheetHeader(eyebrow: String, title: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow.uppercased())
                .font(.system(size: 11, weight: .semibold)).tracking(1.2)
                .foregroundStyle(app.palette.ink.opacity(0.6))
            Text(title)
                .font(BanbeTheme.display(26))
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)
                .accessibilityIdentifier(id)
        }
    }

    private func chapterBreak(size: CGSize) -> some View {
        let done = tour.chapterIndex
        let next = tour.chapters.indices.contains(done + 1) ? tour.chapters[done + 1] : nil
        let nextName = next.map { app.T($0.name.vi, $0.name.en) } ?? ""
        return bottomSheet(size: size, id: "tour.break") {
            sheetHeader(eyebrow: app.T("Xong chương \(done + 1)", "Chapter \(done + 1) done"),
                        title: app.T("Tiếp theo: \(nextName.lowercased())", "Next: \(nextName.lowercased())"),
                        id: "tour.break.title")
            VStack(spacing: 0) {
                ForEach(Array(tour.chapters.enumerated()), id: \.element.id) { i, c in
                    chapterRow(i, c, state: i <= done ? .done : i == done + 1 ? .current : .later)
                }
            }
            .padding(.top, 14).padding(.bottom, 18)
            if let next {
                InkButton(title: app.T("Tiếp tục, \(next.range.count) bước", "Continue, \(next.range.count) \(next.range.count == 1 ? "step" : "steps")")) {
                    tour.continueToNextChapter()
                }
                .accessibilityIdentifier("tour.break.continue")
            }
            Button { app.endOnboardingTour(completed: true) } label: {
                Text(app.T("Dừng ở đây", "Finish for now"))
                    .font(.subheadline.weight(.semibold)).opacity(0.75)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .accessibilityHint(app.T("Xem lại bất cứ lúc nào trong Tài khoản › Trợ giúp", "Replay any time from Account › Help"))
            .accessibilityIdentifier("tour.break.stop")
        }
    }

    private enum RowState { case done, current, later }

    private func chapterRow(_ i: Int, _ c: OnboardingTourController.ChapterRun, state: RowState) -> some View {
        let n = c.range.count
        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(state == .done ? app.palette.ink : .clear)
                    .overlay(Circle().stroke(state == .current ? app.palette.ink : app.palette.rule, lineWidth: 1.5))
                if state == .done {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(app.palette.paper)
                } else {
                    Text("\(i + 1)").font(.system(size: 12, weight: .bold))
                }
            }
            .frame(width: 26, height: 26)
            .accessibilityHidden(true)
            Text(app.T(c.name.vi, c.name.en))
                .font(.system(size: 15, weight: state == .current ? .semibold : .regular))
            Spacer(minLength: 8)
            Text(app.T("\(n) bước", "\(n) \(n == 1 ? "step" : "steps")"))
                .font(.system(size: 12)).opacity(0.6)
        }
        .opacity(state == .later ? 0.6 : 1)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(app.palette.rule).frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityValue(state == .done ? app.T("Đã xong", "Done") : state == .current ? app.T("Tiếp theo", "Next") : "")
    }

    private func finishSheet(size: CGSize) -> some View {
        bottomSheet(size: size, id: "tour.finish") {
            sheetHeader(eyebrow: app.T("Xong hướng dẫn", "Tour complete"), title: app.T("Đó là banbe", "That's banbe"),
                        id: "tour.finish.title")
            Text(app.T("Bạn đã biết cách tìm sự kiện, nơi có lịch và tin nhắn, và chỗ đổi mọi lựa chọn lúc thiết lập. Xem lại bất cứ lúc nào trong Tài khoản › Trợ giúp.",
                       "You've seen how to find an event, where your plans and messages live, and where every choice from setup can be changed. Replay it any time from Account › Help."))
                .font(.subheadline).lineSpacing(3)
                .foregroundStyle(app.palette.ink.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8).padding(.bottom, 18)
            InkButton(title: app.T("Khám phá banbe", "Explore banbe")) { app.endOnboardingTour(completed: true) }
                .accessibilityIdentifier("tour.finish.done")
        }
    }
}
