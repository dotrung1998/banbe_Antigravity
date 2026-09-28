import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins
import ImageIO

/// Pulse/loading UX pass (2026-09-27) — the shared Banbe loading visual,
/// used at every spot the ticket named: a fetching Pulse tab
/// (PulseViewerView), the branded splash screen and Face ID wait screen
/// (SplashView/FaceIDLockView), the Confirmed ticket's QR-generation gap,
/// and a pending seat reservation (RootView's `loadingOverlay`). Web's
/// equivalent is `src/components/BanbeLoadingVisual.jsx`, sharing the same
/// bundled `banbe-loading.gif` (see project.yml — referenced in place from
/// `public/`, exactly like the wordmark/mark artwork, so both platforms
/// draw the literal same file, never two independently-exported copies).
///
/// SwiftUI has no native multi-frame GIF playback (`Image(uiImage:)` only
/// ever paints an animated `UIImage`'s FIRST frame) — frames are decoded
/// once via ImageIO and looped through a small `UIViewRepresentable`
/// (`UIImageView.animationImages`), the standard, documented mechanism for
/// this. Honors Reduce Motion: shows the GIF's own first frame, static,
/// instead of looping it — there's no earlier Reduce-Motion precedent on
/// this codebase to match (grepped both platforms — neither `Loading.jsx`'s
/// `gocTumble` spin nor `SplashView`'s orbit arc guards on it today), so
/// this is a new, narrowly-scoped guard rather than a wider retrofit.
struct BanbeLoadingVisual: View {
    var size: CGFloat = 72
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                if let frame = Self.firstFrame {
                    Image(uiImage: frame).resizable().scaledToFit()
                } else {
                    ProgressView()
                }
            } else if !Self.frames.isEmpty {
                AnimatedGIFView(frames: Self.frames, duration: Self.totalDuration)
            } else {
                // Decode failed — never expected (a bundled asset), but a
                // missing/corrupt file shouldn't blank whichever loading
                // moment is showing this.
                ProgressView()
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Text("Loading"))
    }

    // Decoded once, process-wide — every call site (Pulse alone creates
    // one of these per tab load) shares the same decoded frames instead of
    // re-parsing the bundled GIF from disk each time this view appears.
    private static let (frames, durations, firstFrame): ([UIImage], [Double], UIImage?) = {
        guard let url = Bundle.main.url(forResource: "banbe-loading", withExtension: "gif"),
              let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return ([], [], nil) }
        let count = CGImageSourceGetCount(source)
        var frames: [UIImage] = []
        var durations: [Double] = []
        for i in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            frames.append(UIImage(cgImage: cgImage))
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any]
            let gifProps = props?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
            let delay = (gifProps?[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double)
                ?? (gifProps?[kCGImagePropertyGIFDelayTime as String] as? Double) ?? 0.1
            durations.append(max(delay, 0.02))
        }
        return (frames, durations, frames.first)
    }()

    private static var totalDuration: Double { durations.reduce(0, +) }
}

private struct AnimatedGIFView: UIViewRepresentable {
    let frames: [UIImage]
    let duration: Double

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.animationImages = frames
        view.animationDuration = duration > 0 ? duration : 1
        view.animationRepeatCount = 0
        if !frames.isEmpty { view.startAnimating() }
        return view
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {}
}

/// A photo from the catalogue, loaded remotely from the deployed web app's
/// static assets (see PhotoCatalog / CatalogEvent.photoURL).
struct CatalogPhoto: View {
    let path: String
    var height: CGFloat?
    var width: CGFloat?
    var cornerRadius: CGFloat = 14

    @EnvironmentObject private var app: AppState

    /// Longest edge to decode at, in pixels — a 52pt avatar has no use for
    /// a 1000px decode. Falls back to a full-width card's worth when the
    /// view sizes itself from the container.
    private var maxPixel: CGFloat {
        let points = max(width ?? 0, height ?? 0)
        let longest = points > 0 ? points : 420
        return longest * UIScreen.main.scale
    }

    var body: some View {
        // The frame comes from the placeholder rectangle, and the photo is
        // drawn as an overlay on top of it: an overlay can never change its
        // parent's size, whereas an image sized directly would report its
        // full pixel width and stretch the whole scroll view sideways once
        // it finished downloading.
        Rectangle()
            .fill(app.palette.field)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .overlay { RemoteImage(path: path, maxPixel: maxPixel) }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// The banbe logo, drawn from the same PNGs the web app uses
/// (public/banbe-mark.png and the two wordmarks), so both frontends show
/// the same artwork rather than iOS approximating it with text.
///
/// Drawn as a template tinted with the current ink colour: the artwork is
/// near-black, which is right on the light paper but would be invisible on
/// the dark one. The web app renders the PNG as-is and does lose the logo
/// in its dark theme — tinting keeps the design system's "one ink" rule
/// and stays identical in light mode.
struct BanbeLogo: View {
    enum Kind: String {
        case mark = "banbe-mark"
        case wordmark = "banbe-wordmark"
        case wordmarkSmall = "banbe-wordmark-sm"
    }

    let kind: Kind
    var width: CGFloat?
    var height: CGFloat?

    @EnvironmentObject private var app: AppState

    var body: some View {
        Group {
            if let image = UIImage(named: kind.rawValue) {
                Image(uiImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            } else {
                // Never expected — but a missing asset shouldn't blank the
                // header on the one screen someone is looking at.
                Text("banbe").font(BanbeTheme.display(height ?? 24))
            }
        }
        .frame(width: width, height: height)
        .foregroundStyle(app.palette.ink)
        .accessibilityLabel("banbe")
    }
}

/// Draws a catalogue photo through PhotoLoader. Starts from the memory
/// cache synchronously, so scrolling back to an already-seen card paints
/// immediately rather than flashing its placeholder again.
struct RemoteImage: View {
    let path: String
    let maxPixel: CGFloat
    @State private var image: UIImage?

    init(path: String, maxPixel: CGFloat) {
        self.path = path
        self.maxPixel = maxPixel
        _image = State(initialValue: PhotoLoader.cached(path: path, maxPixel: maxPixel))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                Color.clear
            }
        }
        // BUG 1 (2026-09-22 eleventh follow-up) — real bug, confirmed by
        // reading: `@State private var image` is only seeded from `init`'s
        // `State(initialValue:)` the FIRST time this view is created at a
        // given position in the tree — a caller that swaps `path` while
        // this SAME `RemoteImage` instance stays mounted (e.g.
        // `CatalogPhoto` inside `StoryViewerView`'s `EventShareCard`,
        // whose view identity is preserved across a horizontal host-swipe
        // since it's the same struct at the same tree position) does NOT
        // get a fresh `init()` call, so `image` keeps holding the
        // PREVIOUS path's picture. `.task(id: path)` correctly restarts
        // when `path` changes, but its old `guard image == nil else {
        // return }` treated "already have some image" as "already have
        // THIS path's image" — so it silently skipped loading the new
        // path entirely, leaving the stale photo on screen indefinitely.
        // This is the actual root cause of "swiping to Host B's story
        // updates the host name but keeps showing Host A's cover/card" —
        // not React/SwiftUI state-identity reuse in the abstract, but this
        // ONE concrete stale-guard bug in this shared, widely-used loader.
        // Fixed: check the SYNCHRONOUS cache for the NEW path specifically
        // (paints instantly if it's already warm, e.g. from BUG 3's own
        // preloading) and otherwise clear the stale image immediately
        // (never show the wrong photo) before awaiting a fresh load.
        .task(id: path) {
            if let cached = PhotoLoader.cached(path: path, maxPixel: maxPixel) {
                image = cached
                return
            }
            image = nil
            let loaded = await PhotoLoader.load(path: path, maxPixel: maxPixel)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }
}

/// The on-photo state chip — "Saved", "Going", "Cancelled" and friends.
struct PhotoChip: View {
    let text: String
    var background: Color = BanbeTheme.Chip.saved
    var foreground: Color = .white

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.4)
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.5), lineWidth: 1)
            )
    }
}

/// The primary ink-filled action button used across the web screens.
struct InkButton: View {
    let title: String
    var enabled = true
    var cornerRadius: CGFloat = 18
    let action: () -> Void

    @EnvironmentObject private var app: AppState

    var body: some View {
        Button(action: { if enabled { action() } }) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    enabled ? app.palette.ink : app.palette.ink.opacity(0.16),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .foregroundStyle(enabled ? app.palette.paper : app.palette.ink)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// A labelled text field styled like the web app's glass fields.
struct BanbeField: View {
    let label: String?
    let placeholder: String
    @Binding var text: String
    var secure = false
    var keyboard: UIKeyboardType = .default

    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let label {
                Text(label).font(.system(size: 11.5)).foregroundStyle(app.palette.ink)
            }
            Group {
                if secure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(.system(size: 14))
            .keyboardType(keyboard)
            .autocorrectionDisabled()
            .textInputAutocapitalization(keyboard == .emailAddress ? .never : .sentences)
            .foregroundStyle(app.palette.ink)
            .padding(13)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

/// A back link ("‹ somewhere"), the web app's standard way back.
struct BackLink: View {
    let label: String
    let action: () -> Void
    @EnvironmentObject private var app: AppState

    var body: some View {
        Button(action: action) {
            Text("‹ \(label)")
                .font(.system(size: 12))
                .foregroundStyle(app.palette.ink)
        }
        .buttonStyle(.plain)
    }
}

/// A real, scannable QR of the booking id — the same value
/// check_in_guest() accepts, so the organizer's scanner reads it directly.
/// Fixed black-on-white whatever the theme: a phone camera doesn't know
/// about the app's palette.
struct QRCodeImage: View {
    let value: String
    var size: CGFloat = 76

    var body: some View {
        ZStack {
            Color.white
            if let image = Self.generate(value) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            }
        }
        .frame(width: size, height: size)
    }

    private static func generate(_ value: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        guard let output = filter.outputImage?.transformedBy(.init(scaleX: 10, y: 10)),
              let cgImage = context.createCGImage(output, from: output.extent)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

private extension CIImage {
    func transformedBy(_ transform: CGAffineTransform) -> CIImage { transformed(by: transform) }
}

/// Screen scaffold: paper background, the app's own top inset, and a
/// scrolling body — the shape nearly every web screen has.
// Matches web's PULL_TRIGGER_PX (App.jsx Shell) for the same "how far is
// a real pull" feel on both platforms. A free function, not a `static let`
// on ScreenScaffold itself — stored type properties aren't supported on a
// generic type.
let screenScaffoldPullTriggerDistance: CGFloat = 64

struct ScreenScaffold<Content: View>: View {
    @EnvironmentObject private var app: AppState
    var scroll = true
    // Deployment target is iOS 17 (apps/ios/project.yml), so the native
    // iOS 26 `.tabBarMinimizeBehavior(.onScrollDown)` isn't available —
    // this is the hand-rolled equivalent: screens that show the bottom tab
    // bar (BottomTabBar.swift) opt in here so their own ScrollView's offset
    // drives AppState.bottomBarCollapsed, mirroring src/App.jsx's Shell
    // (which reads the same signal off its own scroll listener).
    var tracksBottomBarScroll = false
    // Home task 3 (2026-09-21 follow-up) — web's App.jsx Shell has one
    // generic, per-screen scroll-position map (`scrollPositions`, keyed by
    // `state.screen`) that every screen gets for free. SwiftUI has no
    // equivalent built in, and no raw pixel-offset restore API at this
    // project's iOS 17 deployment target (`ScrollPosition`/`.scrollPosition(_:)`
    // for an arbitrary Y offset is iOS 18+) — but `.scrollPosition(id:)`
    // (iOS 17) DOES exist for a `.scrollTargetLayout()` container, and is
    // bidirectional: it both reports which id is at the top as the user
    // scrolls AND scrolls TO that id once the view (re)appears with a
    // non-nil binding already set. A caller passes a `@Published` id
    // binding from `AppState` (so it survives the view being torn down and
    // recreated on screen navigation, the same way `mapExploreState` does
    // for Map Explore) and gives each scrollable child a stable `.id(...)`
    // — see `HomeView`'s own use of this for its feed cards.
    var scrollPositionID: Binding<String?>? = nil
    // Refresh-indicator fix pass (2026-09-27, follow-up A) — replaces each
    // root screen's own plain `.refreshable { await ... }` (whose system
    // spinner can't be reskinned, see RootRefreshIndicator's own doc
    // comment). The closure is the exact same reload this screen already
    // called from `.refreshable` — nothing about WHAT gets reloaded
    // changes, only how the pull is triggered/drawn. `nil` (every other
    // screen) means this scaffold behaves exactly as before: no probe
    // wiring, no indicator overlay.
    var onRefresh: (() async -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .top) {
            app.palette.paper.ignoresSafeArea()
            if scroll {
                ScrollView {
                    // maxWidth pins the content to the viewport — without it
                    // any wide child (a photo, a long meta line) makes the
                    // whole page pan sideways.
                    Group {
                        if scrollPositionID != nil {
                            content()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .scrollTargetLayout()
                        } else {
                            content()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .background(
                        (tracksBottomBarScroll || onRefresh != nil)
                            ? AnyView(ScaffoldScrollProbe(
                                onChange: { offsetY in
                                    if tracksBottomBarScroll { app.noteScaffoldScroll(offsetY) }
                                },
                                onPullPhase: onRefresh != nil ? { phase, translationY in
                                    switch phase {
                                    case .began: app.beginRootPull()
                                    case .changed: app.updateRootPull(translationY)
                                    case .ended: app.endRootPull(trigger: onRefresh!)
                                    case .cancelled: app.cancelRootPull()
                                    }
                                } : nil
                              ))
                            : AnyView(EmptyView())
                    )
                }
                .modifier(ScrollPositionIDModifier(id: scrollPositionID))
            } else {
                content().frame(maxWidth: .infinity, alignment: .leading)
            }
            if onRefresh != nil, app.rootPullProgress > 0 || app.rootRefreshing {
                RootRefreshIndicator(screen: app.screen, progress: app.rootPullProgress, refreshing: app.rootRefreshing)
                    .padding(.top, 54)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        // Ticket's own "dismiss on ... tab switch" clause — leaving this
        // screen (a dock tap, a swipe commit, or Back) clears any pull
        // progress/refreshing state before the NEXT onRefresh-enabled
        // screen mounts, so it never inherits a stale indicator.
        .onDisappear { if onRefresh != nil { app.cancelRootPull() } }
    }
}

/// Applies `.scrollPosition(id:)` only when a binding was actually passed —
/// `ScrollView` itself has no "no-op" form of that modifier to fall back to.
private struct ScrollPositionIDModifier: ViewModifier {
    let id: Binding<String?>?
    func body(content: Content) -> some View {
        if let id {
            // TASK 3 (2026-09-22 twentieth follow-up) — the ticket's own
            // preferred fallback is the originating card centered in the
            // revealed viewport, not top-aligned (this modifier's only
            // current caller is HomeView, so this is safe to make the
            // default rather than threading a new parameter through).
            content.scrollPosition(id: id, anchor: .center)
        } else {
            content
        }
    }
}

/// BUG 2 follow-up (4d137235 real-device report): the previous mechanism
/// here — a `GeometryReader` reporting its frame through a `PreferenceKey`
/// — is a well-known SwiftUI limitation, not a wiring mistake: preference
/// values only propagate on the `.default` RunLoop mode, but a LIVE
/// touch-drag runs `UIScrollView`'s own tracking in `.tracking` mode, so
/// this style of scroll-offset tracking silently stops updating for as
/// long as a finger is actually down and only "catches up" once you lift
/// it and momentum/deceleration kicks in (back on `.default` mode) — or
/// sometimes not even then. This is exactly why the wiring (present and
/// correct end-to-end: `tracksBottomBarScroll` on Home/Inbox/Notifications/
/// Account → this probe → `AppState.noteScaffoldScroll()` →
/// `bottomBarCollapsed` → `BottomTabBar`'s `.scaleEffect`) looked completely
/// fine on inspection while still doing nothing live on a real device.
/// KVO on `UIScrollView.contentOffset` does not have this limitation — the
/// change notification fires synchronously as the property mutates,
/// independent of which RunLoop mode is currently active, which is exactly
/// why plain UIKit code has never needed this workaround.
// Refresh-indicator fix pass (2026-09-27, follow-up B) — `.began` only
// fires onward to the caller when the gesture is "qualified": the scroll
// view's own `contentOffset.y` was already at/above the top the instant
// the finger went down. That's the actual root-cause fix for "icon visible
// while idle" — the previous version drove `rootPullProgress` straight off
// raw `contentOffset` KVO, which fires for a momentum bounce past the top,
// a `.scrollPosition(id:)` restore, or the view's first layout pass, none
// of which are a real user pull.
enum ScaffoldPullPhase { case began, changed, ended, cancelled }

struct ScaffoldScrollProbe: UIViewRepresentable {
    let onChange: (CGFloat) -> Void
    var onPullPhase: ((ScaffoldPullPhase, CGFloat) -> Void)? = nil

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = onChange
        view.onPullPhase = onPullPhase
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.onChange = onChange
        uiView.onPullPhase = onPullPhase
    }

    final class ProbeView: UIView {
        var onChange: ((CGFloat) -> Void)?
        var onPullPhase: ((ScaffoldPullPhase, CGFloat) -> Void)?
        private weak var observedScrollView: UIScrollView?
        private var observation: NSKeyValueObservation?
        private weak var attachedGesture: UIPanGestureRecognizer?
        private var pullQualified = false

        override func didMoveToWindow() { super.didMoveToWindow(); attachIfNeeded() }
        override func didMoveToSuperview() { super.didMoveToSuperview(); attachIfNeeded() }

        // Walks up from this (otherwise invisible, zero-size) probe — placed
        // as the scrolled content's own `.background`, so it's always a
        // descendant of the actual `UIScrollView` SwiftUI's `ScrollView`
        // creates — to find and observe that ancestor directly.
        private func attachIfNeeded() {
            guard observedScrollView == nil else { return }
            var responder: UIView? = superview
            while let candidate = responder {
                if let scrollView = candidate as? UIScrollView {
                    observedScrollView = scrollView
                    // Negated to match the old GeometryReader convention
                    // this replaces (0 at the top, increasingly negative
                    // scrolling down) — AppState.noteScaffoldScroll() and
                    // every doc comment referencing "offsetY" assume that
                    // sign, so nothing downstream needed to change.
                    observation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] sv, _ in
                        self?.onChange?(-sv.contentOffset.y)
                    }
                    onChange?(-scrollView.contentOffset.y)
                    if onPullPhase != nil {
                        scrollView.panGestureRecognizer.addTarget(self, action: #selector(handlePanStateChange(_:)))
                        attachedGesture = scrollView.panGestureRecognizer
                    }
                    return
                }
                responder = candidate.superview
            }
        }

        @objc private func handlePanStateChange(_ gesture: UIPanGestureRecognizer) {
            guard let scrollView = observedScrollView else { return }
            switch gesture.state {
            case .began:
                // The only place eligibility is decided — a downward pull
                // that starts anywhere else in the content never qualifies,
                // matching "begins at the TOP of that tab's own scroll
                // container" exactly.
                pullQualified = scrollView.contentOffset.y <= 1
                if pullQualified { onPullPhase?(.began, 0) }
            case .changed:
                guard pullQualified else { return }
                onPullPhase?(.changed, gesture.translation(in: scrollView).y)
            case .ended, .cancelled:
                guard pullQualified else { return }
                pullQualified = false
                onPullPhase?(gesture.state == .ended ? .ended : .cancelled, gesture.translation(in: scrollView).y)
            default:
                break
            }
        }

        deinit {
            if let attachedGesture {
                attachedGesture.removeTarget(self, action: #selector(handlePanStateChange(_:)))
            }
        }
    }
}

// Pulse-teaser note (2026-09-28, same-space pass): `RingFrameProbe` used
// to live here — an invisible probe attached to Home's Pulse ring that
// KVO-observed every ancestor `UIScrollView`'s `contentOffset` and
// reported the ring's `convert(bounds, to: nil)` frame up to
// `app.pulseRingFrame` / `pulseBubbleFrameSink`, which an imperatively
// hosted bubble then turned into its own `UIView.frame`. It is deleted
// along with that whole pipeline: on a real device the bubble still sat
// fixed on screen while the ring scrolled, so the teaser bubble is no
// longer positioned from any reported frame at all — `HomeView.storyRow`
// draws it inside the story row's own scrolling coordinate space
// instead (see `PulseTeaserBubbleContent` in PulseTeaserBubbleView.swift
// and `PulseTeaserBubbleView`'s own "Same-space pass" writeup).

/// Map search-focus fix (2026-09-28 follow-up) — same invisible-probe idiom
/// as `ScaffoldScrollProbe` above: SwiftUI has no API for "this `.sheet`'s
/// own system presentation animation has actually finished," so this walks
/// the real UIKit responder chain to ask for it directly, via
/// `UIViewController.transitionCoordinator` — the same object UIKit itself
/// uses to sequence work alongside a view controller transition.
///
/// Root cause this exists to fix: a fresh (non-restored) `MapExploreView`
/// starts with its `.sheet(isPresented:)` already `true` from `init`, so the
/// sheet's system slide-up-from-bottom transition begins in the SAME commit
/// that mounts `sheetContent`. Setting `@FocusState` (and therefore
/// `becomeFirstResponder()`) from that content's own `.onAppear` fires
/// *during* that in-flight transition — before the search field's hosting
/// view controller is actually the window's frontmost/active one — and
/// UIKit silently drops a first-responder request made mid-transition
/// rather than queuing it. That is a plain iOS/UIKit behavior (not
/// SwiftUI-specific), so no amount of restructuring `.onAppear`/`.task`
/// timing inside SwiftUI alone fixes it; it needs to know the transition
/// really finished, which only UIKit's own `transitionCoordinator` can say
/// with certainty.
struct SheetPresentationSettledProbe: UIViewRepresentable {
    let onSettled: () -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onSettled = onSettled
        view.isHidden = true
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.onSettled = onSettled
    }

    final class ProbeView: UIView {
        var onSettled: (() -> Void)?
        private var fired = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, !fired else { return }
            fired = true
            // Walk the RESPONDER chain (not the view/superview hierarchy —
            // the presenting/presented `UIViewController` sits above the
            // SwiftUI-managed view tree, not as a subview ancestor of it) to
            // find the sheet's own view controller and ask its transition
            // coordinator (non-nil only while a transition is genuinely
            // still in flight) for a true completion callback.
            var responder: UIResponder? = self
            while let current = responder {
                if let vc = current as? UIViewController, let coordinator = vc.transitionCoordinator {
                    coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                        self?.onSettled?()
                    }
                    return
                }
                responder = current.next
            }
            // No in-flight coordinator found — either the presentation had
            // already finished by the time this probe's view landed in a
            // window (e.g. a detent resize re-triggering layout, not a
            // fresh presentation), or this probe is used somewhere outside
            // a `.sheet` transition entirely. Either way the field is
            // already part of the live, interactive hierarchy right now, so
            // there's nothing left to wait for.
            DispatchQueue.main.async { [weak self] in self?.onSettled?() }
        }
    }
}
