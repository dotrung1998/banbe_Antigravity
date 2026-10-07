import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// Profile keychain UI (note 35). Layout decisions:
// - Anchors are PHYSICAL corners (top_left stays on the left in RTL too).
// - The charm hangs from a FIXED attachment point at its card corner; top
//   anchors hang down from the top edge, bottom anchors sit in the bottom
//   corner (never outside the card), always capped to the card so they cannot
//   cover the name/QR/buttons: `.leading` layouts reserve a side gutter,
//   `.centered` layouts cap the width / reserve bottom padding.
// - Hit-testing is limited to the charm frame; the charm frame is also
//   published as a root-gesture exclusion zone so a drag on it never turns
//   into a tab swipe.

// MARK: - Display link driver + motion model

private final class KeychainDisplayLinkProxy: NSObject {
    var tick: ((CFTimeInterval) -> Void)?
    @objc func fire(_ link: CADisplayLink) { tick?(link.timestamp) }
}

@MainActor
final class KeychainCharmModel: ObservableObject {
    @Published private(set) var angle = 0.0
    @Published private(set) var stretch = 0.0
    @Published private(set) var highlight = false
    /// Motion is allowed (setting on, Reduce Motion off). Static charm otherwise.
    @Published private(set) var animates = false

    private var physics = KeychainPhysics()
    private var link: CADisplayLink?
    private let proxy = KeychainDisplayLinkProxy()
    private var lastTimestamp: CFTimeInterval = 0
    private var visible = false
    private var foreground = true
    private var motionEnabled = true
    private var grabbed = false
    private var swingDirection = 1.0
    private var motion: KeychainMotionController!

    init(source: KeychainMotionSource = CoreKeychainMotionSource()) {
        motion = KeychainMotionController(source: source) { [weak self] i in self?.sensorImpulse(i) }
        proxy.tick = { [weak self] ts in MainActor.assumeIsolated { self?.tick(ts) } }
    }

    func configure(visible: Bool? = nil, foreground: Bool? = nil, motionEnabled: Bool? = nil) {
        if let visible { self.visible = visible }
        if let foreground { self.foreground = foreground }
        if let motionEnabled { self.motionEnabled = motionEnabled }
        refresh()
    }

    func refresh() {
        animates = motionEnabled && !UIAccessibility.isReduceMotionEnabled
        motion.update(.init(visible: visible, foreground: foreground, motionEnabled: motionEnabled,
                            reduceMotion: UIAccessibility.isReduceMotionEnabled))
        if !animates || !visible { physics.reset(); grabbed = false; publish() }
        updateLoop()
    }

    private func publish() { angle = physics.angle; stretch = physics.stretch }

    private func updateLoop() {
        let should = animates && visible && foreground && !physics.isSettled && !physics.isDragging
        if should, link == nil {
            let l = CADisplayLink(target: proxy, selector: #selector(KeychainDisplayLinkProxy.fire(_:)))
            l.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            lastTimestamp = 0
            l.add(to: .main, forMode: .common)
            link = l
        } else if !should, let l = link {
            l.invalidate(); link = nil
        }
    }

    private func tick(_ ts: CFTimeInterval) {
        let dt = lastTimestamp == 0 ? 1.0 / 60.0 : ts - lastTimestamp
        lastTimestamp = ts
        physics.step(dt)
        publish()
        if physics.isSettled { updateLoop() }
    }

    private func sensorImpulse(_ i: Double) {
        guard animates, visible, !physics.isDragging else { return }
        physics.applyImpulse(i)
        updateLoop()
    }

    /// The visible, non-drag "Swing" control / accessibility action.
    func swing() {
        if animates {
            Haptics.light()
            motion.noteActivity()
            physics.swing(direction: swingDirection)
            swingDirection = -swingDirection
            updateLoop()
        } else {
            flash()
        }
    }

    private func flash() {
        highlight = true
        Task { try? await Task.sleep(nanoseconds: 700_000_000); highlight = false }
    }

    func dragChanged(_ t: CGSize, height: CGFloat) {
        guard animates, height > 0 else { return }
        if !grabbed { grabbed = true; Haptics.light(); motion.noteActivity() }
        let stretch = Double(t.height / height) * 0.8
        let angle = -atan2(Double(t.width), Double(height) * 0.9)
        physics.drag(stretch: stretch, angle: angle)
        publish()
        updateLoop()
    }

    func dragEnded(velocityX: CGFloat, height: CGFloat) {
        guard grabbed else { return }
        grabbed = false
        Haptics.light()
        let w = -Double(velocityX) / max(Double(height), 1) * 0.9
        physics.release(angularVelocity: w)
        updateLoop()
    }

    func stopAll() { configure(visible: false) }
}

// MARK: - Artwork

private struct KeychainArtImage: View {
    let config: KeychainConfig
    let manifest: KeychainManifest
    let previewImage: UIImage?
    @ObservedObject private var store = KeychainStore.shared

    var body: some View {
        if config.designId == KeychainConfig.customDesignID {
            custom
        } else if let d = manifest.design(config.designId), let ui = KeychainArtwork.bundledImage(d) {
            Image(uiImage: ui).resizable().scaledToFit()
        } else {
            Color.clear
        }
    }

    private var customUIImage: UIImage? {
        previewImage ?? config.customAsset.flatMap { store.customImages[$0.path] }
    }

    private var custom: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack(alignment: .top) {
                if let ui = customUIImage {
                    Image(uiImage: ui).resizable().scaledToFit()
                        .frame(width: w, height: h * 0.88)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                Circle().stroke(Color(white: 0.55), lineWidth: max(1.5, w * 0.035))
                    .frame(width: w * 0.16, height: w * 0.16)
                    .position(x: w / 2, y: h * CGFloat(manifest.pivot.y) + w * 0.08)
            }
        }
    }
}

// MARK: - The charm

struct KeychainCharmView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.scenePhase) private var scenePhase
    let config: KeychainConfig
    let manifest: KeychainManifest
    let width: CGFloat
    var previewImage: UIImage? = nil
    /// Increment to trigger one swing (the visible Swing button in the preview).
    var swingTick = 0
    @StateObject private var model = KeychainCharmModel()

    private var height: CGFloat { width * CGFloat(manifest.imageSize.height / max(manifest.imageSize.width, 1)) }
    private var pivot: UnitPoint { UnitPoint(x: manifest.pivot.x, y: manifest.pivot.y) }

    private var designName: String {
        if config.designId == KeychainConfig.customDesignID { return app.T("ảnh tuỳ chỉnh", "custom art") }
        guard let d = manifest.design(config.designId) else { return "" }
        return app.isEN ? d.en : d.vi
    }

    var body: some View {
        KeychainArtImage(config: config, manifest: manifest, previewImage: previewImage)
            .frame(width: width, height: height)
            .scaleEffect(x: 1, y: 1 + model.stretch, anchor: pivot)
            .rotationEffect(.radians(model.angle), anchor: pivot)
            .frame(width: width, height: height, alignment: .top)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(app.palette.ink.opacity(0.55), lineWidth: 2)
                    .opacity(model.highlight ? 1 : 0)
                    .animation(.easeInOut(duration: 0.25), value: model.highlight)
            )
            .contentShape(Rectangle())
            .highPriorityGesture(drag, including: model.animates ? .all : .none)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(app.T("Móc khoá trang trí: \(designName)", "Decorative keychain: \(designName)"))
            .accessibilityHint(app.T("Chạm đúp để lắc", "Double tap to swing"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: Text(app.T("Lắc", "Swing"))) { model.swing() }
            .accessibilityAdjustableAction { _ in model.swing() }
            .accessibilityAction { model.swing() }
            .accessibilityIdentifier("keychain.charm")
            .onAppear {
                model.configure(visible: true, foreground: scenePhase == .active, motionEnabled: config.motionEnabled)
            }
            .onDisappear { model.stopAll() }
            .onChange(of: scenePhase) { _, p in model.configure(foreground: p == .active) }
            .onChange(of: config.motionEnabled) { _, v in model.configure(motionEnabled: v) }
            .onChange(of: swingTick) { _, _ in model.swing() }
            .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.reduceMotionStatusDidChangeNotification)) { _ in model.refresh() }
            .task(id: config.customAsset?.path) {
                if let p = config.customAsset?.path, previewImage == nil { await KeychainStore.shared.loadCustomImage(path: p) }
            }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { model.dragChanged($0.translation, height: height) }
            .onEnded { model.dragEnded(velocityX: $0.velocity.width, height: height) }
    }
}

// MARK: - Card host modifier

enum KeychainCardLayout { case leading, centered }

private struct KeychainCharmHost: ViewModifier {
    @EnvironmentObject private var app: AppState
    @Environment(\.layoutDirection) private var layoutDirection
    let config: KeychainConfig?
    let layout: KeychainCardLayout
    /// Distance from this view's edge to the visible card edge (padding applied AFTER this modifier).
    let outset: CGFloat
    var previewImage: UIImage? = nil
    var swingTick = 0
    @State private var size: CGSize = .zero

    private static let inset: CGFloat = 8

    func body(content: Content) -> some View {
        if let cfg = config, cfg.enabled, let m = KeychainManifest.bundled {
            content
                .padding(gutterEdge(cfg), gutter(cfg, m))
                .padding(.bottom, bottomReserve(cfg, m))
                .background(GeometryReader { g in
                    Color.clear
                        .onAppear { size = g.size }
                        .onChange(of: g.size) { _, s in size = s }
                })
                .overlay(alignment: alignment(cfg)) {
                    let w = effectiveWidth(cfg, m)
                    let h = w * CGFloat(m.imageSize.height / max(m.imageSize.width, 1))
                    KeychainCharmView(config: cfg, manifest: m, width: w, previewImage: previewImage, swingTick: swingTick)
                        .frame(width: w, height: h)
                        .background(GeometryReader { g in
                            Color.clear.preference(key: RootGestureExclusionZonePreferenceKey.self,
                                                   value: ["keychainCharm": g.frame(in: .named("rootGesture"))])
                        })
                        .offset(x: cfg.anchor.isLeft ? -(outset - Self.inset) : (outset - Self.inset),
                                y: cfg.anchor.isTop ? -(outset - Self.inset) : (outset - Self.inset))
                }
                .onPreferenceChange(RootGestureExclusionZonePreferenceKey.self) { zones in
                    // Merge only our own key — never clobber another screen's zones.
                    if zones["keychainCharm"] != nil || app.rootGestureExclusionZones["keychainCharm"] != nil {
                        var z = app.rootGestureExclusionZones
                        z["keychainCharm"] = zones["keychainCharm"]
                        app.rootGestureExclusionZones = z
                    }
                }
        } else {
            content
        }
    }

    private func physicalEdge(_ cfg: KeychainConfig) -> Edge.Set {
        let leftIsLeading = layoutDirection == .leftToRight
        return cfg.anchor.isLeft == leftIsLeading ? .leading : .trailing
    }
    private func gutterEdge(_ cfg: KeychainConfig) -> Edge.Set { layout == .leading ? physicalEdge(cfg) : [] }
    private func gutter(_ cfg: KeychainConfig, _ m: KeychainManifest) -> CGFloat {
        guard layout == .leading else { return 0 }
        return max(0, min(CGFloat(m.width(cfg.size)), 56) + Self.inset + 6 - outset)
    }
    private func bottomReserve(_ cfg: KeychainConfig, _ m: KeychainManifest) -> CGFloat {
        guard layout == .centered, !cfg.anchor.isTop else { return 0 }
        return max(0, CGFloat(m.height(cfg.size)) + Self.inset - outset + 4)
    }
    private func alignment(_ cfg: KeychainConfig) -> Alignment {
        let h: HorizontalAlignment = physicalEdge(cfg) == .leading ? .leading : .trailing
        return Alignment(horizontal: h, vertical: cfg.anchor.isTop ? .top : .bottom)
    }
    private func effectiveWidth(_ cfg: KeychainConfig, _ m: KeychainManifest) -> CGFloat {
        let w0 = CGFloat(m.width(cfg.size))
        let aspect = CGFloat(m.imageSize.height / max(m.imageSize.width, 1))
        guard size.width > 0, size.height > 0 else { return w0 }
        switch layout {
        case .leading:
            let hMax = size.height + 2 * outset - 2 * Self.inset
            return max(28, min(w0, hMax / aspect, size.width * 0.28))
        case .centered:
            if cfg.anchor.isTop {
                let side = (size.width + 2 * outset - 230) / 2 - Self.inset
                return max(40, min(w0, side))
            }
            return w0
        }
    }
}

extension View {
    /// Charm on a card for an already-resolved config (settings preview).
    func keychainCharm(config: KeychainConfig?, layout: KeychainCardLayout = .leading, outset: CGFloat = 0,
                       previewImage: UIImage? = nil, swingTick: Int = 0) -> some View {
        modifier(KeychainCharmHost(config: config, layout: layout, outset: outset, previewImage: previewImage, swingTick: swingTick))
    }

    /// Charm on a profile card: resolves the owner's own config live, or a visitor's via the cached RPC.
    func keychainProfileCharm(handle: String?, layout: KeychainCardLayout = .leading, outset: CGFloat = 0) -> some View {
        modifier(KeychainProfileResolver(handle: handle, layout: layout, outset: outset))
    }
}

private struct KeychainProfileResolver: ViewModifier {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var store = KeychainStore.shared
    let handle: String?
    let layout: KeychainCardLayout
    let outset: CGFloat

    private var isMine: Bool {
        guard let h = handle, let mine = app.user?.handle else { return false }
        return h.lowercased() == mine.lowercased()
    }
    private var config: KeychainConfig? {
        guard store.featureAvailable, let h = handle, !h.isEmpty else { return nil }
        let c: KeychainConfig? = isMine ? store.mine : (store.cached(h) ?? nil)
        return (c?.enabled == true) ? c : nil
    }

    func body(content: Content) -> some View {
        content
            .keychainCharm(config: config, layout: layout, outset: outset)
            .task(id: handle) {
                guard let h = handle, !h.isEmpty, app.isSignedIn else { return }
                if isMine { if !store.mineLoaded { await app.loadMyKeychain() } }
                else { _ = await app.loadProfileKeychain(handle: h) }
            }
    }
}

// MARK: - Settings (Edit profile > appearance)

struct KeychainSettingsSection: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var store = KeychainStore.shared
    @State private var draft = KeychainConfig.default
    @State private var pendingArt: KeychainPreparedArt?
    @State private var pendingImage: UIImage?
    @State private var removeArt = false
    @State private var busy = false
    @State private var error = ""
    @State private var importing = false
    @State private var photoItem: PhotosPickerItem?
    @State private var swingTick = 0
    @State private var loadedOnce = false

    private var manifest: KeychainManifest? { KeychainManifest.bundled }
    private var base: KeychainConfig { store.mine ?? .default }
    private var hasServerArt: Bool { base.customAsset != nil }
    private var dirty: Bool { draft != base || pendingArt != nil || removeArt }

    var body: some View {
        Group {
            if store.featureAvailable, let m = manifest {
                content(m)
            }
        }
        .task {
            if !store.mineLoaded { await app.loadMyKeychain() }
            if !loadedOnce { draft = base; loadedOnce = true }
        }
        .onChange(of: store.mineLoaded) { _, _ in if !dirty { draft = base } }
    }

    private func content(_ m: KeychainManifest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(app.T("Móc khoá hồ sơ", "Profile keychain")).font(.system(size: 11.5)).foregroundStyle(app.palette.ink)
            Toggle(app.T("Hiện móc khoá trên hồ sơ", "Show a keychain on my profile"), isOn: $draft.enabled)
                .font(.system(size: 13)).accessibilityIdentifier("keychain.enabled")

            if draft.enabled {
                preview(m)
                picker(m)
                anchorPicker
                Picker(app.T("Kích cỡ", "Size"), selection: $draft.size) {
                    ForEach(KeychainSize.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).accessibilityIdentifier("keychain.size")
                Toggle(app.T("Cho phép chuyển động", "Allow motion"), isOn: $draft.motionEnabled)
                    .font(.system(size: 13)).accessibilityIdentifier("keychain.motion")
                artControls(m)
            }

            if !error.isEmpty { Text(error).font(.system(size: 12)).foregroundStyle(BanbeTheme.alert) }

            if dirty {
                HStack(spacing: 10) {
                    Button(app.T("Huỷ", "Cancel")) { cancel() }
                        .font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(app.palette.rule))
                        .disabled(busy).accessibilityIdentifier("keychain.cancel")
                    InkButton(title: busy ? app.T("Đang lưu…", "Saving…") : app.T("Lưu móc khoá", "Save keychain"), enabled: !busy) { save() }
                        .accessibilityIdentifier("keychain.save")
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: KeychainArtValidator.allowedTypes) { result in
            if case .success(let url) = result { loadArt { try KeychainArtValidator.prepare(fileURL: url) } }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                photoItem = nil
                guard let data else { error = KeychainArtError.decodeFailed.message(app.T); return }
                loadArt { try KeychainArtValidator.prepare(data) }
            }
        }
    }

    // preview + non-drag Swing control
    private func preview(_ m: KeychainManifest) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Circle().fill(app.palette.ink.opacity(0.85)).frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 6) {
                    Capsule().fill(app.palette.ink.opacity(0.7)).frame(width: 110, height: 10)
                    Capsule().fill(app.palette.ink.opacity(0.3)).frame(width: 70, height: 8)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 64)
            .keychainCharm(config: draft, layout: .leading, outset: 16, previewImage: pendingImage, swingTick: swingTick)
            .padding(16)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(app.palette.rule))
            .accessibilityIdentifier("keychain.preview")
            Button { swingTick += 1 } label: {
                Label(app.T("Lắc thử", "Swing"), systemImage: "waveform.path")
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .buttonStyle(.bordered).tint(app.palette.ink)
            .accessibilityIdentifier("keychain.swing")
        }
    }

    private func picker(_ m: KeychainManifest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(m.groups) { g in
                Text(app.isEN ? g.en : g.vi).font(.system(size: 11, weight: .semibold)).opacity(0.7)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(m.designs(in: g.id)) { d in tile(d) }
                }
            }
            if pendingImage != nil || (hasServerArt && !removeArt) {
                Text(app.T("Ảnh của tôi", "My art")).font(.system(size: 11, weight: .semibold)).opacity(0.7)
                let selected = draft.designId == KeychainConfig.customDesignID
                Button { draft.designId = KeychainConfig.customDesignID } label: {
                    Group {
                        if let ui = pendingImage ?? base.customAsset.flatMap({ store.customImages[$0.path] }) {
                            Image(uiImage: ui).resizable().scaledToFit()
                        } else { Color.clear }
                    }
                    .frame(width: 44, height: 62).padding(4)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(app.palette.ink, lineWidth: selected ? 2 : 0))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(app.T("Ảnh của tôi", "My art"))
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("keychain.design.custom")
                .task(id: base.customAsset?.path) {
                    if let p = base.customAsset?.path { await store.loadCustomImage(path: p) }
                }
            }
        }
    }

    private func tile(_ d: KeychainManifest.Design) -> some View {
        let selected = draft.designId == d.id
        return Button { draft.designId = d.id } label: {
            Group {
                if let ui = KeychainArtwork.bundledImage(d) { Image(uiImage: ui).resizable().scaledToFit() } else { Color.clear }
            }
            .frame(width: 44, height: 62).padding(4)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(app.palette.ink, lineWidth: selected ? 2 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(app.isEN ? d.en : d.vi)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("keychain.design.\(d.id)")
    }

    private var anchorPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(app.T("Vị trí", "Position")).font(.system(size: 11, weight: .semibold)).opacity(0.7)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(KeychainAnchor.allCases) { a in
                    Button { draft.anchor = a } label: {
                        Text(a.label(app.T)).font(.system(size: 12.5)).frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(app.palette.ink, lineWidth: draft.anchor == a ? 2 : 0))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(draft.anchor == a ? .isSelected : [])
                    .accessibilityIdentifier("keychain.anchor.\(a.rawValue)")
                }
            }
        }
    }

    @ViewBuilder
    private func artControls(_ m: KeychainManifest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(app.T("Dùng ảnh của riêng bạn", "Use my own art")).font(.system(size: 11, weight: .semibold)).opacity(0.7)
            Text(app.T("PNG hoặc WebP, nền trong suốt, tối đa 512 px và 256 KB. Ảnh được thu nhỏ trên máy và xoá siêu dữ liệu trước khi tải lên.",
                       "PNG or WebP with transparency, up to 512 px and 256 KB. Resized on device with metadata removed before upload."))
                .font(.system(size: 11)).opacity(0.6)
            HStack(spacing: 10) {
                Button(app.T("Chọn tệp", "Choose file")) { importing = true }
                    .accessibilityIdentifier("keychain.art.file")
                PhotosPicker(app.T("Thư viện ảnh", "Photo library"), selection: $photoItem, matching: .images)
                    .accessibilityIdentifier("keychain.art.photos")
                if pendingArt != nil || (hasServerArt && !removeArt) {
                    Button(app.T("Xoá ảnh của tôi", "Remove my art")) { removeCustom() }
                        .foregroundStyle(BanbeTheme.alert).accessibilityIdentifier("keychain.art.remove")
                }
            }
            .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(app.palette.ink)

            if let d = m.design(draft.designId), let url = KeychainArtwork.bundledURL(for: d), let ui = KeychainArtwork.bundledImage(d) {
                ShareLink(item: url, preview: SharePreview(app.isEN ? d.en : d.vi, image: Image(uiImage: ui))) {
                    Label(app.T("Xuất ảnh mẫu (PNG)", "Export this artwork (PNG)"), systemImage: "square.and.arrow.up")
                        .font(.system(size: 12.5))
                }
                .foregroundStyle(app.palette.ink).accessibilityIdentifier("keychain.export")
            }
        }
    }

    // MARK: actions

    private func loadArt(_ work: @escaping @Sendable () throws -> KeychainPreparedArt) {
        error = ""
        Task {
            do {
                let art = try await Task.detached(priority: .userInitiated) { try work() }.value
                pendingArt = art
                pendingImage = UIImage(data: art.data)
                removeArt = false
                draft.designId = KeychainConfig.customDesignID
                draft.enabled = true
            } catch let e as KeychainArtError {
                error = e.message(app.T)
            } catch {
                self.error = KeychainArtError.decodeFailed.message(app.T)
            }
        }
    }

    private func removeCustom() {
        pendingArt = nil; pendingImage = nil
        removeArt = hasServerArt
        if draft.designId == KeychainConfig.customDesignID { draft.designId = KeychainConfig.defaultDesignID }
        draft.customAsset = nil
    }

    private func cancel() {
        draft = base; pendingArt = nil; pendingImage = nil; removeArt = false; error = ""
    }

    private func save() {
        busy = true; error = ""
        Task {
            let msg = await app.saveMyKeychain(draft, pendingArt: pendingArt, removeCustomArt: removeArt)
            busy = false
            if let msg { error = msg; return }
            Haptics.success()
            pendingArt = nil; pendingImage = nil; removeArt = false
            draft = store.mine ?? draft
        }
    }
}
