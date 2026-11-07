import Foundation
import UIKit
import Supabase

/// Phase 1 quick wins (docs/impl/phase1-quick-wins.md) — the few reads they need, plus the referral link (Q7). The
/// pure rules live in Lib/QuickWins.swift; web twins are inline in Confirmed.jsx / EventDetail.jsx / Home.jsx and in
/// BanBeContext.jsx (referral).
extension AppState {
    // MARK: Q2 honest waiting

    private struct HostConfirmationTime: Decodable {
        let success: Bool?
        let medianMinutes: Double?
        enum CodingKeys: String, CodingKey { case success; case medianMinutes = "median_minutes" }
    }

    /// This host's typical "reported -> confirmed" minutes (get_host_confirmation_time, migration 198). nil below 5
    /// confirmations, on any error, or before the migration exists — the screen then shows nothing extra.
    func hostConfirmationMinutes(eventID: String) async -> Double? {
        do {
            let r: HostConfirmationTime = try await SupabaseService.client
                .rpc("get_host_confirmation_time", params: ["p_event_id": eventID])
                .execute().value
            return r.success == true ? r.medianMinutes : nil
        } catch {
            return nil
        }
    }

    // MARK: Q1 "Next" block

    struct TicketNextInfo: Equatable {
        var address = ""
        var noteVi = ""
        var noteEn = ""
    }

    private struct TicketNextRow: Decodable {
        let addressLine: String?
        let chatGreeting: String?
        let chatGreetingEn: String?
        enum CodingKeys: String, CodingKey {
            case addressLine = "address_line", chatGreeting = "chat_greeting", chatGreetingEn = "chat_greeting_en"
        }
    }

    /// The venue's street address and the host's own note to guests (events.chat_greeting, migrations 156/157; never
    /// the built-in default greeting). Falls back to the address alone before those columns exist.
    func ticketNextInfo(eventID: String) async -> TicketNextInfo {
        func clean(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        let row: TicketNextRow?
        if let rows: [TicketNextRow] = try? await SupabaseService.client
            .from("events").select("address_line, chat_greeting, chat_greeting_en")
            .eq("id", value: eventID).limit(1).execute().value {
            row = rows.first
        } else {
            let rows: [TicketNextRow]? = try? await SupabaseService.client
                .from("events").select("address_line")
                .eq("id", value: eventID).limit(1).execute().value
            row = rows?.first
        }
        guard let row else { return TicketNextInfo() }
        return TicketNextInfo(address: clean(row.addressLine), noteVi: clean(row.chatGreeting), noteEn: clean(row.chatGreetingEn))
    }

    // MARK: Q3 ended page

    struct HostUpcomingEvent: Decodable, Identifiable, Equatable {
        let id: String
        let name: String
        let status: String
        let startsAt: Date?
        var tz: String? = nil
        var countryCode: String? = nil
        var stateProvince: String? = nil
        enum CodingKeys: String, CodingKey {
            case id, name, status, tz
            case startsAt = "starts_at", countryCode = "country_code", stateProvince = "state_province"
        }
        var timeZoneID: String { EventMarket.rowTimeZoneID(tz: tz, countryCode: countryCode, stateProvince: stateProvince) }
    }

    /// "Next from this host": up to 3 of the host's live events still ahead, excluding this one (QuickWins.nextFromHost).
    func nextFromHost(organizerID: String, excluding key: String) async -> [HostUpcomingEvent] {
        let nowISO = ISO8601DateFormatter().string(from: Date())
        func query(_ columns: String) async throws -> [HostUpcomingEvent] {
            try await SupabaseService.client
                .from("events").select(columns)
                .eq("organizer_id", value: organizerID).eq("status", value: "live").gt("starts_at", value: nowISO)
                .order("starts_at", ascending: true).limit(4)
                .execute().value
        }
        // tz is migration 195; without it the zone is derived from the country/state like everywhere else.
        var rows: [HostUpcomingEvent] = []
        if let full = try? await query("id, name, status, starts_at, tz, country_code, state_province") {
            rows = full
        } else if let basic = try? await query("id, name, status, starts_at") {
            rows = basic
        }
        let keep = QuickWins.nextFromHost(rows.map { .init(key: $0.id, status: $0.status, startsAt: $0.startsAt) },
                                          now: Date(), excluding: key).map(\.key)
        return keep.compactMap { k in rows.first { $0.id == k } }
    }

    // MARK: Q7 referral (web: BanBeContext.jsx referralLink / shareReferral / claimPendingReferralAndWelcome)

    static let pendingReferralDefaultsKey = "banbe.pendingReferral"

    /// This account's own invite link, nil until the profile (and its code) has loaded.
    var referralLink: URL? {
        guard let code = user?.referralCode?.trimmingCharacters(in: .whitespaces), !code.isEmpty else { return nil }
        return URL(string: "https://www.banbe.app/?ref=\(code)")
    }

    /// Native share sheet with the invite link (no reward, so nothing to promise).
    func shareReferral() {
        guard let url = referralLink else { return }
        let text = T("Mỗi tuần một vài buổi hay ho. Supper club, phòng tranh, gig nhạc nhỏ. Tham gia qua link của mình nhé:",
                     "A few good things happening every week. Supper clubs, small galleries, tucked-away gigs. Join through my link:")
        let activity = UIActivityViewController(activityItems: [text, url], applicationActivities: nil)
        activity.completionWithItemsHandler = { type, completed, _, _ in
            guard completed else { return }
            Analytics.track(.shareCompleted(channel: AppEventRules.shareChannel(type), context: "referral"))
        }
        UIApplication.shared.topViewController?.present(activity, animated: true)
    }

    /// A `?ref=CODE` on a universal link / deep link: parked until there is a signed-in account to redeem it for (same
    /// code shape web accepts), then redeemed right away when already signed in.
    func captureReferral(from url: URL) {
        guard let ref = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "ref" })?.value,
              ref.range(of: "^[A-Za-z0-9]{4,12}$", options: .regularExpression) != nil else { return }
        UserDefaults.standard.set(ref.uppercased(), forKey: Self.pendingReferralDefaultsKey)
        if userID != nil { Task { await redeemPendingReferralIfNeeded() } }
    }

    /// redeem_referral (migration 023): attribution only, a quiet no-op server-side for a repeat, a self-referral or an
    /// account that already has a referrer. The parked code is used once either way. Same rule as web
    /// (claimPendingReferralAndWelcome runs only right after sign-up): only a brand-new account (created in the last
    /// 24 hours) is attributed; an existing account opening someone's link never gains a referrer after the fact.
    func redeemPendingReferralIfNeeded() async {
        guard userID != nil, let code = UserDefaults.standard.string(forKey: Self.pendingReferralDefaultsKey) else { return }
        UserDefaults.standard.removeObject(forKey: Self.pendingReferralDefaultsKey)
        guard let created = try? await SupabaseService.client.auth.session.user.createdAt,
              QuickWins.isFreshAccount(createdAt: created, now: Date()) else { return }
        struct Result: Decodable { let success: Bool? }
        let r: Result? = try? await SupabaseService.client.rpc("redeem_referral", params: ["p_code": code]).execute().value
        // Same best-effort email web sends the referrer after a successful redemption.
        if r?.success == true { await AuthAPIService.notify(path: "/api/notify", body: ["type": "referral_joined"]) }
    }
}
