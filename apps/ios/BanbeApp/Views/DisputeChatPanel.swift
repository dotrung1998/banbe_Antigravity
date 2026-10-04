import SwiftUI

/// The temporary dispute chat — the whole block, wherever it renders.
///
/// It renders inside the booking conversation's own scroll view (ChatView) and,
/// for an escalated PAYMENT dispute, inside the host's verification queue. It
/// deliberately owns NO scroll view of its own any more: the old nested
/// `ScrollView` capped at a hard `maxHeight: 220` is what made the newest
/// messages unreachable whenever the enclosing conversation was scrolled
/// anywhere else, and a second vertical scroll inside a vertical scroll is a
/// gesture fight as well as a clipping bug. A plain column means the enclosing
/// scroll owns the position, every message is reachable by scrolling the
/// surface the reader is already on, and a background refresh leaves that
/// position exactly where it was.
///
/// Loading vs. refreshing is separated too: `disputeChatInitialLoadDone`
/// (never `disputeChatLoading`) decides whether the "Loading…" placeholder
/// shows, so a failed or in-flight background poll can never blank a
/// transcript the reader is in the middle of.
struct DisputeChatPanel: View {
    @EnvironmentObject private var app: AppState
    var bookingID: UUID?
    var refundClaimID: UUID?
    /// VERIFIED per-claim state (migration 130). Supplies the amount, claim
    /// status, viewer role, closure state and deletion deadline, so none of
    /// those is inferred from the polled dispute list any more.
    var claim: RefundDisputeThread?
    @State private var pollTask: Task<Void, Never>?
    @State private var highlightedID: UUID?
    /// Close / download / delete-my-copy requests, handled by the shared
    /// dialog flow (RefundDisputeFlows.swift).
    @State private var flowRequest: RefundDisputeFlowRequest?
    /// An attachment upload is running for THIS dispute. Local on purpose: it
    /// exists to dim the "+" while bytes are moving, while the guard that
    /// actually prevents a second upload lives in AppState
    /// (disputeAttachInFlight, keyed by claim id).
    @State private var sendingAttachment = false
    /// The attachment currently opened fullscreen, if any. Tapping an image in
    /// the transcript opens the same kind of viewer the ordinary chat uses —
    /// see DisputeAttachmentViewerView for the two things it deliberately
    /// does NOT offer.
    @State private var viewerItem: DisputeAttachmentViewerItem?
    /// Screen-space Y of the end of this dispute's message history, and of the
    /// end of the whole block. Their difference is what "am I at the end of
    /// this history?" means without a nested scroll view — see the two
    /// sentinels in `messageList`.
    @State private var historyBottomY: CGFloat = 0
    @State private var blockBottomY: CGFloat = 0
    /// Whether the end of this history has already been scrolled to once —
    /// reset whenever the panel is pointed at a different thread.
    @State private var didInitialJump = false
    /// Within this many points of the block's end counts as "reading the end".
    private static let endOfHistoryTolerance: CGFloat = 120

    private var isRefund: Bool { refundClaimID != nil }

    /// The freshest verified claim state. The `claim` parameter is a snapshot
    /// taken when the conversation loaded; the transcript poll keeps
    /// `refundDisputeThreads` current, so "Close" unlocks the moment the goer
    /// confirms the refund instead of on the next reopen.
    private var liveClaim: RefundDisputeThread? {
        if let id = refundClaimID, let fresh = app.refundDisputeThreads[id], fresh.found { return fresh }
        return claim
    }

    /// Same staleness guard the payment-only version had, expressed once and
    /// now key-based: state records WHICH dispute it currently holds and the
    /// panel only renders that one, so one thread's poll landing late can't
    /// paint the wrong conversation here.
    private var isActiveChat: Bool {
        guard let key = app.disputeChatKey else { return false }
        if let refundClaimID { return key == "refund:\(refundClaimID.uuidString)" }
        if let bookingID { return key == "payment:\(bookingID.uuidString)" }
        return false
    }

    private var messages: [DisputeMessage] {
        isActiveChat ? app.disputeChatMessages : []
    }

    /// Once a dispute is concluded the chat is a read-only record until the
    /// purge sweep removes it (both send RPCs refuse once resolved) — so the
    /// composer is hidden rather than left there to fail on submit.
    private var readOnly: Bool {
        isActiveChat && app.disputeChatThread?.resolvedAt != nil
    }

    /// A refund dispute is closed by one of the two parties (migration 130) or
    /// concludes some other way; either way it is "Dispute completed" and the
    /// transcript survives read-only for the rest of its 7-day window.
    private var completed: Bool {
        if isRefund, let claim = liveClaim { return claim.isCompleted }
        return readOnly
    }

    private var readerAtEndOfHistory: Bool {
        guard !messages.isEmpty else { return true }
        return historyBottomY - blockBottomY <= Self.endOfHistoryTolerance
    }

    /// "Deletes on <date>" — the deadline the purge cron will act on, shown
    /// wherever a closed transcript is still readable. A static, render-time
    /// value, never a delete button: dispute_messages must survive until
    /// purge_resolved_dispute_threads() actually removes them.
    private var deletionDeadlineLabel: String? {
        guard completed, let purgeAfter = app.disputeChatThread?.purgeAfter ?? liveClaim?.purgeAfter else { return nil }
        let vi = formatShortDate(purgeAfter, lang: "vi") ?? ""
        let en = formatShortDate(purgeAfter, lang: "en") ?? ""
        guard !vi.isEmpty, !en.isEmpty else { return nil }
        return app.T("Bản ghi bị xoá vào \(vi).", "Transcript is deleted on \(en).")
    }

    // No realtime subscription exists anywhere in this app (no Supabase
    // Realtime channel usage, and dispute_messages was never added to the
    // supabase_realtime publication) — without this poll, the party who
    // didn't just send a message never sees a new one until they leave and
    // reopen this view. 4s, matching the web counterpart.
    //
    // ONE loop per mounted panel, cancelled on disappear and restarted on
    // every thread change, and the loader drops a poll that arrives while the
    // previous one is still in flight (disputeChatInFlight in
    // AppState+Payments) — together, "no overlapping polls, no stale response
    // overwriting another thread".
    private func startPolling() {
        pollTask?.cancel()
        let claimID = refundClaimID
        let booking = bookingID
        // BUG (2026-10-04, physical-iPhone repro): every mounted panel used to
        // poll unconditionally. Two panels on one screen (which the "mount a
        // panel on every declined/confirmed card" bug produced) meant two
        // concurrent loops writing the ONE shared transcript state
        // (disputeChatKey / disputeChatMessages / disputeChatDraft), so they
        // blanked and overwrote each other. A panel now only drives that shared
        // state while it is the dispute that owns it (`isActiveChat`), checked
        // again on every tick so a panel that loses ownership simply goes quiet
        // instead of fighting for it.
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if Task.isCancelled { return }
                guard isActiveChat else { continue }
                if let claimID { await app.loadRefundDisputeChat(claimID) }
                else if let booking { await app.loadDisputeChat(booking) }
            }
        }
    }

    /// Initial (and retry) fetch. This is what CLAIMS the shared transcript
    /// state on mount: it used to bail unless `isActiveChat`, but that only
    /// becomes true once a load has bound the key, so on a cold open nothing
    /// ever loaded until a send bound it. Polling still requires ownership.
    private func reload() async {
        if let refundClaimID { await app.loadRefundDisputeChat(refundClaimID) }
        else if let bookingID { await app.loadDisputeChat(bookingID) }
    }

    private func restart() {
        didInitialJump = false
        highlightedID = nil
        startPolling()
    }

    private func send() async {
        if let refundClaimID { await app.sendRefundDisputeMessage(refundClaimID) }
        else if let bookingID { await app.sendDisputeMessage(bookingID) }
        // Our own message is the one case where jumping to the end is always
        // right, whatever the reader was doing beforehand.
        if let last = messages.last { app.disputeChatScrollTarget = last.id }
    }

    /// Attach a photo or document to THIS refund dispute — the exact same
    /// "+" flow the booking conversation's composer uses (ChatAttachButton,
    /// ChatAttachmentFlow.swift), including its menu, its pickers, the
    /// accepted types and the size cap.
    ///
    /// Only offered for a refund dispute, and only while it is open: the
    /// server refuses both the upload and the message once the dispute is
    /// concluded (send_refund_dispute_attachment re-checks `resolved_at` at
    /// insert time), and the "other party closed it while my photo was
    /// uploading" case is answered by deleting the file we just wrote rather
    /// than by leaving it orphaned — see AppState.sendRefundDisputeAttachment.
    private func sendAttachment(_ payload: AttachmentPayload) async {
        guard let refundClaimID else { return }
        sendingAttachment = true
        let ok = await app.sendRefundDisputeAttachment(payload, claimID: refundClaimID)
        sendingAttachment = false
        guard ok, let last = messages.last else { return }
        app.disputeChatScrollTarget = last.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Text(temporaryChatNotice)
                .font(.system(size: 11)).foregroundStyle(app.palette.ink.opacity(0.7))
            statusBlock
            messageList
            if !readOnly && !completed { composer }
            actions
            if !app.disputeChatError.isEmpty && !(messages.isEmpty && isActiveChat && app.disputeChatInitialLoadDone) {
                Text(app.disputeChatError)
                    .font(.system(size: 11.5)).foregroundStyle(BanbeTheme.alert)
                    .accessibilityIdentifier("disputeChat.error")
            }
        }
        .padding(14)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task(id: refundClaimID ?? bookingID) { await reload() }
        .onAppear {
            startPolling()
            jumpToPendingTargetIfAny()
        }
        .onDisappear { pollTask?.cancel() }
        // A thread switch inside the same panel (two open disputes on one
        // screen) restarts the loop against the new id rather than leaving the
        // old one polling, and re-arms the one-time jump to the end.
        .onChange(of: refundClaimID) { _, _ in restart() }
        .onChange(of: bookingID) { _, _ in restart() }
        .onChange(of: messages.count) { _, _ in jumpToPendingTargetIfAny() }
        .onChange(of: app.disputeChatIncomingTick) { _, _ in
            // An incoming message only pulls the view when the reader is
            // already at the end of this history; someone reading older
            // messages must not be yanked away from them.
            guard readerAtEndOfHistory, let last = messages.last else { return }
            app.disputeChatScrollTarget = last.id
        }
        // chatHighlight is an optional tuple, which has no Equatable
        // conformance for onChange — its presence boolean is the signal that
        // something new arrived to be consumed.
        .onChange(of: app.chatHighlight != nil) { _, _ in consumeChatHighlight() }
        .accessibilityIdentifier("disputeChat.panel")
        // Fullscreen image viewer for a transcript attachment. Presented from
        // here rather than from RootView because this panel has no global
        // viewer slot: unlike the ordinary chat's photo viewer (which also
        // offers Forward and Post to Story), a dispute attachment can only be
        // viewed, saved or shared from here — see DisputeAttachmentViewerView.
        .fullScreenCover(item: $viewerItem) { item in
            DisputeAttachmentViewerView(item: item)
                .ignoresSafeArea()
        }
        .refundDisputeFlows(claimID: refundClaimID ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, request: $flowRequest)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(app.T("Trao đổi trực tiếp về tranh chấp này", "Direct chat about this dispute"))
                .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(app.palette.ink)
            Spacer(minLength: 0)
            if !completed {
                Text(app.T("Tranh chấp đang diễn ra", "Dispute in progress"))
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(BanbeTheme.alert)
                    .accessibilityIdentifier("disputeChat.inProgress")
            }
            if !messages.isEmpty {
                Text(app.T("\(messages.count) tin nhắn", "\(messages.count) messages"))
                    .font(.system(size: 10))
                    .foregroundStyle(app.palette.ink.opacity(0.5))
                    .accessibilityIdentifier("disputeChat.count")
            }
        }
    }

    /// The two kinds have genuinely different endings — a payment dispute is
    /// closed by banbe and emailed a transcript, a refund dispute is settled
    /// between the two parties and auto-deletes — so the promise made to the
    /// reader has to differ too.
    private var temporaryChatNotice: String {
        if isRefund {
            return app.T("Cuộc trò chuyện này là tạm thời: khi tranh chấp kết thúc, nó sẽ tự xoá sau 7 ngày.",
                         "This conversation is temporary: once the dispute is settled it deletes itself after 7 days.")
        }
        return app.T("Cuộc trò chuyện này là tạm thời: sẽ bị xoá sau khi banbe đưa ra quyết định, và bản ghi được gửi qua email cho cả hai bên.",
                     "This conversation is temporary — it is deleted once banbe rules on the dispute, and a copy is emailed to both of you.")
    }

    @ViewBuilder
    private var statusBlock: some View {
        if completed {
            VStack(alignment: .leading, spacing: 3) {
                Text(app.T("Tranh chấp đã hoàn tất", "Dispute completed"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(app.palette.ink.opacity(0.7))
                    .accessibilityIdentifier("disputeChat.completed")
                if let deletionDeadlineLabel {
                    Text(deletionDeadlineLabel)
                        .font(.system(size: 10.5))
                        .foregroundStyle(app.palette.ink.opacity(0.55))
                        .accessibilityIdentifier("disputeChat.deletionDeadline")
                }
                if let closedBy = liveClaim?.disputeClosedByRole, closedBy != "admin" {
                    Text(closedBy == "guest"
                         ? app.T("Đã đóng bởi khách.", "Closed by the guest.")
                         : app.T("Đã đóng bởi người tổ chức.", "Closed by the organizer."))
                        .font(.system(size: 10.5))
                        .foregroundStyle(app.palette.ink.opacity(0.55))
                }
            }
        } else if let resolutionNote = app.disputeChatThread?.resolutionNote, !resolutionNote.isEmpty {
            Text(resolutionNote)
                .font(.system(size: 10.5))
                .foregroundStyle(app.palette.ink.opacity(0.55))
        }
    }

    // MARK: History
    //
    // No nested ScrollView: the enclosing conversation (or verification
    // queue) scrolls. Two 1pt GeometryReader sentinels measure where the end
    // of this history sits relative to the end of the block, which is what
    // decides whether an incoming message auto-scrolls.
    private var messageList: some View {
        VStack(alignment: .leading, spacing: 6) {
            // "Loading…" belongs to the FIRST load of a thread only. A
            // background refresh leaves the messages — and the reader's
            // scroll position — completely alone.
            let loaded = isActiveChat && app.disputeChatInitialLoadDone
            if loaded && messages.isEmpty && !app.disputeChatError.isEmpty {
                // A failed first fetch is not "no messages".
                VStack(alignment: .leading, spacing: 6) {
                    Text(app.disputeChatError)
                        .font(.system(size: 11.5)).foregroundStyle(BanbeTheme.alert)
                    Button(app.T("Thử lại", "Retry")) { Task { await reload() } }
                        .font(.system(size: 12, weight: .semibold))
                        .accessibilityIdentifier("disputeChat.retry")
                }
            } else if !loaded {
                Text(app.T("Đang tải…", "Loading…"))
                    .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.6))
                    .accessibilityIdentifier("disputeChat.loading")
            } else if messages.isEmpty {
                Text(app.T("Chưa có tin nhắn nào.", "No messages yet."))
                    .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.6))
                    .accessibilityIdentifier("disputeChat.empty")
            } else {
                ForEach(messages) { m in
                    messageRow(m)
                        // Stable per-row identity straight off the row's own
                        // uuid, so a poll returning the same transcript
                        // re-renders nothing and the scroll position survives.
                        .id(m.id)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .bottom) {
            GeometryReader { proxy in
                Color.clear.preference(key: DisputeBlockBottomKey.self, value: proxy.frame(in: .global).maxY)
            }
        }
        .onPreferenceChange(DisputeBlockBottomKey.self) { blockBottomY = $0 }
    }

    private func messageRow(_ m: DisputeMessage) -> some View {
        let mine = m.senderId != nil && m.senderId == app.userID
        let isLast = m.id == messages.last?.id
        return VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
            Text(senderLabel(m) + " ▪︎ " + m.createdAt.formatted())
                .font(.system(size: 10)).foregroundStyle(app.palette.ink.opacity(0.55))
            if let path = m.attachmentPath, !path.isEmpty {
                // Same two shapes the ordinary chat draws, from the same
                // shared geometry (AttachmentBubble.boxSize), so a photo looks
                // identical in both places: an inline image at the source
                // image's own ratio that opens fullscreen on tap, or a
                // paperclip chip that opens the document. Attachment-ONLY
                // messages work because `body` is a caption, not the content.
                attachmentBody(m, path: path)
            } else {
                // .fixedSize(horizontal: false, vertical: true) so a long message
                // wraps to as many lines as it needs instead of being clipped to a
                // single line's height inside this fixed-width column — the other
                // half of the "messages are cut off" bug.
                Text(m.body)
                    .font(.system(size: 13))
                    .foregroundStyle(app.palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(BanbeTheme.alert, lineWidth: highlightedID == m.id ? 1.5 : 0)
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        .accessibilityIdentifier("disputeChat.message")
        .background(alignment: .bottom) {
            if isLast {
                GeometryReader { proxy in
                    Color.clear.preference(key: DisputeHistoryBottomKey.self, value: proxy.frame(in: .global).maxY)
                }
            }
        }
        .onPreferenceChange(DisputeHistoryBottomKey.self) { historyBottomY = $0 }
    }

    /// One attachment inside the transcript: an image preview box, or a file
    /// chip. Neither renders `body` beside it — exactly like ChatView's own
    /// bubble, which shows only the attachment and uses the localized "Sent a
    /// photo" caption as an accessible description rather than as visible text.
    ///
    /// The signed URL comes from `app.disputeAttachmentUrls`, which only ever
    /// holds paths the storage policy granted this account — and those paths
    /// are namespaced by DISPUTE thread id, so nothing signed for one dispute
    /// can be drawn inside another's transcript.
    @ViewBuilder
    private func attachmentBody(_ m: DisputeMessage, path: String) -> some View {
        let url = app.disputeAttachmentUrls[path]
        if m.isImageAttachment, let url {
            let box = AttachmentBubble.boxSize(width: m.attachmentWidth, height: m.attachmentHeight)
            AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { app.palette.field }
                .frame(width: min(box.width, 240), height: min(box.height, 320))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(app.palette.rule, lineWidth: 1))
                .accessibilityIdentifier("disputeChat.attachment")
                .onTapGesture {
                    viewerItem = DisputeAttachmentViewerItem(
                        path: path, url: url,
                        width: m.attachmentWidth, height: m.attachmentHeight,
                        senderLabel: senderLabel(m)
                    )
                }
        } else if let url {
            Link(destination: url) {
                HStack(spacing: 8) {
                    Image(systemName: "paperclip")
                    Text(m.body)
                        .lineLimit(2)
                }
                .font(.system(size: 12.5))
                .foregroundStyle(app.palette.ink)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .accessibilityIdentifier("disputeChat.attachment")
        } else {
            // Still signing, or the policy refused: say so rather than
            // silently rendering a broken/empty bubble.
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(app.T("Đang tải tệp…", "Loading attachment…"))
                    .font(.system(size: 12))
            }
            .foregroundStyle(app.palette.ink.opacity(0.6))
            .padding(8)
            .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityIdentifier("disputeChat.attachmentPending")
        }
    }

    /// Reached by tapping a 'dispute_message' toast/notification
    /// (openNotification, AppState+Data.swift) — jumps to the specific message
    /// named by chatHighlight.messageID, or to the end of the thread if that's
    /// nil (an older notification row from before migration 050 added
    /// message_id). clearChatHighlight() consumes it so the 4s poll's
    /// re-renders don't keep re-triggering it.
    private func consumeChatHighlight() {
        guard let highlight = app.chatHighlight else { return }
        guard isRefund ? highlight.refundClaimID == refundClaimID : highlight.bookingID == bookingID else { return }
        guard !messages.isEmpty else { return }
        if let messageID = highlight.messageID, messages.contains(where: { $0.id == messageID }) {
            app.disputeChatScrollTarget = messageID
            highlightedID = messageID
            let token = messageID
            Task {
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                if highlightedID == token { highlightedID = nil }
            }
        } else if let last = messages.last {
            app.disputeChatScrollTarget = last.id
        } else {
            return // nothing to scroll to yet — wait for the next load
        }
        app.clearChatHighlight()
    }

    /// A pending jump can only be applied once its target message actually
    /// exists; until then it stays pending so the first load that contains it
    /// performs the jump rather than dropping it.
    ///
    /// The one jump this performs on its own is the FIRST one, for a thread
    /// that has just opened — everything after that is driven by an explicit
    /// target (own send, deep link, a new incoming message the reader was
    /// already at the bottom for). Silently re-jumping on every later message
    /// is exactly what would yank a reader back out of history they're
    /// reading.
    private func jumpToPendingTargetIfAny() {
        guard !messages.isEmpty, app.disputeChatInitialLoadDone else { return }
        if app.chatHighlight != nil {
            consumeChatHighlight()
            return
        }
        if app.disputeChatScrollTarget != nil { return }
        guard !didInitialJump else { return }
        didInitialJump = true
        if let last = messages.last { app.disputeChatScrollTarget = last.id }
    }

    // MARK: Composer

    private var composer: some View {
        HStack(spacing: 8) {
            // Attachments (migration 131). REFUND disputes only — the payment
            // dispute panel above (host's verification queue) is admin-resolved
            // and has no bucket, no columns and no send RPC for this.
            if let refundClaimID {
                ChatAttachButton(
                    isEnabled: !readOnly && !completed,
                    isSending: sendingAttachment,
                    onPick: { payload in await sendAttachment(payload) },
                    onFailure: { reason in app.disputeChatError = reason },
                    accessibilityIdentifier: "disputeChat.attach"
                )
            }
            TextField(app.T("Nhắn gì đó…", "Say something…"), text: $app.disputeChatDraft, axis: .vertical)
                .font(.system(size: 13)).padding(10)
                .lineLimit(1...4)
                .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityIdentifier("disputeChat.input")
                .onSubmit { Task { await send() } }
            Button {
                Task { await send() }
            } label: {
                Text(app.T("Gửi", "Send"))
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(app.disputeChatDraft.trimmingCharacters(in: .whitespaces).isEmpty
                                ? app.palette.ink.opacity(0.35) : app.palette.ink,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .foregroundStyle(app.palette.paper)
            }
            .buttonStyle(.plain)
            .disabled(app.disputeChatDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityIdentifier("disputeChat.send")
        }
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        // Only a verified participant of this REFUND dispute gets these — the
        // claim's own server-resolved viewer role is the gate, never
        // "this screen happens to show a dispute card".
        if isRefund, let claim = liveClaim, claim.viewerRole != nil {
            HStack(spacing: 10) {
                // Offered BEFORE closing too, so nobody has to close a dispute
                // in order to keep a copy of what was said in it.
                Button {
                    flowRequest = .download
                } label: {
                    Text(exportRunning
                         ? app.T("Đang chuẩn bị…", "Preparing…")
                         : app.T("Tải bản ghi", "Download transcript"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(app.palette.ink.opacity(0.8))
                        .underline()
                }
                .buttonStyle(.plain)
                .disabled(exportRunning)
                .accessibilityIdentifier("disputeChat.download")

                Spacer(minLength: 0)

                if !completed {
                    // Greyed out and unclickable until the refund is settled:
                    // host marks it sent, goer confirms it was received.
                    Button {
                        flowRequest = .close
                    } label: {
                        Text(app.T("Đóng tranh chấp", "Close dispute"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(claim.refundSettled ? BanbeTheme.alert : app.palette.ink.opacity(0.35))
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .disabled(flowBusy || !claim.refundSettled)
                    .accessibilityIdentifier("disputeChat.close")
                } else if claim.viewerRole == "guest" {
                    Button {
                        flowRequest = .deleteCopy
                    } label: {
                        Text(app.T("Xoá bản của tôi", "Delete my copy"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(BanbeTheme.alert)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .disabled(flowBusy)
                    .opacity(flowBusy ? 0.5 : 1)
                    .accessibilityIdentifier("disputeChat.deleteCopy")
                }
            }
            if !app.disputeCloseError.isEmpty {
                Text(app.disputeCloseError)
                    .font(.system(size: 11)).foregroundStyle(BanbeTheme.alert)
                    .padding(.top, 2)
                    .accessibilityIdentifier("disputeChat.closeError")
            }
        }
    }

    private var exportRunning: Bool {
        app.disputeExport.claimID == refundClaimID && app.disputeExport.status == .running
    }

    private var flowBusy: Bool {
        app.refundDisputeClosingClaimId != nil || app.refundDisputeDeletingClaimId != nil
    }

    private func senderLabel(_ m: DisputeMessage) -> String {
        switch m.senderRole {
        case "organizer":
            if m.senderId == app.userID { return app.T("Bạn", "You") }
            return liveClaim?.organizerName ?? app.T("Người tổ chức", "Organizer")
        case "guest":
            return m.senderId == app.userID ? app.T("Bạn", "You") : app.T("Khách", "Guest")
        case "admin": return "banbe"
        default: return app.T("Hệ thống", "System")
        }
    }
}

/// Where the END of this dispute's message history currently is on screen.
private struct DisputeHistoryBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Where the END of the whole dispute block currently is on screen.
private struct DisputeBlockBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Fullscreen attachment viewer (migration 131)

/// One dispute attachment opened fullscreen. `Identifiable` on the object
/// path so `.fullScreenCover(item:)` presents and dismisses it the same way
/// the rest of this app presents a transient detail.
struct DisputeAttachmentViewerItem: Identifiable {
    let path: String
    let url: URL
    let width: Int?
    let height: Int?
    let senderLabel: String
    var id: String { path }
}

/// Fullscreen viewer for a photo shared inside the temporary refund dispute.
///
/// Interaction model is ChatPhotoViewerView's, deliberately: tap toggles the
/// chrome, only a downward drag past the threshold dismisses, the same
/// threshold, drag-reveal distance and dismissal timing constants are used, so
/// "how the photo viewer behaves" is one answer in this app rather than two.
///
/// The action set is deliberately SHORTER than the chat viewer's, and that is
/// the whole point of not reusing that view:
///   * no Forward — a forwarded attachment would be re-uploaded into an
///     ordinary conversation's `chat-attachments`, i.e. copied out of the
///     temporary, participant-scoped, purge-with-the-transcript lifecycle
///     into one that never deletes anything;
///   * no Post to Story — same objection, and public.
/// What it does offer is the ordinary viewer's read/save/share/copy set, plus
/// one line saying plainly that this file goes away with the transcript, so
/// nobody believes a saved-in-app "attachment" is permanent.
private struct DisputeAttachmentViewerView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    let item: DisputeAttachmentViewerItem
    @State private var chromeHidden = false
    @State private var dragOffsetY: CGFloat = 0
    @State private var isDragging = false
    @State private var actionMessage: String?

    private static let dismissMs: Double = 0.26
    private static let dismissThreshold: CGFloat = 90
    private static let dragRevealDistance: CGFloat = 220

    private var dragProgress: Double { min(1, max(0, dragOffsetY) / Self.dragRevealDistance) }

    var body: some View {
        ZStack {
            // Same layering rule as ChatPhotoViewerView: the drag gesture
            // lives on the backdrop+photo layer ONLY, never on a container
            // that wraps the toolbar, or it steals the toolbar's taps.
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
        }
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .bottom) { bottomBar }
        .transition(.opacity)
        // The panel normally renders inside the booking conversation, where
        // the dock is already hidden — but this viewer is a full-window
        // presentation of the MAIN window's hierarchy, which the separate
        // always-on-top dock window would otherwise paint straight through, so
        // it says so for as long as it is up (same mechanism ChatView uses for
        // its own camera/file pickers).
        .onAppear { BottomTabBarOverlay.shared.setForcedHidden(true) }
        .onDisappear { BottomTabBarOverlay.shared.setForcedHidden(false) }
    }

    private var stage: some View {
        ZStack {
            Color.black.ignoresSafeArea()
                .opacity(Double(1 - dragProgress * 0.7))
            AsyncImage(url: item.url) { $0.resizable().scaledToFit() } placeholder: { ProgressView().tint(.white) }
                .frame(maxWidth: UIScreen.main.bounds.width * 0.92, maxHeight: UIScreen.main.bounds.height * 0.7)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .offset(y: dragOffsetY)
                .scaleEffect(1 - dragProgress * 0.08)
                .accessibilityIdentifier("disputeChat.photoViewer.image")
        }
        .contentShape(Rectangle())
        .gesture(stageGesture)
    }

    private var stageGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let dy = value.translation.height
                let dx = value.translation.width
                if !isDragging {
                    guard dy > 6, dy > abs(dx) else { return }
                    isDragging = true
                }
                dragOffsetY = dy
            }
            .onEnded { value in
                defer { isDragging = false }
                let dy = value.translation.height
                let dx = value.translation.width
                guard isDragging else {
                    if abs(dy) < 6 && abs(dx) < 6 { chromeHidden.toggle() }
                    return
                }
                if dy > Self.dismissThreshold {
                    withAnimation(.easeOut(duration: Self.dismissMs)) { dragOffsetY = UIScreen.main.bounds.height }
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.dismissMs) { dismiss() }
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragOffsetY = 0 }
                }
            }
    }

    private var topBar: some View {
        HStack {
            Button { closeTapped() } label: {
                Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityIdentifier("disputeChat.photoViewer.close")
            .padding(.leading, -10)
            Spacer()
            Button { Task { await saveTapped() } } label: {
                Image(systemName: "arrow.down.circle").font(.system(size: 18)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityIdentifier("disputeChat.photoViewer.save")
            Button { shareTapped() } label: {
                Image(systemName: "square.and.arrow.up").font(.system(size: 18)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityIdentifier("disputeChat.photoViewer.share")
            Button { copyTapped() } label: {
                Image(systemName: "doc.on.doc").font(.system(size: 18)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityIdentifier("disputeChat.photoViewer.copy")
        }
        .padding(.horizontal, 18).padding(.top, 56)
        .opacity(chromeHidden ? 0 : Double(1 - dragProgress))
        .allowsHitTesting(!chromeHidden)
        .animation(.easeInOut(duration: 0.2), value: chromeHidden)
    }

    /// Who sent it, and the one promise that must not be left implicit: this
    /// file is deleted with the transcript, so saving a copy is the reader's
    /// only way to keep it.
    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(app.T("Gửi bởi \(item.senderLabel)", "Sent by \(item.senderLabel)"))
                .font(.system(size: 13, weight: .semibold))
            Text(app.T(
                "Tệp đính kèm của tranh chấp tạm thời: tự xoá cùng bản ghi khi tranh chấp kết thúc. Hãy lưu ảnh nếu bạn cần giữ lại.",
                "Temporary dispute attachment: it is deleted with this transcript when the dispute ends. Save the photo now if you need to keep it."
            ))
            .font(.system(size: 12))
            .opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.75), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(edges: .bottom)
        )
        .opacity(chromeHidden ? 0 : Double(1 - dragProgress))
        .allowsHitTesting(!chromeHidden)
        .animation(.easeInOut(duration: 0.2), value: chromeHidden)
    }

    private func closeTapped() {
        withAnimation(.easeOut(duration: Self.dismissMs)) { dragOffsetY = UIScreen.main.bounds.height }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.dismissMs) { dismiss() }
    }

    private func flash(_ text: String) {
        actionMessage = text
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { actionMessage = nil }
        }
    }

    private func saveTapped() async {
        let ok = await app.saveDisputeAttachmentImage(from: item.url)
        flash(ok ? app.T("Đã lưu ảnh", "Photo saved") : app.T("Không lưu được ảnh", "Couldn't save photo"))
    }

    private func shareTapped() {
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: item.url),
                  let image = UIImage(data: data) else { return }
            await MainActor.run {
                let activity = UIActivityViewController(activityItems: [image], applicationActivities: nil)
                UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first?.keyWindow?.rootViewController?
                    .present(activity, animated: true)
            }
        }
    }

    private func copyTapped() {
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: item.url),
                  let image = UIImage(data: data) else { return }
            await MainActor.run {
                UIPasteboard.general.image = image
                actionMessage = app.T("Đã sao chép ảnh", "Image copied")
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { actionMessage = nil }
        }
    }
}