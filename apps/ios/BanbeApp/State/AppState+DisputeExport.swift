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

extension AppState {
    /// The goer says the money arrived, straight from the dispute. The host does
    /// not have to mark anything sent again. Result is checked (never optimistic):
    /// on success the claim is guest_confirmed, which unlocks "Close dispute".
    func confirmRefundReceivedFromDispute(_ claimID: UUID) async -> Bool {
        guard refundActionBusy == nil else { return false }
        refundActionBusy = claimID
        disputeCloseError = ""
        defer { refundActionBusy = nil }
        do {
            let result: ForfeitResult = try await SupabaseService.client
                .rpc("confirm_refund_received", params: ["p_claim_id": claimID.uuidString])
                .execute().value
            guard result.success == true else {
                disputeCloseError = T("Chưa xác nhận được. Thử lại nhé.", "Couldn't confirm. Please try again.")
                return false
            }
            Haptics.success()
        } catch {
            print("confirmRefundReceivedFromDispute failed:", error)
            disputeCloseError = T("Chưa xác nhận được. Thử lại nhé.", "Couldn't confirm. Please try again.")
            return false
        }
        await loadRefundDisputeThread(claimID, force: true)
        if let claim = refundDisputeThreads[claimID], conversationRefundDispute?.refundClaimId == claimID {
            conversationRefundDispute = claim
        }
        reloadRefundClaimEverywhere(claimID)
        return true
    }
}

extension AppState {
    /// "Mark refund received" for a goer: confirms receipt, then closes the
    /// dispute (closing is allowed once the claim is guest_confirmed). If the
    /// confirmation succeeds but the close fails, the dispute stays open with
    /// Close unlocked and the error is shown.
    func confirmReceivedAndCloseDispute(_ claimID: UUID) async -> Bool {
        guard await confirmRefundReceivedFromDispute(claimID) else { return false }
        return await closeRefundDispute(claimID)
    }
}

extension AppState {
    private struct RoundsResponse: Decodable { let rounds: [DisputeRound] }

    /// Earlier closed rounds of this claim's disputes, newest first.
    func loadRefundDisputeRounds(_ claimID: UUID) async {
        guard let response: RoundsResponse = try? await SupabaseService.client
            .rpc("get_refund_dispute_rounds", params: ["p_claim_id": claimID.uuidString])
            .execute().value else { return }
        refundDisputeRounds[claimID] = response.rounds
    }

    /// Reads one earlier round's messages (participant RLS allows it while retained).
    func loadRefundDisputeRoundMessages(_ round: DisputeRound) async {
        guard let rows: [DisputeMessage] = try? await SupabaseService.client
            .from("dispute_messages").select()
            .eq("dispute_thread_id", value: round.disputeThreadId.uuidString)
            .order("created_at", ascending: true)
            .execute().value else { return }
        refundDisputeRoundMessages[round.disputeThreadId] = rows
    }
}
