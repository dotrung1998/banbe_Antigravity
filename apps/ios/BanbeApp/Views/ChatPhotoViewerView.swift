import SwiftUI
import PhotosUI

// Task 2 (2026-09-22 real-device follow-up, 07-notifications.md /
// 14-photo-viewer.md) — a chat photo's own dedicated fullscreen viewer.
// SEPARATE view/state from PhotoViewerView.swift (event-gallery photos) —
// different action set (Post to Story/Save/Share/Forward/Copy, not
// Like/Save-event) and its own back semantics (dismissing returns to the
// exact chat, never Event Detail/Home).
//
// Revised interaction model, mirroring web's ChatPhotoViewer.jsx exactly:
// a tap on the backdrop OR the photo no longer dismisses — it toggles
// "chrome" (top bar + bottom composer) visibility. ONLY a downward drag
// past DISMISS_THRESHOLD dismisses, reusing 14-photo-viewer.md's live-
// drag-follow convention (the photo tracks the finger, chrome/backdrop
// fade with drag progress, release short of threshold springs back).
private let DISMISS_MS: Double = 0.26
private let DISMISS_THRESHOLD: CGFloat = 90
private let DRAG_REVEAL_DISTANCE: CGFloat = 220
private let QUICK_EMOJI = ["❤️", "😂", "😮", "😢", "👏", "🔥"]

struct ChatPhotoViewerView: View {
    @EnvironmentObject var app: AppState
    @State private var actionMessage: String?
    @State private var chromeHidden = false
    @State private var dragOffsetY: CGFloat = 0
    @State private var isDragging = false
    @State private var menuOpen = false
    @State private var draft = ""
    @State private var sending = false
    @State private var replyPhotoItem: PhotosPickerItem?
    @State private var replyPickerOpen = false
    @FocusState private var replyFocused: Bool

    private var item: ChatPhotoViewerItem? { app.chatPhotoViewer }
    private var dragProgress: CGFloat { min(1, max(0, dragOffsetY) / DRAG_REVEAL_DISTANCE) }
    private var eligibleThreads: [InboxThread] { app.inboxThreads.filter { $0.id != app.chatThreadID } }

    var body: some View {
        if let item {
            ZStack {
                // TASK 4 (2026-09-22 twelfth follow-up) — root-caused, real
                // bug: `stageGesture` used to sit on THIS OUTER ZStack, which
                // also contains `topBar`/`bottomComposer` as full-screen
                // overlay children. A `DragGesture(minimumDistance: 0)`
                // attached via `.gesture()` to a container competes with —
                // and, empirically on device, wins against — its own child
                // Buttons' tap recognizers for the SAME touch, since it
                // starts tracking on touch-down with zero movement required.
                // Every tap anywhere, including squarely on a toolbar
                // button, was resolving as `stageGesture`'s own "plain tap"
                // branch (toggle chrome) instead of ever reaching the
                // Button's `action`. Scoping the gesture to ONLY the
                // backdrop+photo layer below (never wrapping topBar/
                // bottomComposer/moreMenu) is the actual fix — mirrors web's
                // ChatPhotoViewer.jsx, where the stage is already a
                // dedicated sibling layer, never an ancestor of the toolbar.
                stage

                if let actionMessage {
                    Text(actionMessage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(app.palette.ink)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color.white.opacity(0.92), in: Capsule())
                        .padding(.top, 96)
                        .frame(maxHeight: .infinity, alignment: .top)
                }

                if menuOpen { moreMenu }
            }
            // BUG 2 fix (2026-09-22 thirteenth follow-up) — `topBar`/
            // `bottomComposer` used to be plain ZStack siblings of `stage`
            // with `.frame(maxWidth: .infinity, maxHeight: .infinity,
            // alignment: .top/.bottom)` applied BEFORE their own
            // `.allowsHitTesting(!chromeHidden)`. In SwiftUI,
            // `.allowsHitTesting` applied AFTER an expanding `.frame()`
            // makes the view's ENTIRE expanded frame hit-testable, not just
            // its visibly-drawn content — `bottomComposer`'s frame was
            // literally the whole screen (`maxWidth: .infinity, maxHeight:
            // .infinity`), so it silently sat ON TOP of `stage` (and
            // `topBar`, listed before it) and swallowed every touch
            // anywhere on screen: no drag-to-dismiss, no tap-to-toggle-
            // chrome, no toolbar button taps. This was invisible before
            // 82a469c because the drag gesture used to live on the ROOT
            // ZStack — an ANCESTOR of everything, which wins gesture
            // arbitration regardless of sibling hit-testing quirks below
            // it. Once the gesture moved down to `stage` (a sibling, no
            // ancestor priority), this pre-existing full-screen invisible
            // catcher became the actual regression. Fixed by using
            // `.overlay(alignment:)` for both instead of a shared ZStack +
            // an expanding `.frame()` — `.overlay` positions its content at
            // its own NATURAL size (topBar's real row height, bottomComposer's
            // real composer-bar height), never inflating either one's
            // hit-testable region beyond what's actually drawn, so every
            // touch elsewhere on screen reaches `stage` underneath exactly
            // as intended.
            .overlay(alignment: .top) { topBar }
            .overlay(alignment: .bottom) { bottomComposer }
            .sheet(isPresented: Binding(get: { item.forwardOpen }, set: { if !$0 { app.closeChatForward() } })) {
                forwardSheet
            }
            .sheet(isPresented: Binding(get: { item.postToStoryConfirm }, set: { if !$0 { app.closePostToStoryConfirm() } })) {
                postToStoryConfirmSheet
            }
            .photosPicker(isPresented: $replyPickerOpen, selection: $replyPhotoItem, matching: .images)
            .onChange(of: replyPhotoItem) { _, newItem in
                Task {
                    guard let newItem, let raw = try? await newItem.loadTransferable(type: Data.self),
                          let image = UIImage(data: raw), let jpeg = ProofImage.jpegDataUnderLimit(from: image),
                          let messageId = item.messageId else { return }
                    let dims = UIImage(data: jpeg)?.size
                    sending = true
                    _ = await app.sendChatAttachment(data: jpeg, contentType: "image/jpeg", fileExtension: "jpg", width: dims.map { Int($0.width) }, height: dims.map { Int($0.height) }, replyToMessageId: messageId)
                    sending = false
                    replyPhotoItem = nil
                }
            }
            .transition(.opacity)
            .zIndex(26)
            .onChange(of: item.messageId) { _, _ in chromeHidden = false; dragOffsetY = 0; draft = "" }
        }
    }

    // MARK: - Stage (backdrop + photo ONLY — see body's own comment on why
    // `stageGesture` must never wrap topBar/bottomComposer/moreMenu)

    private var stage: some View {
        ZStack {
            Color.black.ignoresSafeArea()
                .opacity(Double(1 - dragProgress * 0.7))

            AsyncImage(url: item?.url) { $0.resizable().scaledToFit() } placeholder: { ProgressView().tint(.white) }
                .frame(maxWidth: UIScreen.main.bounds.width * 0.92, maxHeight: UIScreen.main.bounds.height * 0.7)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .offset(y: dragOffsetY)
                .scaleEffect(1 - dragProgress * 0.08)
                .accessibilityIdentifier("chat.photoViewer.image")
        }
        .contentShape(Rectangle())
        .gesture(stageGesture)
    }

    // MARK: - Gesture (chrome toggle vs drag-to-dismiss)

    private var stageGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let dy = value.translation.height
                let dx = value.translation.width
                if !isDragging {
                    guard dy > 6, dy > abs(dx) else { return } // only a clear downward drag engages
                    isDragging = true
                }
                dragOffsetY = dy
            }
            .onEnded { value in
                defer { isDragging = false }
                let dy = value.translation.height
                let dx = value.translation.width
                guard isDragging else {
                    // A plain tap (backdrop or photo, same gesture) — toggle chrome, never dismiss.
                    if abs(dy) < 6 && abs(dx) < 6 { chromeHidden.toggle() }
                    return
                }
                if dy > DISMISS_THRESHOLD {
                    withAnimation(.easeOut(duration: DISMISS_MS)) { dragOffsetY = UIScreen.main.bounds.height }
                    DispatchQueue.main.asyncAfter(deadline: .now() + DISMISS_MS) { app.closeChatPhoto() }
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragOffsetY = 0 }
                }
            }
    }

    // TASK 4 (2026-09-22 twelfth follow-up) — every toolbar button bumped to
    // a real 44x44pt hit region via `.frame` + `.contentShape(Rectangle())`
    // (platform-standard minimum) while keeping the same small glyph, and
    // negative margins compensate so the enlarged hit area doesn't visually
    // widen the row's spacing/alignment.
    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityIdentifier("chat.photoViewer.close")
            .padding(.leading, -10)
            Spacer()
            HStack(spacing: 4) {
                if app.canHost {
                    Button { app.openPostToStoryConfirm() } label: {
                        Image(systemName: "plus.circle").font(.system(size: 18)).foregroundStyle(.white)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("chat.photoViewer.postToStory")
                }
                Button { Task { await saveTapped() } } label: {
                    Image(systemName: "arrow.down.circle").font(.system(size: 18)).foregroundStyle(.white)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityIdentifier("chat.photoViewer.save")
                Button { menuOpen.toggle() } label: {
                    Image(systemName: "ellipsis").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityIdentifier("chat.photoViewer.menu")
            }
            .padding(.trailing, -10)
        }
        .padding(.horizontal, 18).padding(.top, 56)
        .opacity(chromeHidden ? 0 : Double(1 - dragProgress))
        .allowsHitTesting(!chromeHidden)
        .animation(.easeInOut(duration: 0.2), value: chromeHidden)
    }

    private var moreMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            menuRow(app.T("Chia sẻ", "Share"), systemImage: "square.and.arrow.up") { menuOpen = false; shareTapped() }
            if !eligibleThreads.isEmpty {
                Divider().overlay(app.palette.rule)
                menuRow(app.T("Chuyển tiếp", "Forward"), systemImage: "arrowshape.turn.up.right") { menuOpen = false; app.openChatForward() }
            }
            Divider().overlay(app.palette.rule)
            menuRow(app.T("Sao chép ảnh", "Copy image"), systemImage: "doc.on.doc") { menuOpen = false; copyTapped() }
        }
        .frame(width: 220)
        .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(radius: 16)
        .padding(.top, 94).padding(.trailing, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .onTapGesture { } // swallow taps so the backdrop gesture underneath doesn't toggle chrome
    }

    private func menuRow(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage).frame(width: 18)
                Text(title).font(.system(size: 13.5))
                Spacer()
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Post to Story confirm (Task 2.3a — a real review step)

    private var postToStoryConfirmSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(app.T("Đăng ảnh này lên story?", "Post this photo to your Story?"))
                .font(.system(size: 15, weight: .semibold))
            Text(app.T("Story sẽ tự động ẩn sau 24 giờ.", "Your Story disappears automatically after 24 hours."))
                .font(.system(size: 12.5)).foregroundStyle(app.palette.ink.opacity(0.7))
            HStack(spacing: 10) {
                Button(app.T("Huỷ", "Cancel")) { app.closePostToStoryConfirm() }
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(app.palette.rule))
                Button {
                    Task {
                        let ok = await app.postChatPhotoToStory()
                        actionMessage = ok ? app.T("Đã đăng story", "Posted to Story") : app.T("Không đăng được", "Couldn't post")
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        actionMessage = nil
                    }
                } label: {
                    Text(app.storyCreateBusy ? app.T("Đang đăng…", "Posting…") : app.T("Đăng story", "Post"))
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .foregroundStyle(app.palette.paper)
                        .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(app.storyCreateBusy)
                .accessibilityIdentifier("chat.photoViewer.postToStoryConfirm")
            }
        }
        .foregroundStyle(app.palette.ink)
        .padding(20)
        .presentationDetents([.height(180)])
    }

    // MARK: - Bottom composer (Task 3 — reply/reaction)

    private var bottomComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(QUICK_EMOJI, id: \.self) { emoji in
                    Text(emoji).font(.system(size: 20))
                        .onTapGesture { Task { await quickReaction(emoji) } }
                        .accessibilityIdentifier("chat.photoViewer.quickReaction")
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle").foregroundStyle(.white)
                    .onTapGesture { replyPickerOpen = true }
                    .accessibilityIdentifier("chat.photoViewer.replyAttach")
                TextField("", text: $draft, prompt: Text(app.T("Trả lời ảnh này…", "Reply to this photo…")).foregroundStyle(.white.opacity(0.6)))
                    .focused($replyFocused)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color.white.opacity(0.16), in: Capsule())
                    .accessibilityIdentifier("chat.photoViewer.replyInput")
                Button(app.T("Gửi", "Send")) { Task { await sendReply() } }
                    .foregroundStyle(.white)
                    .font(.system(size: 13, weight: .bold))
                    .opacity(draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                    .accessibilityIdentifier("chat.photoViewer.replySend")
            }
        }
        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.75), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(edges: .bottom)
        )
        .opacity(chromeHidden ? 0 : Double(1 - dragProgress))
        .allowsHitTesting(!chromeHidden)
        .animation(.easeInOut(duration: 0.2), value: chromeHidden)
    }

    private func quickReaction(_ emoji: String) async {
        guard let messageId = item?.messageId, !sending else { return }
        sending = true
        let ok = await app.sendChatViewerReply(text: emoji, replyToMessageId: messageId, isTypedReply: false)
        sending = false
        if !ok { showSendError() }
    }
    private func sendReply() async {
        guard let messageId = item?.messageId, !sending, !draft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        sending = true
        let ok = await app.sendChatViewerReply(text: draft, replyToMessageId: messageId, isTypedReply: true)
        sending = false
        // On success the viewer is already gone (app.chatPhotoViewer set to
        // nil by sendChatViewerReply itself) — only clear `draft` here on
        // failure, where the viewer stays open and the user's typed text
        // should stay put for them to retry, not silently vanish either way.
        if ok { draft = "" } else { showSendError() }
    }
    private func showSendError() {
        actionMessage = app.T("Không gửi được", "Couldn't send")
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            actionMessage = nil
        }
    }

    // MARK: - Actions

    private func dismiss() {
        withAnimation(.easeOut(duration: DISMISS_MS)) { dragOffsetY = UIScreen.main.bounds.height }
        DispatchQueue.main.asyncAfter(deadline: .now() + DISMISS_MS) { app.closeChatPhoto() }
    }

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

    // Copy — a real, working action on iOS (UIPasteboard.image genuinely
    // works app-wide, unlike a "Copy" that would need a fallback or
    // conditional hiding the way web's Clipboard API does).
    private func copyTapped() {
        guard let item else { return }
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: item.url), let image = UIImage(data: data) else { return }
            await MainActor.run {
                UIPasteboard.general.image = image
                actionMessage = app.T("Đã sao chép ảnh", "Image copied")
            }
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            await MainActor.run { actionMessage = nil }
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
