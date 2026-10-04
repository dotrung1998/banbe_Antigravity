import Foundation
import Supabase

/// What the UI needs to know about the dispute export in flight.
struct DisputeExportState: Equatable {
    enum Status: Equatable { case idle, running, ready, failed }
    enum Failure: Equatable {
        case attachments(failed: Int, total: Int)
        case unavailable      // transcript purged, not found, or not a party
        case network
        case write
    }
    var status: Status = .idle
    var claimID: UUID?
    var progress: DisputeExportProgress?
    var result: DisputeExportResult?
    var failure: Failure?
}

extension AppState {
    /// Builds the complete export (PDF + ZIP with the real attachment bytes)
    /// for one dispute. Never presents anything and never deletes anything:
    /// the caller decides what happens next from `disputeExport`.
    func startRefundDisputeExport(_ claimID: UUID) {
        disputeExportTask?.cancel()
        DisputeExporter.remove(disputeExport.result)
        DisputeExporter.purgeStale()
        disputeExport = DisputeExportState(status: .running, claimID: claimID,
                                           progress: .init(phase: .downloading, done: 0, total: 0, fraction: 0))
        let isEN = self.isEN
        disputeExportTask = Task { @MainActor [weak self] in
            guard let self else { return }
            @MainActor func fail(_ f: DisputeExportState.Failure) {
                guard !Task.isCancelled else { return }
                disputeExport = DisputeExportState(status: .failed, claimID: claimID, failure: f)
            }
            let transcript: RefundDisputeTranscript
            do {
                transcript = try await SupabaseService.client
                    .rpc("get_refund_dispute_transcript", params: ["p_claim_id": claimID.uuidString])
                    .execute().value
            } catch {
                print("startRefundDisputeExport transcript failed:", error)
                return fail(.network)
            }
            guard transcript.found else { return fail(.unavailable) }
            let bucket = DisputeAttachments.bucket
            do {
                let result = try await DisputeExporter.build(
                    transcript: transcript, isEN: isEN,
                    downloader: { path in
                        try await SupabaseService.client.storage.from(bucket).download(path: path)
                    },
                    progress: { [weak self] p in
                        Task { @MainActor [weak self] in
                            guard let self, self.disputeExport.status == .running, self.disputeExport.claimID == claimID else { return }
                            self.disputeExport.progress = p
                        }
                    })
                guard !Task.isCancelled else { DisputeExporter.remove(result); return }
                disputeExport = DisputeExportState(status: .ready, claimID: claimID, result: result)
            } catch is CancellationError {
                return
            } catch let DisputeExportError.attachmentsFailed(failed, total) {
                fail(.attachments(failed: failed, total: total))
            } catch {
                print("startRefundDisputeExport build failed:", error)
                fail(.write)
            }
        }
    }

    /// Stops a running export and removes whatever it wrote. The dispute and
    /// its chat are untouched.
    func cancelRefundDisputeExport() {
        disputeExportTask?.cancel()
        disputeExportTask = nil
        DisputeExporter.remove(disputeExport.result)
        disputeExport = DisputeExportState()
    }

    /// Ends the export flow and deletes the temporary files.
    func discardRefundDisputeExport() { cancelRefundDisputeExport() }

    /// Closes the dispute if it is still open and removes THIS account's copy.
    /// GOER ONLY (the server refuses anyone else). The shared record stays for
    /// the host until the normal 7 day purge; refund status and the ordinary
    /// booking conversation are never touched.
    func deleteMyRefundDisputeCopy(_ claimID: UUID) async -> Bool {
        guard refundDisputeDeletingClaimId == nil, refundDisputeClosingClaimId == nil else { return false }
        refundDisputeDeletingClaimId = claimID
        disputeCloseError = ""
        defer { refundDisputeDeletingClaimId = nil }
        var ok = false
        do {
            let result: ForfeitResult = try await SupabaseService.client
                .rpc("delete_my_refund_dispute_copy", params: ["p_claim_id": claimID.uuidString])
                .execute().value
            if result.success == true {
                ok = true
                Haptics.success()
            } else if result.error == "NOT_AUTHORIZED" {
                disputeCloseError = T("Chỉ khách của yêu cầu hoàn tiền này mới xoá được bản của mình.",
                                      "Only the guest of this refund can delete their own copy.")
            } else if result.error == "REFUND_NOT_CONFIRMED" {
                disputeCloseError = T("Chưa đóng được. Người tổ chức cần đánh dấu đã hoàn tiền và khách cần xác nhận đã nhận trước.",
                                      "Can't close yet. The host must mark the refund sent and the guest must confirm it was received first.")
            } else if result.error == "ADMIN_RESOLUTION_REQUIRED" {
                disputeCloseError = T("Tranh chấp này đã được chuyển cho banbe xử lý nên không thể tự đóng ở đây.",
                                      "This dispute has been escalated to banbe, so it can't be closed here.")
            } else {
                disputeCloseError = T("Chưa xoá được bản của bạn. Thử lại nhé.", "Couldn't delete your copy. Please try again.")
            }
        } catch {
            print("deleteMyRefundDisputeCopy failed:", error)
            disputeCloseError = T("Chưa xoá được bản của bạn. Thử lại nhé.", "Couldn't delete your copy. Please try again.")
        }
        guard ok else { return false }

        // Every surface agrees at once: this account no longer holds the chat.
        refundDisputeDeletedCopies.insert(claimID)
        refundDisputeThreads.removeValue(forKey: claimID)
        if disputeChatRefundClaimId == claimID {
            disputeChatKey = nil
            disputeChatMessages = []
            disputeChatThread = nil
            disputeChatRefundClaimId = nil
            disputeChatInitialLoadDone = false
            disputeChatDraft = ""
            disputeAttachmentUrls = [:]
        }
        if conversationRefundDispute?.refundClaimId == claimID { conversationRefundDispute = nil }
        if expandedDisputeClaimId == claimID { expandedDisputeClaimId = nil }
        if disputeExport.claimID == claimID { discardRefundDisputeExport() }
        await loadDisputeChats()
        reloadRefundClaimEverywhere(claimID)
        return true
    }
}
