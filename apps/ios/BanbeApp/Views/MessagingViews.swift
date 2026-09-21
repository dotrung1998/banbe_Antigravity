import SwiftUI
import UIKit

/// Port of src/screens/Inbox.jsx — every conversation this account is in,
/// on either side (as guest, and as organizer of their own events).
///
/// 2026-09-21 follow-up: switched from a plain ScrollView/VStack to a
/// `List` so Task 2's swipe-left Star/Archive can use SwiftUI's native
/// `.swipeActions` instead of a hand-rolled drag gesture — the idiomatic,
/// lower-risk choice here (this app's ScreenScaffold's own scroll-collapse
/// probe, used elsewhere for the bottom-bar shrink effect, doesn't apply
/// inside a List the same way; Inbox loses that one shrink-on-scroll nicety,
/// accepted as a small, deliberate trade-off for a correct native swipe
/// gesture rather than reimplementing one by hand).
struct InboxView: View {
    @EnvironmentObject var app: AppState
    @State private var searchOpen = false
    @State private var query = ""
    @State private var settingsOpen = false
    @State private var feedbackOpen = false

    private var visibleThreads: [InboxThread] {
        let byView = app.inboxThreads.filter { t in
            let archived = app.inboxThreadPrefs[t.id]?.archived ?? false
            return app.inboxView == .archived ? archived : !archived
        }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return byView }
        return byView.filter { $0.name.lowercased().contains(q) || $0.snippet.lowercased().contains(q) }
    }

    var body: some View {
        ZStack {
            app.palette.paper.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                header
                if app.inboxView == .archived {
                    Button("‹ " + app.T("Quay lại Tin nhắn", "Back to Messages")) { app.inboxView = .active }
                        .font(.system(size: 12.5)).buttonStyle(.plain)
                        .foregroundStyle(app.palette.ink.opacity(0.7))
                        .padding(.horizontal, 24).padding(.bottom, 6)
                }
                if visibleThreads.isEmpty {
                    Text(app.inboxView == .archived
                         ? app.T("Chưa có cuộc trò chuyện nào được lưu trữ.", "No archived conversations yet.")
                         : app.T("Chưa có cuộc trò chuyện nào. Nhắn cho người tổ chức từ trang sự kiện.", "No conversations yet. Message an organizer from an event page."))
                        .font(.system(size: 14))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 80)
                        .foregroundStyle(app.palette.ink)
                    Spacer()
                } else {
                    List {
                        ForEach(visibleThreads) { thread in
                            InboxRow(thread: thread)
                                .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
                                .listRowSeparatorTint(app.palette.rule)
                                .listRowBackground(app.palette.paper)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    let archived = app.inboxThreadPrefs[thread.id]?.archived ?? false
                                    Button {
                                        Task { archived ? await app.unarchiveThread(thread.id) : await app.archiveThread(thread.id) }
                                    } label: {
                                        Label(archived ? app.T("Bỏ lưu trữ", "Unarchive") : app.T("Lưu trữ", "Archive"), systemImage: archived ? "tray.and.arrow.up" : "archivebox")
                                    }
                                    .tint(app.palette.ink)
                                    Button {
                                        Task { await app.toggleThreadStar(thread.id) }
                                    } label: {
                                        let starred = app.inboxThreadPrefs[thread.id]?.starred ?? false
                                        Label(app.T("Gắn sao", "Star"), systemImage: starred ? "star.fill" : "star")
                                    }
                                    .tint(BanbeTheme.alert)
                                }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(app.palette.paper)
                }
            }
        }
        .task { await app.loadInboxThreads() }
        .overlay {
            if settingsOpen { settingsSheet }
        }
        .fullScreenCover(isPresented: $feedbackOpen) { FeedbackFlowView() }
        // Bug 2a (2026-09-21 follow-up) — the settings sheet and the
        // feedback flow are both hand-rolled/`.fullScreenCover` content
        // INSIDE the main window, but BottomTabBarOverlay is a genuinely
        // separate, always-on-top `UIWindow` (see that file's own doc
        // comment) that `.inbox` staying in `visibleScreens` never hides on
        // its own for a same-screen presentation. Reuses the exact
        // `isHidden`-sync mechanism 4d549f9 already established for
        // Event Detail (`updateVisibility(for:)`), via the new
        // `setForcedHidden(_:)` this pass adds right alongside it.
        .onChange(of: settingsOpen) { _, open in BottomTabBarOverlay.shared.setForcedHidden(open || feedbackOpen) }
        .onChange(of: feedbackOpen) { _, open in BottomTabBarOverlay.shared.setForcedHidden(open || settingsOpen) }
        .onDisappear { BottomTabBarOverlay.shared.setForcedHidden(false) }
    }

    // Bug 2b — a proper spring (not an un-animated snap), the SAME
    // response/dampingFraction the tab bar's own scroll-collapse animation
    // already uses (AppState.noteScaffoldScroll), for consistency with the
    // app's other smooth transitions.
    private func openSettings() { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { settingsOpen = true } }
    private func closeSettings() { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { settingsOpen = false } }

    // Task 1 — "Done" replaced with search + settings icons. Task 5 — each
    // icon-only control gets a small label underneath.
    private var header: some View {
        HStack(alignment: .center) {
            if searchOpen {
                TextField(app.T("Tìm cuộc trò chuyện…", "Search conversations…"), text: $query)
                    .font(.system(size: 13.5))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(app.palette.field, in: Capsule())
                    .foregroundStyle(app.palette.ink)
            } else {
                Text(app.inboxView == .archived ? app.T("Đã lưu trữ", "Archived") : app.T("Tin nhắn", "Messages"))
                    .font(BanbeTheme.display(27))
            }
            Spacer()
            HStack(spacing: 14) {
                iconButton(searchOpen ? "xmark" : "magnifyingglass", label: searchOpen ? app.T("Đóng", "Close") : app.T("Tìm", "Search")) {
                    if searchOpen { query = "" }
                    searchOpen.toggle()
                }
                if app.inboxView == .active {
                    iconButton("gearshape", label: app.T("Cài đặt", "Settings")) { openSettings() }
                }
            }
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private func iconButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 14))
                    .frame(width: 34, height: 34)
                    .background(app.palette.field, in: Circle())
                Text(label).font(.system(size: 9.5)).opacity(0.7)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(app.palette.ink)
    }

    // Bug 2c — a true full-height bottom sheet: the PAPER BACKGROUND
    // extends through the bottom safe area (home indicator strip) via
    // `.ignoresSafeArea` scoped to just that background layer, so there's
    // no exposed corner/gap below the sheet's rounded top corners, while
    // the row CONTENT itself stays padded comfortably above the home
    // indicator through ordinary (non-ignoring) layout.
    private var settingsSheet: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { closeSettings() }
                .transition(.opacity)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(app.T("Cài đặt tin nhắn", "Messaging settings")).font(BanbeTheme.display(18))
                    Spacer()
                    Button { closeSettings() } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                }
                .padding(.bottom, 12)
                Button {
                    closeSettings()
                    app.inboxView = .archived
                } label: {
                    Text(app.T("Đã lưu trữ", "Archived")).font(.system(size: 14.5)).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 13)
                .overlay(Rectangle().fill(app.palette.rule).frame(height: 1), alignment: .top)
                Button {
                    closeSettings()
                    feedbackOpen = true
                } label: {
                    Text(app.T("Gửi phản hồi", "Give feedback")).font(.system(size: 14.5)).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 13)
                .overlay(Rectangle().fill(app.palette.rule).frame(height: 1), alignment: .top)
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                app.palette.paper
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18, style: .continuous))
                    .ignoresSafeArea(edges: .bottom)
            )
            .transition(.move(edge: .bottom))
        }
    }
}

private struct InboxRow: View {
    @EnvironmentObject var app: AppState
    let thread: InboxThread

    // Task 3 (2026-09-21 follow-up) — bolds unread rows using the SAME
    // `thread.unread` signal loadInboxThreads() computes for the dock
    // badge, not a second computation.
    private var unread: Bool { thread.unread }
    private var starred: Bool { app.inboxThreadPrefs[thread.id]?.starred ?? false }

    var body: some View {
        Button { app.openThread(id: thread.id, eventKey: thread.eventKey, back: .inbox, otherName: thread.name) } label: {
            HStack(spacing: 16) {
                // Task 3a — merged avatar: a small badge circle for the
                // OTHER participant's own photo, overlapping the event
                // photo's corner — mirrors src/screens/Inbox.jsx.
                ZStack(alignment: .bottomTrailing) {
                    CatalogPhoto(path: thread.img, height: 56, width: 56, cornerRadius: 28)
                    Group {
                        if let url = thread.otherAvatarURL, let imageURL = URL(string: url) {
                            AsyncImage(url: imageURL) { $0.resizable().scaledToFill() } placeholder: { app.palette.field }
                                .frame(width: 24, height: 24)
                                .clipShape(Circle())
                        } else {
                            Circle().fill(app.palette.ink)
                                .overlay(
                                    Text(String(thread.name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(app.palette.paper)
                                )
                                .frame(width: 24, height: 24)
                        }
                    }
                    .overlay(Circle().stroke(app.palette.paper, lineWidth: 2))
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if unread { Circle().fill(BanbeTheme.alert).frame(width: 7, height: 7) }
                        // Bug 3 (2026-09-21 follow-up) — a fully-read row's
                        // name stays bold (still reads as the row's title)
                        // but lighter-contrast than an unread row's, via
                        // opacity rather than dropping below the preview
                        // line's own weight underneath it.
                        Text(thread.name)
                            .font(BanbeTheme.display(18))
                            .fontWeight(.semibold)
                            .foregroundStyle(app.palette.ink.opacity(unread ? 1 : 0.6))
                    }
                    Text(thread.snippet)
                        .font(.system(size: 13, weight: unread ? .semibold : .regular))
                        .foregroundStyle(app.palette.ink.opacity(unread ? 1 : 0.72))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                // Bug 1 (2026-09-21 follow-up) — moved off the avatar
                // (where it collided with the merged-avatar badge) to the
                // row's own far trailing edge instead.
                if starred {
                    Image(systemName: "star.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(BanbeTheme.alert)
                }
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(app.palette.ink)
    }
}

/// Task 1b — "Give feedback": single-choice screen -> text+bug-toggle
/// screen, matching the attached reference screenshots.
private struct FeedbackFlowView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0 // 0 = choice, 1 = detail
    @State private var text = ""
    @State private var isBug = false
    @State private var sending = false

    var body: some View {
        ZStack {
            app.palette.paper.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    if step == 1 { step = 0 } else { dismiss() }
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .foregroundStyle(app.palette.ink)

                if step == 0 {
                    Text(app.T("Gửi phản hồi", "Give feedback")).font(BanbeTheme.display(24)).padding(.top, 16)
                    Text(app.T(
                        "Hãy cho chúng tôi biết phản hồi của bạn là về điều gì. Chúng tôi đọc mọi phản hồi nhưng không thể trả lời từng người.",
                        "Please let us know what your feedback is about. We review all feedback but are unable to respond individually."
                    ))
                    .font(.system(size: 13)).foregroundStyle(app.palette.ink.opacity(0.75)).padding(.top, 10)

                    HStack {
                        Text(app.T("Phản hồi chung về hộp thư", "General feedback about the inbox")).font(.system(size: 14))
                        Spacer()
                        ZStack {
                            Circle().stroke(app.palette.ink, lineWidth: 2).frame(width: 20, height: 20)
                            Circle().fill(app.palette.ink).frame(width: 10, height: 10)
                        }
                    }
                    .padding(.vertical, 14)
                    .overlay(Rectangle().fill(app.palette.rule).frame(height: 1), alignment: .top)
                    .overlay(Rectangle().fill(app.palette.rule).frame(height: 1), alignment: .bottom)
                    .padding(.top, 16)

                    Spacer()
                    Button(app.T("Tiếp", "Next")) { step = 1 }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(app.palette.paper)
                        .padding(.horizontal, 26).padding(.vertical, 13)
                        .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    Text(app.T("Kể cho chúng tôi nghe", "Tell us about it")).font(BanbeTheme.display(24)).padding(.top, 16)
                    Text(app.T("Chia sẻ trải nghiệm của bạn. Điều gì tốt? Điều gì có thể tốt hơn?", "Share your experience with us. What went well? What could have gone better?"))
                        .font(.system(size: 13)).foregroundStyle(app.palette.ink.opacity(0.75)).padding(.top, 10)

                    TextEditor(text: $text)
                        .font(.system(size: 13.5))
                        .frame(minHeight: 160)
                        .padding(8)
                        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(app.palette.rule, lineWidth: 1))
                        .padding(.top, 14)

                    HStack {
                        Text(app.T("Tôi đang báo lỗi", "I'm reporting a bug")).font(.system(size: 14))
                        Spacer()
                        Toggle("", isOn: $isBug).labelsHidden().tint(app.palette.ink)
                    }
                    .padding(.top, 16)

                    Spacer()
                    HStack {
                        Button(app.T("Quay lại", "Back")) { step = 0 }
                            .font(.system(size: 13.5)).buttonStyle(.plain)
                        Spacer()
                        Button {
                            Task {
                                sending = true
                                _ = await app.submitFeedback(text, isBugReport: isBug)
                                sending = false
                                dismiss()
                            }
                        } label: {
                            Text(sending ? app.T("Đang gửi…", "Sending…") : app.T("Gửi", "Send"))
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(app.palette.paper)
                        .padding(.horizontal, 26).padding(.vertical, 13)
                        .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .buttonStyle(.plain)
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || sending)
                        .opacity(text.trimmingCharacters(in: .whitespaces).isEmpty || sending ? 0.5 : 1)
                    }
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }
}

/// Port of src/screens/Chat.jsx — the real threads/messages conversation,
/// polled every few seconds while open (there's no realtime subscription on
/// the web side either).
struct ChatView: View {
    @EnvironmentObject var app: AppState
    @State private var pollTask: Task<Void, Never>?
    // Task 4 (2026-09-21 follow-up) — the composer's "+" attach flow.
    @State private var fileImporterOpen = false
    @State private var cameraOpen = false
    @State private var sendingAttachment = false

    private var event: CatalogEvent { app.currentEvent }

    var body: some View {
        ZStack {
            app.palette.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Divider().overlay(app.palette.rule)
                messages
                composer
            }
        }
        .onAppear {
            pollTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    if let id = app.chatThreadID { await app.loadChatMessages(id) }
                }
            }
        }
        .onDisappear { pollTask?.cancel() }
        .fileImporter(isPresented: $fileImporterOpen, allowedContentTypes: [.image, .pdf]) { result in
            guard case let .success(url) = result else { return }
            Task { await sendPickedFile(url) }
        }
        // Task 4 — Camera's native "Retake"/"Use Photo" review step comes
        // from UIImagePickerController itself (CameraPicker.swift) — no
        // custom preview UI needed to satisfy that requirement.
        .fullScreenCover(isPresented: $cameraOpen) {
            CameraPicker { image in
                cameraOpen = false
                guard let data = ProofImage.jpegDataUnderLimit(from: image) else { return }
                Task {
                    sendingAttachment = true
                    _ = await app.sendChatAttachment(data: data, contentType: "image/jpeg", fileExtension: "jpg")
                    sendingAttachment = false
                }
            }
            .ignoresSafeArea()
        }
    }

    private func sendPickedFile(_ url: URL) async {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else { return }
        let isPDF = url.pathExtension.lowercased() == "pdf"
        sendingAttachment = true
        if isPDF {
            _ = await app.sendChatAttachment(data: data, contentType: "application/pdf", fileExtension: "pdf")
        } else if let image = UIImage(data: data), let jpeg = ProofImage.jpegDataUnderLimit(from: image) {
            _ = await app.sendChatAttachment(data: jpeg, contentType: "image/jpeg", fileExtension: "jpg")
        }
        sendingAttachment = false
    }

    // Task 3b — the OTHER participant's own name (host name for a guest,
    // guest name for an organizer), set once at openThread()/openChat(for:)
    // time since it depends on which side of the thread I'm on, not just
    // the event. Falls back to event.hostShort for the one caller that
    // doesn't know it yet (a 'new_message' notification tap).
    private var headerTitle: String { app.chatOtherName.isEmpty ? event.hostShort : app.chatOtherName }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                Button("‹ " + (app.chatBack == .inbox ? app.T("Tin nhắn", "Messages") : app.chatBack == .notifications ? app.T("Thông báo", "Notifications") : event.orgName)) {
                    app.chatBackAction()
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .accessibilityIdentifier("chat.back")
                Text(headerTitle).font(BanbeTheme.display(18))
                // Task 3b — event date + name subtitle directly under the title.
                Text("\(event.when) · \(event.name)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(app.palette.ink.opacity(0.65))
            }
            Spacer()
            Button(app.T("Chi tiết", "Details")) { app.goEvent(event.key) }
                .font(.system(size: 11.5, weight: .semibold))
                .buttonStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(app.palette.field, in: Capsule())
                .accessibilityIdentifier("chat.details")
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if app.chatMessages.isEmpty {
                        bubble(text: event.greeting, mine: false, messageID: nil, senderLabel: headerTitle, createdAt: nil, attachmentPath: nil, attachmentType: nil)
                    }
                    ForEach(app.chatMessages) { message in
                        // Task 2 — unread divider: rendered once, right
                        // above the first message that was unread at the
                        // moment this thread was opened
                        // (app.chatUnreadDividerID, captured once by
                        // loadChatMessages(_:computeDivider:)). Naturally
                        // disappears on the next open since those rows are
                        // marked read immediately.
                        if message.id == app.chatUnreadDividerID {
                            unreadDivider
                        }
                        if message.kind == "system", let card = classifySystemMessage(message.body) {
                            systemCard(card, messageID: message.id)
                        } else {
                            bubble(
                                text: message.body, mine: message.senderId == app.userID,
                                messageID: message.id,
                                senderLabel: message.senderId == app.userID ? app.T("Bạn", "You") : headerTitle,
                                createdAt: message.createdAt,
                                attachmentPath: message.attachmentPath, attachmentType: message.attachmentType
                            )
                            .id(message.id)
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }
            .onChange(of: app.chatMessages.count) {
                if let last = app.chatMessages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var unreadDivider: some View {
        HStack(spacing: 10) {
            Rectangle().fill(app.palette.rule).frame(height: 1)
            Text("— \(app.T("Chưa đọc", "Unread")) —")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(BanbeTheme.alert)
            Rectangle().fill(app.palette.rule).frame(height: 1)
        }
        .opacity(0.55)
        .padding(.vertical, 4)
        .accessibilityIdentifier("chat.unreadDivider")
    }

    // Task 3d — payment-status system messages as a distinct inline card
    // (reference: "Confirmed ... Show details"), not a plain text bubble.
    // messages.kind only has 'text'/'system' (schema-confirmed) — no
    // dedicated kind per lifecycle event — so this classifies by the exact
    // body prefix each RPC already writes today: confirm_payment()
    // (060:83), reject_pending_guest() (059:151), cancel_booking()
    // (022:167). Content-based, in the UI layer only, mirrors
    // src/screens/Chat.jsx's classifySystemMessage() exactly.
    private func classifySystemMessage(_ body: String) -> (status: String, label: String)? {
        if body.hasPrefix("Host marked payment received via") {
            return ("confirmed", app.T("Đã xác nhận thanh toán", "Payment confirmed"))
        }
        if body.hasPrefix("Người tổ chức không nhận yêu cầu đặt chỗ này") || body.hasPrefix("Booking cancelled.") {
            return ("declined", app.T("Đặt chỗ đã bị huỷ", "Booking cancelled"))
        }
        return nil
    }

    private func systemCard(_ card: (status: String, label: String), messageID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(card.status == "confirmed" ? app.palette.ink : BanbeTheme.alert)
            if let message = app.chatMessages.first(where: { $0.id == messageID }) {
                Text(message.body)
                    .font(.system(size: 12.5))
                    .foregroundStyle(app.palette.ink.opacity(0.75))
            }
            Button(app.T("Xem chi tiết", "Show details")) { app.goEvent(event.key) }
                .font(.system(size: 11.5, weight: .semibold))
                .underline()
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(app.palette.rule, lineWidth: 1))
        .foregroundStyle(app.palette.ink)
        .accessibilityIdentifier("chat.systemCard")
    }

    private func formattedTime(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    // Task 3c — each bubble shows its own sender + timestamp, not just a
    // bare bubble. `createdAt` is nil only for the static greeting
    // placeholder (no real row to time-stamp).
    private func bubble(text: String, mine: Bool, messageID: UUID?, senderLabel: String, createdAt: Date?, attachmentPath: String?, attachmentType: String?) -> some View {
        VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
            if let createdAt {
                Text("\(senderLabel) · \(formattedTime(createdAt))")
                    .font(.system(size: 10))
                    .foregroundStyle(app.palette.ink.opacity(0.5))
                    .padding(.horizontal, 4)
            }
            HStack {
                if mine { Spacer(minLength: 40) }
                // Own messages only — messageID is nil for the static greeting
                // placeholder, and a system note is never `mine` (senderId nil
                // can't equal app.userID), so neither ever gets this.
                if mine, let messageID {
                    Button {
                        Task { await app.deleteMessage(messageID) }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(app.palette.ink.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("chat.message.delete")
                }
                // Task 4 — attachment rendering: an inline image for an
                // image/* attachment, a small document chip otherwise.
                // The signed URL comes from app.chatAttachmentUrls, the
                // same batched-signed-URL pattern `proofUrls` already uses
                // for the private payment-proof bucket.
                if let attachmentPath {
                    let url = app.chatAttachmentUrls[attachmentPath]
                    if attachmentType?.hasPrefix("image/") == true, let url {
                        AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { app.palette.field }
                            .frame(maxWidth: 220, maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(app.palette.rule, lineWidth: 1))
                            .accessibilityIdentifier("chat.attachment")
                    } else {
                        Link(destination: url ?? URL(string: "about:blank")!) {
                            HStack(spacing: 8) {
                                Image(systemName: "paperclip")
                                Text(text)
                            }
                            .font(.system(size: 12.5))
                            .foregroundStyle(app.palette.ink)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .accessibilityIdentifier("chat.attachment")
                    }
                } else {
                    Text(text)
                        .font(.system(size: 13.5))
                        .lineSpacing(3)
                        .foregroundStyle(mine ? app.palette.paper : app.palette.ink)
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .background(
                            mine ? app.palette.ink : app.palette.paper,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(mine ? .clear : app.palette.rule, lineWidth: 1)
                        )
                }
                if !mine { Spacer(minLength: 40) }
            }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Divider().overlay(app.palette.rule)
            HStack(spacing: 8) {
                // Task 4 — "+" attach button + its two-option menu.
                Menu {
                    Button {
                        fileImporterOpen = true
                    } label: {
                        Label(app.T("Thêm ảnh hoặc tài liệu", "Add photo or document"), systemImage: "photo.on.rectangle")
                    }
                    Button {
                        cameraOpen = true
                    } label: {
                        Label(app.T("Máy ảnh", "Camera"), systemImage: "camera")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 40, height: 40)
                        .background(app.palette.field, in: Circle())
                        .foregroundStyle(app.palette.ink)
                }
                .disabled(app.chatThreadID == nil || sendingAttachment)
                .opacity(app.chatThreadID == nil ? 0.5 : 1)
                .accessibilityIdentifier("chat.attach")

                TextField(
                    app.chatThreadID != nil
                        ? app.T("Viết cho \(event.hostShort)…", "Message \(event.hostShort)…")
                        : app.T("Đang mở cuộc trò chuyện…", "Opening conversation…"),
                    text: $app.chatDraft
                )
                .font(.system(size: 13.5))
                .foregroundStyle(app.palette.ink)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(app.palette.field, in: Capsule())
                .disabled(app.chatThreadID == nil)
                .onSubmit { Task { await app.chatSend() } }

                Button(app.T("Gửi", "Send")) { Task { await app.chatSend() } }
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(app.palette.paper)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(app.palette.ink, in: Capsule())
                    .buttonStyle(.plain)
                    .disabled(app.chatThreadID == nil)
                    .opacity(app.chatThreadID == nil ? 0.5 : 1)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
    }
}

/// Redesigned to read like Instagram/Facebook's own notification list
/// (07-notifications.md's 2026-09-18 follow-up): a left avatar per row
/// (derived per-kind — see avatarSource(for:maps:accountType:)), a bold
/// title + single-line truncated preview, and time-based sections with
/// unread always pinned to the top regardless of age. Same fonts/colors as
/// everywhere else in the app (BanbeTheme/app.palette) — no new design system.
private let notificationCollapseAt = 20

struct NotificationsView: View {
    @EnvironmentObject var app: AppState
    // Which sections have had their "Xem thêm" tapped — purely a
    // render-time slice of already-loaded data (loadNotifications() fetches
    // up to 50 at once), so a plain local Set is enough; nothing here needs
    // a new query.
    @State private var expandedSections: Set<String> = []
    // BUG 4: the "•••" action menu, open for at most one row's
    // notification at a time.
    @State private var menuFor: AppNotification?
    // 2026-09-18 follow-up (BUG 3): a notification's SECTION is decided
    // once — the first time this screen sees it — and frozen from then on,
    // keyed by id. Reading it only flips its own readAt (handled live in
    // row(_:), for the bold/dim weight), it never moves the row to a
    // different section. Without this, section membership was recomputed
    // from live readAt on every body re-render — app.notifications is also
    // overwritten wholesale every 5s by the app-wide toast poll
    // (startNotificationPolling(), AppState+Data.swift), so a plain
    // computed property re-shuffled a notification the instant either
    // markNotificationRead() OR that unrelated poll tick re-rendered this
    // screen — which is what "reading moves it" actually was.
    @State private var sectionMembership: [UUID: String] = [:]

    private struct NotificationSection: Identifiable {
        let id: String
        let title: String
        let items: [AppNotification]
        // 2026-09-19 follow-up: "week"/"older" get a finer per-calendar-day
        // header underneath this section's own title; "new"/"today" stay
        // flat exactly as before, per this ticket's own ask.
        var dayGrouped: Bool = false
    }

    private func classifyAtLoad(_ n: AppNotification, now: Date) -> String {
        guard n.readAt == nil else {
            switch notificationAgeBucket(n.createdAt, now: now) {
            case .today: return "today"
            case .week: return "week"
            case .older: return "older"
            }
        }
        return "new"
    }

    /// Assigns a section to any notification not already in
    /// `sectionMembership` — called on load and whenever `app.notifications`
    /// changes, but never touches an id that's already been assigned.
    private func syncSectionMembership() {
        let now = Date()
        for n in app.notifications where sectionMembership[n.id] == nil {
            sectionMembership[n.id] = classifyAtLoad(n, now: now)
        }
    }

    // Exactly one bucket per key, regardless of how many unread items are
    // interleaved with read ones in app.notifications — grouping by a
    // frozen, pre-computed membership id can never split "Mới" into two
    // blocks the way a live re-scan keyed on readAt (recomputed mid-list)
    // could.
    private var sections: [NotificationSection] {
        var grouped: [String: [AppNotification]] = ["new": [], "today": [], "week": [], "older": []]
        let now = Date()
        for n in app.notifications {
            let key = sectionMembership[n.id] ?? classifyAtLoad(n, now: now)
            grouped[key, default: []].append(n)
        }
        return [
            NotificationSection(id: "new", title: app.T("Mới", "New"), items: grouped["new"] ?? []),
            NotificationSection(id: "today", title: app.T("Hôm nay", "Today"), items: grouped["today"] ?? []),
            NotificationSection(id: "week", title: app.T("7 ngày qua", "Last 7 days"), items: grouped["week"] ?? [], dayGrouped: true),
            NotificationSection(id: "older", title: app.T("Cũ hơn", "Older"), items: grouped["older"] ?? [], dayGrouped: true),
        ].filter { !$0.items.isEmpty }
    }

    var body: some View {
        ZStack {
            ScreenScaffold(tracksBottomBarScroll: true) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(app.T("Thông báo", "Notifications")).font(BanbeTheme.display(27))
                        Spacer()
                        Button(app.T("Xong", "Done")) { app.goHome() }
                            .font(.system(size: 12)).buttonStyle(.plain)
                    }
                    .padding(.bottom, 14)

                    let allSections = sections
                    if allSections.isEmpty {
                        Text(app.T("Chưa có thông báo nào.", "No notifications yet."))
                            .font(.system(size: 14))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 80)
                    } else {
                        ForEach(allSections) { sec in
                            section(sec)
                        }
                    }
                }
                .foregroundStyle(app.palette.ink)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 100)
            }
            .task {
                await app.loadNotifications()
                syncSectionMembership()
            }
            .onChange(of: app.notifications) { _, _ in syncSectionMembership() }

            // BUG 4: replaces the old per-row "×" delete with a "•••" menu,
            // modeled on Facebook's own notification action sheet — but
            // only the actions this app can actually back for real (no
            // "Show more"/"Show less": nothing ranks or personalizes this
            // list; no "Report issue": no generic issue-report mechanism
            // exists anywhere else in the app to call into — see
            // 07-notifications.md). Reuses BottomSheet, the same
            // dim-overlay + sliding-panel component ReasonSheetView already
            // uses, rather than inventing a new dropdown/floating-menu.
            if let n = menuFor {
                BottomSheet(onDismiss: { menuFor = nil }) {
                    menuRow(n.readAt != nil ? app.T("Đánh dấu chưa đọc", "Mark as unread") : app.T("Đánh dấu đã đọc", "Mark as read")) {
                        Task {
                            if n.readAt != nil { await app.markNotificationUnread(n) } else { await app.markNotificationRead(n) }
                        }
                        menuFor = nil
                    }
                    .accessibilityIdentifier("notification.menu.toggleRead")
                    Divider().overlay(app.palette.rule)
                    menuRow(app.T("Tắt loại thông báo này", "Turn off this kind of notification")) {
                        Task { await app.muteNotificationKind(n.kind) }
                        menuFor = nil
                    }
                    .accessibilityIdentifier("notification.menu.mute")
                    Divider().overlay(app.palette.rule)
                    menuRow(app.T("Xoá thông báo này", "Delete this notification"), destructive: true) {
                        Task { await app.deleteNotification(n) }
                        menuFor = nil
                    }
                    .accessibilityIdentifier("notification.menu.delete")
                }
            }
        }
    }

    private func menuRow(_ label: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14.5))
                .foregroundStyle(destructive ? BanbeTheme.alert : app.palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private func section(_ sec: NotificationSection) -> some View {
        let expanded = expandedSections.contains(sec.id)
        return VStack(alignment: .leading, spacing: 6) {
            Text(sec.title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(app.palette.ink.opacity(0.6))
            if !sec.dayGrouped {
                let visible = expanded ? sec.items : Array(sec.items.prefix(notificationCollapseAt))
                ForEach(visible) { item in
                    // Live readAt, not the (frozen) section — marking a
                    // notification read only changes its weight/dimming in
                    // place, per BUG 3, never which section it's in.
                    row(item, unread: item.readAt == nil)
                    Divider().overlay(app.palette.rule)
                }
                moreButton(hiddenCount: sec.items.count - visible.count, sectionID: sec.id)
            } else {
                // "7 ngày qua"/"Cũ hơn": one header per calendar day
                // underneath this section's own outer title, collapsing
                // whole days at a time (collapseDayGroups() never cuts a
                // single day's items in half) instead of a flat
                // notificationCollapseAt slice across the range.
                let dayGroups = groupNotificationsByDay(sec.items, lang: app.lang)
                let (visibleDays, hiddenDays): ([NotificationDayGroup], [NotificationDayGroup]) = expanded
                    ? (dayGroups, [])
                    : collapseDayGroups(dayGroups, limit: notificationCollapseAt)
                ForEach(visibleDays) { day in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(day.label)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(app.palette.ink.opacity(0.5))
                            .accessibilityIdentifier("notification.dayHeader")
                        ForEach(day.items) { item in
                            row(item, unread: item.readAt == nil)
                            Divider().overlay(app.palette.rule)
                        }
                    }
                    .padding(.bottom, 8)
                }
                moreButton(hiddenCount: hiddenDays.reduce(0) { $0 + $1.items.count }, sectionID: sec.id)
            }
        }
        .padding(.bottom, 22)
    }

    @ViewBuilder
    private func moreButton(hiddenCount: Int, sectionID: String) -> some View {
        if hiddenCount > 0 {
            Button(app.T("Xem thêm (\(hiddenCount))", "View more (\(hiddenCount))")) {
                expandedSections.insert(sectionID)
            }
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(app.palette.ink.opacity(0.65))
            .buttonStyle(.plain)
            .padding(.vertical, 12)
            .accessibilityIdentifier("notifications.more.\(sectionID)")
        }
    }

    private func row(_ item: AppNotification, unread: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button { app.openNotification(item) } label: {
                HStack(alignment: .top, spacing: 10) {
                    avatar(for: item)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            // BUG 3: bold only while unread — reading a
                            // notification unbolds it in place (fontWeight
                            // only), it never moves sections.
                            Text(item.title)
                                .font(BanbeTheme.display(15))
                                .fontWeight(unread ? .bold : .regular)
                                .lineLimit(1)
                            Spacer(minLength: 12)
                            Text(app.trStatus(EventLabels.ago(hoursAgo(item.createdAt))))
                                .font(.system(size: 11))
                        }
                        // Instagram's own "bold actor/action + secondary
                        // preview" shape — one truncated line, not the old
                        // full-body wrap.
                        Text(item.body)
                            .font(.system(size: 13))
                            .foregroundStyle(app.palette.ink.opacity(0.75))
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // BUG 4: "•••" opens the action menu (delete / toggle read /
            // mute this kind) instead of deleting directly.
            Button {
                menuFor = item
            } label: {
                Text("•••")
                    .font(.system(size: 15))
                    .foregroundStyle(app.palette.ink.opacity(0.4))
                    .padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("notification-menu")
        }
        .opacity(unread ? 1 : 0.6)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func avatar(for item: AppNotification) -> some View {
        switch avatarSource(for: item, maps: app.notificationAvatarMaps, accountType: app.accountType) {
        case .image(let url):
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    avatarFallback
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
        case .catalogPhoto(let path):
            CatalogPhoto(path: path, height: 40, width: 40, cornerRadius: 20)
        case .fallback:
            avatarFallback
        }
    }

    // A plain colored circle with the app's own bell mark — never a broken
    // image. Used whenever avatarSource(for:maps:accountType:) can't
    // resolve an event photo or a guest avatar (neither exists, or the
    // notification kind has no specific actor at all, e.g. referral_joined).
    private var avatarFallback: some View {
        Circle()
            .fill(app.palette.ink.opacity(0.08))
            .frame(width: 40, height: 40)
            .overlay(Text("🔔").font(.system(size: 16)))
    }

    private func hoursAgo(_ date: Date) -> Int {
        max(1, Int(Date().timeIntervalSince(date) / 3600))
    }
}
