import SwiftUI

/// Port of src/screens/sheets/PhotoViewer.jsx — a tapped gallery photo shown
/// over a fully blurred copy of itself. Deliberately not full-screen: the
/// photo sits in the middle third of the display with the same 14pt corner
/// every other photo in the app has, and the credit, tagline and actions sit
/// on the blur *outside* it, so nothing covers the picture.
struct PhotoViewerView: View {
    @EnvironmentObject var app: AppState
    let item: PhotoViewerItem

    @State private var shared = false

    private var liked: Bool { app.isPhotoLiked(item.path) }
    private var saved: Bool { app.isSaved(item.eventKey) }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // The photo itself, blown up and blurred into a backdrop.
                // Pushed past the edges so the blur has no soft, transparent
                // border to show at the screen edge — but via scaleEffect,
                // which is layout-neutral (the web does the same with
                // transform: scale). Giving it an oversized *frame* instead
                // made the ZStack size itself to that larger child, and
                // GeometryReader pins its content topLeading rather than
                // centring it, which shunted the photo and captions down and
                // right by the overflow.
                CatalogPhoto(path: item.path, height: proxy.size.height, cornerRadius: 0)
                    .frame(width: proxy.size.width)
                    .scaleEffect(1.24)
                    .blur(radius: 34)
                    .overlay(Color.black.opacity(0.38))
                    .allowsHitTesting(false)

                CatalogPhoto(path: item.path,
                             height: proxy.size.height / 3,
                             width: proxy.size.width - 40,
                             cornerRadius: 14)
                    .shadow(color: .black.opacity(0.4), radius: 22, y: 10)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("photoViewer.photo")

                VStack(alignment: .leading, spacing: 0) {
                    caption(app.T("Ảnh của", "Photo by") + " \(item.organizer)")
                        .accessibilityIdentifier("photoViewer.credit")
                    Spacer(minLength: 0)
                    HStack(alignment: .bottom) {
                        caption(shared ? app.T("Đã sao chép link", "Link copied") : "banbe ▪︎ bạn mới mỗi tuần")
                            .accessibilityIdentifier("photoViewer.tagline")
                        Spacer(minLength: 12)
                        actions
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 14)
            }
            // Pinned to the space GeometryReader actually measured, so its
            // topLeading placement has nothing left to shift.
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { app.closePhoto() }
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
                .frame(width: 34, height: 34)
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
        let url = URL(string: "https://banbe-two.vercel.app/?org=\(item.eventKey)")
        let text = app.T(
            "Xem ảnh và các buổi sắp tới của \(item.organizer) trên banbe:",
            "See \(item.organizer)'s photos and what they have coming up on banbe:"
        )
        let items: [Any] = [text, url].compactMap { $0 }
        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.keyWindow?.rootViewController?
            .present(activity, animated: true)
        shared = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { shared = false }
    }
}
