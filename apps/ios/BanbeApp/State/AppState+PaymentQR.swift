import Foundation
import Supabase

/// An uploaded payment QR: where its image lives in storage, and the text
/// that was decoded from it on-device (what a long-press hands to the
/// payment app).
struct PayQR: Equatable {
    var path: String
    var payload: String
    var isEmpty: Bool { path.isEmpty }
}

/// Uploaded payment QR codes — host "Getting Paid" QR (bucket `pay-qr`,
/// `organizers.pay_qr_path`/`pay_qr_payload`) and an attendee's refund-account
/// QR (bucket `refund-qr`, `refund_destinations.qr_path`/`qr_payload`),
/// migration 122.
///
/// Every read here is its own small, failure-tolerant query. Deliberately NOT
/// folded into the existing payment/refund selects: those load for every
/// user, and a new column there would break them outright until migration 122
/// is applied. If it isn't, these just come back empty.
extension AppState {

    private struct QRRpcResult: Decodable {
        let success: Bool?
        let error: String?
    }

    private struct PayQRColumns: Decodable {
        let payQrPath: String?
        let payQrPayload: String?
        enum CodingKeys: String, CodingKey {
            case payQrPath = "pay_qr_path"
            case payQrPayload = "pay_qr_payload"
        }
    }

    private struct EventOrganizerQR: Decodable {
        let organizers: PayQRColumns?
    }

    private struct DestinationQRRow: Decodable {
        let id: UUID
        let qrPath: String?
        let qrPayload: String?
        enum CodingKeys: String, CodingKey {
            case id
            case qrPath = "qr_path"
            case qrPayload = "qr_payload"
        }
    }

    private func qrErrorMessage() -> String {
        T("Chưa lưu được mã QR. Thử lại nhé.", "Couldn't save the QR code. Please try again.")
    }

    // MARK: Host — Getting Paid

    func loadPayoutQR() async {
        guard let orgID = myOrganizerIDs.first else { return }
        do {
            let row: PayQRColumns = try await SupabaseService.client
                .from("organizers")
                .select("pay_qr_path, pay_qr_payload")
                .eq("id", value: orgID)
                .single().execute().value
            payoutQR = PayQR(path: row.payQrPath ?? "", payload: row.payQrPayload ?? "")
        } catch {
            print("loadPayoutQR failed:", error)
        }
    }

    func uploadPayoutQR(_ prepared: PaymentQR.Prepared) async {
        guard let orgID = myOrganizerIDs.first else {
            payoutQRError = T("Chưa có trang tổ chức.", "No host page yet.")
            return
        }
        payoutQRBusy = true
        payoutQRError = ""
        defer { payoutQRBusy = false }
        let previous = payoutQR.path
        let path = "\(orgID)/qr-\(Int(Date().timeIntervalSince1970)).jpg"
        do {
            _ = try await SupabaseService.client.storage
                .from("pay-qr")
                .upload(path, data: prepared.jpeg, options: FileOptions(contentType: "image/jpeg", upsert: true))
            _ = try await SupabaseService.client
                .rpc("set_organizer_pay_qr", params: [
                    "p_organizer": orgID, "p_path": path, "p_payload": prepared.payload,
                ])
                .execute()
            payoutQR = PayQR(path: path, payload: prepared.payload)
            payoutSaved = false
            if !previous.isEmpty, previous != path {
                _ = try? await SupabaseService.client.storage.from("pay-qr").remove(paths: [previous])
            }
        } catch {
            print("uploadPayoutQR failed:", error)
            payoutQRError = qrErrorMessage()
        }
    }

    func removePayoutQR() async {
        guard let orgID = myOrganizerIDs.first, !payoutQR.isEmpty else { return }
        payoutQRBusy = true
        payoutQRError = ""
        defer { payoutQRBusy = false }
        let previous = payoutQR.path
        do {
            _ = try await SupabaseService.client
                .rpc("set_organizer_pay_qr", params: ["p_organizer": orgID, "p_path": "", "p_payload": ""])
                .execute()
            payoutQR = PayQR(path: "", payload: "")
            _ = try? await SupabaseService.client.storage.from("pay-qr").remove(paths: [previous])
        } catch {
            print("removePayoutQR failed:", error)
            payoutQRError = qrErrorMessage()
        }
    }

    // MARK: Payer — the host's QR for a booking's event

    func loadPayQR(forEventKey eventKey: String) async {
        do {
            let row: EventOrganizerQR = try await SupabaseService.client
                .from("events")
                .select("organizers(pay_qr_path, pay_qr_payload)")
                .eq("id", value: eventKey)
                .single().execute().value
            let qr = PayQR(path: row.organizers?.payQrPath ?? "", payload: row.organizers?.payQrPayload ?? "")
            payQRByEvent[eventKey] = qr
        } catch {
            print("loadPayQR failed:", error)
        }
    }

    // MARK: Attendee — refund accounts

    func loadRefundDestinationQRs() async {
        guard let uid = user?.id else { refundDestinationQR = [:]; return }
        do {
            let rows: [DestinationQRRow] = try await SupabaseService.client
                .from("refund_destinations")
                .select("id, qr_path, qr_payload")
                .eq("user_id", value: uid.uuidString)
                .execute().value
            var map: [UUID: PayQR] = [:]
            for r in rows {
                if let p = r.qrPath, !p.isEmpty { map[r.id] = PayQR(path: p, payload: r.qrPayload ?? "") }
            }
            refundDestinationQR = map
        } catch {
            print("loadRefundDestinationQRs failed:", error)
        }
    }

    /// Attach (or replace) the QR on one of the user's own saved accounts.
    @discardableResult
    func uploadRefundDestinationQR(_ destinationID: UUID, _ prepared: PaymentQR.Prepared) async -> Bool {
        guard let uid = user?.id else { return false }
        refundDestinationQRBusy = true
        refundDestinationError = ""
        defer { refundDestinationQRBusy = false }
        let previous = refundDestinationQR[destinationID]?.path
        let path = "\(uid.uuidString.lowercased())/\(destinationID.uuidString.lowercased())-\(Int(Date().timeIntervalSince1970)).jpg"
        do {
            _ = try await SupabaseService.client.storage
                .from("refund-qr")
                .upload(path, data: prepared.jpeg, options: FileOptions(contentType: "image/jpeg", upsert: true))
            let result: QRRpcResult = try await SupabaseService.client
                .rpc("set_refund_destination_qr", params: [
                    "p_id": destinationID.uuidString, "p_qr_path": path, "p_qr_payload": prepared.payload,
                ])
                .execute().value
            guard result.success != false else {
                refundDestinationError = qrErrorMessage()
                return false
            }
            refundDestinationQR[destinationID] = PayQR(path: path, payload: prepared.payload)
            if let previous, !previous.isEmpty, previous != path {
                _ = try? await SupabaseService.client.storage.from("refund-qr").remove(paths: [previous])
            }
            return true
        } catch {
            print("uploadRefundDestinationQR failed:", error)
            refundDestinationError = qrErrorMessage()
            return false
        }
    }

    func removeRefundDestinationQR(_ destinationID: UUID) async {
        guard let existing = refundDestinationQR[destinationID], !existing.isEmpty else { return }
        refundDestinationQRBusy = true
        refundDestinationError = ""
        defer { refundDestinationQRBusy = false }
        do {
            let result: QRRpcResult = try await SupabaseService.client
                .rpc("set_refund_destination_qr", params: ["p_id": destinationID.uuidString])
                .execute().value
            guard result.success != false else {
                refundDestinationError = qrErrorMessage()
                return
            }
            refundDestinationQR[destinationID] = nil
            _ = try? await SupabaseService.client.storage.from("refund-qr").remove(paths: [existing.path])
        } catch {
            print("removeRefundDestinationQR failed:", error)
            refundDestinationError = qrErrorMessage()
        }
    }
}
