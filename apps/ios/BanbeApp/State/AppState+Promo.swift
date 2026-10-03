import Foundation
import Supabase

/// Host promotional messages (migration 123). Consent is a separate,
/// server-stored choice (default OFF) — never tied to sign-in. A host can only
/// ever be handed ONE consenting recipient at a time, and the server rechecks
/// host permission, consent and audience immediately before revealing that
/// recipient's phone.
struct PromoRecipient: Decodable, Equatable {
    let id: UUID
    let displayName: String
    let locale: String
    enum CodingKeys: String, CodingKey { case id, displayName = "display_name", locale }
}

struct PromoCompose: Decodable, Equatable {
    let logId: UUID
    let phone: String
    let displayName: String
    let locale: String
    let eventName: String
    let organizerId: String
    let organizerName: String
    enum CodingKeys: String, CodingKey {
        case logId = "log_id", phone, displayName = "display_name", locale
        case eventName = "event_name", organizerId = "organizer_id", organizerName = "organizer_name"
    }
}

enum PromoError: Equatable { case notAuthorized, rateLimited, notEligible, gate, other }

extension AppState {

    private struct ConsentResult: Decodable {
        let success: Bool?
        let consented: Bool?
        let error: String?
    }

    private struct NextResult: Decodable {
        let success: Bool?
        let error: String?
        let recipient: PromoRecipient?
    }

    private struct BeginResult: Decodable {
        let success: Bool?
        let error: String?
        let logId: UUID?
        let phone: String?
        let displayName: String?
        let locale: String?
        let eventName: String?
        let organizerId: String?
        let organizerName: String?
        enum CodingKeys: String, CodingKey {
            case success, error, logId = "log_id", phone, displayName = "display_name", locale
            case eventName = "event_name", organizerId = "organizer_id", organizerName = "organizer_name"
        }
    }

    // MARK: Consent (Account -> Security)

    func loadHostPromoConsent() async {
        do {
            let r: ConsentResult = try await SupabaseService.client.rpc("get_host_promo_consent").execute().value
            if r.success == true { hostPromoConsent = r.consented ?? false }
        } catch {
            print("loadHostPromoConsent failed")
        }
    }

    /// Returns true when the server stored the choice.
    @discardableResult
    func setHostPromoConsent(_ enabled: Bool) async -> Bool {
        hostPromoConsentBusy = true
        hostPromoConsentError = ""
        defer { hostPromoConsentBusy = false }
        do {
            let r: ConsentResult = try await SupabaseService.client
                .rpc("set_host_promo_consent", params: ["p_enabled": enabled]).execute().value
            guard r.success == true else {
                hostPromoConsentError = T("Chưa lưu được lựa chọn. Thử lại sau.", "Couldn't save your choice. Please try again.")
                return false
            }
            hostPromoConsent = r.consented ?? enabled
            return true
        } catch {
            hostPromoConsentError = T("Chưa lưu được lựa chọn. Thử lại sau.", "Couldn't save your choice. Please try again.")
            return false
        }
    }

    // MARK: Host: one recipient at a time

    func nextPromoRecipient(eventKey: String) async -> (PromoRecipient?, PromoError?) {
        do {
            let r: NextResult = try await SupabaseService.client
                .rpc("next_promo_recipient", params: ["p_event_id": eventKey]).execute().value
            if r.success == true { return (r.recipient, nil) }
            return (nil, Self.promoError(r.error))
        } catch { return (nil, .other) }
    }

    /// Rechecks everything server-side and only then returns the recipient's phone.
    func beginPromoCompose(eventKey: String, recipientID: UUID) async -> (PromoCompose?, PromoError?) {
        do {
            let r: BeginResult = try await SupabaseService.client
                .rpc("begin_promo_compose", params: ["p_event_id": eventKey, "p_recipient_id": recipientID.uuidString])
                .execute().value
            guard r.success == true, let log = r.logId, let phone = r.phone else { return (nil, Self.promoError(r.error)) }
            return (PromoCompose(logId: log, phone: phone, displayName: r.displayName ?? "", locale: r.locale ?? "vi",
                                 eventName: r.eventName ?? "", organizerId: r.organizerId ?? "", organizerName: r.organizerName ?? ""), nil)
        } catch { return (nil, .other) }
    }

    func finishPromoCompose(logID: UUID, result: String) async {
        _ = try? await SupabaseService.client
            .rpc("finish_promo_compose", params: ["p_log_id": logID.uuidString, "p_result": result]).execute()
    }

    private static func promoError(_ code: String?) -> PromoError {
        switch code {
        case "NOT_AUTHORIZED": return .notAuthorized
        case "RATE_LIMITED": return .rateLimited
        case "NOT_ELIGIBLE", "ALREADY_PROMPTED": return .notEligible
        case "GATE_REQUIRED": return .gate
        default: return .other
        }
    }
}
