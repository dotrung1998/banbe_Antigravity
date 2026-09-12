import SwiftUI

/// Port of src/screens/sheets/PhotoViewer.jsx — a tapped gallery photo shown
/// larger over a dimmed backdrop. Deliberately not full-screen: it sits in
/// the middle third of the display, keeping the same 14pt corner the photos
/// everywhere else in the app have. Tapping anywhere closes it.
struct PhotoViewerView: View {
    @EnvironmentObject var app: AppState
    let item: PhotoViewerItem

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.72)
                    .ignoresSafeArea()

                CatalogPhoto(path: item.path,
                             height: proxy.size.height / 3,
                             width: proxy.size.width - 40,
                             cornerRadius: 14)
                    .overlay(alignment: .topLeading) { caption(app.T("Ảnh của", "Photo by") + " \(item.organizer)") }
                    .overlay(alignment: .bottomLeading) { caption("banbe ▪︎ bạn mới mỗi tuần") }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .contentShape(Rectangle())
            .onTapGesture { app.closePhoto() }
        }
        .transition(.opacity)
        .accessibilityIdentifier("photoViewer")
    }

    /// Faint, but never illegible: a photo can be any colour underneath, so
    /// the white sits on the same soft shadow the on-photo chips use.
    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .kerning(0.4)
            .foregroundStyle(.white.opacity(0.72))
            .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
            .padding(14)
            .allowsHitTesting(false)
    }
}
