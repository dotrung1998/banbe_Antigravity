import LinkPresentation
import SwiftUI

/// Port of src/screens/sheets/PhotoViewer.jsx — a tapped gallery photo shown
/// over a fully blurred copy of itself. Deliberately not full-screen: the
/// photo sits in the middle third of the display with the same 14pt corner
/// every other photo in the app has, and the credit/tagline/actions sit
/// right against the photo's own top and bottom edges rather than the
/// screen's.
///
/// Gesture zones (14-photo-viewer.md — fixes tapping the photo instantly
/// closing the viewer, the previous behavior, on this platform too):
/// - Tap/release on the LEFT half of the PHOTO ITSELF -> previous photo.
/// - Tap/release on the RIGHT half of the PHOTO ITSELF -> next photo.
/// - A horizontal drag past `swipeThreshold` on the photo -> same
///   prev/next, unchanged from before this fix.
/// - A downward drag past `swipeThreshold` on the photo -> dismiss.
/// - A tap anywhere OUTSIDE the photo (credit line, tagline/actions row,
///   the blurred/dimmed surround) -> dismiss.
/// The photo's own gesture is `.highPriorityGesture` (the same
/// parent-vs-child gesture-precedence convention this app's swipe-back fix
/// already established, RootView.swift/note 09) so it always wins over the
/// backdrop's plain `.onTapGesture` dismiss for anything starting on the
/// photo. Dismissing (either path) shrinks the photo back to the exact
/// thumbnail rect it was opened from, rather than fading/sliding away
/// generically.
struct PhotoViewerView: View {
    @EnvironmentObject var app: AppState
    let item: PhotoViewerItem

    @State private var shared = false
    // The photo's own natural (pre-transform) on-screen frame, captured
    // continuously so the dismiss animation knows exactly what to shrink
    // from, regardless of screen size/orientation.
    @State private var photoRect: CGRect = .zero
    // Non-nil only while the shrink-back dismiss animation is playing.
    @State private var dismissTransform: (scale: CGSize, offset: CGSize)?
    // Task 2b follow-up: live 1:1 drag-follow for the dismiss gesture —
    // previously this view only evaluated `value.translation` once, in
    // `onEnded`, with no visual feedback while the finger was still down.
    // `dragTranslation` is updated on every `onChanged` callback with NO
    // `withAnimation` wrapper (unlike `dismissTransform`, which always
    // animates) so the photo tracks the finger exactly, the same
    // distinction src/screens/sheets/PhotoViewer.jsx's ref-driven (not
    // state-driven) live styles draw on web. `isDraggingDown` gates this
    // to a clearly-vertical-and-downward drag only, so a horizontal
    // swipe-browse drag is never affected.
    @State private var dragTranslation: CGSize = .zero
    @State private var isDraggingDown = false
    // The decoded foreground photo, tagged with the path it belongs to so a
    // page change never sizes/draws the new index from the previous
    // photo's pixels. Released with this view on dismiss (NSCache in
    // PhotoLoader keeps its own, evictable copy exactly as before).
    @State private var loadedPhoto: (path: String, image: UIImage)?

    // Vertical room the stage needs besides the photo itself: the credit
    // line (~13pt at 10.5pt) + 8pt gap above the photo, 8pt gap + the 34pt
    // tagline/actions row below it — rounded up — plus breathing room
    // above and below the whole column.
    private let stageChromeHeight: CGFloat = 82
    private let stageVerticalMargin: CGFloat = 24

    // How far (pt) a downward drag has to travel before the backdrop is
    // fully revealed (opacity 0) — independent of `swipeThreshold` (which
    // only decides prev/next/dismiss at release); a careful drag can
    // travel well past the threshold without releasing, and should keep
    // getting visibly closer to fully-revealed the whole way.
    private let dragRevealDistance: CGFloat = 200
    private var dragProgress: CGFloat {
        guard isDraggingDown else { return 0 }
        return min(1, max(0, dragTranslation.height / dragRevealDistance))
    }

    // Photo-interactions redesign (2026-09-26) — reads the canonical
    // engagement map (AppState+PhotoEngagement.swift), keyed by the photo's
    // real `event_photos.id`, replacing the old local-only
    // `photoLikes`/`isPhotoLiked(path:)` pair (structurally disconnected
    // from Pulse's real photo_likes/photo_shares tables).
    private var engagement: PhotoEngagement { app.photoEngagement[item.current.id] ?? PhotoEngagement(likeCount: 0, shareCount: 0, likedByMe: false) }
    private var liked: Bool { engagement.likedByMe }
    private var saved: Bool { app.isSaved(item.current.eventId) }

    /// A swipe past this many points changes the photo (or, vertically,
    /// dismisses); anything short of that (including a plain tap, which
    /// never moves at all) is a tap instead.
    private let swipeThreshold: CGFloat = 44
    private let dismissDuration: Double = 0.28

    /// Same easing this app already uses for its entrance animations.
    private var dismissAnimation: Animation {
        .timingCurve(0.22, 0.61, 0.36, 1, duration: dismissDuration)
    }

    // Task 2a (real-device follow-up): confirmed by reading this function's
    // own call sites, not assumed — the backdrop's `.onTapGesture { dismiss()
    // }` below and the swipe-past-threshold branch in the drag gesture's
    // `onEnded` already both call this SAME function, not two separate
    // "plain" vs "shrink-back" implementations. Nothing changed here.
    //
    // Task 2b: `photoRect` is the photo's LAYOUT frame (from the
    // `GeometryReader` in `.background`), which `.scaleEffect`/`.offset`
    // never change (those are post-layout render transforms, not layout
    // itself) — so unlike web's `getBoundingClientRect()`, it stays
    // constant during a live drag. `withAnimation` still makes this
    // "continue from the current dragged position" correctly: it animates
    // the `.offset()`/`.scaleEffect()` modifiers' CURRENTLY-RENDERED value
    // (`dragTranslation`, applied unanimated by onChanged below) to the
    // NEW target computed here, regardless of which state produced the
    // starting value — SwiftUI tracks the resolved value per frame, not
    // which `@State` fed it.
    private func dismiss() {
        guard dismissTransform == nil else { return }
        guard photoRect.width > 0, photoRect.height > 0 else { app.closePhoto(); return }
        let o = item.originRect
        let scale = CGSize(width: o.width / photoRect.width, height: o.height / photoRect.height)
        let offset = CGSize(width: o.midX - photoRect.midX, height: o.midY - photoRect.midY)
        withAnimation(dismissAnimation) {
            dismissTransform = (scale, offset)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + dismissDuration) {
            app.closePhoto()
        }
    }

    /// Which photo of how many: dots for a short gallery, "n / N" beyond 8.
    /// Always reserves its height so the photo never jumps on a 1-photo gallery.
    @ViewBuilder
    private var pageIndicator: some View {
        let total = item.gallery.count
        Group {
            if total > 1 && total <= 8 {
                HStack(spacing: 6) {
                    ForEach(0..<total, id: \.self) { i in
                        Circle().fill(Color.white.opacity(i == item.index ? 0.95 : 0.35))
                            .frame(width: i == item.index ? 7 : 6, height: i == item.index ? 7 : 6)
                    }
                }
            } else if total > 8 {
                Text("\(item.index + 1) / \(total)")
                    .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color.white.opacity(0.9))
            } else {
                Color.clear
            }
        }
        .frame(height: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.T("Ảnh \(item.index + 1) trên \(total)", "Photo \(item.index + 1) of \(total)"))
    }

    var body: some View {
        GeometryReader { proxy in
            // This GeometryReader ignores the safe area (see below), so its
            // proxy reports zero insets — read the window's real ones.
            let insets = windowSafeAreaInsets
            // The largest box the photo may occupy: full width minus the
            // stage's 20pt side padding (and landscape side insets), full
            // height minus the safe areas, the caption/actions chrome and
            // the breathing margin.
            let available = CGSize(
                width: max(0, proxy.size.width - 40 - insets.left - insets.right),
                height: max(0, proxy.size.height - insets.top - insets.bottom
                            - stageChromeHeight - 2 * stageVerticalMargin)
            )
            // Deliberately the SAME maxPixel the backdrop's CatalogPhoto
            // below computes for itself (`max(width ?? 0, height ?? 0) *
            // scale` with only `height` given) — same PhotoLoader cache
            // key, so foreground and backdrop share ONE decoded image
            // instead of two.
            let decodePixel = proxy.size.height * UIScreen.main.scale
            let image = currentPhoto(maxPixel: decodePixel)
            // Aspect-FIT: the whole, uncropped photo at the largest size
            // that fits `available`, never upscaled past its own pixels.
            // Until it has decoded, the tapped thumbnail's own frame stands
            // in for the aspect so the column doesn't collapse.
            let photoSize = Self.fitSize(image?.size ?? placeholderAspect, in: available, capToNative: image != nil)
            // Caption/actions column matches the photo's own width, with a
            // floor so the actions row stays usable under an extremely
            // tall/narrow photo.
            let columnWidth = max(photoSize.width, min(available.width, 200))
            ZStack {
                // The photo itself, blown up and blurred into a backdrop.
                // Pushed past the edges so the blur has no soft, transparent
                // border to show at the screen edge — via scaleEffect, which
                // is layout-neutral (the web does the same with
                // transform: scale) rather than an oversized frame, which
                // would make the ZStack size itself to that larger child and
                // shift everything off-centre (GeometryReader places its
                // content topLeading, not centred).
                CatalogPhoto(path: item.current.url, height: proxy.size.height, cornerRadius: 0)
                    .frame(width: proxy.size.width)
                    .scaleEffect(1.24)
                    // `opaque: true` — same radius as before, but edge
                    // pixels are clamped instead of fading to transparent,
                    // so the (left/right, where the 1.24 overscale only
                    // pushes ~47pt past a 390pt-wide screen) blur fringe
                    // can't let whatever is behind the viewer show through.
                    .blur(radius: 34, opaque: true)
                    .overlay(Color.black.opacity(0.38))
                    .allowsHitTesting(false)
                    // Task 2b: fades progressively as a downward dismiss
                    // drag continues, revealing Event Detail underneath —
                    // unanimated (no `.animation(value:)` targets this),
                    // same live 1:1 reasoning as the photo's own offset.
                    .opacity(1 - dragProgress)

                // The "stage": credit, photo and the tagline/actions row
                // stacked tight against one another as one column, so the
                // text sits close to the photo's own edges instead of the
                // screen's. This whole column is the "outside" tap target —
                // the photo below carves out its own gesture area and wins
                // via `.highPriorityGesture` for anything starting on it.
                VStack(alignment: .center, spacing: 8) {
                    caption(app.T("Ảnh của", "Photo by") + " \(item.organizer)")
                        .accessibilityIdentifier("photoViewer.credit")
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Aspect-FIT foreground (replaces the old fixed
                    // `height / 3` CatalogPhoto, whose RemoteImage is
                    // `.scaledToFill()` and so cropped the photo to that
                    // box). The frame already has the photo's exact aspect,
                    // so `.scaledToFit()` fills it edge to edge.
                    ZStack {
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .transition(.opacity)
                        }
                    }
                        .frame(width: photoSize.width, height: photoSize.height)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.4), radius: 22, y: 10)
                        .id(item.index)
                        .transition(.opacity)
                        .background(
                            GeometryReader { photoGeo in
                                Color.clear
                                    .onAppear { photoRect = photoGeo.frame(in: .global) }
                                    .onChange(of: photoGeo.frame(in: .global)) { _, newValue in photoRect = newValue }
                            }
                        )
                        .scaleEffect(dismissTransform?.scale ?? (isDraggingDown ? CGSize(width: 1 - dragProgress * 0.06, height: 1 - dragProgress * 0.06) : CGSize(width: 1, height: 1)))
                        .offset(dismissTransform?.offset ?? (isDraggingDown ? dragTranslation : .zero))
                        .contentShape(Rectangle())
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard dismissTransform == nil else { return }
                                    let dx = value.translation.width
                                    let dy = value.translation.height
                                    if isDraggingDown {
                                        dragTranslation = value.translation
                                    } else if dy > 6 && dy > abs(dx) {
                                        isDraggingDown = true
                                        dragTranslation = value.translation
                                    }
                                }
                                .onEnded { value in
                                    let dx = value.translation.width
                                    let dy = value.translation.height
                                    if abs(dy) > abs(dx) && dy > swipeThreshold {
                                        dismiss()
                                        return
                                    }
                                    if isDraggingDown {
                                        // Task 2b: released short of the
                                        // threshold — spring back to fully
                                        // open, same easing/duration as the
                                        // dismiss animation itself, rather
                                        // than the swipe/tap logic below.
                                        withAnimation(dismissAnimation) {
                                            isDraggingDown = false
                                            dragTranslation = .zero
                                        }
                                        return
                                    }
                                    if abs(dx) > swipeThreshold {
                                        if dx < 0 { app.showPhoto(at: item.index + 1) }
                                        else { app.showPhoto(at: item.index - 1) }
                                        return
                                    }
                                    // A plain tap: which half of the
                                    // photo's own width it landed in.
                                    if value.location.x >= photoSize.width / 2 {
                                        app.showPhoto(at: item.index + 1)
                                    } else {
                                        app.showPhoto(at: item.index - 1)
                                    }
                                }
                        )
                        .accessibilityIdentifier("photoViewer.photo")

                    pageIndicator
                        .accessibilityIdentifier("photoViewer.pageIndicator")

                    // Top-aligned, not bottom: the row is as tall as the
                    // 34pt icon buttons, and bottom-aligning the tagline
                    // inside that box pushed it well below the photo —
                    // top-aligning puts it right after the 8pt spacing,
                    // matching the credit's gap above.
                    HStack(alignment: .top) {
                        caption(shared ? app.T("Đã sao chép link", "Link copied") : "banbe ▪︎ bạn mới mỗi tuần")
                            .accessibilityIdentifier("photoViewer.tagline")
                        Spacer(minLength: 12)
                        actions
                    }
                }
                .frame(width: columnWidth)
                // Task 3 follow-up (real-device report: backdrop tap does
                // nothing): this VStack's own natural height is just its
                // content (credit + photo + tagline row), vertically
                // CENTERED by the enclosing ZStack — leaving real, empty
                // backdrop space above and below it that this modifier
                // chain's `.contentShape`/`.onTapGesture` never covered
                // (only `maxWidth: .infinity` was set, not `maxHeight`).
                // The backdrop blur layer directly behind it, meanwhile,
                // has `.allowsHitTesting(false)` (by design, so it never
                // steals a tap meant for this VStack) — so a tap landing
                // in that dead zone reached NEITHER handler and fell
                // through to whatever's behind the whole viewer. Adding
                // `maxHeight: .infinity` here (paired with `alignment:
                // .leading`, whose vertical component is `.center` —
                // `Alignment.leading == .init(horizontal: .leading,
                // vertical: .center)` — so the visible content's own
                // position is unchanged) makes this the full-bleed hit
                // target the web build's equivalent stage div already is
                // (`PhotoViewer.jsx`'s `position: 'absolute', inset: 0`
                // wrapper) — confirmed via that platform comparison that
                // web never had this gap, only iOS did.
                // (Now `.center`: the column above is sized to the fitted
                // photo's own width, so it's centred horizontally too; the
                // vertical component is `.center` either way.)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, 20)
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }
            }
            .animation(.easeOut(duration: 0.18), value: item.index)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .task(id: "\(item.current.url)@\(Int(decodePixel))") {
                let path = item.current.url
                if let cached = PhotoLoader.cached(path: path, maxPixel: decodePixel) {
                    loadedPhoto = (path, cached)
                    return
                }
                guard let loaded = await PhotoLoader.load(path: path, maxPixel: decodePixel),
                      !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.2)) { loadedPhoto = (path, loaded) }
            }
        }
        .ignoresSafeArea()
        .transition(.opacity)
        // Driven by the same `withAnimation(dismissAnimation) { ... }`
        // block that sets `dismissTransform` in `dismiss()` — no separate
        // `.animation(value:)` needed here, that transaction already
        // covers every dependent property, this one included.
        .opacity(dismissTransform == nil ? 1 : 0)
    }

    /// The current index's decoded photo, if there is one yet — from this
    /// view's own load, or straight from PhotoLoader's memory cache so an
    /// already-warm photo sizes and paints on the first frame.
    private func currentPhoto(maxPixel: CGFloat) -> UIImage? {
        if let loadedPhoto, loadedPhoto.path == item.current.url { return loadedPhoto.image }
        return PhotoLoader.cached(path: item.current.url, maxPixel: maxPixel)
    }

    /// Stand-in aspect while the photo decodes: the tapped thumbnail's own
    /// frame, else square.
    private var placeholderAspect: CGSize {
        let o = item.originRect
        return (o.width > 0 && o.height > 0) ? o.size : CGSize(width: 1, height: 1)
    }

    /// The window's safe-area insets (this view's GeometryReader ignores
    /// the safe area, so its own proxy reports zero).
    private var windowSafeAreaInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.keyWindow?.safeAreaInsets ?? .zero
    }

    /// Aspect-fit: `source` scaled uniformly to the largest size inside
    /// `bounds`. With `capToNative`, never scaled up past 1 image pixel per
    /// point (the same ceiling the web viewer's `<img>` has: 1 image pixel
    /// per CSS px) — a small photo shows smaller instead of stretched.
    private static func fitSize(_ source: CGSize, in bounds: CGSize, capToNative: Bool) -> CGSize {
        guard source.width > 0, source.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        var scale = min(bounds.width / source.width, bounds.height / source.height)
        if capToNative { scale = min(scale, 1) }
        return CGSize(width: source.width * scale, height: source.height * scale)
    }

    /// Photo-interactions redesign (2026-09-26) — same caption text style as
    /// the credit line above (`caption(_:)`), minus its own drag-fade (the
    /// enclosing `actions` HStack already applies that once, below —
    /// nesting both would compound the fade).
    private func countLabel(_ n: Int) -> some View {
        Text("\(n)")
            .font(.system(size: 10.5))
            .kerning(0.4)
            .foregroundStyle(.white.opacity(0.72))
            .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
    }

    private var actions: some View {
        HStack(spacing: 14) {
            // Like count immediately to the LEFT of the heart icon.
            HStack(spacing: 2) {
                countLabel(engagement.likeCount)
                action("heart", filled: liked, on: liked,
                       id: "photoViewer.like",
                       label: app.T("Thích ảnh này", "Like this photo")) {
                    Task { await app.togglePhotoLike(item.current.id) }
                }
            }
            action("bookmark", filled: saved, on: saved,
                   id: "photoViewer.save",
                   label: app.T("Lưu sự kiện", "Save this event")) {
                app.toggleFavorite(item.current.eventId)
            }
            // Share count immediately to the LEFT of the share icon.
            HStack(spacing: 2) {
                countLabel(engagement.shareCount)
                action("square.and.arrow.up", filled: false, on: false,
                       id: "photoViewer.share",
                       label: app.T("Chia sẻ", "Share")) {
                    share()
                }
            }
        }
        // Task 4: fades out with the same `dragProgress` driving the
        // backdrop's own fade, so the buttons don't stay opaque, floating
        // detached, once the backdrop behind them has mostly revealed
        // Event Detail. Restoring is automatic on snap-back — see
        // `caption(_:)`'s own doc comment for why no extra code is needed.
        .opacity(1 - dragProgress)
    }

    private func action(_ symbol: String, filled: Bool, on: Bool, id: String,
                        label: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: filled ? "\(symbol).fill" : symbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.white.opacity(on ? 1 : 0.72))
                .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
                // "square.and.arrow.up"'s own artwork sits a couple of
                // points lower in its em box than heart/bookmark — measured
                // on an actual screenshot (its ink extended ~3-7px lower at
                // 3x scale), not eyeballed. This nudges just that one back
                // level with the other two.
                .offset(y: symbol == "square.and.arrow.up" ? -1.5 : 0)
                // Top-aligned, not centred: centring left as much empty
                // space above the icon as below inside its 34pt box, which
                // is what made the row read as sitting further from the
                // photo than the credit text above it.
                .frame(width: 34, height: 34, alignment: .top)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    /// Faint, but never illegible: the blur underneath can land on any
    /// colour, so the white sits on the same soft shadow the on-photo chips
    /// use.
    ///
    /// Task 4: fades out progressively during a downward dismiss drag (same
    /// `dragProgress` the backdrop's own `.opacity(1 - dragProgress)`
    /// already uses), and back in on snap-back — needs no separate
    /// "restore" code: `dragProgress` is a plain computed property of
    /// `dragTranslation`/`isDraggingDown`, and the snap-back branch in the
    /// drag gesture's `onEnded` already resets both of those INSIDE
    /// `withAnimation(dismissAnimation)`, which SwiftUI applies to every
    /// dependent animatable value (this opacity included) that changed
    /// within that transaction — not just the ones the code explicitly
    /// names.
    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .kerning(0.4)
            .lineLimit(1)
            .foregroundStyle(.white.opacity(0.72))
            .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
            .allowsHitTesting(false)
            .opacity(1 - dragProgress)
    }

    /// Shares this photo. Photo-interactions redesign (2026-09-26) — the
    /// link now carries "?pid=<real event_photos.id>" (matching web's own
    /// unified `sharePhoto`), which `/api/photo-share` already resolves
    /// server-side (unchanged, no edit needed there) into this exact
    /// photo/event/organizer's Open Graph preview. Real share tracking
    /// (`log_photo_share`, migration 083) is logged ONLY once the native
    /// share sheet genuinely completes — `UIActivityViewController`'s own
    /// `completionWithItemsHandler` reporting `completed == true` — never
    /// merely from presenting it, mirroring web's `sharePhoto`'s own
    /// "only on a genuine completed share, never on cancellation" rule.
    private func share() {
        let photoId = item.current.id
        guard let url = URL(string: "https://banbe-two.vercel.app/api/photo-share?pid=\(photoId)") else { return }
        let text = app.T(
            "Xem ảnh và các buổi sắp tới của \(item.organizer) trên banbe:",
            "See \(item.organizer)'s photos and what they have coming up on banbe:"
        )
        Task {
            let image = await PhotoLoader.load(path: item.current.url, maxPixel: 1600)
            // The link goes through PhotoShareSource so the share sheet's
            // own preview shows this photo straight from the cache rather
            // than waiting to scrape the URL — what the target sends is the
            // text plus the link, which previews the same photo via the
            // tags that endpoint serves.
            let items: [Any] = [text, PhotoShareSource(image: image, title: text, url: url)]
            await MainActor.run {
                let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
                activity.completionWithItemsHandler = { _, completed, _, _ in
                    guard completed else { return }
                    Task { await app.logPhotoShare(photoId) }
                }
                UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first?.keyWindow?.rootViewController?
                    .present(activity, animated: true)
                shared = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { shared = false }
            }
        }
    }
}

/// Hands the share sheet the link, while supplying the photo as its preview
/// image so the sheet shows the picture immediately instead of the generic
/// text-document icon it picked when the items were just a string and a
/// URL. What gets sent is text + link; the link previews the same photo
/// wherever it lands, via the tags /api/photo-share serves.
private final class PhotoShareSource: NSObject, UIActivityItemSource {
    private let image: UIImage?
    private let title: String
    private let url: URL?

    init(image: UIImage?, title: String, url: URL?) {
        self.image = image
        self.title = title
        self.url = url
    }

    // A placeholder only tells the sheet what *kind* of thing is coming, so
    // an empty UIImage is right even when the photo failed to load.
    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any {
        url ?? ""
    }

    func activityViewController(_ controller: UIActivityViewController,
                                itemForActivityType type: UIActivity.ActivityType?) -> Any? {
        url
    }

    func activityViewController(_ controller: UIActivityViewController,
                                subjectForActivityType type: UIActivity.ActivityType?) -> String {
        title
    }

    func activityViewControllerLinkMetadata(_ controller: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = title
        metadata.originalURL = url
        if let image { metadata.imageProvider = NSItemProvider(object: image) }
        return metadata
    }
}
