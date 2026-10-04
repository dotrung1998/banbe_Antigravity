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
    @State private var confirmCloseOpen = false
    @State private var transcriptBusy = false
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
        if isRefund, let claim { return claim.isCompleted }
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
        guard completed, let purgeAfter = app.disputeChatThread?.purgeAfter ?? claim?.purgeAfter else { return nil }
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
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if Task.isCancelled { return }
                if let claimID { await app.loadRefundDisputeChat(claimID) }
                else if let booking { await app.loadDisputeChat(booking) }
            }
        }
    }

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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Text(temporaryChatNotice)
                .font(.system(size: 11)).foregroundStyle(app.palette.ink.opacity(0.7))
            statusBlock
            messageList
            if !readOnly && !completed { composer }
            actions
            if !app.disputeChatError.isEmpty {
                Text(app.disputeChatError)
                    .font(.system(size: 11.5)).foregroundStyle(BanbeTheme.alert)
                    .accessibilityIdentifier("disputeChat.error")
            }
        }
        .padding(14)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task { await reload() }
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
        .sheet(isPresented: $app.disputeTranscriptReadyToShare) {
            if let url = app.disputeTranscriptExportURL {
                BanbeShareSheet(items: [url])
                    .onDisappear { app.disputeTranscriptReadyToShare = false }
            }
        }
        .alert(app.T("Đóng tranh chấp này?", "Close this dispute?"), isPresented: $confirmCloseOpen) {
            Button(app.T("Huỷ", "Cancel"), role: .cancel) {}
            Button(app.T("Đóng tranh chấp", "Close dispute"), role: .destructive) {
                guard let refundClaimID else { return }
                Task { await app.closeRefundDispute(refundClaimID) }
            }
        } message: {
            // Says plainly that this is only about the argument: it must never
            // read as "the refund is settled", because closing a dispute moves
            // no money at all — the refund is still owed and still has to be
            // sent and confirmed on its own.
            Text(app.T(
                "Sau khi đóng, hai bên không gửi được tin nhắn trong tranh chấp này nữa. Bản ghi vẫn đọc được trong 7 ngày rồi tự xoá. Khoản hoàn không thay đổi — vẫn cần chuyển và xác nhận như bình thường.",
                "After closing, neither of you can post in this dispute again. The transcript stays readable for 7 days, then deletes itself. This does not settle the refund — the money still has to be sent and confirmed as usual."
            ))
        }
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
                if let closedBy = claim?.disputeClosedByRole, closedBy != "admin" {
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
            if !app.disputeChatInitialLoadDone && app.disputeChatLoading {
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
            // .fixedSize(horizontal: false, vertical: true) so a long message
            // wraps to as many lines as it needs instead of being clipped to a
            // single line's height inside this fixed-width column — the other
            // half of the "messages are cut off" bug.
            Text(m.body)
                .font(.system(size: 13))
                .foregroundStyle(app.palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(BanbeTheme.alert, lineWidth: highlightedID == m.id ? 1.5 : 0)
        )
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
        if isRefund, let claim, claim.viewerRole != nil {
            HStack(spacing: 10) {
                // Offered BEFORE closing too, so nobody has to close a dispute
                // in order to keep a copy of what was said in it.
                Button {
                    guard let refundClaimID else { return }
                    transcriptBusy = true
                    Task {
                        await app.prepareRefundDisputeTranscript(refundClaimID)
                        transcriptBusy = false
                    }
                } label: {
                    Text(transcriptBusy
                         ? app.T("Đang chuẩn bị…", "Preparing…")
                         : app.T("Tải bản ghi", "Download transcript"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(app.palette.ink.opacity(0.8))
                        .underline()
                }
                .buttonStyle(.plain)
                .disabled(transcriptBusy)
                .accessibilityIdentifier("disputeChat.download")

                Spacer(minLength: 0)

                if !completed {
                    Button {
                        confirmCloseOpen = true
                    } label: {
                        Text(app.T("Đóng tranh chấp / Đánh dấu hoàn tất", "Close dispute / Mark as completed"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(BanbeTheme.alert)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .disabled(app.refundDisputeClosingClaimId != nil)
                    .opacity(app.refundDisputeClosingClaimId != nil ? 0.5 : 1)
                    .accessibilityIdentifier("disputeChat.close")
                }
            }
            if !app.disputeTranscriptError.isEmpty {
                Text(app.disputeTranscriptError)
                    .font(.system(size: 11)).foregroundStyle(BanbeTheme.alert)
                    .padding(.top, 2)
                    .accessibilityIdentifier("disputeChat.transcriptError")
            }
            if !app.disputeCloseError.isEmpty {
                Text(app.disputeCloseError)
                    .font(.system(size: 11)).foregroundStyle(BanbeTheme.alert)
                    .padding(.top, 2)
                    .accessibilityIdentifier("disputeChat.closeError")
            }
        }
    }

    private func senderLabel(_ m: DisputeMessage) -> String {
        switch m.senderRole {
        case "organizer":
            if m.senderId == app.userID { return app.T("Bạn", "You") }
            return claim?.organizerName ?? app.T("Người tổ chức", "Organizer")
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