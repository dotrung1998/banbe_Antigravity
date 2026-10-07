import Foundation
import Supabase

// Rewards & badges (migration 165; web: src/lib/rewards.js + Rewards.jsx). Every number is
// server-computed. The client never supplies a balance, an attendance or an amount: it reads the
// owner-scoped RPCs and calls one transactional redeem. A missing RPC (migration not applied)
// just hides the feature. Coins are cosmetic only: no cash value, not purchasable or
// transferable, and they never affect booking, priority or eligibility.

enum RewardsStatus: Equatable { case idle, loading, loaded, unavailable, error }

struct RewardSummary: Equatable {
    var balance: Int
    var streak: Int
    var activeToday: Bool
}

struct RewardsRedeemResult: Equatable {
    var code: String
    var ok: Bool
    var error: String?
    var already: Bool = false
}

struct RewardsPayload: Decodable, Equatable {
    struct Rules: Decodable, Equatable {
        var onboardingCoins: Int?
        var attendanceCoins: Int?
        var attendanceCoinCapPerMonth: Int?
        var version: Int?
        var timezone: String?
        enum CodingKeys: String, CodingKey {
            case onboardingCoins = "onboarding_coins", attendanceCoins = "attendance_coins"
            case attendanceCoinCapPerMonth = "attendance_coin_cap_per_month", version, timezone
        }
    }
    struct Streak: Decodable, Equatable {
        var current: Int
        var longest: Int
        var activeToday: Bool?
        var timezone: String?
        enum CodingKeys: String, CodingKey { case current, longest, activeToday = "active_today", timezone }
    }
    struct Badge: Decodable, Equatable, Identifiable {
        var code: String
        var titleVi: String, titleEn: String, descVi: String, descEn: String
        var target: Int
        var progress: Int
        var earned: Bool
        var id: String { code }
        enum CodingKeys: String, CodingKey {
            case code, target, progress, earned
            case titleVi = "title_vi", titleEn = "title_en", descVi = "desc_vi", descEn = "desc_en"
        }
    }
    struct Entry: Decodable, Equatable, Identifiable {
        var id: String
        var type: String
        var amount: Int
        var reason: String
        var createdAt: String
        var eventName: String?
        var itemCode: String?
        enum CodingKeys: String, CodingKey {
            case id, type, amount, reason, createdAt = "created_at", eventName = "event_name", itemCode = "item_code"
        }
    }
    struct Item: Decodable, Equatable, Identifiable {
        var code: String
        var designId: String
        var price: Int
        var unlocked: Bool
        var id: String { code }
        enum CodingKeys: String, CodingKey { case code, price, unlocked, designId = "design_id" }
    }
    var success: Bool
    var balance: Int
    var rules: Rules
    var streak: Streak
    var badges: [Badge]
    var history: [Entry]
    var catalog: [Item]
}

/// Pure helpers (no AppState): unit-tested, mirrors src/lib/rewards.js.
enum RewardsLogic {
    /// 1234 -> "1234", 12500 -> "12.5k" (Home header stays narrow).
    static func compactCoins(_ n: Int) -> String {
        let a = abs(n)
        if a < 10_000 { return String(n) }
        let k = (Double(a) / 100).rounded() / 10
        let body = k.rounded() == k ? String(Int(k)) : String(format: "%.1f", k)
        return (n < 0 ? "-" : "") + body + "k"
    }

    static func shortfall(balance: Int, price: Int) -> Int { max(0, price - balance) }

    static func isFunctionMissing(_ error: Error) -> Bool {
        if let pg = error as? PostgrestError {
            return pg.code == "PGRST202" || pg.code == "42883"
                || pg.message.localizedCaseInsensitiveContains("could not find the function")
        }
        return false
    }

    static func historyLabel(reason: String, eventName: String?, T: (String, String) -> String) -> String {
        let base: String
        switch reason {
        case "onboarding_preferences": base = T("Hoàn thành câu hỏi sở thích", "Completed the preference questions")
        case "attendance": base = T("Tham dự sự kiện", "Attended an event")
        case "attendance_cap": base = T("Tham dự sự kiện (đã đạt giới hạn xu tháng này)", "Attended an event (monthly coin cap reached)")
        case "attendance_reversed": base = T("Điều chỉnh: điểm danh bị huỷ", "Adjustment: attendance was undone")
        case "redemption": base = T("Đổi phần thưởng", "Redeemed a reward")
        default: base = T("Hoạt động", "Activity")
        }
        if let e = eventName, !e.isEmpty { return "\(base) ▪︎ \(e)" }
        return base
    }

    static func ruleLines(_ r: RewardsPayload.Rules, T: (String, String) -> String) -> [String] {
        let on = r.onboardingCoins ?? 0, at = r.attendanceCoins ?? 0, cap = r.attendanceCoinCapPerMonth ?? 0
        var out = [
            T("Hoàn thành câu hỏi sở thích một lần: +\(on) xu.", "Complete the preference questions once: +\(on) coins."),
            T("Mỗi sự kiện khác nhau mà người tổ chức xác nhận bạn đã tham dự: +\(at) xu.", "Each different event the host confirms you attended: +\(at) coins."),
        ]
        if cap > 0 {
            out.append(T("Giới hạn: tối đa \(cap) sự kiện được tính xu mỗi tháng (\(cap * at) xu). Vượt giới hạn vẫn được tính huy hiệu và chuỗi ngày nhưng không có xu.",
                         "Cap: at most \(cap) events pay coins per month (\(cap * at) coins). Beyond it you still progress badges and your streak, just without coins."))
        }
        return out
    }

    static func noCoinLines(T: (String, String) -> String) -> [String] {
        [
            T("Không có xu cho: mở ứng dụng, chi tiêu, thích, theo dõi, lưu lặp lại, tải lên, huỷ, hay đồng ý nhận tin/cấp quyền.",
              "No coins for: opening the app, spending, likes, follows, repeated saves, uploads, cancellations, or marketing/permission consent."),
            T("Chủ sự kiện, thành viên Team và tự điểm danh không được tính xu cho sự kiện của chính mình.",
              "Event owners, team members and self check-ins don't earn at their own events."),
            T("Vé tặng: xu thuộc về người nhận đã nhận vé và thực sự tham dự, không phải người mua. Vé tặng chưa được nhận thì chưa ai được tính.",
              "Gifted tickets: coins go to the recipient who claimed the ticket and attended, not the buyer. A gift that was never claimed credits nobody."),
        ]
    }

    static func streakLines(tz: String?, T: (String, String) -> String) -> [String] {
        let zone = tz ?? "Asia/Ho_Chi_Minh"
        return [
            T("Một ngày được tính khi bạn lưu một sự kiện (đã được máy chủ xác minh) hoặc được xác nhận tham dự. Mở ứng dụng hay tìm kiếm không được tính.",
              "A day counts when you save an event (verified by the server) or are confirmed as attending. Opening the app or searching does not count."),
            T("Ngày được tính theo giờ cố định \(zone), mỗi ngày tối đa một lần.", "Days follow the fixed \(zone) time zone, at most once per day."),
        ]
    }

    static func termsLines(T: (String, String) -> String) -> [String] {
        [
            T("Xu không thể mua, chuyển nhượng hay đổi thành tiền. Không có rút thăm hay giải thưởng ngẫu nhiên.", "Coins cannot be bought, transferred or cashed out. There are no random prizes or draws."),
            T("Xu và huy hiệu không ảnh hưởng đến việc đặt chỗ, thứ tự ưu tiên hay điều kiện tham gia.", "Coins and badges never affect booking, priority or eligibility."),
            T("Đổi thưởng chỉ mở khoá mẫu móc khoá (tuỳ chọn). Các mẫu miễn phí luôn dùng được.", "Redeeming only unlocks an optional keychain design. The free charms always stay available."),
            T("Nếu một lần điểm danh bị huỷ sau khi bạn đã dùng xu, số xu đó vẫn bị trừ lại, số dư có thể âm cho tới khi bạn kiếm lại. Phần thưởng đã mở khoá không bị thu hồi.",
              "If a check-in is undone after you spent those coins, the coins are still reversed and your balance can go negative until you earn it back. Unlocked rewards are never taken away."),
            T("Chuỗi ngày chỉ là thống kê: bỏ lỡ ngày nào cũng không bị trừ xu hay khoá tính năng.", "Your streak is just a counter: missing a day never costs coins or blocks anything."),
        ]
    }

    static func redeemErrorMessage(_ code: String?, T: (String, String) -> String) -> String {
        switch code ?? "" {
        case "INSUFFICIENT_BALANCE": return T("Chưa đủ xu để đổi phần thưởng này.", "You don't have enough coins for this reward yet.")
        case "ITEM_NOT_FOUND": return T("Phần thưởng này không còn nữa.", "This reward is no longer available.")
        case "NETWORK": return T("Lỗi mạng. Chưa trừ xu. Vui lòng thử lại.", "Network error. No coins were spent. Please try again.")
        default: return T("Vui lòng thử lại.", "Please try again.")
        }
    }
}

extension AppState {

    func resetRewardsState() {
        rewardsSummary = nil
        rewardsSummaryStatus = .idle
        rewards = nil
        rewardsStatus = .idle
        rewardsUnlocked = []
        rewardsRedeemBusy = ""
        rewardsRedeemResult = nil
        rewardsOwnerID = nil
    }

    /// Call whenever the signed-in account may have changed (clears the previous account's numbers first).
    func syncRewardsOwner() {
        guard rewardsOwnerID != userID else { return }
        resetRewardsState()
        rewardsOwnerID = userID
        if userID != nil { Task { await loadRewardsSummary() } }
    }

    func loadRewardsSummary() async {
        guard let uid = userID else { return }
        if rewardsOwnerID != uid { rewardsOwnerID = uid }
        struct Env: Decodable {
            var success: Bool?
            var balance: Int?
            var streak: Int?
            var activeToday: Bool?
            enum CodingKeys: String, CodingKey { case success, balance, streak, activeToday = "active_today" }
        }
        do {
            let env: Env = try await SupabaseService.client.rpc("get_my_reward_summary").execute().value
            guard userID == uid else { return }
            guard env.success == true else { rewardsSummaryStatus = .error; return }
            rewardsSummary = RewardSummary(balance: env.balance ?? 0, streak: env.streak ?? 0, activeToday: env.activeToday ?? false)
            rewardsSummaryStatus = .loaded
        } catch {
            guard userID == uid else { return }
            rewardsSummaryStatus = RewardsLogic.isFunctionMissing(error) ? .unavailable : .error
            if rewardsSummaryStatus == .error { print("loadRewardsSummary failed:", error) }
        }
    }

    func loadRewards() async {
        guard let uid = userID else { return }
        if rewardsStatus != .loaded { rewardsStatus = .loading }
        do {
            let payload: RewardsPayload = try await SupabaseService.client.rpc("get_my_rewards").execute().value
            guard userID == uid else { return }
            guard payload.success else { rewardsStatus = .error; return }
            rewards = payload
            rewardsStatus = .loaded
            rewardsSummary = RewardSummary(balance: payload.balance, streak: payload.streak.current, activeToday: payload.streak.activeToday ?? false)
            rewardsSummaryStatus = .loaded
            await loadRewardsUnlocked()
        } catch {
            guard userID == uid else { return }
            rewardsStatus = RewardsLogic.isFunctionMissing(error) ? .unavailable : .error
            if rewardsStatus == .error { print("loadRewards failed:", error) }
        }
    }

    func loadRewardsUnlocked() async {
        guard let uid = userID else { return }
        struct Env: Decodable { var designIds: [String]?
            enum CodingKeys: String, CodingKey { case designIds = "design_ids" } }
        if let env: Env = try? await SupabaseService.client.rpc("get_my_unlocked_cosmetics").execute().value,
           userID == uid, let ids = env.designIds {
            rewardsUnlocked = ids
        }
    }

    /// Redeems one catalog item. The server re-checks the balance inside a per-account lock; a retry is never double-charged.
    @discardableResult
    func redeemReward(_ code: String) async -> RewardsRedeemResult? {
        guard let uid = userID, rewardsRedeemBusy.isEmpty else { return nil }
        rewardsRedeemBusy = code
        rewardsRedeemResult = nil
        struct Env: Decodable { var success: Bool?; var error: String?; var alreadyUnlocked: Bool?
            enum CodingKeys: String, CodingKey { case success, error, alreadyUnlocked = "already_unlocked" } }
        var result: RewardsRedeemResult
        do {
            let env: Env = try await SupabaseService.client
                .rpc("redeem_reward", params: ["p_item_code": code]).execute().value
            result = RewardsRedeemResult(code: code, ok: env.success == true, error: env.error, already: env.alreadyUnlocked == true)
        } catch {
            print("redeemReward failed:", error)
            result = RewardsRedeemResult(code: code, ok: false, error: "NETWORK")
        }
        guard userID == uid else { return nil }
        rewardsRedeemBusy = ""
        rewardsRedeemResult = result
        await loadRewards() // refresh from the server whatever the outcome
        return result
    }

    /// After a successful save: ask the server to verify it and count the day. Never blocks the save.
    func recordSaveDay(eventKey: String) async {
        guard userID != nil, rewardsSummaryStatus != .unavailable else { return }
        struct Env: Decodable { var success: Bool? }
        if let env: Env = try? await SupabaseService.client
            .rpc("record_active_day", params: ["p_source": "save", "p_ref": eventKey]).execute().value, env.success == true {
            await loadRewardsSummary()
        }
    }
}
