import SwiftUI

/// What a refund dispute screen asks the shared flow to start.
enum RefundDisputeFlowRequest: Equatable {
    /// The "Close dispute" button. The goer gets the keep / delete choice, the
    /// host gets the plain close confirmation.
    case close
    /// A plain "Download" button: build the export and share it. Never deletes.
    case download
    /// The goer wants their copy gone from a dispute that is already closed.
    case deleteCopy
    /// The goer's "Mark refund received": confirms receipt AND closes the dispute,
    /// after offering to download the transcript first.
    case confirmReceived
}

/// The close, download and delete dialogs for ONE refund dispute, shared by
/// the chat panel (DisputeChatPanel) and the refund card (RefundDisputeEntry)
/// so both behave identically and neither can drift.
///
/// Rules this enforces:
///   * Deleting the goer's copy always passes through "Download your
///     conversation first?". Downloading never deletes by itself.
///   * After an export the share sheet's own result decides what happens next:
///     only a completed activity leads to the deletion confirmation, and even
///     then deletion needs its own explicit tap. Closing the sheet is NOT a
///     save: nothing is deleted and the chat stays.
///   * An export failure keeps the chat as it was and offers Retry or Cancel.
///   * Nothing here touches refund status. The server is the authority on who
///     may close or delete (the goer only for deletion).
struct RefundDisputeFlows: ViewModifier {
    @EnvironmentObject private var app: AppState
    let claimID: UUID
    @Binding var request: RefundDisputeFlowRequest?

    private enum Intent { case downloadOnly, deleteAfter, downloadThenConfirm }

    @State private var intent: Intent = .downloadOnly
    @State private var showHostClose = false
    @State private var showGoerChoice = false
    @State private var showDownloadFirst = false
    @State private var showDeleteConfirm = false
    @State private var showNotSaved = false
    @State private var showFailure = false
    @State private var showConfirmReceived = false
    @State private var sheetOpen = false
    @State private var sharing = false
    @State private var shareCompleted = false

    private var isGoer: Bool { app.refundDisputeThreads[claimID]?.viewerRole == "guest" }
    private var exportIsMine: Bool { app.disputeExport.claimID == claimID }

    func body(content: Content) -> some View {
        content
            .onChange(of: request) { _, new in
                guard let new else { return }
                request = nil
                begin(new)
            }
            .onChange(of: app.disputeExport) { _, state in
                guard state.claimID == claimID, sheetOpen else { return }
                if state.status == .ready, !sharing {
                    shareCompleted = false
                    sharing = true
                } else if state.status == .failed {
                    sheetOpen = false
                    sharing = false
                    afterSheetClosed { showFailure = true }
                }
            }
            .onDisappear {
                // Leaving the screen ends the flow and removes the temporary
                // files; nothing was deleted from the server.
                if exportIsMine, app.disputeExport.status != .idle { app.discardRefundDisputeExport() }
            }
            .sheet(isPresented: $sheetOpen, onDismiss: sheetClosed) {
                sheetContent
                    .presentationDetents(sharing ? [.medium, .large] : [.height(270)])
                    .interactiveDismissDisabled(!sharing)
            }
            // Host: plain close.
            .alert(app.T("Đóng tranh chấp này?", "Close this dispute?"), isPresented: $showHostClose) {
                Button(app.T("Huỷ", "Cancel"), role: .cancel) {}
                Button(app.T("Đóng tranh chấp", "Close dispute"), role: .destructive) {
                    Task { await app.closeRefundDispute(claimID) }
                }
            } message: { Text(Self.closeNotice(app)) }
            // Goer: keep for 7 days, or delete their copy now.
            .confirmationDialog(app.T("Đóng tranh chấp này?", "Close this dispute?"),
                                isPresented: $showGoerChoice, titleVisibility: .visible) {
                Button(app.T("Đóng và giữ 7 ngày", "Close and keep for 7 days")) {
                    Task { await app.closeRefundDispute(claimID) }
                }
                .accessibilityIdentifier("disputeFlow.closeKeep")
                Button(app.T("Đóng và xoá bản của tôi ngay", "Close and delete my copy now"), role: .destructive) {
                    showDownloadFirst = true
                }
                .accessibilityIdentifier("disputeFlow.closeDelete")
                Button(app.T("Huỷ", "Cancel"), role: .cancel) {}
            } message: {
                Text(Self.closeNotice(app) + "\n\n" + app.T(
                    "Giữ 7 ngày: cả hai bên vẫn đọc được cuộc trò chuyện trong 7 ngày.\nXoá bản của tôi ngay: cuộc trò chuyện biến mất khỏi tài khoản của bạn. Người tổ chức vẫn giữ bản ghi của họ trong 7 ngày.",
                    "Keep for 7 days: you and the organizer can still read the conversation for 7 days.\nDelete my copy now: the conversation disappears from your account. The organizer keeps their record for 7 days."))
            }
            // Always offered before an immediate deletion.
            .alert(app.T("Tải cuộc trò chuyện về trước?", "Download your conversation first?"), isPresented: $showDownloadFirst) {
                Button(app.T("Tải tất cả", "Download everything")) {
                    intent = .deleteAfter
                    startExport()
                }
                Button(app.T("Xoá không tải", "Delete without downloading"), role: .destructive) {
                    Task { _ = await app.deleteMyRefundDisputeCopy(claimID) }
                }
                Button(app.T("Huỷ", "Cancel"), role: .cancel) {}
            } message: {
                Text(app.T("Hãy lưu tin nhắn, ảnh và tệp trước khi xoá bản của bạn.",
                           "Save the messages, photos and files before deleting your copy."))
            }
            // The share sheet closed without a saved or shared result.
            .alert(app.T("Chưa lưu tệp tải về", "Download not saved"), isPresented: $showNotSaved) {
                Button(app.T("Thử lại", "Try again")) {
                    shareCompleted = false
                    sharing = true
                    sheetOpen = true
                }
                Button(app.T("Huỷ", "Cancel"), role: .cancel) { app.discardRefundDisputeExport() }
            } message: {
                Text(app.T("Bảng chia sẻ đã đóng mà chưa lưu. Chưa có gì bị xoá. Cuộc trò chuyện vẫn còn.",
                           "The share sheet closed without saving. Nothing was deleted. Your conversation is still available."))
            }
            // A separate, explicit deletion step after a completed share.
            .alert(app.T("Xoá bản của bạn ngay?", "Delete your copy now?"), isPresented: $showDeleteConfirm) {
                Button(app.T("Xoá bản của tôi", "Delete my copy"), role: .destructive) {
                    Task {
                        let ok = await app.deleteMyRefundDisputeCopy(claimID)
                        if !ok { app.discardRefundDisputeExport() }
                    }
                }
                Button(app.T("Giữ lại", "Keep my copy"), role: .cancel) { app.discardRefundDisputeExport() }
            } message: {
                Text(app.T("Chỉ tiếp tục nếu tệp đã được lưu ở nơi bạn muốn. Bản của bạn sẽ bị xoá khỏi tài khoản. Người tổ chức vẫn giữ bản ghi của họ đến khi hết hạn. Trạng thái hoàn tiền không thay đổi.",
                           "Only continue if your files are saved where you want them. Your copy is removed from your account. The organizer keeps their record until it expires. The refund status does not change."))
            }
            // Goer: confirming receipt also closes the dispute.
            .confirmationDialog(app.T("Xác nhận đã nhận tiền hoàn?", "Mark refund received?"),
                                isPresented: $showConfirmReceived, titleVisibility: .visible) {
                Button(app.T("Tải bản ghi trước", "Download transcript first")) {
                    intent = .downloadThenConfirm
                    startExport()
                }
                .accessibilityIdentifier("disputeFlow.confirmDownloadFirst")
                Button(app.T("Xác nhận và đóng tranh chấp", "Confirm and close dispute")) {
                    Task { _ = await app.confirmReceivedAndCloseDispute(claimID) }
                }
                .accessibilityIdentifier("disputeFlow.confirmAndClose")
                Button(app.T("Huỷ", "Cancel"), role: .cancel) {}
            } message: {
                Text(app.T("Việc này cũng sẽ đóng tranh chấp. Cuộc trò chuyện vẫn xem được trong 7 ngày. Chỉ xác nhận nếu tiền đã vào tài khoản của bạn. Bạn có muốn tải bản ghi trước không?",
                           "This also closes the dispute. The conversation stays readable for 7 days. Only confirm if the money is in your account. Do you want to download the transcript first?"))
            }
            .alert(app.T("Tải về không thành công", "Download failed"), isPresented: $showFailure) {
                Button(app.T("Thử lại", "Retry")) { startExport() }
                Button(app.T("Huỷ", "Cancel"), role: .cancel) { app.discardRefundDisputeExport() }
            } message: { Text(failureMessage) }
    }

    // MARK: Flow

    private func begin(_ r: RefundDisputeFlowRequest) {
        switch r {
        case .close:
            if isGoer { showGoerChoice = true } else { showHostClose = true }
        case .download:
            intent = .downloadOnly
            startExport()
        case .deleteCopy:
            guard isGoer else { return }
            showDownloadFirst = true
        case .confirmReceived:
            guard isGoer else { return }
            showConfirmReceived = true
        }
    }

    private func startExport() {
        sharing = false
        shareCompleted = false
        sheetOpen = true
        app.startRefundDisputeExport(claimID)
    }

    /// The share/progress sheet closed, by any route.
    private func sheetClosed() {
        guard sharing else { return }
        sharing = false
        switch intent {
        case .downloadOnly:
            // Nothing is promised or deleted. Just remove the temporary files.
            app.discardRefundDisputeExport()
        case .downloadThenConfirm:
            // Whether or not it was saved, go back to the confirmation so the
            // goer decides; nothing was confirmed or closed by downloading.
            app.discardRefundDisputeExport()
            afterSheetClosed { showConfirmReceived = true }
        case .deleteAfter:
            let saved = shareCompleted
            afterSheetClosed {
                if saved { showDeleteConfirm = true } else { showNotSaved = true }
            }
        }
    }

    /// Alerts can't present while a sheet is still animating away.
    private func afterSheetClosed(_ action: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            action()
        }
    }

    // MARK: Sheet

    @ViewBuilder
    private var sheetContent: some View {
        if sharing, let result = app.disputeExport.result, exportIsMine {
            BanbeShareSheet(items: [result.pdfURL, result.zipURL], onFinish: { completed in
                shareCompleted = completed
                sheetOpen = false
            })
        } else {
            progressView
        }
    }

    private var progressView: some View {
        let p = app.disputeExport.progress
        let phaseText: String = {
            guard let p else { return app.T("Đang bắt đầu…", "Starting…") }
            switch p.phase {
            case .downloading:
                return p.total == 0
                    ? app.T("Đang lấy bản ghi…", "Fetching the conversation…")
                    : app.T("Đang tải tệp \(min(p.done + 1, p.total)) trên \(p.total)", "Downloading file \(min(p.done + 1, p.total)) of \(p.total)")
            case .renderingPDF: return app.T("Đang tạo PDF…", "Creating the PDF…")
            case .buildingZIP: return app.T("Đang tạo gói ZIP…", "Creating the ZIP…")
            }
        }()
        return VStack(spacing: 14) {
            Text(app.T("Đang chuẩn bị bản tải về", "Preparing your download"))
                .font(.system(size: 16, weight: .bold))
            ProgressView(value: p?.fraction ?? 0)
                .accessibilityIdentifier("disputeFlow.progress")
            Text(phaseText)
                .font(.system(size: 13))
                .foregroundStyle(app.palette.ink.opacity(0.7))
            Text(app.T("Ảnh và tệp được tải về máy trước khi tạo PDF và ZIP.",
                       "Photos and files are downloaded to your phone before the PDF and ZIP are made."))
                .font(.system(size: 11.5))
                .foregroundStyle(app.palette.ink.opacity(0.55))
                .multilineTextAlignment(.center)
            Button(app.T("Huỷ", "Cancel")) {
                app.cancelRefundDisputeExport()
                sheetOpen = false
            }
            .accessibilityIdentifier("disputeFlow.cancelExport")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(app.palette.paper)
    }

    private var failureMessage: String {
        switch app.disputeExport.failure {
        case .attachments(let failed, let total):
            return app.T("\(failed) trên \(total) tệp đính kèm không tải được, nên bản tải về chưa đầy đủ. Cuộc trò chuyện vẫn còn.",
                         "\(failed) of \(total) attachments could not be downloaded, so the export is not complete. Your conversation is still available.")
        case .unavailable:
            return app.T("Bản ghi tranh chấp này không còn hoặc bạn không có quyền xem. Cuộc trò chuyện vẫn còn.",
                         "This dispute record is no longer available, or you do not have access. Your conversation is still available.")
        case .network, .write, .none:
            return app.T("Chưa tạo được bản tải về. Kiểm tra kết nối rồi thử lại. Cuộc trò chuyện vẫn còn.",
                         "Couldn't prepare the download. Check your connection and try again. Your conversation is still available.")
        }
    }

    /// Shared by the host dialog and the goer's choice dialog.
    static func closeNotice(_ app: AppState) -> String {
        app.T("Đóng sẽ dừng tin nhắn mới. Cuộc trò chuyện vẫn xem được trong 7 ngày. Đóng không xác nhận khoản hoàn. Khoản tiền vẫn cần được chuyển và xác nhận.",
              "Closing stops new messages. The conversation remains available for 7 days. Closing does not confirm the refund. Payment must still be sent and confirmed.")
    }
}

extension View {
    func refundDisputeFlows(claimID: UUID, request: Binding<RefundDisputeFlowRequest?>) -> some View {
        modifier(RefundDisputeFlows(claimID: claimID, request: request))
    }
}


/// The settlement area of an open refund dispute, shared by the chat panel and
/// the refund card:
///   * the GOER sees "Mark refund received". The host already marked the refund
///     sent before the dispute, so nobody marks it again: confirming receipt is
///     what unlocks "Close dispute";
///   * why Close is locked, per role;
///   * the automatic close reminder (the dispute closes by itself 7 days after
///     it was opened; a notification also goes out on day 6).
struct DisputeSettlementBlock: View {
    @EnvironmentObject private var app: AppState
    let claimID: UUID
    let claim: RefundDisputeThread
    @Binding var request: RefundDisputeFlowRequest?

    private var autoCloseNote: String? {
        guard !claim.isCompleted, claim.claimStatus == "disputed", let at = claim.autoCloseAt else { return nil }
        if at.timeIntervalSinceNow <= 86400 {
            return app.T("Tranh chấp này sẽ tự đóng trong chưa đầy 24 giờ.", "This dispute closes automatically in less than 24 hours.")
        }
        let vi = formatShortDate(at, lang: "vi") ?? "", en = formatShortDate(at, lang: "en") ?? ""
        return app.T("Nếu không ai phản hồi, tranh chấp sẽ tự đóng vào \(vi).", "If nobody acts, this dispute closes automatically on \(en).")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if claim.canConfirmReceived {
                Button {
                    request = .confirmReceived
                } label: {
                    Text(app.T("Tôi đã nhận được tiền hoàn", "Mark refund received"))
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .foregroundStyle(app.palette.paper)
                }
                .buttonStyle(.plain)
                .disabled(app.refundActionBusy != nil)
                .opacity(app.refundActionBusy != nil ? 0.5 : 1)
                .accessibilityIdentifier("disputeSettlement.confirmReceived")
            }
            if !claim.isCompleted, !claim.refundSettled {
                Text(claim.viewerRole == "guest"
                     ? app.T("Xác nhận bạn đã nhận được tiền hoàn. Việc này cũng sẽ đóng tranh chấp.",
                             "Confirm that you received the refund. This also closes the dispute.")
                     : app.T("Bạn có thể đóng tranh chấp này sau khi khách xác nhận đã nhận được tiền hoàn.",
                             "You can close this dispute after the guest confirms the refund was received."))
                    .font(.system(size: 10.5)).foregroundStyle(app.palette.ink.opacity(0.6))
                    .accessibilityIdentifier("disputeSettlement.lockedHint")
            }
            if let autoCloseNote {
                Text(autoCloseNote)
                    .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(app.palette.ink.opacity(0.7))
                    .accessibilityIdentifier("disputeSettlement.autoClose")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Earlier dispute rounds on the same refund claim, shown read only under the
/// current dispute. A new dispute never overwrites them: each keeps its own
/// messages until its own 7 day purge.
struct PreviousDisputeRounds: View {
    @EnvironmentObject private var app: AppState
    let claimID: UUID
    @State private var expanded: Set<UUID> = []

    var body: some View {
        let rounds = app.refundDisputeRounds[claimID] ?? []
        if !rounds.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(rounds.enumerated()), id: \.element.id) { index, round in
                    let isOpen = expanded.contains(round.id)
                    Button {
                        if isOpen { expanded.remove(round.id) } else {
                            expanded.insert(round.id)
                            Task { await app.loadRefundDisputeRoundMessages(round) }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(label(round, number: rounds.count - index))
                                .font(.system(size: 11.5, weight: .semibold))
                            Spacer(minLength: 0)
                            Image(systemName: isOpen ? "chevron.up" : "chevron.down").font(.system(size: 10))
                        }
                        .foregroundStyle(app.palette.ink.opacity(0.75))
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("disputeRounds.row")
                    if isOpen {
                        let messages = app.refundDisputeRoundMessages[round.id]
                        VStack(alignment: .leading, spacing: 4) {
                            if messages == nil {
                                BanbeLoadingVisual(size: 28)
                            } else {
                                ForEach(messages ?? []) { m in
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(who(m) + " ▪︎ " + m.createdAt.formatted())
                                            .font(.system(size: 9.5)).foregroundStyle(app.palette.ink.opacity(0.5))
                                        Text(m.hasAttachment
                                             ? (m.isImageAttachment ? app.T("Đã gửi một ảnh", "Sent a photo") : app.T("Đã gửi một tệp", "Sent a file"))
                                             : m.body)
                                            .font(.system(size: 12)).foregroundStyle(app.palette.ink)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                        .padding(.leading, 8)
                    }
                    Divider().overlay(app.palette.rule)
                }
            }
        }
    }

    private func label(_ r: DisputeRound, number: Int) -> String {
        let when = r.closedAt.map { formatShortDate($0, lang: app.isEN ? "en" : "vi") ?? "" } ?? ""
        return app.T("Tranh chấp trước, lần \(number), đã đóng \(when)", "Earlier dispute \(number), closed \(when)")
    }

    private func who(_ m: DisputeMessage) -> String {
        switch m.senderRole {
        case "organizer": return m.senderId == app.userID ? app.T("Bạn", "You") : app.T("Người tổ chức", "Organizer")
        case "guest": return m.senderId == app.userID ? app.T("Bạn", "You") : app.T("Khách", "Guest")
        default: return app.T("Hệ thống", "System")
        }
    }
}
