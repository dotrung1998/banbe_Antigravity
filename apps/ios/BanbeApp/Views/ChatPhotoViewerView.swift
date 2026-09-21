import SwiftUI

// Task 2 (07-notifications.md / 14-photo-viewer.md follow-up) — a chat
// photo's own dedicated fullscreen viewer. A SEPARATE view/state from
// PhotoViewerView.swift (event-gallery photos) — different action set
// (Save/Share/Forward, not Like/Save-event) and its own back semantics
// (dismissing returns to the exact chat, never Event Detail/Home).
struct ChatPhotoViewerView: View {
    @EnvironmentObject var app: AppState
    @State private var actionMessage: String?

    private var item: ChatPhotoViewerItem? { app.chatPhotoViewer }

    var body: some View {
        if let item {
            ZStack {
                Color.black.opacity(0.92).ignoresSafeArea()
                    .onTapGesture { app.closeChatPhoto() }

                AsyncImage(url: item.url) { $0.resizable().scaledToFit() } placeholder: { ProgressView().tint(.white) }
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.92, maxHeight: UIScreen.main.bounds.height * 0.7)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityIdentifier("chat.photoViewer.image")

                VStack {
                    HStack {
                        Button { app.closeChatPhoto() } label: {
                            Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                        }
                        .accessibilityIdentifier("chat.photoViewer.close")
                        Spacer()
                        Menu {
                            Button(app.T("Lưu ảnh", "Save photo")) { Task { await saveTapped() } }
                            Button(app.T("Chia sẻ", "Share")) { shareTapped() }
                            if !eligibleThreads.isEmpty {
                                Button(app.T("Chuyển tiếp", "Forward")) { app.openChatForward() }
                            }
                        } label: {
                            Image(systemName: "ellipsis").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                        }
                        .accessibilityIdentifier("chat.photoViewer.menu")
                    }
                    .padding(.horizontal, 18).padding(.top, 56)
                    Spacer()
                }

                if let actionMessage {
                    Text(actionMessage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(app.palette.ink)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color.white.opacity(0.92), in: Capsule())
                        .padding(.top, 96)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .sheet(isPresented: Binding(get: { item.forwardOpen }, set: { if !$0 { app.closeChatForward() } })) {
                forwardSheet
            }
            .transition(.opacity)
            .zIndex(26)
        }
    }

    private var eligibleThreads: [InboxThread] { app.inboxThreads.filter { $0.id != app.chatThreadID } }

    private func saveTapped() async {
        let ok = await app.downloadChatPhoto()
        actionMessage = ok ? app.T("Đã lưu ảnh", "Photo saved") : app.T("Không lưu được ảnh", "Couldn't save photo")
        try? await Task.sleep(nanoseconds: 1_800_000_000)
        actionMessage = nil
    }

    private func shareTapped() {
        guard let item else { return }
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: item.url), let image = UIImage(data: data) else { return }
            await MainActor.run {
                let activity = UIActivityViewController(activityItems: [image], applicationActivities: nil)
                UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first?.keyWindow?.rootViewController?
                    .present(activity, animated: true)
            }
        }
    }

    private var forwardSheet: some View {
        NavigationStack {
            List(eligibleThreads) { t in
                Button(t.name) { Task { _ = await app.forwardChatPhoto(to: t.id) } }
                    .accessibilityIdentifier("chat.photoViewer.forwardTarget")
            }
            .navigationTitle(app.T("Chuyển tiếp đến", "Forward to"))
        }
    }
}
