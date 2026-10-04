import Foundation
import Supabase
import UIKit
import Photos

// Payments and documents — the iOS half of what GocContext.jsx does for the
// web app. banbe never holds the money on either platform; what these carry
// is where to send it, the evidence it was sent, and the paperwork after.
extension AppState {

    // MARK: - What the guest owes, and to whom

    func loadPaymentBookings() async {
        guard let uid = userID else {
            paymentBookingsSeq += 1
            paymentBookings = []
            paymentsLoading = false
            return
        }
        let seq = { paymentBookingsSeq += 1; return paymentBookingsSeq }()
        paymentsLoading = true
        do {
            let rows: [PayableBookingRow] = try await SupabaseService.client
                .from("bookings")
                .select("""
                    id, qty, total_vnd, code, status, paid_marked_at, proof_uploaded_at, created_at, event_id,
                    payment_state, payment_ref, hold_expires_at, transaction_id, verify_due_at, dispute_reason, cancel_reason, nudge_count,
                    purchaser_id, recipient_name, recipient_email, recipient_dob, gifted_at, claim_code, claimed_at, claimed_by_user_id, admission_token,
                    events(name, organizers(name, pay_methods, bank_name, bank_account_name,
                                            bank_account_no, momo_phone, pay_note))
                    """)
                .or("user_id.eq.\(uid.uuidString),purchaser_id.eq.\(uid.uuidString)")
                .order("created_at", ascending: false)
                .execute().value
            // Only the newest in-flight call may write state — see
            // paymentBookingsSeq's own doc comment (AppState.swift).
            guard seq == paymentBookingsSeq else { return }
            paymentBookings = rows.map(\.asPayable)
            paymentsLoading = false
        } catch {
            print("loadPaymentBookings failed:", error)
            guard seq == paymentBookingsSeq else { return }
            paymentBookings = []
            paymentsLoading = false
        }
    }

    func openPaymentDetails(_ bookingID: UUID, back: Screen = .profile) {
        paymentBookingID = bookingID
        paymentBack = back
        paymentProofError = ""
        screen = .paymentDetails
        Task { await loadPaymentBookings() }
    }

    /// Copy with a short "copied" flash, keyed by field so only the row that
    /// was tapped changes its label.
    func copyPayField(_ field: String, _ value: String) {
        UIPasteboard.general.string = value
        paymentCopied = field
        Haptics.light()
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if paymentCopied == field { paymentCopied = "" }
        }
    }

    /// The guest's "I've transferred" evidence. Note what it does NOT do:
    /// mark the booking paid. Only the organizer, who can see their own
    /// account, gets to say the money arrived.
    func uploadPaymentProof(bookingID: UUID, imageData: Data, fileExtension: String = "jpg") async {
        paymentProofUploading = true
        paymentProofError = ""
        do {
            // The first path segment is the booking id, which is exactly what
            // the bucket's RLS policies split on — a file can only land under
            // a booking the uploader owns. Lowercased: the policy compares
            // this raw text against `bookings.id::text`, and Postgres's own
            // uuid-to-text cast is always lowercase — Foundation's
            // `UUID.uuidString`, unlike Postgres, is UPPERCASE, so an
            // un-lowercased path here reads as a completely different
            // string to `split_part(name, '/', 1) = b.id::text` and the
            // INSERT is rejected as not matching any booking at all (a
            // storage 403 "new row violates row-level security policy",
            // not an actual ownership problem).
            let path = "\(bookingID.uuidString.lowercased())/proof-\(Int(Date().timeIntervalSince1970)).\(fileExtension)"
            _ = try await SupabaseService.client.storage
                .from("pay-proof")
                .upload(path, data: imageData,
                        options: FileOptions(contentType: fileExtension == "pdf" ? "application/pdf" : "image/jpeg",
                                             upsert: true))
            _ = try await SupabaseService.client
                .rpc("mark_payment_proof", params: [
                    "p_booking": bookingID.uuidString,
                    "p_path": path,
                    "p_note": "",
                ])
                .execute()
            paymentProofUploading = false
            await loadPaymentBookings()
        } catch {
            print("uploadPaymentProof failed:", error)
            paymentProofUploading = false
            paymentProofError = T("Không gửi được ảnh xác nhận. Thử lại nhé.",
                                  "Couldn't send that confirmation. Please try again.")
        }
    }

    /// 14-organizer-checkin.md (Bug 1 follow-up): the guest's ONE actionable
    /// control while awaiting the organizer's confirm window — nudges via
    /// the same in-app toast + bell notification every other event in this
    /// lifecycle already uses (no real push infra, see 07-notifications.md).
    /// Rate-limited server-side to 2 uses per hold (nudge_organizer() RPC,
    /// migration 059) — this only reflects that limit, it doesn't enforce
    /// its own separate one.
    func nudgeOrganizer(bookingID: UUID) async {
        nudgeSending = true
        nudgeError = ""
        do {
            let result: NudgeResult = try await SupabaseService.client
                .rpc("nudge_organizer", params: ["p_booking": bookingID.uuidString])
                .execute().value
            nudgeSending = false
            guard result.success == true else {
                nudgeError = result.error == "NUDGE_LIMIT_REACHED"
                    ? T("Bạn đã nhắc tối đa 2 lần cho lượt giữ chỗ này.", "You've already nudged the max 2 times for this hold.")
                    : T("Không gửi được lời nhắc. Thử lại nhé.", "Couldn't send the nudge. Please try again.")
                return
            }
            if let idx = paymentBookings.firstIndex(where: { $0.id == bookingID }) {
                paymentBookings[idx].nudgeCount = result.nudgeCount ?? paymentBookings[idx].nudgeCount
            }
        } catch {
            nudgeSending = false
            nudgeError = T("Không gửi được lời nhắc. Thử lại nhé.", "Couldn't send the nudge. Please try again.")
        }
    }

    // 15-organizer-checkin.md follow-up: ConfirmedView's "Xem Receipt"
    // needs to know, per booking, whether a live payment_documents receipt
    // already exists before deciding whether tapping it opens that file or
    // sends a request instead.
    func loadReceiptStatus(bookingID: UUID) async {
        do {
            let docs: [PaymentDocument] = try await SupabaseService.client
                .from("payment_documents").select("*")
                .eq("booking_id", value: bookingID.uuidString)
                .eq("kind", value: "receipt")
                .is("superseded_at", value: nil)
                .execute().value
            receiptDoc = docs.first
            receiptChecked = true
        } catch {
            print("loadReceiptStatus failed:", error)
            receiptDoc = nil
            receiptChecked = true
        }
    }

    func requestReceipt(bookingID: UUID) async {
        receiptRequestSending = true
        receiptRequestError = ""
        do {
            let result: RequestReceiptResult = try await SupabaseService.client
                .rpc("request_receipt", params: ["p_booking": bookingID.uuidString])
                .execute().value
            receiptRequestSending = false
            guard result.success == true else {
                receiptRequestError = result.error == "ALREADY_REQUESTED_RECENTLY"
                    ? T("Bạn vừa yêu cầu gần đây, hãy đợi người tổ chức phản hồi.", "You already asked recently, give the organizer a little time to respond.")
                    : T("Không gửi được yêu cầu. Thử lại nhé.", "Couldn't send the request. Please try again.")
                return
            }
            receiptRequestSent = true
        } catch {
            receiptRequestSending = false
            receiptRequestError = T("Không gửi được yêu cầu. Thử lại nhé.", "Couldn't send the request. Please try again.")
        }
    }

    // MARK: - Billing identity (the buyer block on every document)

    func openBilling() {
        billingError = ""
        billingSaved = false
        screen = .billing
        Task {
            guard let uid = userID else { return }
            do {
                let row: BillingRow? = try await SupabaseService.client
                    .from("profiles")
                    .select("display_name, phone, billing_name, billing_address, billing_phone, billing_tax_code")
                    .eq("id", value: uid.uuidString)
                    .single().execute().value
                guard let row else { return }
                billingName = row.billingName.isEmpty ? row.displayName : row.billingName
                billingAddress = row.billingAddress
                billingPhone = row.billingPhone.isEmpty ? row.phone : row.billingPhone
                billingTaxCode = row.billingTaxCode
            } catch {
                print("openBilling load failed:", error)
            }
        }
    }

    func saveBillingDetails() async {
        billingSaving = true
        billingError = ""
        billingSaved = false
        do {
            _ = try await SupabaseService.client
                .rpc("save_billing_details", params: [
                    "p_name": billingName,
                    "p_address": billingAddress,
                    "p_phone": billingPhone,
                    "p_tax_code": billingTaxCode,
                ])
                .execute()
            billingSaving = false
            billingSaved = true
        } catch {
            print("saveBillingDetails failed:", error)
            billingSaving = false
            billingError = T("Chưa lưu được. Thử lại nhé.", "Couldn't save. Please try again.")
        }
    }

    // MARK: - Payout details (where the organizer wants to be paid)

    func openPayout() {
        payoutError = ""
        payoutQRError = ""
        payoutSaved = false
        screen = .payout
        Task { await loadPayoutQR() }
        Task {
            guard let orgID = myOrganizerIDs.first else { return }
            do {
                let row: PayoutRow? = try await SupabaseService.client
                    .from("organizers")
                    .select("bank_name, bank_account_name, bank_account_no, momo_phone, pay_note, billing_address, tax_code")
                    .eq("id", value: orgID)
                    .single().execute().value
                guard let row else { return }
                payoutBankName = row.bankName
                payoutAccountName = row.bankAccountName
                payoutAccountNo = row.bankAccountNo
                payoutMomo = row.momoPhone
                payoutNote = row.payNote
                payoutAddress = row.billingAddress
                payoutTaxCode = row.taxCode
            } catch {
                print("openPayout load failed:", error)
            }
        }
    }

    func savePayoutDetails() async {
        guard let orgID = myOrganizerIDs.first else {
            payoutError = T("Chưa có trang tổ chức.", "No host page yet.")
            return
        }
        payoutSaving = true
        payoutError = ""
        payoutSaved = false
        do {
            _ = try await SupabaseService.client
                .rpc("save_organizer_payment", params: [
                    "p_organizer": orgID,
                    "p_bank_name": payoutBankName,
                    "p_bank_account_name": payoutAccountName,
                    "p_bank_account_no": payoutAccountNo,
                    "p_momo_phone": payoutMomo,
                    "p_pay_note": payoutNote,
                    "p_billing_address": payoutAddress,
                    "p_tax_code": payoutTaxCode,
                ])
                .execute()
            payoutSaving = false
            payoutSaved = true
        } catch {
            print("savePayoutDetails failed:", error)
            payoutSaving = false
            payoutError = T("Chưa lưu được. Thử lại nhé.", "Couldn't save. Please try again.")
        }
    }

    // MARK: - The documents

    // Sub-section-of-a-group back-navigation fix (2026-09-29) — `back`
    // records where to return to (see `documentsListBack`'s own doc
    // comment, AppState.swift); every current call site is a row inside
    // AccountGroupView's "payments" group page, so the default matches
    // that without every caller needing to pass it explicitly.
    func openDocuments(kind: String, role: String, back: Screen = .accountGroup) {
        documentsKind = kind
        documentsRole = role
        documents = []
        documentsListBack = back
        screen = .documents
        Task { await loadDocuments() }
    }

    func loadDocuments() async {
        guard let uid = userID else {
            documents = []
            documentsLoading = false
            return
        }
        documentsLoading = true
        do {
            // Documents are organizer-uploaded now (migration 056). Lists
            // BOTH the live document AND any still-live superseded copy
            // (purge_after > now(), Task 5's 24h soft-delete grace window)
            // — until this pass that old copy was only ever a bare count on
            // Attendance, with no way to actually open it before it's gone
            // for good (08-payment-documents.md's 2026-09-17 follow-up #7 —
            // BUG 1). RLS doesn't gate on superseded_at, so this is purely a
            // query-filter change. Once purge_after passes the row is
            // hard-deleted by the purge cron and simply stops matching.
            //
            // `events(...)` embeds via the event_id FK — needed because an
            // uploaded file's row leaves the `event` jsonb column at its
            // '{}' default (only event_id is set), confirmed live
            // (08-payment-documents.md's 2026-09-17 follow-up #4) — the web
            // side's loadDocuments() (GocContext.jsx) embeds the same way.
            let nowIso = ISO8601DateFormatter().string(from: Date())
            var query = SupabaseService.client
                .from("payment_documents").select("*, events(name, starts_at, event_date, event_time)")
                .eq("kind", value: documentsKind)
                .or("superseded_at.is.null,purge_after.gt.\(nowIso)")

            if documentsRole == "host" {
                // An organizer is usually also a goer, so leaning on RLS alone
                // would mix their own tickets into "documents I issued".
                guard !myOrganizerIDs.isEmpty else {
                    documents = []
                    documentsLoading = false
                    return
                }
                query = query.in("organizer_id", values: myOrganizerIDs)
            } else {
                query = query.eq("user_id", value: uid.uuidString)
            }

            documents = try await query.order("issued_at", ascending: false).execute().value
            documentsLoading = false
        } catch {
            print("loadDocuments failed:", error)
            documents = []
            documentsLoading = false
        }
    }

    func openDocument(_ id: UUID, backTo: Screen = .documents) {
        documentID = id
        documentBack = backTo
        screen = .documentView
        documentFileURL = nil
        documentFileURLFailed = false
        documentFileURLErrorDetail = ""
        if let path = documents.first(where: { $0.id == id })?.filePath, !path.isEmpty {
            Task {
                let url = await signedDocumentFileURL(path)
                documentFileURL = url
                if url == nil { documentFileURLFailed = true }
            }
        }
    }

    /// Retries fetching the current document's signed URL — the "Try again"
    /// button DocumentViewerView shows once `documentFileURLFailed` is set.
    func retryDocumentFileURL() {
        guard let doc = currentDocument, let path = doc.filePath, !path.isEmpty else { return }
        documentFileURLFailed = false
        documentFileURLErrorDetail = ""
        Task {
            let url = await signedDocumentFileURL(path)
            documentFileURL = url
            if url == nil { documentFileURLFailed = true }
        }
    }

    var currentDocument: PaymentDocument? {
        documents.first { $0.id == documentID }
    }

    /// The URL the LEGACY document viewer loads — only for a document with
    /// no file_path (issued before migration 056's switch to organizer
    /// uploads). Rendering happens server-side with the very same module
    /// the web app prints from (api/payment-document.js), so a receipt
    /// can't look one way on iOS and another on the web. The access token
    /// goes in a header, set on the web view's own request.
    func documentURL(_ id: UUID) -> URL? {
        URL(string: "\(AppConfig.apiBaseURL)/api/payment-document?id=\(id.uuidString.lowercased())&lang=\(lang)")
    }

    /// A signed URL for an uploaded document's own file — the bucket is
    /// private (RLS-scoped to the booking's guest/organizer), so a plain
    /// public URL won't load it.
    ///
    /// 15-organizer-checkin.md follow-up (Bug 1): a failure here used to
    /// return nil with nothing else — `documentFileURL` stayed nil forever,
    /// which `DocumentViewerView` renders as a bare, permanent
    /// `ProgressView()` with no error, no retry, and no way to tell a
    /// genuine failure apart from "still loading". A 12s timeout is added
    /// here so a hung request (no network, a slow signed-URL round trip)
    /// surfaces the same way an outright error does, instead of spinning
    /// forever — `openDocument`/`openDocumentFromNotification` set
    /// `documentFileURLFailed` when this returns nil either way.
    func signedDocumentFileURL(_ path: String) async -> URL? {
        let (url, detail) = await signedDocumentFileURLResult(path)
        if url == nil { documentFileURLErrorDetail = detail } else { documentFileURLErrorDetail = "" }
        return url
    }

    /// `(url, errorDetail)` — `errorDetail` is only meaningful when `url` is
    /// nil. Kept separate from `signedDocumentFileURL()`'s `URL?` return so
    /// the reason a real-device repro actually failed (a thrown auth/network
    /// error vs. a per-path `.failure` from the sign API vs. the 12s
    /// timeout) is preserved instead of collapsing into one undifferentiated
    /// nil, the way it did through two straight investigation passes.
    private func signedDocumentFileURLResult(_ path: String) async -> (URL?, String) {
        await withTaskGroup(of: (URL?, String).self) { group in
            group.addTask {
                do {
                    let results = try await SupabaseService.client.storage
                        .from("payment-documents")
                        .createSignedURLs(paths: [path], expiresIn: 600)
                    for result in results {
                        switch result {
                        case let .success(resultPath, signedURL) where resultPath == path:
                            return (signedURL, "")
                        case let .failure(resultPath, error) where resultPath == path:
                            return (nil, "sign API failure: \(error)")
                        default:
                            continue
                        }
                    }
                    return (nil, "sign API returned no matching result for path")
                } catch {
                    print("signedDocumentFileURL failed:", error)
                    return (nil, "sign request threw: \(error)")
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                return (nil, "timed out after 12s")
            }
            // Whichever finishes first wins — a genuine failure and a
            // timeout both mean "no URL", so nothing needs to distinguish
            // them here; the caller only cares whether it got one (the
            // *reason* is still kept, for display, above).
            let first = await group.next() ?? (nil, "")
            group.cancelAll()
            return first
        }
    }

    /// The organizer's replacement for the old auto-generation (Task 2):
    /// uploads a real file to the private 'payment-documents' bucket, then
    /// upload_payment_document() (migration 056) records it — supersedes
    /// whatever live document of this kind existed for the booking only
    /// when `reason` is non-empty (the RPC itself requires one exactly when
    /// there's something to replace), and writes the in-app notification.
    /// The email (Task 4/6) is a separate, best-effort call to /api/notify,
    /// same "client calls it right after its own action succeeds" pattern
    /// as the rest of this file's notify calls.
    @discardableResult
    func uploadPaymentDocument(bookingID: UUID, kind: String, fileData: Data, fileExtension: String, reason: String = "") async -> Bool {
        documentUploading = true
        documentUploadError = ""
        do {
            let contentType = fileExtension == "pdf" ? "application/pdf" : "image/jpeg"
            let path = "\(bookingID.uuidString.lowercased())/\(kind)-\(Int(Date().timeIntervalSince1970)).\(fileExtension)"
            _ = try await SupabaseService.client.storage
                .from("payment-documents")
                .upload(path, data: fileData, options: FileOptions(contentType: contentType, upsert: true))

            let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            // The SQL function treats an empty string the same as SQL NULL
            // (NULLIF(btrim(...), '')) — matching mark_payment_proof's own
            // "p_note": "" convention above rather than needing an Optional
            // value type in this params dictionary.
            let doc: PaymentDocument = try await SupabaseService.client
                .rpc("upload_payment_document", params: [
                    "p_booking": bookingID.uuidString, "p_kind": kind, "p_file_path": path,
                    "p_upload_reason": trimmedReason,
                ])
                .execute().value

            if let token = try? await SupabaseService.client.auth.session.accessToken {
                var request = URLRequest(url: URL(string: "\(AppConfig.apiBaseURL)/api/notify")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "content-type")
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.httpBody = try? JSONSerialization.data(withJSONObject: [
                    "type": trimmedReason.isEmpty ? "document_uploaded" : "document_replaced",
                    "documentId": doc.id.uuidString,
                ])
                _ = try? await URLSession.shared.data(for: request)
            }

            documentUploading = false
            return true
        } catch {
            print("uploadPaymentDocument failed:", error)
            documentUploading = false
            // upload_payment_document() (056) raises one of these exact
            // codes — surface whichever one it actually was instead of
            // collapsing every failure into the same generic message
            // (08-payment-documents.md's 2026-09-17 follow-up #5).
            let raw = "\(error)"
            if raw.contains("REASON_REQUIRED") {
                documentUploadError = T("Cần nêu lý do khi thay thế chứng từ đã có.", "A reason is required when replacing an existing document.")
            } else if raw.contains("FILE_REQUIRED") {
                documentUploadError = T("Vui lòng chọn tệp.", "Please choose a file.")
            } else if raw.contains("NOT_AUTHORIZED") {
                documentUploadError = T("Bạn không có quyền tải lên cho đơn này.", "You're not authorized to upload for this booking.")
            } else if raw.contains("BOOKING_NOT_FOUND") {
                documentUploadError = T("Không tìm thấy đơn đặt chỗ này.", "Couldn't find that booking.")
            } else {
                documentUploadError = T("Không tải lên được. Thử lại nhé.", "Couldn't upload. Please try again.")
            }
            return false
        }
    }

    // MARK: - The organizer's "mark as paid"

    /// confirm_payment issues the receipt and notifies the guest in the same
    /// transaction (migration 024), which is what makes this one action
    /// rather than a second step an organizer could forget.
    func markGuestPaid(_ bookingID: UUID, method: String = "bank") async {
        do {
            _ = try await SupabaseService.client
                .rpc("confirm_payment", params: ["p_booking": bookingID.uuidString, "p_method": method])
                .execute()
            Haptics.success()
            // 15-organizer-checkin.md follow-up: confirm_payment() (migration
            // 060) now flips payment_state to 'confirmed' server-side too,
            // not just status — but PaymentViews' countdown, both Home
            // banners, and the Verifications queue all read client-side
            // state only refreshed by their own poll/mount otherwise. Patch
            // all three in place immediately so none of them linger.
            if let idx = paymentBookings.firstIndex(where: { $0.id == bookingID }) {
                paymentBookings[idx].paymentState = .confirmed
                paymentBookings[idx].holdExpiresAt = nil
                paymentBookings[idx].verifyDueAt = nil
            }
            verifications.removeAll { $0.bookingId == bookingID }
            if booking?.id == bookingID {
                booking?.status = "confirmed"
                booking?.paymentState = .confirmed
                booking?.holdExpiresAt = nil
                booking?.verifyDueAt = nil
            }
            if let key = attendanceEventKey { await loadAttendanceGuests(key) }
        } catch {
            print("markGuestPaid failed:", error)
        }
    }
}

// MARK: - Row shapes used only for decoding

private struct BookingIDRow: Decodable { let id: UUID }

private struct HoldingRow: Decodable {
    let holdExpiresAt: Date?
    enum CodingKeys: String, CodingKey { case holdExpiresAt = "hold_expires_at" }
}

private struct BillingRow: Decodable {
    let displayName: String
    let phone: String
    let billingName: String
    let billingAddress: String
    let billingPhone: String
    let billingTaxCode: String

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case phone
        case billingName = "billing_name"
        case billingAddress = "billing_address"
        case billingPhone = "billing_phone"
        case billingTaxCode = "billing_tax_code"
    }
}

private struct PayoutRow: Decodable {
    let bankName: String
    let bankAccountName: String
    let bankAccountNo: String
    let momoPhone: String
    let payNote: String
    let billingAddress: String
    let taxCode: String

    enum CodingKeys: String, CodingKey {
        case bankName = "bank_name"
        case bankAccountName = "bank_account_name"
        case bankAccountNo = "bank_account_no"
        case momoPhone = "momo_phone"
        case payNote = "pay_note"
        case billingAddress = "billing_address"
        case taxCode = "tax_code"
    }
}

private struct PayableBookingRow: Decodable {
    let id: UUID
    let qty: Int
    let totalVnd: Int
    let code: String?
    let status: String
    let paidMarkedAt: Date?
    let proofUploadedAt: Date?
    let eventId: String
    let paymentState: String?
    let paymentRef: String?
    let holdExpiresAt: Date?
    let transactionId: String?
    let verifyDueAt: Date?
    let disputeReason: String?
    let cancelReason: String?
    let nudgeCount: Int?
    let purchaserId: UUID?
    let recipientName: String?
    let recipientEmail: String?
    let recipientDob: String?
    let giftedAt: Date?
    let claimCode: String?
    let claimedAt: Date?
    let claimedByUserId: UUID?
    let admissionToken: UUID?
    let events: EventRow?

    struct EventRow: Decodable {
        let name: String?
        let organizers: OrganizerRow?
    }
    struct OrganizerRow: Decodable {
        let name: String?
        let payMethods: [String]?
        let bankName: String?
        let bankAccountName: String?
        let bankAccountNo: String?
        let momoPhone: String?
        let payNote: String?

        enum CodingKeys: String, CodingKey {
            case name
            case payMethods = "pay_methods"
            case bankName = "bank_name"
            case bankAccountName = "bank_account_name"
            case bankAccountNo = "bank_account_no"
            case momoPhone = "momo_phone"
            case payNote = "pay_note"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, qty, code, status, events
        case totalVnd = "total_vnd"
        case paidMarkedAt = "paid_marked_at"
        case proofUploadedAt = "proof_uploaded_at"
        case eventId = "event_id"
        case paymentState = "payment_state"
        case paymentRef = "payment_ref"
        case holdExpiresAt = "hold_expires_at"
        case transactionId = "transaction_id"
        case verifyDueAt = "verify_due_at"
        case disputeReason = "dispute_reason"
        case cancelReason = "cancel_reason"
        case nudgeCount = "nudge_count"
        case purchaserId = "purchaser_id"
        case recipientName = "recipient_name"
        case recipientEmail = "recipient_email"
        case recipientDob = "recipient_dob"
        case giftedAt = "gifted_at"
        case claimCode = "claim_code"
        case claimedAt = "claimed_at"
        case claimedByUserId = "claimed_by_user_id"
        case admissionToken = "admission_token"
    }

    var asPayable: PayableBooking {
        let org = events?.organizers
        return PayableBooking(
            id: id, eventKey: eventId, qty: qty, totalVnd: totalVnd, code: code ?? "", status: status,
            paymentState: PaymentPhase(rawValue: paymentState ?? "holding") ?? .holding,
            paymentRef: paymentRef ?? "",
            holdExpiresAt: holdExpiresAt,
            transactionId: transactionId ?? "",
            verifyDueAt: verifyDueAt,
            paidMarkedAt: paidMarkedAt, proofUploadedAt: proofUploadedAt,
            eventName: events?.name ?? "",
            organizerName: org?.name ?? "",
            payMethods: org?.payMethods ?? [],
            bankName: org?.bankName ?? "",
            bankAccountName: org?.bankAccountName ?? "",
            bankAccountNo: org?.bankAccountNo ?? "",
            momoPhone: org?.momoPhone ?? "",
            payNote: org?.payNote ?? "",
            disputeReason: disputeReason,
            cancelReason: cancelReason,
            nudgeCount: nudgeCount ?? 0,
            purchaserId: purchaserId,
            recipientName: recipientName,
            recipientEmail: recipientEmail,
            recipientDob: recipientDob,
            giftedAt: giftedAt,
            claimCode: claimCode,
            claimedAt: claimedAt,
            claimedByUserId: claimedByUserId,
            admissionToken: admissionToken
        )
    }
}

// MARK: - Two-phase payment state machine (migrations 026/027)

extension AppState {

    /// PHASE 1 -> PHASE 2. The freeze is performed by submit_payment_proof on
    /// the server, never here: a countdown stopped only in client state would
    /// restart on relaunch and the seat would be swept out from under a buyer
    /// who had already paid.
    func submitPaymentProof(bookingID: UUID, imageData: Data,
                            transactionID: String, fileExtension: String = "jpg") async {
        let txn = transactionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !txn.isEmpty else {
            paymentProofError = T("Cần mã giao dịch.", "A transaction ID is required.")
            return
        }
        paymentProofUploading = true
        paymentProofError = ""
        do {
            // `.session` (not `.currentSession`) refreshes the token first if
            // it's stale — the 'pay-proof' bucket's INSERT policy checks
            // `auth.uid()` against the booking's owner, so an expired token
            // at upload time reads there as "not this user's booking" (a
            // confusing 403) rather than the auth problem it actually is.
            // Awaiting this first turns that into a precise AuthError
            // instead, and normally just re-validates an already-good token.
            _ = try await SupabaseService.client.auth.session

            // Lowercased: the RLS policy compares this raw path text against
            // `bookings.id::text`, and Postgres's own uuid-to-text cast is
            // always lowercase — Foundation's `UUID.uuidString`, unlike
            // Postgres, is UPPERCASE, so an un-lowercased path here reads as
            // a completely different string to `split_part(name, '/', 1) =
            // b.id::text` and the INSERT is rejected outright: exactly the
            // `StorageError(statusCode: "403", message: "new row violates
            // row-level security policy")` this was still failing with —
            // not an actual ownership or auth problem.
            let path = "\(bookingID.uuidString.lowercased())/proof-\(Int(Date().timeIntervalSince1970)).\(fileExtension)"
            _ = try await SupabaseService.client.storage
                .from("pay-proof")
                .upload(path, data: imageData,
                        options: FileOptions(contentType: fileExtension == "pdf" ? "application/pdf" : "image/jpeg",
                                             upsert: true))
            // The organizer's PHASE 2 response window — 60 minutes, not the
            // buyer's own PHASE 1 hold (30 minutes, hold_seats()'s
            // hold_minutes). Two independent clocks on two different
            // people; picking the wrong one here silently gave the
            // organizer a 15-minute window instead of the intended 60.
            let result: SubmitProofResult = try await SupabaseService.client
                .rpc("submit_payment_proof", params: SubmitProofParams(
                    booking: bookingID.uuidString, transactionID: txn, proofPath: path,
                    ip: nil, userAgent: "banbe-ios", slaMinutes: 60))
                .execute().value

            if result.success == false {
                paymentProofError = {
                    switch result.error ?? "" {
                    case "HOLD_EXPIRED_AND_SOLD_OUT":
                        return T("Rất tiếc, chỗ đã hết trong lúc chờ thanh toán. Hãy liên hệ người tổ chức để được hoàn tiền.",
                                 "Sorry — the seat sold out while this was pending. Contact the organizer for a refund.")
                    default:
                        // Not one of the friendly-copy cases above — still
                        // surface the RPC's own error code (BOOKING_NOT_FOUND,
                        // NOT_AUTHORIZED, INVALID_STATE, …) rather than a bare
                        // generic message with no way to tell which failed.
                        return T("Chưa gửi được. ", "Couldn't submit. ") + (result.error ?? "UNKNOWN_ERROR")
                    }
                }()
                paymentProofUploading = false
                return
            }

            paymentTxnId = ""
            paymentProofUploading = false
            Haptics.success()
            // Patch `paymentBookings` in place FIRST, before the refetch —
            // PaymentViews derives its rendered booking straight from this
            // array, so an immediate patch means the very next render
            // (including one after navigating away and straight back in,
            // which re-appears this screen and fires its own
            // loadPaymentBookings() again) can never race an in-flight
            // fetch and land on stale 'holding' data.
            if let idx = paymentBookings.firstIndex(where: { $0.id == bookingID }) {
                paymentBookings[idx].paymentState = .pendingVerification
                paymentBookings[idx].transactionId = txn
                paymentBookings[idx].verifyDueAt = result.verifyDueAt
            }
            await loadPaymentBookings()
        } catch {
            print("submitPaymentProof failed:", error)
            paymentProofUploading = false
            paymentProofError = Self.describeProofUploadError(error, T: T)
        }
    }

    /// Surfaces the *actual* failure instead of a generic "Couldn't submit"
    /// — a StorageError/PostgrestError's own status code and message name
    /// the real cause (an oversized file past the bucket's cap, an expired
    /// session so `auth.uid()` is null against storage's RLS check, a
    /// rejected MIME type, …) precisely, in contrast to `error.localizedDescription`
    /// on an arbitrary Swift `Error`, which is frequently just "The operation
    /// couldn't be completed." with no actionable detail at all.
    static func describeProofUploadError(_ error: Error, T: (String, String) -> String) -> String {
        let detail: String
        if let storageError = error as? StorageError {
            detail = "Storage" + (storageError.statusCode.map { " \($0)" } ?? "") + ": " + storageError.message
        } else if let postgrestError = error as? PostgrestError {
            detail = "DB" + (postgrestError.code.map { " \($0)" } ?? "") + ": " + postgrestError.message
        } else {
            detail = error.localizedDescription
        }
        return T("Chưa gửi được. ", "Couldn't submit. ") + detail
    }

    // MARK: Organizer verification queue

    /// Guarded here, not just by the organizer-mode-gated UI that links here
    /// (HomeView's banner, AccountView's "Awaiting verification" row) — this
    /// is the one place that actually decides whether the screen opens at
    /// all, so a participant navigating here by any other means (a replayed
    /// notification, …) still can't land on what is meant to be an
    /// organizer-only management screen. RLS already limits what data such
    /// a request could ever read (a participant only ever owns their own
    /// booking row), but this keeps them from seeing the screen's
    /// organizer-framed copy and action buttons ("Money received"/"Can't
    /// find it") over their own payment at all, not just from acting on it.
    func openVerifications(back: Screen = .profile) {
        guard canHost else { return }
        screen = .verifications
        verifications = []
        verificationsFocusBookingID = nil
        verificationsBack = back
        Task { await loadVerifications() }
    }

    /// Refund-discoverability fix — a dedicated "Refunds" row/entry point.
    /// Calls the EXACT SAME openVerifications() above (same gate, same
    /// screen, same data loaders) and only additionally sets a one-shot
    /// scroll flag — no duplicated backend/state logic, no second refund
    /// surface.
    func openVerificationsRefunds(back: Screen = .profile) {
        openVerifications(back: back)
        verificationsScrollAnchorID = "refundSection"
    }

    /// 14-organizer-checkin.md: Attendance's "Check payment" — jumps
    /// straight to this one booking's own row, whether it's the only
    /// pending item or buried far down a long queue. Same event-ownership
    /// guard as bug 1's openNotification() fix (myOrgEventKeys, not just
    /// the account-wide canHost check) since this is reachable from a bell
    /// notification tap too, not just Attendance's own (already-scoped) list.
    func openVerificationDetail(bookingID: UUID, eventKey: String?, back: Screen = .profile) {
        if let eventKey, !myOrgEventKeys.contains(eventKey) { return }
        guard canHost else { return }
        screen = .verifications
        verifications = []
        verificationsFocusBookingID = bookingID
        verificationsBack = back
        Task { await loadVerifications() }
    }

    // v_pending_verifications has no organizer filter of its own — it
    // relies on bookings' RLS, an OR of bookings_select_guest (own row) and
    // bookings_select_host (organizes the event). A plain guest's OWN
    // pending_verification booking came back too (via the guest policy)
    // and got miscounted as an organizer-facing "awaiting your OK" item.
    // Scope explicitly to organizer_id, same pattern loadOrganizerHoldingSummary
    // already uses below; only admins (bookings_select_admin RLS) see every
    // organizer's queue.
    func loadVerifications() async {
        guard userID != nil else { verifications = []; return }
        guard isAdmin || !myOrganizerIDs.isEmpty else { verifications = []; return }
        verificationsLoading = true
        do {
            var query = SupabaseService.client
                .from("v_pending_verifications").select()
            if !isAdmin {
                query = query.in("organizer_id", values: myOrganizerIDs)
            }
            verifications = try await query.order("proof_submitted_at", ascending: true).execute().value
        } catch {
            print("loadVerifications failed:", error)
            verifications = []
        }
        verificationsLoading = false
        await signProofUrls(verifications.compactMap(\.proofPath))
    }

    /// Signs every given 'pay-proof' path in one batched call and merges the
    /// result into `proofUrls` (path -> viewable URL, 10 minutes — long
    /// enough for one review pass). VerificationsView renders these — this
    /// is what an organizer actually needs to inspect the receipt before
    /// approving or rejecting, which nothing rendered before this.
    func signProofUrls(_ paths: [String]) async {
        let wanted = Array(Set(paths))
        guard !wanted.isEmpty else { return }
        do {
            let results = try await SupabaseService.client.storage
                .from("pay-proof")
                .createSignedURLs(paths: wanted, expiresIn: 600)
            for result in results {
                if case let .success(path, signedURL) = result {
                    proofUrls[path] = signedURL
                }
            }
        } catch {
            print("signProofUrls failed:", error)
        }
    }

    /// Signs 'refund-proof' paths (host's refund receipt) into `refundProofUrls`.
    func signRefundProofUrls(_ paths: [String]) async {
        let wanted = Array(Set(paths)).filter { refundProofUrls[$0] == nil }
        guard !wanted.isEmpty else { return }
        do {
            let results = try await SupabaseService.client.storage
                .from("refund-proof")
                .createSignedURLs(paths: wanted, expiresIn: 600)
            for result in results {
                if case let .success(path, signedURL) = result { refundProofUrls[path] = signedURL }
            }
        } catch {
            print("signRefundProofUrls failed:", error)
        }
    }

    func approvePayment(_ bookingID: UUID) async {
        verificationBusy = bookingID
        defer { verificationBusy = nil }
        do {
            _ = try await SupabaseService.client
                .rpc("verify_payment", params: VerifyPaymentParams(
                    booking: bookingID.uuidString, via: "organizer", actorKind: "organizer"))
                .execute()
            Haptics.success()
        } catch {
            print("approvePayment failed:", error)
        }
        await loadVerifications()
    }

    /// "Can't find it" — informational, not a verdict. reject_payment() (as
    /// of migration 032) never touches payment_state; it only records the
    /// reason and messages the guest, so this alone never puts banbe in the
    /// picture. See escalateDispute below for the separate, explicit action
    /// that actually does that.
    func rejectPayment(_ bookingID: UUID, reason: String) async {
        verificationBusy = bookingID
        defer { verificationBusy = nil }
        do {
            _ = try await SupabaseService.client
                .rpc("reject_payment", params: ["p_booking": bookingID.uuidString, "p_reason": reason])
                .execute()
        } catch {
            print("rejectPayment failed:", error)
        }
        await loadVerifications()
    }

    /// The one deliberate action that actually brings banbe in — an
    /// organizer reaches for this only once they and the guest genuinely
    /// can't resolve a payment between themselves. Unlike rejectPayment,
    /// this does move the booking to payment_state = 'disputed'.
    func escalateDispute(_ bookingID: UUID, reason: String) async {
        verificationBusy = bookingID
        defer { verificationBusy = nil }
        do {
            _ = try await SupabaseService.client
                .rpc("escalate_payment_dispute", params: ["p_booking": bookingID.uuidString, "p_reason": reason])
                .execute()
        } catch {
            print("escalateDispute failed:", error)
        }
        await loadVerifications()
        await loadOpenDisputes()
    }

    /// v_disputes, RLS-scoped the same way bookings always are — an
    /// organizer querying it only ever sees their own events' disputes.
    /// Reused here (not just the web-only admin desk) so an organizer can
    /// keep talking with a guest after escalating: the booking leaves
    /// v_pending_verifications the moment it's escalated, so without this
    /// there's nowhere left on VerificationsView to reach it again.
    func loadOpenDisputes() async {
        guard userID != nil else { openDisputes = []; return }
        do {
            let rows: [DisputeRow] = try await SupabaseService.client
                .from("v_disputes").select()
                .execute().value
            openDisputes = rows.filter { $0.disputeResolvedAt == nil }
        } catch {
            print("loadOpenDisputes failed:", error)
            openDisputes = []
        }
    }

    // MARK: Flow 2 — host refund -> guest confirmation

    private struct RefundClaimBookingRow: Decodable {
        let id: UUID
        let userId: UUID?
        let eventId: String?
        enum CodingKeys: String, CodingKey { case id; case userId = "user_id"; case eventId = "event_id" }
    }
    private struct RefundClaimEventRow: Decodable {
        let id: String
        let name: String?
        let organizerId: String?
        enum CodingKeys: String, CodingKey { case id, name; case organizerId = "organizer_id" }
    }
    private struct RefundClaimProfileRow: Decodable {
        let id: UUID
        let displayName: String?
        enum CodingKeys: String, CodingKey { case id; case displayName = "display_name" }
    }

    /// TASK A (2026-09-30 pass) — this used to be an entirely separate
    /// implementation from AttendanceView's Refund Center: its own client-
    /// composed query (refund_claims -> bookings -> events -> profiles, all
    /// joined in Swift) with no recipient-snapshot check at all, which is
    /// the actual cause of a claim with no valid destination still showing
    /// an active "Mark refund sent" CTA on THIS screen even after
    /// AttendanceView was fixed — two independent copies of "what's
    /// actionable," only one of which got fixed. Fixed: calls the exact
    /// same get_host_refund_claims() RPC (migration 077/078)
    /// loadRefundCenter() uses, with no event id (nil = every claim across
    /// every event this host runs; admin-vs-organizer scoping is now
    /// enforced server-side by the RPC itself, not trusted from `isAdmin`).
    /// A monotonic `refundQueueSeq` guard (same pattern as
    /// `attendanceGuestsSeq`) means a slower, older in-flight call (a poll
    /// tick that started before a more recent one) can never overwrite what
    /// that more recent call already applied.
    func loadRefundQueue() async {
        // Investigation fix — this gate used to read ONLY `myOrganizerIDs.
        // isEmpty`, which is true in THREE different situations: genuinely
        // owns no organizer, organizer discovery hasn't run/finished yet,
        // and organizer discovery FAILED. Only the first is a real
        // "nothing to show" — the other two must surface distinctly
        // instead of silently reporting the same empty queue.
        if !isAdmin {
            switch myOrganizerIdsStatus {
            case "idle", "loading":
                refundQueueGateReason = "awaiting-organizer-discovery"
                return
            case "error":
                refundQueue = []
                refundQueueLoading = false
                refundQueueError = T("Không thể xác định các sự kiện bạn tổ chức. Vui lòng thử lại.", "Could not determine which events you organize. Please try again.")
                refundQueueGateReason = "organizer-discovery-failed"
                return
            default:
                if myOrganizerIDs.isEmpty {
                    refundQueue = []
                    refundQueueLoading = false
                    refundQueueError = ""
                    refundQueueGateReason = "no-organizers"
                    return
                }
            }
        }
        refundQueueSeq += 1
        let seq = refundQueueSeq
        refundQueueLoading = true
        refundQueueError = ""
        do {
            let result: GetHostRefundClaimsResult = try await SupabaseService.client
                .rpc("get_host_refund_claims", params: GetHostRefundClaimsParams(pEventId: nil))
                .execute().value
            guard seq == refundQueueSeq else { refundQueueGateReason = "skipped-stale"; return }
            guard result.success == true else {
                print("loadRefundQueue failed:", result.error ?? "unknown", "userID:", userID?.uuidString ?? "nil")
                refundQueueLoading = false
                refundQueueGateReason = "success-false"
                refundQueueError = T("Không thể tải danh sách hoàn tiền. Vui lòng thử lại.", "Could not load the refund queue. Please try again.")
                return
            }
            refundQueue = result.claims ?? []
            refundQueueGateReason = "ok"
            refundQueueErrorStage = ""; refundQueueErrorCode = ""; refundQueueErrorMessage = ""
        } catch {
            guard seq == refundQueueSeq else { return }
            print("loadRefundQueue failed:", error, "userID:", userID?.uuidString ?? "nil")
            refundQueueError = T("Không thể tải danh sách hoàn tiền. Vui lòng thử lại.", "Could not load the refund queue. Please try again.")
            // Point 1 (new diagnostics) — distinguish a server-side
            // PostgrestError (RPC business/transport result, with the
            // actual code/message/details/hint Postgres returned — e.g.
            // 42883 "operator does not exist") from a DecodingError (the
            // response didn't match GetHostRefundClaimsResult's shape —
            // exact codingPath/expected type/mismatch), never collapsing
            // both into the same generic "rpc-error".
            if let pgError = error as? PostgrestError {
                refundQueueGateReason = "rpc-error"
                refundQueueErrorStage = "rpc"
                refundQueueErrorCode = pgError.code ?? ""
                refundQueueErrorMessage = pgError.message
            } else if let decodingError = error as? DecodingError {
                refundQueueGateReason = "decode-error"
                refundQueueErrorStage = "decode"
                refundQueueErrorCode = ""
                refundQueueErrorMessage = Self.describeDecodingError(decodingError)
            } else {
                refundQueueGateReason = "transport-error"
                refundQueueErrorStage = "transport"
                refundQueueErrorCode = ""
                refundQueueErrorMessage = error.localizedDescription
            }
        }
        refundQueueLoading = false
    }

    private static func describeDecodingError(_ error: DecodingError) -> String {
        switch error {
        case .typeMismatch(let type, let context):
            return "typeMismatch(\(type)) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .valueNotFound(let type, let context):
            return "valueNotFound(\(type)) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .keyNotFound(let key, let context):
            return "keyNotFound(\(key.stringValue)) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .dataCorrupted(let context):
            return "dataCorrupted at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        @unknown default:
            return "unknown decoding error"
        }
    }

    private struct MarkRefundSentParams: Encodable {
        let claimID: String
        let note: String
        let proofPath: String?
        enum CodingKeys: String, CodingKey {
            case claimID = "p_claim_id", note = "p_note", proofPath = "p_proof_path"
        }
    }

    private struct MarkRefundSentResult: Decodable {
        let success: Bool?
        let error: String?
        let claim: RefundClaim?
    }

    /// Host's "Đã hoàn tiền" — owed -> host_marked_sent. TASK C (2026-09-30
    /// pass): mark_refund_sent() (migration 078) rejects a claim with no
    /// valid recipient snapshot with the stable business code
    /// REFUND_DESTINATION_REQUIRED (renamed from NO_DESTINATION_SELECTED),
    /// and now returns the complete canonical claim on every path —
    /// including an idempotent repeat tap. That canonical claim is patched
    /// directly into both refundQueue and refundCenterClaims BY ID right
    /// away, so the card can never bounce back to "Mark refund sent" in the
    /// window between this succeeding and the backstop loadRefundQueue()
    /// refetch completing — it's not showing stale pre-mutation data in
    /// that window any more. Returns whether it succeeded so callers
    /// (AttendanceView's "Hoàn lại lần nữa") know whether to also refresh
    /// their own Refund Center view.
    @discardableResult
    func markRefundSent(_ claimID: UUID, note: String = "", proofJPEG: Data? = nil) async -> Bool {
        guard refundActionBusy != claimID else { return false } // already in flight — no double-submit
        refundActionBusy = claimID
        refundBatchError = ""
        defer { refundActionBusy = nil }
        var ok = false
        do {
            // Optional transfer receipt: upload first, then pass its path.
            // Lowercased claim id — the storage policy compares the folder to
            // `refund_claims.id::text` (see submitPaymentProof's note on the
            // same uppercase-UUID trap).
            var proofPath: String?
            if let proofJPEG {
                _ = try await SupabaseService.client.auth.session
                let path = "\(claimID.uuidString.lowercased())/refund-\(Int(Date().timeIntervalSince1970)).jpg"
                _ = try await SupabaseService.client.storage
                    .from("refund-proof")
                    .upload(path, data: proofJPEG, options: FileOptions(contentType: "image/jpeg", upsert: true))
                proofPath = path
            }
            let result: MarkRefundSentResult = try await SupabaseService.client
                .rpc("mark_refund_sent", params: MarkRefundSentParams(claimID: claimID.uuidString, note: note, proofPath: proofPath))
                .execute().value
            if result.success == true {
                ok = true
                Haptics.success()
                if let canonical = result.claim {
                    // Never strip the claim out here — VerificationsView's
                    // own activeRefundRows/pendingRefundRows split (by
                    // status) is what moves it into the non-actionable
                    // "Đang chờ xác nhận" section; this patch only ever
                    // needs to update the ONE row by id. guestName/eventName
                    // aren't part of get_host_refund_claims()'s to_jsonb()
                    // shape here — carried over from the existing row so
                    // the card doesn't blank them out.
                    refundQueue = refundQueue.map { existing in
                        guard existing.id == canonical.id else { return existing }
                        var merged = canonical
                        merged.guestName = existing.guestName
                        merged.eventName = existing.eventName
                        return merged
                    }
                    refundCenterClaims = refundCenterClaims.map { rc in
                        rc.id == canonical.id
                            ? RefundCenterClaim(claim: canonical, guestName: rc.guestName, eligible: false, needsDestination: false, overdue: false)
                            : rc
                    }
                }
            } else {
                refundBatchError = result.error == "REFUND_DESTINATION_REQUIRED"
                    ? T("Chưa thể đánh dấu đã hoàn tiền. Khách cần chọn tài khoản nhận trước.", "Cannot mark this refund sent yet: the guest needs to choose a destination first.")
                    : T("Không thể cập nhật lúc này. Vui lòng thử lại.", "Could not update right now. Please try again.")
            }
        } catch {
            print("markRefundSent failed:", error, "claimID:", claimID.uuidString, "userID:", userID?.uuidString ?? "nil")
            refundBatchError = T("Không thể cập nhật lúc này. Vui lòng thử lại.", "Could not update right now. Please try again.")
        }
        // Backstop canonical refetch — both loaders' own seq guards mean a
        // stale response from either can never clobber a fresher one.
        await loadRefundQueue()
        // A refund dispute CONCLUDES the moment the host re-sends the money
        // (the claim leaves 'disputed', migration 129), which is what starts
        // the temporary chat's 7-day countdown. Refresh the pinned Messages
        // entry so it flips to its concluded/read-only state now rather than
        // on the next unrelated poll.
        await loadDisputeChats()
        return ok
    }

    /// Guest's "Đã nhận tiền" — host_marked_sent -> guest_confirmed.
    /// Optimistic local patch first (this ticket's own explicit ask), then
    /// reconciled by the real re-fetch below — never the other way around.
    func confirmRefundReceived(_ claimID: UUID) async {
        refundActionBusy = claimID
        defer { refundActionBusy = nil }
        if paymentRefundClaim?.id == claimID {
            paymentRefundClaim?.status = "guest_confirmed"
            paymentRefundClaim?.guestConfirmedAt = Date()
        }
        do {
            _ = try await SupabaseService.client
                .rpc("confirm_refund_received", params: ["p_claim_id": claimID.uuidString])
                .execute()
            Haptics.success()
        } catch {
            print("confirmRefundReceived failed:", error)
        }
        await loadPaymentRefundClaim(claimID: claimID)
    }

    /// Guest's "Chưa nhận được" — owed/host_marked_sent -> disputed.
    func disputeRefund(_ claimID: UUID, reason: String = "") async {
        refundActionBusy = claimID
        defer { refundActionBusy = nil }
        if paymentRefundClaim?.id == claimID {
            paymentRefundClaim?.status = "disputed"
        }
        do {
            _ = try await SupabaseService.client
                .rpc("dispute_refund", params: ["p_claim_id": claimID.uuidString, "p_reason": reason])
                .execute()
        } catch {
            print("disputeRefund failed:", error)
        }
        await loadPaymentRefundClaim(claimID: claimID)
        // dispute_refund() opened the temporary chat server-side (migration
        // 129), so this account's own pinned Messages entry has to appear
        // immediately — this is the moment the goer lands on the chat they're
        // about to be asked about, and a stale empty list would read as
        // "nothing happened".
        await loadDisputeChats()
    }

    /// The guest's own single refund claim for whatever booking
    /// PaymentDetailsView is currently showing — fetched by booking id
    /// (normal load) or re-fetched by its own claim id after an action
    /// above (so a stale concurrent poll response, keyed by the OLD
    /// booking id, can't overwrite a state change that already landed —
    /// see this function's own guard below, the same stale-poll lesson
    /// Flow 1 already learned).
    func loadPaymentRefundClaim(bookingID: UUID) async {
        do {
            let claims: [RefundClaim] = try await SupabaseService.client
                .from("refund_claims").select("id, booking_id, reservation_id, amount_vnd, reason, status, host_marked_at, guest_confirmed_at, note, created_at, refund_due_at, disputed_at, host_response_due_at, transfer_reference, resend_reference, resend_bank_name, resend_transferred_at, resend_note, selected_destination_id, recipient_snapshot, proof_path")
                .or("booking_id.eq.\(bookingID.uuidString),reservation_id.eq.\(bookingID.uuidString)")
                .order("created_at", ascending: false)
                .limit(1)
                .execute().value
            if paymentBookingID == bookingID { paymentRefundClaim = claims.first }
        } catch {
            print("loadPaymentRefundClaim failed:", error)
        }
    }

    func loadPaymentRefundClaim(claimID: UUID) async {
        do {
            let claims: [RefundClaim] = try await SupabaseService.client
                .from("refund_claims").select("id, booking_id, reservation_id, amount_vnd, reason, status, host_marked_at, guest_confirmed_at, note, created_at, refund_due_at, disputed_at, host_response_due_at, transfer_reference, resend_reference, resend_bank_name, resend_transferred_at, resend_note, selected_destination_id, recipient_snapshot, proof_path")
                .eq("id", value: claimID.uuidString)
                .execute().value
            guard let claim = claims.first else { return }
            if paymentBookingID == (claim.bookingId ?? claim.reservationId) { paymentRefundClaim = claim }
        } catch {
            print("loadPaymentRefundClaim failed:", error)
        }
    }

    // MARK: Refund MVP — goer's own refund destinations (many, migration 074)

    private struct RpcResultWithID: Decodable {
        let success: Bool?
        let error: String?
        let id: UUID?
    }
    private struct RpcResult: Decodable {
        let success: Bool?
        let error: String?
    }

    /// All of the signed-in goer's own saved refund_destinations rows.
    func loadRefundDestinations() async {
        guard let uid = user?.id else { refundDestinations = []; refundDestinationsLoaded = false; return }
        do {
            let rows: [RefundDestination] = try await SupabaseService.client
                .from("refund_destinations")
                .select("id, user_id, label, bank_name, account_number, account_holder_name, transfer_note, is_default, position, confirmed_at, updated_at")
                .eq("user_id", value: uid.uuidString)
                .order("position", ascending: true)
                .execute().value
            // TASK B point 5 — never let a plain refetch land mid-drag and
            // overwrite the optimistic/authoritative order
            // reorderRefundDestinations() is actively managing.
            guard !refundDestinationsReordering else { return }
            refundDestinations = rows
            refundDestinationsLoaded = true
            await loadRefundDestinationQRs()
        } catch {
            print("loadRefundDestinations failed:", error)
        }
    }

    private struct ReorderRefundDestinationsResult: Decodable {
        let success: Bool?
        let error: String?
        let destinations: [RefundDestination]?
    }

    /// TASK B — was: optimistic reorder, then an UNCONDITIONAL separate
    /// loadRefundDestinations() fetch to find out what actually got
    /// persisted. That second network round trip is exactly the shape of
    /// bug that produces a "snap back"/white reload: nothing stopped a
    /// stray refetch from landing with pre-reorder positions and
    /// clobbering the just-applied optimistic order.
    ///
    /// Fixed: the RPC (migration 076) now returns the canonical saved rows
    /// in its own response — this never fetches again on success, so there
    /// is no second request left to race. `refundDestinationsReordering`
    /// blocks a concurrent loadRefundDestinations() call from overwriting
    /// the optimistic/authoritative order while this is in flight. On
    /// failure, the array is restored to exactly what it was before the
    /// drag, and a friendly error is shown.
    func reorderRefundDestinations(_ orderedIDs: [UUID]) async {
        let previous = refundDestinations
        let byID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        let optimistic: [RefundDestination] = orderedIDs.enumerated().compactMap { i, id in
            guard var d = byID[id] else { return nil }
            d.position = i
            d.isDefault = i == 0
            return d
        }
        guard optimistic.count == previous.count else { return } // stale id set — never apply a partial/mismatched reorder
        refundDestinations = optimistic
        refundDestinationsReordering = true
        refundDestinationError = ""
        do {
            let result: ReorderRefundDestinationsResult = try await SupabaseService.client
                .rpc("reorder_refund_destinations", params: ["p_ordered_ids": orderedIDs.map(\.uuidString)])
                .execute().value
            guard result.success == true else {
                print("reorderRefundDestinations RPC error:", result.error ?? "unknown", "orderedIDs:", orderedIDs.map(\.uuidString), "userID:", userID?.uuidString ?? "nil")
                refundDestinations = previous
                refundDestinationError = T("Chưa thể lưu thứ tự. Vui lòng thử lại.", "Couldn't save the order. Please try again.")
                refundDestinationsReordering = false
                return
            }
            // The RPC's own response is now authoritative — no second fetch.
            refundDestinations = result.destinations ?? optimistic
            refundDestinationsReordering = false
        } catch {
            // Full diagnostic only in dev — never shown raw to the user.
            print("reorderRefundDestinations failed:", error, "orderedIDs:", orderedIDs.map(\.uuidString), "userID:", userID?.uuidString ?? "nil")
            refundDestinations = previous
            refundDestinationError = T("Chưa thể lưu thứ tự. Vui lòng thử lại.", "Couldn't save the order. Please try again.")
            refundDestinationsReordering = false
        }
    }

    /// Goer adds (`id` nil) or edits (`id` given) one of their own refund
    /// bank accounts. `confirmed` must be true (an explicit checkbox/step in
    /// the UI) or the server refuses to save (save_refund_destination()'s
    /// own CONFIRMATION_REQUIRED gate). Returns the saved row's id.
    @discardableResult
    func saveRefundDestination(id: UUID?, label: String, bankName: String, accountNumber: String, accountHolderName: String, transferNote: String, setDefault: Bool, confirmed: Bool) async -> UUID? {
        refundDestinationBusy = true
        refundDestinationError = ""
        defer { refundDestinationBusy = false }
        do {
            let result: RpcResultWithID = try await SupabaseService.client
                .rpc("save_refund_destination", params: SaveRefundDestinationParams(
                    id: id?.uuidString, label: label.isEmpty ? nil : label, bankName: bankName, accountNumber: accountNumber,
                    accountHolderName: accountHolderName, transferNote: transferNote.isEmpty ? nil : transferNote,
                    setDefault: setDefault, confirmed: confirmed
                ))
                .execute().value
            guard result.success == true, let newID = result.id else {
                refundDestinationError = result.error == "CONFIRMATION_REQUIRED"
                    ? T("Vui lòng xác nhận thông tin trước khi lưu.", "Please confirm the details before saving.")
                    : T("Hiện chưa thể thực hiện. Vui lòng thử lại sau.", "This isn't available right now. Please try again later.")
                return nil
            }
            await loadRefundDestinations()
            return newID
        } catch {
            print("saveRefundDestination failed:", error)
            refundDestinationError = T("Hiện chưa thể thực hiện. Vui lòng thử lại sau.", "This isn't available right now. Please try again later.")
            return nil
        }
    }

    @discardableResult
    func deleteRefundDestination(_ id: UUID) async -> Bool {
        refundDestinationBusy = true
        defer { refundDestinationBusy = false }
        var ok = false
        do {
            let result: RpcResult = try await SupabaseService.client
                .rpc("delete_refund_destination", params: ["p_id": id.uuidString])
                .execute().value
            ok = result.success != false
        } catch {
            print("deleteRefundDestination failed:", error)
            refundDestinationError = T("Hiện chưa thể thực hiện. Vui lòng thử lại sau.", "This isn't available right now. Please try again later.")
        }
        await loadRefundDestinations()
        return ok
    }

    func setDefaultRefundDestination(_ id: UUID) async {
        do {
            _ = try await SupabaseService.client
                .rpc("set_default_refund_destination", params: ["p_id": id.uuidString])
                .execute()
        } catch {
            print("setDefaultRefundDestination failed:", error)
        }
        await loadRefundDestinations()
    }

    /// Goer's explicit confirmation of which saved account a SPECIFIC claim
    /// should be refunded into — snapshots the recipient onto the claim
    /// itself server-side (select_refund_destination(), migration 074).
    @discardableResult
    func selectRefundDestinationForClaim(claimID: UUID, destinationID: UUID) async -> Bool {
        refundDestinationBusy = true
        refundDestinationError = ""
        defer { refundDestinationBusy = false }
        var ok = false
        do {
            let result: RpcResult = try await SupabaseService.client
                .rpc("select_refund_destination", params: ["p_claim_id": claimID.uuidString, "p_destination_id": destinationID.uuidString])
                .execute().value
            ok = result.success == true
            if ok { Haptics.selection() }
            if !ok { refundDestinationError = T("Hiện chưa thể thực hiện. Vui lòng thử lại sau.", "This isn't available right now. Please try again later.") }
        } catch {
            print("selectRefundDestinationForClaim failed:", error)
            refundDestinationError = T("Hiện chưa thể thực hiện. Vui lòng thử lại sau.", "This isn't available right now. Please try again later.")
        }
        if ok {
            await loadPaymentRefundClaim(claimID: claimID)
            // Account/Home's "Things to do" read myRefunds, not the single claim above.
            await loadMyRefunds()
        }
        return ok
    }

    /// All of the goer's own active refund claims (owed/host_marked_sent/
    /// disputed) — the persistent "Refunds" list (product rule A).
    func loadMyRefunds() async {
        guard let uid = user?.id else { myRefunds = []; myRefundsLoading = false; return }
        myRefundsLoading = true
        defer { myRefundsLoading = false }
        do {
            let bookings: [RefundClaimBookingRow] = try await SupabaseService.client
                .from("bookings").select("id, user_id, event_id")
                .eq("user_id", value: uid.uuidString)
                .execute().value
            guard !bookings.isEmpty else { myRefunds = []; return }
            let bookingByID = Dictionary(uniqueKeysWithValues: bookings.map { ($0.id, $0) })
            var claims: [RefundClaim] = try await SupabaseService.client
                .from("refund_claims")
                .select("id, booking_id, reservation_id, amount_vnd, status, host_marked_at, disputed_at, host_response_due_at, refund_due_at, created_at, selected_destination_id, recipient_snapshot, proof_path")
                .or(bookings.map { "booking_id.eq.\($0.id.uuidString)" }.joined(separator: ","))
                .in("status", values: ["owed", "host_marked_sent", "disputed"])
                .order("created_at", ascending: false)
                .execute().value
            let eventIDs = Set(claims.compactMap { bookingByID[$0.bookingId ?? $0.reservationId ?? UUID()]?.eventId })
            var eventByID: [String: RefundClaimEventRow] = [:]
            if !eventIDs.isEmpty {
                let events: [RefundClaimEventRow] = try await SupabaseService.client
                    .from("events").select("id, name, organizer_id")
                    .in("id", values: Array(eventIDs))
                    .execute().value
                for e in events { eventByID[e.id] = e }
            }
            for i in claims.indices {
                let b = bookingByID[claims[i].bookingId ?? claims[i].reservationId ?? UUID()]
                claims[i].eventKey = b?.eventId
                claims[i].eventName = b?.eventId.flatMap { eventByID[$0]?.name } ?? ""
            }
            myRefunds = claims
        } catch {
            print("loadMyRefunds failed:", error)
            myRefunds = []
        }
    }

    func openRefundAccounts(back: Screen = .profile, returnToClaimID: UUID? = nil, returnToBookingID: UUID? = nil) {
        refundAccountsBackScreen = back
        refundAccountsReturnToClaimID = returnToClaimID
        refundAccountsReturnToBookingID = returnToBookingID
        screen = .refundAccounts
        UserDefaults.standard.set("refundAccounts", forKey: "banbe.lastScreen")
    }
    func backFromRefundAccounts() {
        screen = refundAccountsBackScreen
        refundAccountsReturnToClaimID = nil
        refundAccountsReturnToBookingID = nil
        UserDefaults.standard.removeObject(forKey: "banbe.lastScreen")
    }

    func openMyRefunds(back: Screen = .profile) {
        myRefundsBackScreen = back
        screen = .myRefunds
        UserDefaults.standard.set("myRefunds", forKey: "banbe.lastScreen")
        Task { await loadMyRefunds() }
    }
    func backFromMyRefunds() {
        screen = myRefundsBackScreen
        UserDefaults.standard.removeObject(forKey: "banbe.lastScreen")
    }

    // MARK: Refund MVP — host's per-event Refund Center

    /// All refund claims for one event (not just active ones — the progress
    /// summary needs host_marked_sent/guest_confirmed rows too). Recipient
    /// info comes straight from each claim's OWN `recipientSnapshot`/
    /// `selectedDestinationId` (migration 074) — never a live
    /// refund_destinations join — so a guest editing/adding accounts
    /// elsewhere can never race this list into a wrong/missing recipient or
    /// a transient "ineligible" flicker.
    ///
    /// BUG FIX (root cause of the "0đ / disappearing / reappearing"
    /// report): this used to unconditionally reset `refundCenterSelected`
    /// to `[]` on every call — including the routine 6s poll. A host
    /// mid-review with rows selected would have that selection silently
    /// wiped by the next background poll tick, collapsing the review
    /// screen's own "N khách / tổng X₫" to 0 selected / 0₫ and disabling
    /// the confirm CTA — not any actual mutation of `amount_vnd` on a claim,
    /// which is never written by anything client-side. Fixed by PRESERVING
    /// selection across reloads, pruned only to ids that still exist and
    /// are still eligible.
    private struct GetHostRefundClaimsResult: Decodable {
        let success: Bool?
        let error: String?
        let claims: [RefundClaim]?
    }

    /// TASK A (2026-09-29 pass) — was: two client-composed queries (this
    /// event's bookings, then refund_claims via a client-built `.or(
    /// booking_id.eq...)` string) plus a separate profiles fetch plus a
    /// Swift-side "drop rows whose booking isn't in bookingByID" filter.
    /// That filter is a UI-level bandaid, not a real fix — it can only
    /// discard what already got fetched, and the actual ownership/identity
    /// chain (claim -> booking -> event -> organizer) lived in three
    /// unsynchronized places (RLS, the client bookings prefetch, the client
    /// filter). Fixed: get_host_refund_claims() (migration 077) performs
    /// the whole canonical join server-side with INNER JOINs — a row can
    /// only come back if claim -> booking -> THIS event -> an organizer the
    /// caller owns all resolve in one query, including the guest's display
    /// name. No client-side validity check is left to get out of sync.
    func loadRefundCenter(eventKey: String) async {
        refundCenterSeq += 1
        let seq = refundCenterSeq
        refundCenterLoading = true
        defer { refundCenterLoading = false }
        guard let eventUUID = UUID(uuidString: eventKey) else { return }
        do {
            let result: GetHostRefundClaimsResult = try await SupabaseService.client
                .rpc("get_host_refund_claims", params: GetHostRefundClaimsParams(pEventId: eventUUID.uuidString))
                .execute().value
            // Only the newest call may write refundCenterClaims — a slower
            // older in-flight poll tick landing late must never overwrite a
            // fresher one.
            guard seq == refundCenterSeq else { return }
            guard result.success == true else {
                print("loadRefundCenter failed:", result.error ?? "unknown", "eventKey:", eventKey, "userID:", userID?.uuidString ?? "nil")
                return
            }
            let claims = result.claims ?? []
            let now = Date()
            let enriched = claims.map { c -> RefundCenterClaim in
                let overdue = (c.status == "owed" && (c.refundDueAt.map { $0 < now } ?? false))
                    || (c.status == "disputed" && (c.hostResponseDueAt.map { $0 < now } ?? false))
                // TASK B — shared presentation (RefundClaim.hasValidDestination
                // /isActiveRefundStatus, this file's own extension above), the
                // same rule VerificationsView's refund queue now uses too.
                return RefundCenterClaim(
                    claim: c,
                    guestName: c.hostGuestName?.isEmpty == false ? c.hostGuestName! : T("Khách", "Guest"),
                    eligible: c.hasValidDestination && c.isActiveRefundStatus,
                    needsDestination: c.isActiveRefundStatus && !c.hasValidDestination,
                    overdue: overdue
                )
            }
            let eligibleIDs = Set(enriched.filter(\.eligible).map(\.id))
            refundCenterClaims = enriched
            refundCenterSelected = refundCenterSelected.intersection(eligibleIDs)
        } catch {
            guard seq == refundCenterSeq else { return }
            // Full diagnostic only in dev — never shown raw to the user.
            print("loadRefundCenter failed:", error, "eventKey:", eventKey, "userID:", userID?.uuidString ?? "nil")
            // A transient fetch error must never clobber an already-
            // populated list.
        }
    }

    func toggleRefundCenterSelect(_ claimID: UUID) {
        if refundCenterSelected.contains(claimID) { refundCenterSelected.remove(claimID) } else { refundCenterSelected.insert(claimID) }
    }

    func selectAllEligibleRefundCenter() {
        refundCenterSelected = Set(refundCenterClaims.filter(\.eligible).map(\.id))
    }

    func clearRefundCenterSelection() { refundCenterSelected = [] }

    /// Host's "Xác nhận đã chuyển tiền" — one real, atomic batch RPC call,
    /// not a client-side loop of individual mark_refund_sent calls.
    /// `refundBatchInFlight` (not just `refundBatchBusy`) guards against a
    /// double-tap firing the RPC twice.
    @discardableResult
    func confirmRefundBatch(eventKey: String, note: String = "") async -> RefundBatchResult? {
        guard !refundBatchInFlight else { return nil }
        let claimIDs = Array(refundCenterSelected)
        guard !claimIDs.isEmpty else { return nil }
        refundBatchBusy = true
        refundBatchInFlight = true
        refundBatchError = ""
        defer { refundBatchBusy = false; refundBatchInFlight = false }
        do {
            let result: RefundBatchResult = try await SupabaseService.client
                .rpc("create_and_confirm_refund_batch", params: CreateRefundBatchParams(
                    claimIds: claimIDs.map(\.uuidString), note: note
                ))
                .execute().value
            guard result.success == true else {
                refundBatchError = T("Không thể cập nhật lúc này. Vui lòng thử lại.", "Could not update right now. Please try again.")
                return nil
            }
            // Server result is the sole source of truth from here — no
            // local amount/status patch, only a full canonical reload.
            refundBatchResult = result
            Haptics.success()
            await loadRefundCenter(eventKey: eventKey)
            return result
        } catch {
            print("confirmRefundBatch failed:", error)
            refundBatchError = T("Không thể cập nhật lúc này. Vui lòng thử lại.", "Could not update right now. Please try again.")
            return nil
        }
    }

    /// Host's "Gửi lại thông tin chuyển khoản" on a disputed claim — resends
    /// transfer proof without changing status. `refundResendInFlight`
    /// disables only that row's own CTA and blocks a double-submit on the
    /// same claim.
    @discardableResult
    func resendRefundTransferInfo(eventKey: String, claimID: UUID, reference: String, bankName: String, transferredAt: Date?) async -> Bool {
        guard !refundResendInFlight.contains(claimID) else { return false }
        refundResendBusy = claimID
        refundResendInFlight.insert(claimID)
        defer { refundResendBusy = nil; refundResendInFlight.remove(claimID) }
        var ok = false
        do {
            let result: RpcResult = try await SupabaseService.client
                .rpc("resend_refund_transfer_info", params: ResendRefundTransferInfoParams(
                    claimId: claimID.uuidString, reference: reference, bankName: bankName,
                    transferredAt: transferredAt.map { ISO8601DateFormatter().string(from: $0) }
                ))
                .execute().value
            ok = result.success == true
        } catch {
            print("resendRefundTransferInfo failed:", error)
        }
        await loadRefundCenter(eventKey: eventKey)
        return ok
    }

    // MARK: Admin dashboard

    func openAdminDashboard() {
        guard isAdmin else { return }
        screen = .disputes
        Task { await loadAdminDisputes() }
    }

    /// Same v_disputes query as loadOpenDisputes, but for an admin RLS
    /// returns every dispute rather than just this account's own events —
    /// and unlike the organizer's list, this doesn't filter out resolved
    /// ones (AdminDashboardView shows both, same as web's Disputes.jsx).
    func loadAdminDisputes() async {
        guard isAdmin else { adminDisputes = []; return }
        adminDisputesLoading = true
        do {
            adminDisputes = try await SupabaseService.client
                .from("v_disputes").select()
                .order("disputed_at", ascending: false)
                .execute().value
        } catch {
            print("loadAdminDisputes failed:", error)
            adminDisputes = []
        }
        adminDisputesLoading = false
        await signProofUrls(adminDisputes.compactMap(\.proofPath))
    }

    /// The T1/T2/T3 trail for one booking — what a dispute is actually
    /// argued on.
    func loadAuditTrail(_ bookingID: UUID) async {
        auditBookingId = bookingID
        auditTrail = []
        do {
            auditTrail = try await SupabaseService.client
                .from("payment_audit_log").select()
                .eq("booking_id", value: bookingID.uuidString)
                .order("at", ascending: true)
                .execute().value
        } catch {
            print("loadAuditTrail failed:", error)
        }
    }

    /// resolve_dispute (the RPC) only flips database state — payment
    /// confirmed/expired, the dispute thread marked resolved and scheduled
    /// for purge, one note left in the guest's ordinary chat. The
    /// confirmation email itself (with the transcript PDF and the receipt
    /// image attached) is a separate step, api/dispute-resolved-email.js —
    /// best-effort here: if it fails, the database resolution already
    /// stands and disputeEmailError surfaces so an admin can retry rather
    /// than the whole action rolling back or silently never emailing
    /// anyone.
    func resolveDispute(_ bookingID: UUID, uphold: Bool, note: String,
                        reasonCategory: DisputeReasonCategory = .other) async {
        disputeBusy = bookingID
        disputeEmailError = ""
        var resolved = false
        do {
            let result: ForfeitResult = try await SupabaseService.client
                .rpc("resolve_dispute", params: ResolveDisputeParams(
                    booking: bookingID.uuidString, uphold: uphold, resolution: note,
                    reasonCategory: reasonCategory.rawValue))
                .execute().value
            if result.success == false {
                print("resolveDispute failed:", result.error ?? "unknown")
            } else {
                resolved = true
            }
        } catch {
            print("resolveDispute failed:", error)
        }
        // The DB resolution above is the part the admin is actually waiting
        // on — it must update the screen (disputeBusy cleared, the row
        // moved to "Resolved") regardless of what happens next. The
        // confirmation email (api/dispute-resolved-email.js: puppeteer-core
        // + @sparticuz/chromium, never load-tested end-to-end — see
        // 05-notify-retention.md) used to be awaited INSIDE this same do
        // block, ahead of these two lines: a slow cold start or a hung
        // request there silently blocked every visible sign the resolution
        // had already succeeded, reading as "the button does nothing" even
        // though the dispute really was resolved.
        disputeBusy = nil
        await loadAdminDisputes()

        if resolved {
            Task { await sendDisputeResolvedEmail(bookingID) }
        }
    }

    /// Fire-and-forget half of resolveDispute — see the comment there.
    private func sendDisputeResolvedEmail(_ bookingID: UUID) async {
        guard let token = try? await SupabaseService.client.auth.session.accessToken,
              let url = URL(string: AppConfig.apiBaseURL + "/api/dispute-resolved-email")
        else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["bookingId": bookingID.uuidString])
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                disputeEmailError = (body?["error"] as? String) ?? "HTTP_\(http.statusCode)"
            }
        } catch {
            print("sendDisputeResolvedEmail failed:", error)
            disputeEmailError = "NETWORK_ERROR"
        }
    }

// MARK: Temporary dispute chat
    //
    // One refresh loop per active thread, and the transcript is only ever
    // cleared on a real thread SWITCH. Both were loader-level bugs:
    //
    //   * loadDisputeChat()/loadRefundDisputeChat() used to reset
    //     disputeChatMessages/disputeChatThread/disputeChatLoading on EVERY
    //     call, including the 4s poll the panel itself drives — so the
    //     transcript visibly blinked out and back once per tick and the
    //     scroll position was thrown away with it.
    //   * nothing stopped a second poll starting while one was still in
    //     flight, and a late response for a thread the user had already
    //     navigated away from could paint over the new one's messages.
    //
    // The fix is the pair below: `bindDisputeChat` decides whether a call is
    // a switch (clear once) or a refresh (leave everything alone), and a
    // monotonic sequence number plus an exact key comparison decide whether a
    // given response is still the one on screen.

    private struct DisputeThreadRow: Decodable {
        let id: UUID
        let bookingId: UUID?
        let resolvedAt: Date?
        let purgeAfter: Date?
        let resolutionNote: String?
        enum CodingKeys: String, CodingKey {
            case id
            case bookingId = "booking_id"
            case resolvedAt = "resolved_at"
            case purgeAfter = "purge_after"
            case resolutionNote = "resolution_note"
        }
    }

    private static let disputeThreadSelect = "id, booking_id, resolved_at, purge_after, resolution_note"

    /// Point the panel at ONE temporary chat. Returns true when this actually
    /// switched threads — the only case where the transcript, the read-only
    /// state and the scroll position may be thrown away.
    ///
    /// The per-key draft map is what makes "preserve drafts across refreshes
    /// AND across thread switches" honest: the outgoing thread's half-typed
    /// message is parked under its own key instead of being clobbered by
    /// whatever the incoming thread had saved the last time it was open.
    @discardableResult
    private func bindDisputeChat(kind: String, id: UUID) -> Bool {
        let key = "\(kind):\(id.uuidString)"
        if disputeChatKey == key { return false }
        if let old = disputeChatKey { disputeChatDrafts[old] = disputeChatDraft }
        disputeChatDraft = disputeChatDrafts[key] ?? ""
        disputeChatKey = key
        disputeChatBookingId = (kind == "payment") ? id : nil
        disputeChatRefundClaimId = (kind == "refund") ? id : nil
        disputeChatKind = kind
        disputeChatMessages = []
        disputeChatThread = nil
        disputeChatError = ""
        disputeChatInitialLoadDone = false
        disputeChatSeq += 1
        return true
    }

    /// Commit a fetched transcript, but only if it is still the thread on
    /// screen and no newer load has started. Bumps `disputeChatIncomingTick`
    /// only when genuinely NEW messages arrived, which is what lets the panel
    /// scroll to the bottom for an incoming message while the reader is
    /// already there and leave them alone when they are reading history.
    private func commitDisputeChat(_ fresh: [DisputeMessage], key: String, seq: Int) {
        guard seq == disputeChatSeq, disputeChatKey == key else { return }
        let previousLast = disputeChatMessages.last?.id
        let previousCount = disputeChatMessages.count
        disputeChatMessages = fresh
        if let previousLast, let newLast = fresh.last, newLast.id != previousLast, fresh.count > previousCount {
            disputeChatIncomingTick += 1
        }
        disputeChatInitialLoadDone = true
        disputeChatLoading = false
    }

    private func restoreDisputeDraft(_ body: String, key: String?) {
        disputeChatDraft = body
        if let key { disputeChatDrafts[key] = body }
    }

    func loadDisputeChat(_ bookingID: UUID, retried: Bool = false) async {
        bindDisputeChat(kind: "payment", id: bookingID)
        let key = disputeChatKey ?? "payment:\(bookingID.uuidString)"
        // Overlapping-poll guard: an in-flight load for THIS thread already
        // has everything a second one would fetch.
        guard !disputeChatInFlight.contains(key) else { return }
        disputeChatInFlight.insert(key)
        disputeChatSeq += 1
        let seq = disputeChatSeq
        // Loading only ever means "first load, nothing to show yet" — a
        // background refresh never blanks what is already on screen.
        disputeChatLoading = !disputeChatInitialLoadDone
        defer { disputeChatInFlight.remove(key) }
        do {
            let thread: DisputeThreadRow = try await SupabaseService.client
                .from("dispute_threads").select(Self.disputeThreadSelect)
                .eq("booking_id", value: bookingID.uuidString)
                .single().execute().value
            let messages: [DisputeMessage] = try await SupabaseService.client
                .from("dispute_messages").select()
                .eq("dispute_thread_id", value: thread.id.uuidString)
                .order("created_at", ascending: true)
                .execute().value
            guard seq == disputeChatSeq, disputeChatKey == key else { return }
            // Read-only — drives the retention countdown label
            // (DisputeChatPanel.swift) instead of a delete button, since
            // dispute_messages must survive until the purge
            // (05-notify-retention.md).
            disputeChatThread = (threadId: thread.id, resolvedAt: thread.resolvedAt,
                                 purgeAfter: thread.purgeAfter, resolutionNote: thread.resolutionNote)
            disputeChatError = ""
            commitDisputeChat(messages, key: key, seq: seq)
        } catch {
            // A dispute_threads row RLS is quietly hiding from this account
            // (a stale/mislinked organizer_id — the ART10025 symptom)
            // throws here exactly the same as a genuinely missing row.
            // resolve_dispute()'s own repair only fires once a dispute is
            // closed, and reject_payment()/escalate_payment_dispute() won't
            // run again once payment_state = 'disputed' — resync_dispute_
            // thread() has no state restriction, so try it once and retry
            // the load before giving up and surfacing an error.
            print("loadDisputeChat failed:", error)
            if !retried {
                struct ResyncResult: Decodable { let success: Bool? }
                let resync: ResyncResult? = try? await SupabaseService.client
                    .rpc("resync_dispute_thread", params: ["p_booking": bookingID.uuidString])
                    .execute().value
                if resync?.success == true {
                    await loadDisputeChat(bookingID, retried: true)
                    return
                }
            }
            guard seq == disputeChatSeq, disputeChatKey == key else { return }
            // A failed BACKGROUND refresh must not empty a transcript that is
            // already on screen: the error rides alongside the existing
            // messages, which stay exactly where they are.
            disputeChatError = T("Không tải được đoạn chat. Thử lại nhé.", "Couldn't load this chat. Please try again.")
            disputeChatInitialLoadDone = true
            disputeChatLoading = false
        }
    }

    func sendDisputeMessage(_ bookingID: UUID) async {
        let body = disputeChatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        let key = disputeChatKey
        disputeChatDraft = ""
        disputeChatDrafts[key ?? ""] = ""
        disputeChatError = ""
        do {
            let result: ForfeitResult = try await SupabaseService.client
                .rpc("send_dispute_message", params: ["p_booking": bookingID.uuidString, "p_body": body])
                .execute().value
            if result.success == false {
                print("sendDisputeMessage failed:", result.error ?? "unknown")
                restoreDisputeDraft(body, key: key)
                disputeChatError = T("Chưa gửi được. Thử lại nhé.", "Couldn't send. Please try again.")
                return
            }
        } catch {
            print("sendDisputeMessage failed:", error)
            restoreDisputeDraft(body, key: key)
            disputeChatError = T("Chưa gửi được. Thử lại nhé.", "Couldn't send. Please try again.")
            return
        }
        await loadDisputeChat(bookingID)
    }

    // MARK: The refund half of the same chat panel: same two tables, keyed by
    // refund_claims.id instead of bookings.id (migration 129).

    func loadRefundDisputeChat(_ claimID: UUID) async {
        bindDisputeChat(kind: "refund", id: claimID)
        let key = disputeChatKey ?? "refund:\(claimID.uuidString)"
        guard !disputeChatInFlight.contains(key) else { return }
        disputeChatInFlight.insert(key)
        disputeChatSeq += 1
        let seq = disputeChatSeq
        disputeChatLoading = !disputeChatInitialLoadDone
        defer { disputeChatInFlight.remove(key) }
        do {
            let thread: DisputeThreadRow = try await SupabaseService.client
                .from("dispute_threads").select(Self.disputeThreadSelect)
                .eq("refund_claim_id", value: claimID.uuidString)
                .single().execute().value
            let messages: [DisputeMessage] = try await SupabaseService.client
                .from("dispute_messages").select()
                .eq("dispute_thread_id", value: thread.id.uuidString)
                .order("created_at", ascending: true)
                .execute().value
            guard seq == disputeChatSeq, disputeChatKey == key else { return }
            disputeChatThread = (threadId: thread.id, resolvedAt: thread.resolvedAt,
                                 purgeAfter: thread.purgeAfter, resolutionNote: thread.resolutionNote)
            disputeChatError = ""
            commitDisputeChat(messages, key: key, seq: seq)
            // Sign only genuinely NEW attachment paths (never every path on
            // every 4s tick) for exactly the reason signChatAttachmentUrls'
            // own doc comment gives: a fresh signed URL for an unchanged file
            // makes SwiftUI tear the AsyncImage down and re-fetch it, which
            // showed up as thumbnails blinking once every few seconds.
            let newPaths = messages.compactMap(\.attachmentPath).filter { disputeAttachmentUrls[$0] == nil }
            if !newPaths.isEmpty { await signDisputeAttachmentUrls(newPaths) }
            // Keep the verified per-claim card state in step with what the
            // transcript itself reported (message count, closure), so the
            // card around it never sits on a snapshot the transcript has
            // already contradicted.
            await loadRefundDisputeThread(claimID, force: true)
        } catch {
            print("loadRefundDisputeChat failed:", error)
            guard seq == disputeChatSeq, disputeChatKey == key else { return }
            disputeChatError = T("Không tải được đoạn chat. Thử lại nhé.", "Couldn't load this chat. Please try again.")
            disputeChatInitialLoadDone = true
            disputeChatLoading = false
        }
    }

    func sendRefundDisputeMessage(_ claimID: UUID) async {
        let body = disputeChatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        let key = disputeChatKey
        disputeChatDraft = ""
        disputeChatDrafts[key ?? ""] = ""
        disputeChatError = ""
        do {
            let result: ForfeitResult = try await SupabaseService.client
                .rpc("send_refund_dispute_message", params: ["p_refund_claim_id": claimID.uuidString, "p_body": body])
                .execute().value
            if result.success == false {
                print("sendRefundDisputeMessage failed:", result.error ?? "unknown")
                restoreDisputeDraft(body, key: key)
                // DISPUTE_RESOLVED isn't a transient failure like the rest —
                // the chat is a read-only record until the purge sweep removes
                // it, so say so rather than implying a retry could work.
                disputeChatError = result.error == "DISPUTE_RESOLVED"
                    ? T("Tranh chấp này đã kết thúc nên không còn gửi được.", "This dispute has ended, so it's no longer open.")
                    : T("Chưa gửi được. Thử lại nhé.", "Couldn't send. Please try again.")
                return
            }
        } catch {
            print("sendRefundDisputeMessage failed:", error)
            restoreDisputeDraft(body, key: key)
            disputeChatError = T("Chưa gửi được. Thử lại nhé.", "Couldn't send. Please try again.")
            return
        }
        await loadRefundDisputeChat(claimID)
        await loadDisputeChats()
    }

    // MARK: Attachments in the temporary REFUND dispute chat (migration 131).
    //
    // Same two-step shape as the ordinary chat's sendChatAttachment —
    // upload the object first, then write the message row referencing it —
    // with one extra obligation that chat doesn't have: if the row write is
    // refused (or anything else fails), the object just uploaded is deleted
    // again. A dispute transcript is temporary and private to two people, so
    // an orphaned file would sit in storage forever, reachable by the parties
    // of a dispute whose own transcript has already been purged.

    /// Signs `dispute-attachments` paths in one batched call — the same
    /// pattern signChatAttachmentUrls uses for the ordinary bucket, and the
    /// same "never overwrite an already-signed path" guard, so a 4s poll can't
    /// churn a thumbnail.
    func signDisputeAttachmentUrls(_ paths: [String]) async {
        let wanted = Array(Set(paths)).filter { !$0.isEmpty && disputeAttachmentUrls[$0] == nil }
        guard !wanted.isEmpty else { return }
        do {
            let results = try await SupabaseService.client.storage
                .from(DisputeAttachments.bucket)
                .createSignedURLs(paths: wanted, expiresIn: 600)
            for result in results {
                if case let .success(path, signedURL) = result, disputeAttachmentUrls[path] == nil {
                    disputeAttachmentUrls[path] = signedURL
                }
            }
        } catch {
            print("signDisputeAttachmentUrls failed:", error)
        }
    }

    /// Attaches a photo/document to ONE refund dispute.
    ///
    /// Scoped to the exact claim it was started for — the thread id is looked
    /// up once, up front, and every later step (path, RPC, reload) is keyed by
    /// that same thread, so a dispute switch mid-upload can't file the file
    /// under another thread or paint another transcript. Refuses outright if
    /// another upload for the same claim is already running, and cleans up the
    /// object it wrote whenever the message row is refused — which is exactly
    /// what happens when the other party closes the dispute while the file is
    /// still uploading.
    func sendRefundDisputeAttachment(_ payload: AttachmentPayload, claimID: UUID) async -> Bool {
        guard userID != nil else { return false }
        guard !disputeAttachInFlight.contains(claimID) else { return false }
        disputeAttachInFlight.insert(claimID)
        defer { disputeAttachInFlight.remove(claimID) }

        // The dispute's thread id is the ONLY address an attachment may live
        // under, and it's also what the storage policies authorize — so read
        // it before writing anything, and never guess it from the claim id.
        guard let threadID = await refundDisputeThreadId(claimID) else {
            disputeChatError = T("Không tìm thấy cuộc tranh chấp này.", "Couldn't find this dispute.")
            return false
        }
        // Refuse client-side too, not only server-side: while this dispute is
        // concluded there is nothing to attach to, and starting a multi-
        // megabyte upload just to have the server refuse it is the bug.
        if let thread = disputeChatThread, thread.resolvedAt != nil,
           disputeChatRefundClaimId == claimID {
            disputeChatError = T("Tranh chấp này đã kết thúc nên không còn gửi được.", "This dispute has ended, so it's no longer open.")
            return false
        }

        let path = "\(threadID.uuidString.lowercased())/\(Int(Date().timeIntervalSince1970 * 1000)).\(payload.fileExtension)"
        let uploaded = await uploadDisputeAttachment(path: path, data: payload.data, contentType: payload.contentType)
        guard uploaded else {
            disputeChatError = T("Chưa gửi được tệp. Thử lại nhé.", "Couldn't upload the file. Please try again.")
            return false
        }

        let body = payload.contentType == "application/pdf"
            ? T("Đã gửi một tệp", "Sent a file")
            : T("Đã gửi một ảnh", "Sent a photo")
        var ok = false
        var ended = false
        do {
            let result: ForfeitResult = try await SupabaseService.client
                .rpc("send_refund_dispute_attachment", params: RefundDisputeAttachmentParams(
                    claimID: claimID.uuidString, body: body, path: path,
                    type: payload.contentType, width: payload.width, height: payload.height))
                .execute().value
            if result.success == true {
                ok = true
            } else {
                print("sendRefundDispute_attachment failed:", result.error ?? "unknown")
                // The closure race lands here: the file uploaded fine, but the
                // dispute was closed before the message could be written.
                ended = result.error == "DISPUTE_RESOLVED"
            }
        } catch {
            print("sendRefundDispute_attachment failed:", error)
        }

        if ok {
            await signDisputeAttachmentUrls([path])
            // Reload the transcript for THIS claim only — the panel's own poll
            // would get there in a few seconds, but the sender should see
            // their photo immediately, exactly as chatSend() does.
            await loadRefundDisputeChat(claimID)
            await loadDisputeChats()
            return true
        }

        // Nothing references the object: remove it, or it becomes an orphan no
        // purge will ever collect (the sweep keys off dispute thread rows).
        await deleteDisputeAttachment(path: path)
        if ended {
            // Not a transient failure — say so instead of implying a retry
            // could work, then refresh so the panel goes read-only at once.
            disputeChatError = T("Tranh chấp này đã kết thúc nên không còn gửi được.", "This dispute has ended, so it's no longer open.")
            await loadRefundDisputeChat(claimID)
        } else {
            disputeChatError = T("Chưa gửi được. Thử lại nhé.", "Couldn't send. Please try again.")
        }
        return false
    }

    /// Uploads one object into the private dispute bucket. Split out so the
    /// caller owns every decision about what happens if it fails.
    private func uploadDisputeAttachment(path: String, data: Data, contentType: String) async -> Bool {
        do {
            _ = try await SupabaseService.client.storage
                .from(DisputeAttachments.bucket)
                .upload(path, data: data, options: FileOptions(contentType: contentType))
            return true
        } catch {
            print("uploadDisputeAttachment failed:", error)
            return false
        }
    }

    /// Cleanup for a failed / refused send. Scoped by the storage policy to
    /// the caller's own dispute threads, so this can only ever remove an
    /// object this account uploaded into a dispute it is a party to.
    func deleteDisputeAttachment(path: String) async {
        do {
            _ = try await SupabaseService.client.storage
                .from(DisputeAttachments.bucket).remove(paths: [path])
            disputeAttachmentUrls.removeValue(forKey: path)
        } catch {
            print("deleteDisputeAttachment failed:", error)
        }
    }

    /// The dispute THREAD an attachment may be filed under. Read through the
    /// already-verified per-claim card when it's loaded (no network), and
    /// through the one row the transcript itself reads otherwise — never
    /// derived from the claim id.
    private func refundDisputeThreadId(_ claimID: UUID) async -> UUID? {
        if let known = refundDisputeThreads[claimID]?.disputeThreadId { return known }
        struct Row: Decodable { let id: UUID }
        let row: Row? = try? await SupabaseService.client
            .from("dispute_threads").select("id")
            .eq("refund_claim_id", value: claimID.uuidString)
            .single().execute().value
        return row?.id
    }

    /// Saves a dispute attachment image to the device's photo library — the
    /// dispute transcript's own copy of what the chat photo viewer's Save
    /// button does (AppState+Data.downloadChatPhoto), pointed at whichever
    /// signed URL is on screen.
    func saveDisputeAttachmentImage(from url: URL) async -> Bool {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return false }
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else { return false }
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            return true
        } catch {
            print("saveDisputeAttachmentImage failed:", error)
            return false
        }
    }

// MARK: The dispute index behind Inbox-row highlighting and cross-screen
    // badges. Deliberately NOT an entry point any screen navigates from —
    // see loadRefundDisputeThread(_:force:) below for the verified, per-claim
    // lookup that is.

    /// Every dispute chat this account is a party to, open ones first, plus
    /// the ones still inside their 7-day post-conclusion window. One RPC
    /// rather than a client-side join: get_my_dispute_chats (migrations
    /// 129/130) does its own guest/organizer/admin scoping, and the same row
    /// shape feeds an open dispute, a concluded one, and the Inbox row
    /// highlight for the conversation it renders inside.
    func loadDisputeChats() async {
        guard userID != nil else { disputeChats = []; return }
        disputeChatsLoading = true
        disputeChatsError = ""
        do {
            let rows: [DisputeChatSummary] = try await SupabaseService.client
                .rpc("get_my_dispute_chats").execute().value
            disputeChats = rows
            disputeThreadClaimIndex = rows.reduce(into: [UUID: UUID]()) { index, row in
                if let claim = row.refundClaimId { index[row.threadId] = claim }
            }
        } catch {
            print("loadDisputeChats failed:", error)
            // A failed refresh must NOT wipe the rows the Inbox is currently
            // highlighting — it keeps what it has and says it couldn't update.
            if disputeChats.isEmpty {
                disputeChatsError = T("Không tải được danh sách tranh chấp.", "Couldn't load disputes.")
            }
        }
        disputeChatsLoading = false
    }

    /// Expand/collapse a dispute. Kept for callers that hold a dispute THREAD
    /// id; the refund half resolves the CLAIM (the id that is actually
    /// stable) via openDisputeForRefundClaim below.
    func toggleDisputeChat(_ threadID: UUID) {
        if openDisputeChatThreadId == threadID {
            openDisputeChatThreadId = nil
            expandedDisputeClaimId = nil
            return
        }
        openDisputeChatThreadId = threadID
        expandedDisputeClaimId = disputeThreadClaimIndex[threadID]
    }

    /// The refund dispute attached to the booking conversation currently
    /// open, resolved by EXACT conversation thread id
    /// (get_refund_dispute_for_conversation, migration 130) rather than by
    /// event name — so a second booking of the same event can never light up
    /// the wrong card, and two conversations on one event can each carry
    /// their own dispute.
    /// The escalated PAYMENT dispute on the same conversation, if any — the
    /// "other dispute type" that attaches to its own matching system card.

    /// Pure selection of which BOOKING carries a live payment dispute, given the
    /// thread rows and booking states already fetched. Split out of
    /// loadConversationDispute() so the rule is unit-testable without a network
    /// (see BanbeAppTests/ConversationDisputeAttachmentTests.swift).
    ///
    /// A payment dispute is live only when its thread is unresolved AND its
    /// booking is still `payment_state == "disputed"` with no
    /// `dispute_resolved_at`. resolve_dispute() moves the booking out of
    /// `disputed` and stamps `dispute_resolved_at`, so a settled dispute can
    /// never look live again. Ties break by booking id so the choice is stable
    /// across polls.
    /// Which booking, if any, is carrying a LIVE payment dispute on this
    /// conversation. Nonisolated on purpose: pure filtering/sorting over
    /// caller-supplied dicts, no state of its own, so the unit suite can
    /// exercise it without a main-actor hop.
    nonisolated static func livePaymentDisputeBookingID(
        threadRows: [(bookingId: UUID?, resolved: Bool)],
        bookingStates: [UUID: (paymentState: String, disputeResolvedAt: Date?)]
    ) -> UUID? {
        threadRows
            .filter { !$0.resolved }
            .compactMap(\.bookingId)
            .filter { bookingStates[$0]?.paymentState == "disputed" && bookingStates[$0]?.disputeResolvedAt == nil }
            .sorted { $0.uuidString < $1.uuidString }
            .first
    }

    /// True while the CURRENT conversation has an active temporary dispute
    /// (open refund dispute, or an unresolved payment dispute). Both fields are
    /// resolved server-side per conversation and cleared on thread switch, so
    /// this never leaks to other conversations, and a closed dispute (which
    /// `closeRefundDispute` refreshes into `conversationRefundDispute`) lifts it.
    var normalMessagingPaused: Bool {
        conversationRefundDispute?.isActive == true || conversationPaymentDisputeBookingID != nil
    }

    func loadConversationDispute(conversationThreadID: UUID) async {
        // Rapid conversation switching: every load claims a generation and only
        // the newest may write. Without this, tapping two conversations quickly
        // let the FIRST (slower) response land last and repaint the second
        // conversation's card with the first one's dispute.
        conversationDisputeGeneration += 1
        let myGeneration = conversationDisputeGeneration
        conversationDisputeLoading = true
        conversationPaymentDisputeBookingID = nil

        // 1. Refund half — one RPC, exact conversation-thread match, RLS
        //    checked server-side.
        if let value: RefundDisputeThread = try? await SupabaseService.client
            .rpc("get_refund_dispute_for_conversation", params: ["p_thread": conversationThreadID.uuidString])
            .execute().value {
            guard myGeneration == conversationDisputeGeneration else { return }
            if value.found {
                conversationRefundDispute = value
                if let claimID = value.refundClaimId { refundDisputeThreads[claimID] = value }
            } else {
                conversationRefundDispute = nil
            }
        }
        guard myGeneration == conversationDisputeGeneration else { return }

        // 2. Payment half — a payment thread is keyed by booking_id and
        //    carries the conversation's own event_id, while refund threads are
        //    exactly the ones with a NULL booking_id. Filtering on that
        //    separates the two kinds without guessing from a name.
        struct ThreadRef: Decodable {
            let eventId: String
            let guestId: UUID?
            enum CodingKeys: String, CodingKey {
                case eventId = "event_id"
                case guestId = "guest_id"
            }
        }
        // Bounded exactly like the chat's own loadChatMessages guard: a thread
        // row the viewer cannot read (deleted mid-switch, or RLS-scoped away)
        // must stop here rather than fall through and write the payment half of
        // a DIFFERENT conversation's state.
        guard let ref: ThreadRef = try? await SupabaseService.client
            .from("threads").select("event_id, guest_id")
            .eq("id", value: conversationThreadID.uuidString).single().execute().value,
              let guestID = ref.guestId else {
            if myGeneration == conversationDisputeGeneration { conversationDisputeLoading = false }
            return
        }
        // `kind` separates the two dispute families (migration 129 defaults
        // every pre-existing payment thread to 'payment' and writes 'refund'
        // for the new ones), and the (event_id, guest_id) pair IS the
        // conversation — so this can only ever match a payment dispute
        // belonging to THIS conversation, never a second guest's on the same
        // event.
        //
        // BUG (2026-10-04, physical-iPhone repro): this ended at
        // `paymentRows?.first?.bookingId`, which mounted an (empty, spurious)
        // PAYMENT dispute panel under "Payment confirmed" on a conversation
        // that only ever had a REFUND dispute. Two things were unchecked:
        // whether the thread is still unresolved at all, and whether its
        // booking is still in the payment-dispute state. A payment dispute
        // thread is retained as history after banbe rules on it, so "a thread
        // row exists" is not "there is a live payment dispute".
        //
        // A payment dispute is shown ONLY when all three hold:
        //   1. an unresolved (resolved_at IS NULL) payment thread for THIS
        //      conversation's (event_id, guest_id),
        //   2. its booking is currently payment_state = 'disputed'
        //      (resolve_dispute() moves the booking out of 'disputed', so this
        //      is the authoritative "still live" signal), and
        //   3. the booking has no dispute_resolved_at.
        // This narrows only the wrong positives: a genuine open payment dispute
        // still satisfies all three and is never hidden.
        struct PaymentDisputeBooking: Decodable {
            let id: UUID
            let paymentState: String
            let disputeResolvedAt: Date?
            enum CodingKeys: String, CodingKey {
                case id
                case paymentState = "payment_state"
                case disputeResolvedAt = "dispute_resolved_at"
            }
        }
        let openPaymentRows: [DisputeThreadRow]? = try? await SupabaseService.client
            .from("dispute_threads").select(Self.disputeThreadSelect)
            .eq("event_id", value: ref.eventId)
            .eq("guest_id", value: guestID.uuidString)
            .eq("kind", value: "payment")
            .is("resolved_at", value: nil)
            .execute().value
        guard myGeneration == conversationDisputeGeneration else { return }

        let candidates = (openPaymentRows ?? []).map { ($0.bookingId, $0.resolvedAt != nil) }
        var states: [UUID: (paymentState: String, disputeResolvedAt: Date?)] = [:]
        let candidateBookingIDs = Array(Set(candidates.compactMap { $0.0 }))
        if !candidateBookingIDs.isEmpty {
            let bookings: [PaymentDisputeBooking]? = try? await SupabaseService.client
                .from("bookings").select("id, payment_state, dispute_resolved_at")
                .in("id", values: candidateBookingIDs.map(\.uuidString))
                .execute().value
            guard myGeneration == conversationDisputeGeneration else { return }
            for b in bookings ?? [] { states[b.id] = (b.paymentState, b.disputeResolvedAt) }
        }
        conversationPaymentDisputeBookingID = Self.livePaymentDisputeBookingID(
            threadRows: candidates, bookingStates: states
        )
        if myGeneration == conversationDisputeGeneration { conversationDisputeLoading = false }
    }

    // MARK: Closing a refund dispute, and downloading its transcript
    // (migration 130). Both are participant-authorized server-side; the
    // client never decides who is allowed to close.

    /// Reads (and caches) the VERIFIED dispute state for one refund claim.
    /// This — not the polled `disputeChats` list — is what every refund entry
    /// point renders from, so a screen reached before any Inbox load (deep
    /// link, cold open, notification) still gets the right actions, the right
    /// "chat with…" label and the right read-only state.
    @discardableResult
    func loadRefundDisputeThread(_ claimID: UUID, force: Bool = false) async -> RefundDisputeThread? {
        if !force, let cached = refundDisputeThreads[claimID] { return cached }
        refundDisputeThreadsLoading.insert(claimID)
        defer { refundDisputeThreadsLoading.remove(claimID) }
        guard let value: RefundDisputeThread = try? await SupabaseService.client
            .rpc("get_refund_dispute_thread", params: ["p_claim_id": claimID.uuidString])
            .execute().value else {
            print("loadRefundDisputeThread failed:", claimID)
            return nil
        }
        guard value.found else {
            refundDisputeThreads.removeValue(forKey: claimID)
            // The goer deleted their own copy (migration 134): remember it, so
            // every screen says so instead of waiting for a dispute that this
            // account can no longer read.
            if value.reason == "deleted_by_you" { refundDisputeDeletedCopies.insert(claimID) }
            return nil
        }
        refundDisputeThreads[claimID] = value
        return value
    }

    /// Close this refund dispute / mark it completed. Either authorized party
    /// may do this; close_refund_dispute() is idempotent server-side, so a
    /// double tap cannot extend the 7-day retention window.
    ///
    /// Explicitly does NOT move any money: refund_claims.status is left
    /// exactly as it was, so the refund stays owed, the host can still mark
    /// it sent afterwards, and the goer can still confirm.
    func closeRefundDispute(_ claimID: UUID) async -> Bool {
        guard refundDisputeClosingClaimId == nil else { return false }
        refundDisputeClosingClaimId = claimID
        disputeCloseError = ""
        defer { refundDisputeClosingClaimId = nil }
        var ok = false
        do {
            let result: ForfeitResult = try await SupabaseService.client
                .rpc("close_refund_dispute", params: ["p_claim_id": claimID.uuidString, "p_note": ""])
                .execute().value
            if result.success == true {
                ok = true
                Haptics.success()
            } else if result.error == "REFUND_NOT_CONFIRMED" {
                disputeCloseError = T(
                    "Chưa đóng được. Người tổ chức cần đánh dấu đã hoàn tiền và khách cần xác nhận đã nhận trước.",
                    "Can't close yet. The host must mark the refund sent and the guest must confirm it was received first.")
            } else if result.error == "ADMIN_RESOLUTION_REQUIRED" {
                disputeCloseError = T(
                    "Tranh chấp này đã được chuyển cho banbe xử lý nên không thể tự đóng ở đây.",
                    "This dispute has been escalated to banbe, so it can't be closed here.")
            } else {
                disputeCloseError = T("Chưa đóng được tranh chấp. Thử lại nhé.", "Couldn't close this dispute. Please try again.")
            }
        } catch {
            print("closeRefundDispute failed:", error)
            disputeCloseError = T("Chưa đóng được tranh chấp. Thử lại nhé.", "Couldn't close this dispute. Please try again.")
        }
        if ok {
            // Every surface has to agree immediately, not on the next poll:
            // the transcript goes read-only, the card flips to
            // "Dispute completed", and the active-dispute indicator clears.
            await loadRefundDisputeChat(claimID)
            await loadRefundDisputeThread(claimID, force: true)
            await loadDisputeChats()
            if let claim = refundDisputeThreads[claimID], conversationRefundDispute?.refundClaimId == claimID {
                conversationRefundDispute = claim
            }
            reloadRefundClaimEverywhere(claimID)
        }
        return ok
    }

    /// Re-reads whichever refund lists this account happens to have loaded,
    /// matching by CLAIM id rather than by the older booking id — a stale
    /// concurrent response keyed by the booking id is exactly how a state
    /// change that already landed used to get overwritten. Lists that were
    /// never loaded are left alone.
    func reloadRefundClaimEverywhere(_ claimID: UUID) {
        if let bookingID = refundBookingIdForClaim(claimID) {
            Task { await loadPaymentRefundClaim(bookingID: bookingID) }
        }
        if myRefunds.contains(where: { $0.id == claimID }) { Task { await loadMyRefunds() } }
        if refundQueue.contains(where: { $0.id == claimID }) { Task { await loadRefundQueue() } }
    }

    private func refundBookingIdForClaim(_ claimID: UUID) -> UUID? {
        if let known = refundDisputeThreads[claimID]?.bookingId { return known }
        if let c = myRefunds.first(where: { $0.id == claimID }) { return c.bookingId ?? c.reservationId }
        if let c = refundQueue.first(where: { $0.id == claimID }) { return c.bookingId ?? c.reservationId }
        if paymentRefundClaim?.id == claimID { return paymentBookingID }
        return nil
    }

    /// Open a refund dispute's chat where it actually lives: inside the
    /// EXISTING booking conversation for this claim, with its dispute block
    /// expanded. Replaces the old hop through the removed yellow Messages
    /// accordion — there is no second conversation to open, and nothing is
    /// matched on event name.
    func openDisputeForRefundClaim(_ claimID: UUID, back: Screen) async {
        guard let claim = await loadRefundDisputeThread(claimID, force: true) else { return }
        openDisputeChatThreadId = claim.disputeThreadId
        expandedDisputeClaimId = claimID
        guard let conversationID = claim.conversationThreadId, let eventID = claim.eventId else {
            // The dispute was raised before anyone ever messaged about this
            // booking, so there is no conversation to render into yet: fall
            // back to the get-or-create open, which creates exactly the one
            // conversation that would have existed anyway (threads is
            // UNIQUE(event_id, guest_id), so it can never duplicate).
            await openChat(for: claim.eventId ?? "", back: back)
            return
        }
        // Both parties open the SAME threads row, so neither needs to know
        // how the other one's Inbox is built.
        let otherName = claim.viewerRole == "organizer" ? "" : (claim.organizerName ?? "")
        openThread(id: conversationID, eventKey: eventID, back: back, otherName: otherName)
    }

    /// The PAYMENT half of the same idea, for the host's escalated-dispute
    /// list: resolve the booking's (event, guest) pair and open the ONE
    /// conversation that already exists for it — never create a second.
    /// Returns false when there is genuinely no conversation to open, so the
    /// caller can say so instead of appearing to do nothing.
    @discardableResult
    func openDisputeForBooking(_ bookingID: UUID, back: Screen) async -> Bool {
        struct BookingRow: Decodable {
            let eventId: String
            let userId: UUID?
            enum CodingKeys: String, CodingKey {
                case eventId = "event_id"
                case userId = "user_id"
            }
        }
        guard let b: BookingRow = try? await SupabaseService.client
            .from("bookings").select("event_id, user_id")
            .eq("id", value: bookingID.uuidString).single().execute().value,
              let guestID = b.userId else { return false }
        struct ThreadRow: Decodable { let id: UUID }
        let threads: [ThreadRow]? = try? await SupabaseService.client
            .from("threads").select("id")
            .eq("event_id", value: b.eventId)
            .eq("guest_id", value: guestID.uuidString)
            .limit(1).execute().value
        guard let threadID = threads?.first?.id else { return false }
        openDisputeChatThreadId = nil
        expandedDisputeClaimId = nil
        openThread(id: threadID, eventKey: b.eventId, back: back, otherName: "")
        return true
    }

    /// Which conversation row, if any, is currently carrying an ACTIVE refund
    /// dispute — drives the red "Dispute in progress" highlight on the Inbox
    /// list. Exact thread-id match (threads is UNIQUE(event_id, guest_id), so
    /// this is a 1:1 conversation identity), never an event-name comparison.
    var activeDisputeConversationThreadIds: Set<UUID> {
        Set(disputeChats.filter(\.isActiveDispute).compactMap(\.conversationThreadId))
    }

    /// Shown while a dispute is active, on both the Inbox row and the dispute
    /// card. Never shown for a concluded one — that collapses back to the
    /// ordinary card with a quiet "Dispute completed" instead.
    var hasActiveDispute: Bool { !activeDisputeConversationThreadIds.isEmpty }


    /// "Refund dispute open › View" in the action center. Opens the EXACT
    /// booking conversation that claim's dispute belongs to, with its dispute
    /// card expanded — not the refund list, which is one more tap away from
    /// the thing the item is about.
    ///
    /// Falls back to the account's refund list when the dispute genuinely has
    /// no conversation yet, so a tap can never land on nothing.
    func openRefundDisputeFromActionCenter(claimID: UUID, back: Screen) {
        Task {
            await openDisputeForRefundClaim(claimID, back: back)
            guard screen != .chat else { return }
            switch back {
            case .dashboard: refundQueueFocusClaimID = claimID; openVerifications(back: .dashboard)
            default: openMyRefunds(back: back)
            }
        }
    }

    /// Backwards-compatible shim for callers that still hold a dispute THREAD
    /// id (an older notification payload, the removed Inbox accordion). It
    /// resolves the CLAIM that thread belongs to and opens the booking
    /// conversation; a thread whose claim isn't in the index is refreshed
    /// once and then dropped rather than silently doing nothing.
    func openDisputeChatInInbox(_ threadID: UUID) {
        if let claimID = disputeThreadClaimIndex[threadID] {
            Task { await openDisputeForRefundClaim(claimID, back: .inbox) }
            return
        }
        Task {
            await loadDisputeChats()
            guard let claimID = disputeThreadClaimIndex[threadID] else { return }
            await openDisputeForRefundClaim(claimID, back: .inbox)
        }
    }

    /// The PHASE 1 counterpart of loadVerifications — how many buyers are
    /// currently holding a seat on this account's own events. There is no
    /// view for this (v_pending_verifications only ever covers PHASE 2), so
    /// it reads bookings directly; the existing bookings_select_host RLS
    /// policy already scopes an organizer to their own events' rows, the
    /// same way it does everywhere else this account reads its own bookings.
    func loadOrganizerHoldingSummary() async {
        guard !myOrganizerIDs.isEmpty else { organizerHoldingSummary = nil; return }
        do {
            let response: PostgrestResponse<[HoldingRow]> = try await SupabaseService.client
                .from("bookings")
                .select("hold_expires_at, events!inner(organizer_id)", count: .exact)
                .eq("payment_state", value: "holding")
                .in("events.organizer_id", values: myOrganizerIDs)
                .order("hold_expires_at", ascending: true)
                .limit(1)
                .execute()
            guard let count = response.count, count > 0 else {
                organizerHoldingSummary = nil
                return
            }
            organizerHoldingSummary = OrganizerHoldingSummary(
                count: count, soonestHoldExpiresAt: response.value.first?.holdExpiresAt)
        } catch {
            print("loadOrganizerHoldingSummary failed:", error)
            organizerHoldingSummary = nil
        }
    }
}

struct PendingVerification: Codable, Identifiable, Hashable {
    let bookingId: UUID
    var eventName: String?
    var guestName: String?
    var qty: Int
    var totalVnd: Int
    var paymentRef: String?
    var transactionId: String?
    var proofSubmittedAt: Date?
    var verifyDueAt: Date?
    var overdue: Bool?
    var escalated: Bool?
    var proofPath: String?
    /// Set by reject_payment() ("Can't find it") — non-nil/non-empty means
    /// a dispute_threads row already exists even though this row is still
    /// in the ordinary queue (not yet escalated). See VerificationsView's
    /// per-row chat entry.
    var disputeReason: String?
    var id: UUID { bookingId }

    enum CodingKeys: String, CodingKey {
        case bookingId = "booking_id"
        case eventName = "event_name"
        case guestName = "guest_name"
        case qty
        case totalVnd = "total_vnd"
        case paymentRef = "payment_ref"
        case transactionId = "transaction_id"
        case proofSubmittedAt = "proof_submitted_at"
        case verifyDueAt = "verify_due_at"
        case overdue, escalated
        case proofPath = "proof_path"
        case disputeReason = "dispute_reason"
    }
}

/// Flow 2 (host refund -> guest confirmation) — refund_claims' own columns
/// plus two enrichment fields the organizer queue fills in client-side
/// after its own batch fetch (guestName/eventName have no corresponding
/// CodingKeys case, so the synthesized decoder leaves them at their
/// default and never tries to decode them from the raw row — same pattern
/// PendingVerification's own decoding relies on for its optional fields).
struct RefundClaim: Codable, Identifiable, Equatable {
    let id: UUID
    var bookingId: UUID?
    var reservationId: UUID?
    var amountVnd: Int
    var reason: String
    var status: String
    var hostMarkedAt: Date?
    var guestConfirmedAt: Date?
    var note: String?
    var createdAt: Date?
    var guestName: String = ""
    var eventName: String = ""
    // Refund MVP additions (migration 072) — deadlines + resend info.
    var refundDueAt: Date?
    var disputedAt: Date?
    var hostResponseDueAt: Date?
    var transferReference: String?
    var resendReference: String?
    var resendBankName: String?
    var resendTransferredAt: Date?
    var resendNote: String?
    // Refund MVP (migration 074) — the goer's EXPLICIT destination choice
    // for this specific claim, snapshotted at selection time. `destination`
    // below is decoded straight from `recipientSnapshot`, never from a live
    // refund_destinations join.
    var selectedDestinationId: UUID?
    var recipientSnapshot: RecipientSnapshot?
    /// Host's optional photo/PDF of the refund transfer (migration 128),
    /// a path in the private 'refund-proof' bucket.
    var proofPath: String?
    // Refund MVP (Refunds list) — filled client-side by loadMyRefunds()
    // only (reuses `eventName` above, decoded as "" by default since that
    // query's own SELECT list has no `guestName`/`eventName` columns).
    var eventKey: String?
    // get_host_refund_claims() (migration 077) returns this straight from
    // its own canonical join — no separate profiles fetch needed.
    var hostGuestName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case bookingId = "booking_id"
        case reservationId = "reservation_id"
        case amountVnd = "amount_vnd"
        case reason, status, note
        case hostMarkedAt = "host_marked_at"
        case guestConfirmedAt = "guest_confirmed_at"
        case createdAt = "created_at"
        case refundDueAt = "refund_due_at"
        case disputedAt = "disputed_at"
        case hostResponseDueAt = "host_response_due_at"
        case transferReference = "transfer_reference"
        case resendReference = "resend_reference"
        case resendBankName = "resend_bank_name"
        case resendTransferredAt = "resend_transferred_at"
        case resendNote = "resend_note"
        case selectedDestinationId = "selected_destination_id"
        case recipientSnapshot = "recipient_snapshot"
        case proofPath = "proof_path"
        case hostGuestName = "guest_name"
        // Investigation fix (2026-10-?? pass) — get_host_refund_claims()
        // (migration 078) returns `event_name`/`event_id` directly in its
        // own canonical join, exactly like `guest_name` above, but neither
        // was ever in this CodingKeys list — `init(from:)` below hardcoded
        // `eventName = ""`/`eventKey = nil` unconditionally instead of
        // decoding them, so every host-queue/Refund-Center row showed a
        // blank event name regardless of what the RPC actually returned.
        // A CodingKeys case must match a real stored property name for
        // Swift to auto-synthesize Encodable (confirmed by the compiler
        // itself: an earlier attempt at a differently-named case here
        // failed with "does not match any stored properties") — using the
        // real `eventName`/`eventKey` names is correct AND harmless for
        // loadMyRefunds()'s own manual post-decode patch (that query's
        // SELECT has no event_id/event_name columns, so decoding this key
        // there just yields nil/"", immediately overwritten by that
        // function's own assignment either way).
        case eventName = "event_name"
        case eventKey = "event_id"
    }

    // Real bug found (2026-10-01): a refund claim visible on web (loosely
    // typed JS — a null/unexpected field just reads as falsy) was silently
    // MISSING ENTIRELY on iOS. Root cause, confirmed by reading the decode
    // path: `[RefundClaim]` used Swift's default synthesized Decodable,
    // which is atomic per element — a single claim with e.g. `amount_vnd`
    // or `reason` null (both were declared non-optional here) throws for
    // the WHOLE array, which get_host_refund_claims() returns as ONE
    // top-level result — so one malformed/edge-case row silently emptied
    // the entire admin/host refund queue, on every platform-wide load, not
    // just that one row. This custom initializer decodes every field
    // defensively (`decodeIfPresent` + a safe default) so no single claim
    // can ever take down the batch again, regardless of which field is
    // eventually null for some future edge case.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        bookingId = try c.decodeIfPresent(UUID.self, forKey: .bookingId)
        reservationId = try c.decodeIfPresent(UUID.self, forKey: .reservationId)
        amountVnd = try c.decodeIfPresent(Int.self, forKey: .amountVnd) ?? 0
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        hostMarkedAt = try c.decodeIfPresent(Date.self, forKey: .hostMarkedAt)
        guestConfirmedAt = try c.decodeIfPresent(Date.self, forKey: .guestConfirmedAt)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        refundDueAt = try c.decodeIfPresent(Date.self, forKey: .refundDueAt)
        disputedAt = try c.decodeIfPresent(Date.self, forKey: .disputedAt)
        hostResponseDueAt = try c.decodeIfPresent(Date.self, forKey: .hostResponseDueAt)
        transferReference = try c.decodeIfPresent(String.self, forKey: .transferReference)
        resendReference = try c.decodeIfPresent(String.self, forKey: .resendReference)
        resendBankName = try c.decodeIfPresent(String.self, forKey: .resendBankName)
        resendTransferredAt = try c.decodeIfPresent(Date.self, forKey: .resendTransferredAt)
        resendNote = try c.decodeIfPresent(String.self, forKey: .resendNote)
        selectedDestinationId = try c.decodeIfPresent(UUID.self, forKey: .selectedDestinationId)
        recipientSnapshot = try? c.decodeIfPresent(RecipientSnapshot.self, forKey: .recipientSnapshot)
        proofPath = try c.decodeIfPresent(String.self, forKey: .proofPath)
        hostGuestName = try c.decodeIfPresent(String.self, forKey: .hostGuestName)
        guestName = hostGuestName ?? ""
        eventName = (try c.decodeIfPresent(String.self, forKey: .eventName)) ?? ""
        eventKey = try c.decodeIfPresent(String.self, forKey: .eventKey)
    }
}

/// TASK B (shared host refund presentation, 2026-09-30 pass) — the ONE
/// shared mapper for "what can a host actually do with this claim", used by
/// both AttendanceView's Refund Center (via RefundCenterClaim, computed at
/// loadRefundCenter()) AND VerificationsView's own refund queue. Mirrors
/// refundClaimPresentation() in src/lib/refundPresentation.js exactly, and
/// goc_refund_snapshot_valid() (migration 075) server-side. Before this,
/// VerificationsView never checked for a valid destination at all — that
/// drift (one screen enforcing this, the other not) is the actual cause of
/// a claim with no valid recipient snapshot still showing an active "Đã
/// hoàn tiền" CTA there.
extension RefundClaim {
    var hasValidDestination: Bool {
        selectedDestinationId != nil
            && !(recipientSnapshot?.bankName.isEmpty ?? true)
            && !(recipientSnapshot?.accountNumber.isEmpty ?? true)
            && !(recipientSnapshot?.accountHolderName.isEmpty ?? true)
    }
    var isActiveRefundStatus: Bool { status == "owed" || status == "disputed" }
    /// Single-claim "Đã hoàn tiền"/mark-sent CTA — owed + valid destination
    /// only. A disputed claim has its own resend/response flow, never this.
    var isRefundActionable: Bool { status == "owed" && hasValidDestination }

    /// A host_marked_sent claim settles itself as confirmed this many days
    /// after the host marked it, if the guest neither confirms nor disputes.
    /// Enforced server-side by goc_auto_confirm_refunds() (migration 127) and
    /// stated in the Terms — change all three together.
    static let autoConfirmDays = 7
    /// When auto-confirmation will happen; nil unless host_marked_sent.
    var autoConfirmAt: Date? {
        guard status == "host_marked_sent", let m = hostMarkedAt else { return nil }
        return Calendar.current.date(byAdding: .day, value: Self.autoConfirmDays, to: m)
    }

    /// One-line description of the account chosen for this claim, e.g.
    /// "Default account ▪︎ Vietcombank ▪︎ NGUYEN VAN A ▪︎ ...1234". nil when
    /// no destination is selected. `destinations` nil (not loaded) skips the
    /// default/different tag rather than guessing.
    func refundAccountSummary(destinations: [RefundDestination]?, T: (String, String) -> String) -> String? {
        guard selectedDestinationId != nil, let s = recipientSnapshot else { return nil }
        var parts: [String] = []
        if let destinations {
            let isDefault = destinations.first(where: \.isDefault)?.id == selectedDestinationId
            parts.append(isDefault ? T("Tài khoản mặc định", "Default account") : T("Tài khoản khác", "Different account"))
        }
        parts.append(s.bankName)
        parts.append(s.accountHolderName)
        parts.append("..." + String(s.accountNumber.suffix(4)))
        return parts.joined(separator: " ▪︎ ")
    }
}

/// Refund MVP (migration 074) — a claim's own `recipient_snapshot` jsonb,
/// decoded directly (never a live join) — a plain copy of whichever
/// refund_destinations row the goer picked, frozen at selection time.
struct RecipientSnapshot: Codable, Equatable {
    var label: String?
    var bankName: String
    var accountNumber: String
    var accountHolderName: String
    /// Uploaded QR frozen into the snapshot (migration 122) — nil for older
    /// snapshots and for accounts without one.
    var qrPath: String?
    var qrPayload: String?
    enum CodingKeys: String, CodingKey {
        case qrPath = "qr_path"
        case qrPayload = "qr_payload"
        case label
        case bankName = "bank_name"
        case accountNumber = "account_number"
        case accountHolderName = "account_holder_name"
    }
}

/// Refund MVP — one of the goer's own saved bank accounts (migration 074:
/// many per user, replacing the earlier one-row-per-user shape).
struct RefundDestination: Codable, Equatable, Identifiable {
    var id: UUID
    var userId: UUID
    var label: String?
    var bankName: String
    var accountNumber: String
    var accountHolderName: String
    var transferNote: String?
    var isDefault: Bool
    var position: Int = 0
    var confirmedAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case label
        case bankName = "bank_name"
        case accountNumber = "account_number"
        case accountHolderName = "account_holder_name"
        case transferNote = "transfer_note"
        case isDefault = "is_default"
        case position
        case confirmedAt = "confirmed_at"
        case updatedAt = "updated_at"
    }
}

/// Refund MVP — one row in the host's per-event Refund Center, a
/// `RefundClaim` joined with the guest's name and a computed eligibility
/// flag (mirrors src/state/GocContext.jsx's own `loadRefundCenter()`
/// enrichment exactly). `destination` is the claim's own snapshot, not a
/// live join — see `RefundClaim.recipientSnapshot`'s own doc comment.
struct RefundCenterClaim: Identifiable, Equatable {
    let claim: RefundClaim
    let guestName: String
    let eligible: Bool
    let needsDestination: Bool
    let overdue: Bool
    var id: UUID { claim.id }
    var destination: RecipientSnapshot? { claim.recipientSnapshot }
    var transferReference: String? { claim.transferReference }
    var amountVnd: Int { claim.amountVnd }
}

/// The jsonb `create_and_confirm_refund_batch()` returns.
struct RefundBatchResult: Decodable, Equatable {
    let success: Bool?
    let batchId: UUID?
    let appliedCount: Int?
    let skippedCount: Int?
    let totalAmountVnd: Int?
    enum CodingKeys: String, CodingKey {
        case success
        case batchId = "batch_id"
        case appliedCount = "applied_count"
        case skippedCount = "skipped_count"
        case totalAmountVnd = "total_amount_vnd"
    }
}

/// PHASE 1 buyer-hold summary for this account's own events — the
/// organizer counterpart of `verifications` (which only ever covers PHASE 2).
struct OrganizerHoldingSummary: Equatable {
    let count: Int
    let soonestHoldExpiresAt: Date?
}

private struct SubmitProofResult: Decodable {
    let success: Bool?
    let error: String?
    let state: String?
    let verifyDueAt: Date?

    enum CodingKeys: String, CodingKey {
        case success, error, state
        case verifyDueAt = "verify_due_at"
    }
}

private struct NudgeResult: Decodable {
    let success: Bool?
    let error: String?
    let nudgeCount: Int?

    enum CodingKeys: String, CodingKey {
        case success, error
        case nudgeCount = "nudge_count"
    }
}

private struct RequestReceiptResult: Decodable {
    let success: Bool?
    let error: String?
}

/// Shared by forfeitExpiredHold (AppState+Data.swift) — not private, since
/// that function lives in a different file within the same module.
struct ForfeitResult: Decodable {
    let success: Bool?
    let error: String?
    let state: String?
}

private struct SubmitProofParams: Encodable {
    let booking: String
    let transactionID: String
    let proofPath: String
    let ip: String?
    let userAgent: String
    let slaMinutes: Int
    enum CodingKeys: String, CodingKey {
        case booking = "p_booking"
        case transactionID = "p_transaction_id"
        case proofPath = "p_proof_path"
        case ip = "p_ip"
        case userAgent = "p_user_agent"
        case slaMinutes = "p_sla_minutes"
    }
}

/// Typed params for send_refund_dispute_attachment() (migration 131) —
/// the same Encodable-with-CodingKeys convention every other multi-parameter
/// RPC call in this file uses, rather than a `[String: Any]` dictionary: the
/// two optional pixel dimensions must encode as real JSON nulls, not as a
/// Swift Optional smuggled through `Any`.
private struct RefundDisputeAttachmentParams: Encodable {
    let claimID: String
    let body: String
    let path: String
    let type: String
    let width: Int?
    let height: Int?
    enum CodingKeys: String, CodingKey {
        case claimID = "p_refund_claim_id"
        case body = "p_body"
        case path = "p_attachment_path"
        case type = "p_attachment_type"
        case width = "p_attachment_width"
        case height = "p_attachment_height"
    }
}

private struct VerifyPaymentParams: Encodable {
    let booking: String
    let via: String
    let actorKind: String
    enum CodingKeys: String, CodingKey {
        case booking = "p_booking"
        case via = "p_via"
        case actorKind = "p_actor_kind"
    }
}

private struct SaveRefundDestinationParams: Encodable {
    let id: String?
    let label: String?
    let bankName: String
    let accountNumber: String
    let accountHolderName: String
    let transferNote: String?
    let setDefault: Bool
    let confirmed: Bool
    enum CodingKeys: String, CodingKey {
        case id = "p_id"
        case label = "p_label"
        case bankName = "p_bank_name"
        case accountNumber = "p_account_number"
        case accountHolderName = "p_account_holder_name"
        case transferNote = "p_transfer_note"
        case setDefault = "p_set_default"
        case confirmed = "p_confirmed"
    }
}

/// `pEventId: nil` requests every claim across every event the caller
/// hosts (Verifications' Account-level queue); a value scopes to one event
/// (Attendance's Refund Center) — see get_host_refund_claims() (078).
private struct GetHostRefundClaimsParams: Encodable {
    let pEventId: String?
    enum CodingKeys: String, CodingKey { case pEventId = "p_event_id" }
}

private struct CreateRefundBatchParams: Encodable {
    let claimIds: [String]
    let note: String
    enum CodingKeys: String, CodingKey {
        case claimIds = "p_claim_ids"
        case note = "p_note"
    }
}

private struct ResendRefundTransferInfoParams: Encodable {
    let claimId: String
    let reference: String
    let bankName: String
    let transferredAt: String?
    enum CodingKeys: String, CodingKey {
        case claimId = "p_claim_id"
        case reference = "p_reference"
        case bankName = "p_bank_name"
        case transferredAt = "p_transferred_at"
    }
}

private struct ResolveDisputeParams: Encodable {
    let booking: String
    let uphold: Bool
    let resolution: String
    let reasonCategory: String
    enum CodingKeys: String, CodingKey {
        case booking = "p_booking"
        case uphold = "p_uphold"
        case resolution = "p_resolution"
        case reasonCategory = "p_reason_category"
    }
}

/// Mirrors public.dispute_reason_category (migration 047) exactly — the
/// anonymized classification that feeds dispute_resolution_stats, kept
/// separate from the free-text resolution note (never aggregated). Not
/// enforced as required at the DB layer (resolve_dispute defaults to
/// 'other'), but AdminDashboardView has the admin pick one every time so
/// the quality-review view isn't just a pile of 'other'.
enum DisputeReasonCategory: String, CaseIterable, Identifiable {
    case proofNotFound = "proof_not_found"
    case wrongAmount = "wrong_amount"
    case duplicateClaim = "duplicate_claim"
    case expiredOrLate = "expired_or_late"
    case other

    var id: String { rawValue }

    @MainActor func label(_ app: AppState) -> String {
        switch self {
        case .proofNotFound: return app.T("Không tìm thấy khoản thanh toán", "Payment not found")
        case .wrongAmount: return app.T("Sai số tiền", "Wrong amount")
        case .duplicateClaim: return app.T("Trùng biên lai/mã giao dịch", "Duplicate proof/reference")
        case .expiredOrLate: return app.T("Nộp biên lai trễ hạn", "Submitted after the window")
        case .other: return app.T("Khác", "Other")
        }
    }
}
