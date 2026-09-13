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
                    payment_state, payment_ref, hold_expires_at, transaction_id, verify_due_at,
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
            // a booking the uploader owns.
            let path = "\(bookingID.uuidString)/proof-\(Int(Date().timeIntervalSince1970)).\(fileExtension)"
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
            // As a guest, mint any missing invoice first. ensure_payment_document
            // is idempotent, so this fills the gaps once and is a no-op after.
            // Receipts are never minted here — only an organizer confirming
            // payment can create one.
            if documentsRole == "guest" && documentsKind == "invoice" {
                let mine: [BookingIDRow] = try await SupabaseService.client
                    .from("bookings").select("id")
                    .eq("user_id", value: uid.uuidString)
                    .in("status", values: ["pending", "confirmed", "attended"])
                    .execute().value
                for row in mine {
                    _ = try? await SupabaseService.client
                        .rpc("ensure_payment_document", params: [
                            "p_booking": row.id.uuidString, "p_kind": "invoice",
                        ])
                        .execute()
                }
            }

            var query = SupabaseService.client
                .from("payment_documents").select("*")
                .eq("kind", value: documentsKind)

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

    func openDocument(_ id: UUID) {
        documentID = id
        screen = .documentView
    }

    var currentDocument: PaymentDocument? {
        documents.first { $0.id == documentID }
    }

    /// The URL the document viewer loads. Rendering happens server-side with
    /// the very same module the web app prints from (api/payment-document.js),
    /// so a receipt can't look one way on iOS and another on the web. The
    /// access token goes in a header, set on the web view's own request.
    func documentURL(_ id: UUID) -> URL? {
        URL(string: "\(AppConfig.apiBaseURL)/api/payment-document?id=\(id.uuidString.lowercased())&lang=\(lang)")
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
            payNote: org?.payNote ?? ""
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
            try await SupabaseService.client.auth.refreshSession()

            let path = "\(bookingID.uuidString)/proof-\(Int(Date().timeIntervalSince1970)).\(fileExtension)"
            _ = try await SupabaseService.client.storage
                .from("pay-proof")
                .upload(path, data: imageData,
                        options: FileOptions(contentType: fileExtension == "pdf" ? "application/pdf" : "image/jpeg",
                                             upsert: true))
<<<<<<< HEAD
=======
            _ = try await SupabaseService.client.auth.getSession()
>>>>>>> parent of 3fd2822 (refactor(ios): use session refresh instead of session retrieval during proof upload)

            let result: SubmitProofResult = try await SupabaseService.client
                .rpc("submit_payment_proof", params: SubmitProofParams(
                    booking: bookingID.uuidString, transactionID: txn, proofPath: path,
                    ip: nil, userAgent: "banbe-ios", slaMinutes: 15))
                .execute().value

            if result.success == false {
                paymentProofError = {
                    switch result.error ?? "" {
                    case "HOLD_EXPIRED_AND_SOLD_OUT":
                        return T("Rất tiếc, chỗ đã hết trong lúc chờ thanh toán. Hãy liên hệ người tổ chức để được hoàn tiền.",
                                 "Sorry — the seat sold out while this was pending. Contact the organizer for a refund.")
                    case "AUTH_REQUIRED":
                        return T("Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.", "Your session has expired. Please sign in again.")
                    case "BOOKING_NOT_FOUND":
                        return T("Không tìm thấy đặt chỗ này.", "This booking could not be found.")
                    case "NOT_AUTHORIZED":
                        return T("Bạn không được phép thực hiện thao tác này.", "You are not authorized to perform this action.")
                    case "INVALID_STATE":
                        return T("Trạng thái đặt chỗ không cho phép thao tác này.", "This booking can't be processed in its current state.")
                    default:
                        return T("Chưa gửi được. Thử lại nhé.", "Couldn't submit. Please try again.")
                    }
                }()
                paymentProofUploading = false
                return
            }

            paymentTxnId = ""
            paymentProofUploading = false
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await loadPaymentBookings()
        } catch {
            print("submitPaymentProof failed:", error)
            paymentProofUploading = false
            let raw = "\(error)"
            if raw.contains("session") || raw.contains("Session") || raw.contains("Unauthorized") || raw.contains("unauthorized") {
                paymentProofError = T("Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.", "Your session has expired. Please sign in again.")
            } else if raw.isEmpty {
                paymentProofError = T("Chưa gửi được. Thử lại nhé.", "Couldn't submit. Please try again.")
            } else {
                paymentProofError = T("Đã có lỗi: \(raw)", "Something went wrong: \(raw)")
            }
        }
    }

    // MARK: Organizer verification queue

    func openVerifications() {
        screen = .verifications
        verifications = []
        Task { await loadVerifications() }
    }

    func loadVerifications() async {
        guard userID != nil else { verifications = []; return }
        verificationsLoading = true
        do {
            verifications = try await SupabaseService.client
                .from("v_pending_verifications").select()
                .order("proof_submitted_at", ascending: true)
                .execute().value
        } catch {
            print("loadVerifications failed:", error)
            verifications = []
        }
        verificationsLoading = false
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
