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
            // Documents are organizer-uploaded now (migration 056) — nothing
            // to mint here anymore. `superseded_at IS NULL` hides a replaced
            // version immediately (Task 5's soft-delete: the row itself
            // still exists, queryable for 24h, but never in this list).
            var query = SupabaseService.client
                .from("payment_documents").select("*")
                .eq("kind", value: documentsKind)
                .is("superseded_at", value: nil)

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
            documentUploadError = "\(error)".contains("REASON_REQUIRED")
                ? T("Cần nêu lý do khi thay thế chứng từ đã có.", "A reason is required when replacing an existing document.")
                : T("Không tải lên được. Thử lại nhé.", "Couldn't upload. Please try again.")
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
    func openVerifications() {
        guard canHost else { return }
        screen = .verifications
        verifications = []
        verificationsFocusBookingID = nil
        Task { await loadVerifications() }
    }

    /// 14-organizer-checkin.md: Attendance's "Check payment" — jumps
    /// straight to this one booking's own row, whether it's the only
    /// pending item or buried far down a long queue. Same event-ownership
    /// guard as bug 1's openNotification() fix (myOrgEventKeys, not just
    /// the account-wide canHost check) since this is reachable from a bell
    /// notification tap too, not just Attendance's own (already-scoped) list.
    func openVerificationDetail(bookingID: UUID, eventKey: String?) {
        if let eventKey, !myOrgEventKeys.contains(eventKey) { return }
        guard canHost else { return }
        screen = .verifications
        verifications = []
        verificationsFocusBookingID = bookingID
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
