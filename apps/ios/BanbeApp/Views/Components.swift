import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

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
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
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
                        tracksBottomBarScroll
                            ? AnyView(ScaffoldScrollProbe { app.noteScaffoldScroll($0) })
                            : AnyView(EmptyView())
                    )
                }
                .modifier(ScrollPositionIDModifier(id: scrollPositionID))
            } else {
                content().frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Applies `.scrollPosition(id:)` only when a binding was actually passed —
/// `ScrollView` itself has no "no-op" form of that modifier to fall back to.
private struct ScrollPositionIDModifier: ViewModifier {
    let id: Binding<String?>?
    func body(content: Content) -> some View {
        if let id {
            content.scrollPosition(id: id)
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
private struct ScaffoldScrollProbe: UIViewRepresentable {
    let onChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.onChange = onChange
    }

    final class ProbeView: UIView {
        var onChange: ((CGFloat) -> Void)?
        private weak var observedScrollView: UIScrollView?
        private var observation: NSKeyValueObservation?

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
                    return
                }
                responder = candidate.superview
            }
        }
    }
}
