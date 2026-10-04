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

    private enum Intent { case downloadOnly, deleteAfter }

    @State private var intent: Intent = .downloadOnly
    @State private var showHostClose = false
    @State private var showGoerChoice = false
    @State private var showDownloadFirst = false
    @State private var showDeleteConfirm = false
    @State private var showNotSaved = false
    @State private var showFailure = false
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
        case .deleteAfter:
            let saved = shareCompleted
            afterSheetClosed {
                if saved { showDeleteConfirm = true } else { showNotSaved = true }
            }
        }
    }

    /// Alerts can't present while a sheet is still animating away.
    private func afterSheetClosed(_ action: @escaping () -> Void) {
        Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            await MainActor.run(body: action)
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
