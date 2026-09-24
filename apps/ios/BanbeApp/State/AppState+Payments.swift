import Foundation
import Supabase
import UIKit

// Payments and documents — the iOS half of what GocContext.jsx does for the
// web app. banbe never holds the money on either platform; what these carry
// is where to send it, the evidence it was sent, and the paperwork after.
extension AppState {

    // MARK: - What the guest owes, and to whom

    func loadPaymentBookings() async {
        guard let uid = userID else {
            paymentBookings = []
            paymentsLoading = false
            return
        }
        paymentsLoading = true
        do {
            let rows: [PayableBookingRow] = try await SupabaseService.client
                .from("bookings")
                .select("""
                    id, qty, total_vnd, code, status, paid_marked_at, proof_uploaded_at, created_at, event_id,
                    payment_state, payment_ref, hold_expires_at, transaction_id, verify_due_at, dispute_reason, cancel_reason, nudge_count,
                    events(name, organizers(name, pay_methods, bank_name, bank_account_name,
                                            bank_account_no, momo_phone, pay_note))
                    """)
                .eq("user_id", value: uid.uuidString)
                .order("created_at", ascending: false)
                .execute().value
            paymentBookings = rows.map(\.asPayable)
            paymentsLoading = false
        } catch {
            print("loadPaymentBookings failed:", error)
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
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
                    ? T("Bạn vừa yêu cầu gần đây — hãy đợi người tổ chức phản hồi.", "You already asked recently — give the organizer a little time to respond.")
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
        payoutSaved = false
        screen = .payout
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

    func openDocuments(kind: String, role: String) {
        documentsKind = kind
        documentsRole = role
        documents = []
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
            UINotificationFeedbackGenerator().notificationOccurred(.success)
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
            nudgeCount: nudgeCount ?? 0
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
            UINotificationFeedbackGenerator().notificationOccurred(.success)
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

    func approvePayment(_ bookingID: UUID) async {
        verificationBusy = bookingID
        defer { verificationBusy = nil }
        do {
            _ = try await SupabaseService.client
                .rpc("verify_payment", params: VerifyPaymentParams(
                    booking: bookingID.uuidString, via: "organizer", actorKind: "organizer"))
                .execute()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
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

    /// The organizer's own refund queue — the smallest addition to this
    /// screen's existing surface, per this ticket's own ask, not a new
    /// screen. Only flat `.in()` queries (mirrors
    /// loadNotificationAvatarMaps()'s own batch-fetch shape) — no embedded-
    /// resource FK hints, since this session has no live database to
    /// verify the exact constraint names against.
    func loadRefundQueue() async {
        guard isAdmin || !myOrganizerIDs.isEmpty else { refundQueue = []; return }
        refundQueueLoading = true
        do {
            let claims: [RefundClaim] = try await SupabaseService.client
                .from("refund_claims").select("id, booking_id, reservation_id, amount_vnd, reason, status, host_marked_at, guest_confirmed_at, note, created_at, refund_due_at, disputed_at, host_response_due_at, transfer_reference, resend_reference, resend_bank_name, resend_transferred_at, resend_note")
                .in("status", values: ["owed", "disputed"])
                .order("created_at", ascending: true)
                .execute().value
            let bookingIDs = Set(claims.compactMap { $0.bookingId ?? $0.reservationId })
            var bookingByID: [UUID: RefundClaimBookingRow] = [:]
            if !bookingIDs.isEmpty {
                let bookings: [RefundClaimBookingRow] = try await SupabaseService.client
                    .from("bookings").select("id, user_id, event_id")
                    .in("id", values: bookingIDs.map(\.uuidString))
                    .execute().value
                for b in bookings { bookingByID[b.id] = b }
            }
            let eventIDs = Set(bookingByID.values.compactMap(\.eventId))
            var eventByID: [String: RefundClaimEventRow] = [:]
            if !eventIDs.isEmpty {
                let events: [RefundClaimEventRow] = try await SupabaseService.client
                    .from("events").select("id, name, organizer_id")
                    .in("id", values: Array(eventIDs))
                    .execute().value
                for e in events { eventByID[e.id] = e }
            }
            // Defense in depth, same reasoning as loadVerifications() above
            // — RLS already scopes refund_claims_select_host to the
            // caller's own organizer(s).
            let scoped = isAdmin ? claims : claims.filter { c in
                guard let b = bookingByID[c.bookingId ?? c.reservationId ?? UUID()],
                      let eventID = b.eventId, let ev = eventByID[eventID],
                      let organizerID = ev.organizerId else { return false }
                return myOrganizerIDs.contains(organizerID)
            }
            let userIDs = Set(scoped.compactMap { bookingByID[$0.bookingId ?? $0.reservationId ?? UUID()]?.userId })
            var nameByUserID: [UUID: String] = [:]
            if !userIDs.isEmpty {
                let profiles: [RefundClaimProfileRow] = try await SupabaseService.client
                    .from("profiles").select("id, display_name")
                    .in("id", values: userIDs.map(\.uuidString))
                    .execute().value
                for p in profiles { nameByUserID[p.id] = p.displayName ?? "" }
            }
            refundQueue = scoped.map { c in
                var claim = c
                if let b = bookingByID[c.bookingId ?? c.reservationId ?? UUID()] {
                    claim.guestName = b.userId.flatMap { nameByUserID[$0] } ?? ""
                    claim.eventName = b.eventId.flatMap { eventByID[$0]?.name } ?? ""
                }
                return claim
            }
        } catch {
            print("loadRefundQueue failed:", error)
            refundQueue = []
        }
        refundQueueLoading = false
    }

    /// Host's "Đã hoàn tiền" — owed -> host_marked_sent. TASK C fix:
    /// mark_refund_sent() (migration 075) now rejects a claim with no
    /// valid recipient snapshot (NO_DESTINATION_SELECTED), surfaced here
    /// instead of the previous silent print-only failure. Returns whether
    /// it succeeded so callers (AttendanceView's "Hoàn lại lần nữa") know
    /// whether to also refresh their own Refund Center view.
    @discardableResult
    func markRefundSent(_ claimID: UUID, note: String = "") async -> Bool {
        refundActionBusy = claimID
        refundBatchError = ""
        defer { refundActionBusy = nil }
        var ok = false
        do {
            let result: RpcResult = try await SupabaseService.client
                .rpc("mark_refund_sent", params: ["p_claim_id": claimID.uuidString, "p_note": note])
                .execute().value
            if result.success == true {
                ok = true
            } else {
                refundBatchError = result.error == "NO_DESTINATION_SELECTED"
                    ? T("Chưa thể đánh dấu đã hoàn tiền. Khách cần chọn tài khoản nhận trước.", "Cannot mark this refund sent yet — the guest needs to choose a destination first.")
                    : T("Không thể cập nhật lúc này. Vui lòng thử lại.", "Could not update right now. Please try again.")
            }
        } catch {
            print("markRefundSent failed:", error)
            refundBatchError = T("Không thể cập nhật lúc này. Vui lòng thử lại.", "Could not update right now. Please try again.")
        }
        await loadRefundQueue()
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
                .from("refund_claims").select("id, booking_id, reservation_id, amount_vnd, reason, status, host_marked_at, guest_confirmed_at, note, created_at, refund_due_at, disputed_at, host_response_due_at, transfer_reference, resend_reference, resend_bank_name, resend_transferred_at, resend_note")
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
                .from("refund_claims").select("id, booking_id, reservation_id, amount_vnd, reason, status, host_marked_at, guest_confirmed_at, note, created_at, refund_due_at, disputed_at, host_response_due_at, transfer_reference, resend_reference, resend_bank_name, resend_transferred_at, resend_note")
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
        guard let uid = user?.id else { refundDestinations = []; return }
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
            if !ok { refundDestinationError = T("Hiện chưa thể thực hiện. Vui lòng thử lại sau.", "This isn't available right now. Please try again later.") }
        } catch {
            print("selectRefundDestinationForClaim failed:", error)
            refundDestinationError = T("Hiện chưa thể thực hiện. Vui lòng thử lại sau.", "This isn't available right now. Please try again later.")
        }
        if ok { await loadPaymentRefundClaim(claimID: claimID) }
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
                .select("id, booking_id, reservation_id, amount_vnd, status, host_marked_at, disputed_at, host_response_due_at, refund_due_at, created_at")
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
        refundCenterLoading = true
        defer { refundCenterLoading = false }
        guard let eventUUID = UUID(uuidString: eventKey) else { return }
        do {
            let result: GetHostRefundClaimsResult = try await SupabaseService.client
                .rpc("get_host_refund_claims", params: ["p_event_id": eventUUID.uuidString])
                .execute().value
            guard result.success == true else {
                print("loadRefundCenter failed:", result.error ?? "unknown", "eventKey:", eventKey, "userID:", userID?.uuidString ?? "nil")
                return
            }
            let claims = result.claims ?? []
            let now = Date()
            let enriched = claims.map { c -> RefundCenterClaim in
                // TASK C — matches the server's own goc_refund_snapshot_valid()
                // (migration 075): a bare selectedDestinationId with no real
                // snapshot content must never read as "has a destination".
                let hasDestination = c.selectedDestinationId != nil
                    && !(c.recipientSnapshot?.bankName.isEmpty ?? true)
                    && !(c.recipientSnapshot?.accountNumber.isEmpty ?? true)
                    && !(c.recipientSnapshot?.accountHolderName.isEmpty ?? true)
                let isActive = c.status == "owed" || c.status == "disputed"
                let overdue = (c.status == "owed" && (c.refundDueAt.map { $0 < now } ?? false))
                    || (c.status == "disputed" && (c.hostResponseDueAt.map { $0 < now } ?? false))
                return RefundCenterClaim(
                    claim: c,
                    guestName: c.hostGuestName?.isEmpty == false ? c.hostGuestName! : T("Khách", "Guest"),
                    eligible: hasDestination && isActive,
                    needsDestination: isActive && !hasDestination,
                    overdue: overdue
                )
            }
            let eligibleIDs = Set(enriched.filter(\.eligible).map(\.id))
            refundCenterClaims = enriched
            refundCenterSelected = refundCenterSelected.intersection(eligibleIDs)
        } catch {
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

    func loadDisputeChat(_ bookingID: UUID, retried: Bool = false) async {
        disputeChatBookingId = bookingID
        disputeChatMessages = []
        disputeChatThread = nil
        disputeChatLoading = true
        disputeChatError = ""
        defer { disputeChatLoading = false }
        struct ThreadRow: Decodable { let id: UUID; let resolvedAt: Date?; let purgeAfter: Date?
            enum CodingKeys: String, CodingKey { case id; case resolvedAt = "resolved_at"; case purgeAfter = "purge_after" } }
        do {
            let thread: ThreadRow = try await SupabaseService.client
                .from("dispute_threads").select("id, resolved_at, purge_after")
                .eq("booking_id", value: bookingID.uuidString)
                .single().execute().value
            disputeChatMessages = try await SupabaseService.client
                .from("dispute_messages").select()
                .eq("dispute_thread_id", value: thread.id.uuidString)
                .order("created_at", ascending: true)
                .execute().value
            // Read-only — drives the retention countdown label
            // (DisputeChatPanel.swift) instead of a delete button, since
            // dispute_messages must survive until the 72h purge
            // (05-notify-retention.md).
            disputeChatThread = (resolvedAt: thread.resolvedAt, purgeAfter: thread.purgeAfter)
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
            disputeChatError = T("Không tải được đoạn chat. Thử lại nhé.", "Couldn't load this chat. Please try again.")
        }
    }

    func sendDisputeMessage(_ bookingID: UUID) async {
        let body = disputeChatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        disputeChatDraft = ""
        disputeChatError = ""
        do {
            let result: ForfeitResult = try await SupabaseService.client
                .rpc("send_dispute_message", params: ["p_booking": bookingID.uuidString, "p_body": body])
                .execute().value
            if result.success == false {
                print("sendDisputeMessage failed:", result.error ?? "unknown")
                disputeChatDraft = body
                disputeChatError = T("Chưa gửi được. Thử lại nhé.", "Couldn't send. Please try again.")
                return
            }
        } catch {
            print("sendDisputeMessage failed:", error)
            disputeChatDraft = body
            disputeChatError = T("Chưa gửi được. Thử lại nhé.", "Couldn't send. Please try again.")
            return
        }
        await loadDisputeChat(bookingID)
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
        case hostGuestName = "guest_name"
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
    enum CodingKeys: String, CodingKey {
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
