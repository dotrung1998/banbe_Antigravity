import LinkPresentation
import SwiftUI

/// Port of src/screens/sheets/PhotoViewer.jsx — a tapped gallery photo shown
/// over a fully blurred copy of itself. Deliberately not full-screen: the
/// photo sits in the middle third of the display with the same 14pt corner
/// every other photo in the app has, and the credit/tagline/actions sit
/// right against the photo's own top and bottom edges rather than the
/// screen's. A left/right swipe moves through the rest of the gallery it
/// was opened from without closing the viewer; a plain tap (no movement)
/// closes it.
struct PhotoViewerView: View {
    @EnvironmentObject var app: AppState
    let item: PhotoViewerItem

    @State private var shared = false
    @State private var dragTranslation: CGFloat = 0

    private var liked: Bool { app.isPhotoLiked(item.path) }
    private var saved: Bool { app.isSaved(item.eventKey) }

    /// A swipe past this many points changes the photo; anything short of
    /// that (including a plain tap, which never moves at all) closes the
    /// viewer instead.
    private let swipeThreshold: CGFloat = 44

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // The photo itself, blown up and blurred into a backdrop.
                // Pushed past the edges so the blur has no soft, transparent
                // border to show at the screen edge — via scaleEffect, which
                // is layout-neutral (the web does the same with
                // transform: scale) rather than an oversized frame, which
                // would make the ZStack size itself to that larger child and
                // shift everything off-centre (GeometryReader places its
                // content topLeading, not centred).
                CatalogPhoto(path: item.path, height: proxy.size.height, cornerRadius: 0)
                    .frame(width: proxy.size.width)
                    .scaleEffect(1.24)
                    .blur(radius: 34)
                    .overlay(Color.black.opacity(0.38))
                    .allowsHitTesting(false)

                // The "stage": credit, photo and the tagline/actions row
                // stacked tight against one another as one column, so the
                // text sits close to the photo's own edges instead of the
                // screen's.
                VStack(alignment: .leading, spacing: 8) {
                    caption(app.T("Ảnh của", "Photo by") + " \(item.organizer)")
                        .accessibilityIdentifier("photoViewer.credit")

                    CatalogPhoto(path: item.path,
                                 height: proxy.size.height / 3,
                                 width: proxy.size.width - 40,
                                 cornerRadius: 14)
                        .shadow(color: .black.opacity(0.4), radius: 22, y: 10)
                        .id(item.index)
                        .transition(.opacity)
                        .accessibilityIdentifier("photoViewer.photo")

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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
            }
            .animation(.easeOut(duration: 0.18), value: item.index)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in dragTranslation = value.translation.width }
                    .onEnded { value in
                        let dx = value.translation.width
                        dragTranslation = 0
                        if abs(dx) > swipeThreshold {
                            if dx < 0 { app.showPhoto(at: item.index + 1) }
                            else { app.showPhoto(at: item.index - 1) }
                        } else {
                            app.closePhoto()
                        }
                    }
            )
        }
        .ignoresSafeArea()
        .transition(.opacity)
    }

    private var actions: some View {
        HStack(spacing: 2) {
            action("heart", filled: liked, on: liked,
                   id: "photoViewer.like",
                   label: app.T("Thích ảnh này", "Like this photo")) {
                app.togglePhotoLike(item.path)
            }
            action("bookmark", filled: saved, on: saved,
                   id: "photoViewer.save",
                   label: app.T("Lưu sự kiện", "Save this event")) {
                app.toggleFavorite(item.eventKey)
            }
            action("square.and.arrow.up", filled: false, on: false,
                   id: "photoViewer.share",
                   label: app.T("Chia sẻ", "Share")) {
                share()
            }
        }
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
    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .kerning(0.4)
            .lineLimit(1)
            .foregroundStyle(.white.opacity(0.72))
            .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
            .allowsHitTesting(false)
    }

    /// Shares the photo's organizer, not the photo file itself — a bare
    /// image URL says nothing about who took it or where to find more. The
    /// link carries "?org=<eventKey>", which lands on that organizer's page
    /// on the web and offers to reopen it here via banbe://.
    private func share() {
        // /api/photo-share carries Open Graph tags naming this photo as the
        // preview image and then forwards into the app, so the picture
        // survives as the link's own preview. Sharing the photo as a file
        // attachment instead put the picture in the message but cost the
        // caption — share targets take the attachment and drop the text.
        let photoFile = (item.path as NSString).lastPathComponent
        var components = URLComponents(string: "https://banbe-two.vercel.app/api/photo-share")
        components?.queryItems = [
            URLQueryItem(name: "org", value: item.eventKey),
            URLQueryItem(name: "photo", value: photoFile),
            URLQueryItem(name: "by", value: item.organizer),
        ]
        let url = components?.url
        let text = app.T(
            "Xem ảnh và các buổi sắp tới của \(item.organizer) trên banbe:",
            "See \(item.organizer)'s photos and what they have coming up on banbe:"
        )
        Task {
            let image = await PhotoLoader.load(path: item.path, maxPixel: 1600)
            // The link goes through PhotoShareSource so the share sheet's
            // own preview shows this photo straight from the cache rather
            // than waiting to scrape the URL — what the target sends is the
            // text plus the link, which previews the same photo via the
            // tags that endpoint serves.
            let items: [Any] = [text, PhotoShareSource(image: image, title: text, url: url)]
            await MainActor.run {
                let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
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
