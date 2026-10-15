import PhotosUI
import SwiftUI

/// First-time host setup (replaces the old "retry" card on Account > Host): choose a cover from the
/// built-in set or upload a photo, name the profile, write a short intro. Finishing plays the
/// reveal: the sheet's elements dissolve into dots, swirl into a rotating sphere, then assemble
/// into the host card. Skippable; never shown again once finished or skipped. Mirrors web's
/// HostSetupSheet.jsx / HostReveal.jsx.
struct HostSetupView: View {
    @EnvironmentObject private var app: AppState

    private enum Phase { case form, saving, reveal }

    @State private var coverID: String? = HostStockCover.all[0].id
    @State private var uploaded: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var name = ""
    @State private var intro = ""
    @State private var phase: Phase = .form
    @State private var error = ""

    @State private var sourceFrames: [CGRect] = []
    @State private var origin: CGPoint = .zero
    @State private var canvasSize: CGSize = .zero
    @State private var particles: [HostReveal.Particle] = []
    @State private var revealStart: Date?
    @State private var darkBackdrop = false
    @State private var fadedOut = false
    @State private var finalTarget: CGRect?

    private let nameMax = 80, introMax = 280
    private var previewImage: UIImage? {
        if let uploaded { return uploaded }
        return HostStockCover.all.first { $0.id == coverID }?.image(side: 320)
    }
    private var canSubmit: Bool { phase == .form && !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                (darkBackdrop ? Color(hex: 0x0E0C09).opacity(0.94) : app.palette.paper).ignoresSafeArea()
                content
                    .opacity(phase == .reveal ? 0 : 1)
                    .animation(.easeOut(duration: 0.32), value: phase == .reveal)
                    .allowsHitTesting(phase != .reveal)
                if phase == .reveal, let start = revealStart, !particles.isEmpty {
                    revealCanvas(start: start)
                }
            }
            .opacity(fadedOut ? 0 : 1)
            .onAppear {
                origin = geo.frame(in: .global).origin
                canvasSize = geo.size
                if name.isEmpty { name = EnsureOrganizerLogic.defaultName(displayName: app.user?.displayName, isEN: app.isEN) }
            }
            .onChange(of: geo.size) { _, new in canvasSize = new; origin = geo.frame(in: .global).origin }
        }
        .ignoresSafeArea()
        .onPreferenceChange(RevealSourceKey.self) { sourceFrames = $0 }
        .onChange(of: pickerItem) { _, item in
            Task {
                guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                await MainActor.run { uploaded = image; coverID = nil; error = "" }
            }
        }
        .accessibilityIdentifier("hostSetup.root")
    }

    // MARK: form

    private var content: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                // X = "I don't want to be a host right now": organizer mode goes back off and no organizer
                // profile is created (it is only created by the Create button below).
                Button { if phase == .form { app.cancelHostSetup() } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(app.palette.field, in: Circle())
                }
                .opacity(phase == .form ? 1 : 0.3)
                .buttonStyle(.plain)
                .accessibilityLabel(app.T("Đóng", "Close"))
                .accessibilityIdentifier("hostSetup.skip")
            }
            .padding(.horizontal, 22).padding(.top, 60)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(app.T("Tạo hồ sơ tổ chức", "Set up your host profile"))
                        .font(BanbeTheme.display(30)).padding(.top, 6).revealSource()
                    Text(app.T("Đây là diện mạo khách sẽ thấy. Bạn có thể đổi bất cứ lúc nào.", "This is how guests will see you. You can change it any time."))
                        .font(.system(size: 14)).opacity(0.68).padding(.top, 8).revealSource()

                    previewCard.padding(.top, 22)

                    sectionLabel(app.T("Ảnh bìa", "Cover"))
                    coverRow.revealSource()

                    sectionLabel(app.T("Tên", "Name"))
                    TextField(app.T("Tên tổ chức của bạn", "Your host name"), text: $name)
                        .font(.system(size: 15))
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onChange(of: name) { _, v in if v.count > nameMax { name = String(v.prefix(nameMax)) } }
                        .revealSource()
                        .accessibilityIdentifier("hostSetup.name")

                    HStack {
                        sectionLabel(app.T("Giới thiệu", "About"))
                        Spacer()
                        Text("\(intro.count)/\(introMax)").font(.system(size: 11)).opacity(0.55).padding(.top, 26)
                    }
                    TextField(app.T("Bạn tổ chức những gì? Vì sao khách nên đến?", "What do you host? Why should guests come?"), text: $intro, axis: .vertical)
                        .lineLimit(4...6)
                        .font(.system(size: 15))
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onChange(of: intro) { _, v in if v.count > introMax { intro = String(v.prefix(introMax)) } }
                        .revealSource()
                        .accessibilityIdentifier("hostSetup.intro")

                    if !error.isEmpty {
                        Text(error).font(.system(size: 12.5)).foregroundStyle(BanbeTheme.alert).padding(.top, 14)
                            .accessibilityIdentifier("hostSetup.error")
                    }
                }
                .padding(.horizontal, 22).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)

            InkButton(title: phase == .form ? app.T("Tạo hồ sơ", "Create host profile") : app.T("Đang chuẩn bị…", "Setting things up…"), enabled: canSubmit) {
                Task { await finish() }
            }
            .revealSource()
            .padding(.horizontal, 22).padding(.bottom, 22)
            .accessibilityIdentifier("hostSetup.submit")
        }
        .foregroundStyle(app.palette.ink)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .semibold)).kerning(0.6).opacity(0.55).padding(.top, 26).padding(.bottom, 10)
    }

    private var previewCard: some View {
        VStack(spacing: 6) {
            ZStack {
                if let img = previewImage { Image(uiImage: img).resizable().scaledToFill() } else { app.palette.ink }
            }
            .frame(width: 104, height: 104)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 14, y: 8)
            .revealSource()
            Text(name.trimmingCharacters(in: .whitespaces).isEmpty ? app.T("Tên của bạn", "Your name") : name)
                .font(BanbeTheme.display(22)).multilineTextAlignment(.center).padding(.top, 12)
            Text(intro.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? app.T("Giới thiệu ngắn về bạn", "A short line about you") : intro)
                .font(.system(size: 13)).multilineTextAlignment(.center)
                .opacity(intro.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 0.75)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8).padding(.bottom, 4)
    }

    private var coverRow: some View {
        // The PhotosPicker label closure is nonisolated, so read the main-actor palette out here.
        let ink = app.palette.ink
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    ZStack {
                        if let uploaded {
                            Image(uiImage: uploaded).resizable().scaledToFill()
                        } else {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(ink.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            Image(systemName: "plus").font(.system(size: 18, weight: .regular)).opacity(0.7)
                        }
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(selectionRing(uploaded != nil))
                }
                .accessibilityIdentifier("hostSetup.upload")
                ForEach(HostStockCover.all) { c in
                    let on = uploaded == nil && coverID == c.id
                    Button {
                        uploaded = nil; coverID = c.id; error = ""
                    } label: {
                        Image(uiImage: c.image(side: 128)).resizable().scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(selectionRing(on))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(app.isEN ? c.en : c.vi)
                    .accessibilityIdentifier("hostSetup.cover.\(c.id)")
                }
            }
            .padding(6)
        }
        .padding(-6)
    }

    private func selectionRing(_ on: Bool) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(on ? app.palette.ink : Color.clear, lineWidth: 2.5)
            .padding(-4)
    }

    // MARK: save + reveal

    /// The organizer row is created by ensure_my_organizer. Call it directly (with a few quiet retries)
    /// instead of waiting on the background trigger, whose gating can keep it from ever running.
    private func obtainOrganizer() async -> String? {
        if let id = app.myOrganizerID ?? app.myOrganizerIDs.first { return id }
        for attempt in 1...3 {
            await app.ensureOrganizerIfNeeded(force: true, modeSettled: true)
            if let id = app.myOrganizerID ?? app.myOrganizerIDs.first { return id }
            try? await Task.sleep(nanoseconds: UInt64(700_000_000 * attempt))
        }
        return nil
    }

    private func finish() async {
        guard canSubmit else { return }
        phase = .saving; error = ""
        let image = uploaded ?? (HostStockCover.all.first { $0.id == coverID } ?? HostStockCover.all[0]).image(side: 640)
        guard let organizerID = await obtainOrganizer() else {
            phase = .form
            error = app.T("Chưa tạo được hồ sơ lúc này. Kiểm tra kết nối rồi nhấn Tạo hồ sơ lại.",
                          "We couldn't create your profile just now. Check your connection and tap Create again.")
                + (app.ensureOrganizerErrorCode.isEmpty ? "" : " (\(app.ensureOrganizerErrorCode))")
            return
        }
        let ok = await app.saveOrganizerProfile(avatarImage: image, organizerID: organizerID,
                                                name: name.trimmingCharacters(in: .whitespaces),
                                                intro: intro.trimmingCharacters(in: .whitespacesAndNewlines))
        guard ok else {
            phase = .form
            error = app.orgProfileError.isEmpty ? app.T("Không thể lưu. Vui lòng thử lại.", "Could not save. Please try again.") : app.orgProfileError
            return
        }
        // Land on the host card the dots will assemble into.
        app.screen = .profile
        app.accountTab = "host"
        startReveal()
    }

    private func startReveal() {
        if UIAccessibility.isReduceMotionEnabled {
            phase = .reveal
            withAnimation(.easeInOut(duration: 0.6)) { darkBackdrop = true }
            Task {
                try? await Task.sleep(nanoseconds: 150_000_000)
                withAnimation(.easeInOut(duration: 0.6)) { fadedOut = true }
                try? await Task.sleep(nanoseconds: 650_000_000)
                app.finishHostSetup("done")
            }
            return
        }
        let w = Double(canvasSize.width), h = Double(canvasSize.height)
        let view = revealView
        let sources = sourceFrames.map { HostReveal.SourceRect(rect: $0.offsetBy(dx: -origin.x, dy: -origin.y), radius: 20) }
            .filter { $0.rect.width > 4 && $0.rect.height > 4 }
        let fallback = [HostReveal.SourceRect(rect: CGRect(x: w * 0.1, y: h * 0.3, width: w * 0.8, height: h * 0.3), radius: 20)]
        particles = HostReveal.buildParticles(count: 1500, sources: sources.isEmpty ? fallback : sources, target: cardTarget(), view: view, seed: 11)
        revealStart = Date()
        phase = .reveal
        withAnimation(.easeInOut(duration: 0.6)) { darkBackdrop = true }
        Task {
            // The real card is mounted by now; aim at where it actually is.
            try? await Task.sleep(nanoseconds: UInt64((HostReveal.Timeline.coalesceStart - 50) * 1_000_000))
            let target = cardTarget()
            finalTarget = target
            var rng = HostReveal.Mulberry32(seed: 99)
            if let target { for i in particles.indices { let d = HostReveal.sample(in: target, radius: 22, rng: &rng); particles[i].dx = d.x; particles[i].dy = d.y } }
            // The dark backdrop lifts exactly as the finished card lights up.
            try? await Task.sleep(nanoseconds: UInt64((HostReveal.Timeline.flashStart - HostReveal.Timeline.coalesceStart + 50) * 1_000_000))
            withAnimation(.easeInOut(duration: 0.8)) { fadedOut = true }
            try? await Task.sleep(nanoseconds: UInt64((HostReveal.Timeline.flash + 100) * 1_000_000))
            app.finishHostSetup("done")
        }
    }

    private var revealView: HostReveal.View {
        let w = Double(canvasSize.width), h = Double(canvasSize.height)
        return .init(cx: w / 2, cy: h * 0.46, radius: max(70, min(130, min(w, h) * 0.2)))
    }

    /// The card frame as last measured (kept fresh in `finalTarget` when the dots retarget).
    private var cardTargetForDrawing: CGRect? { finalTarget ?? cardTarget() }

    private func cardTarget() -> CGRect? {
        let f = app.hostCardFrame
        guard f.width > 10, f.height > 10 else { return nil }
        return f.offsetBy(dx: -origin.x, dy: -origin.y)
    }

    private func revealCanvas(start: Date) -> some View {
        let view = revealView
        let parts = particles
        let target = cardTargetForDrawing
        return TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSince(start) * 1000
                let tc = HostReveal.Timeline.coalesceStart
                let halo = HostReveal.clamp01((t - HostReveal.Timeline.gather * 0.6) / 900) * (1 - HostReveal.clamp01((t - tc) / HostReveal.Timeline.coalesce))
                if halo > 0 {
                    let c = CGPoint(x: view.cx, y: view.cy)
                    ctx.fill(Path(CGRect(origin: .zero, size: size)),
                             with: .radialGradient(Gradient(colors: [.white.opacity(0.16 * halo), .white.opacity(0)]),
                                                   center: c, startRadius: view.radius * 0.2, endRadius: view.radius * 1.9))
                }
                for p in parts {
                    let s = HostReveal.state(p, at: t, view: view)
                    if s.alpha <= 0.01 { continue }
                    ctx.fill(Path(ellipseIn: CGRect(x: s.x - s.r, y: s.y - s.r, width: s.r * 2, height: s.r * 2)),
                             with: .color(.white.opacity(s.alpha)))
                }
                // The finished card lights up: a bright bloom hugging its outline that rises fast and decays.
                let flash = HostReveal.flashLevel(t)
                if flash > 0, let card = target {
                    let path = Path(roundedRect: card, cornerRadius: 22)
                    ctx.drawLayer { layer in
                        layer.addFilter(.shadow(color: .white.opacity(0.95), radius: 40 * flash, x: 0, y: 0))
                        layer.fill(path, with: .color(.white.opacity(0.42 * flash)))
                    }
                    ctx.stroke(path, with: .color(.white.opacity(0.9 * flash)), lineWidth: 1.5)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - reveal source frames

struct RevealSourceKey: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value.append(contentsOf: nextValue()) }
}

private extension View {
    /// Reports this view's global frame so the reveal can launch dots from it.
    func revealSource(radius: CGFloat = 14) -> some View {
        background(GeometryReader { g in Color.clear.preference(key: RevealSourceKey.self, value: [g.frame(in: .global)]) })
    }
}
