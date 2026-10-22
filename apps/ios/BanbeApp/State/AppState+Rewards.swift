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
    /// Rewards v2 (migration 192); nil from an older server.
    var weekStreak: Int? = nil
    var weekActive: Bool = false
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
        /// Rules v2 (migration 191); nil from an older server.
        var attendanceWindowBeforeHours: Int?
        var attendanceWindowAfterHours: Int?
        enum CodingKeys: String, CodingKey {
            case onboardingCoins = "onboarding_coins", attendanceCoins = "attendance_coins"
            case attendanceCoinCapPerMonth = "attendance_coin_cap_per_month", version, timezone
            case attendanceWindowBeforeHours = "attendance_window_before_hours", attendanceWindowAfterHours = "attendance_window_after_hours"
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
        var earnedAt: String?
        /// Migration 192; nil from an older server.
        var family: String?
        var tier: Int?
        var id: String { code }
        enum CodingKeys: String, CodingKey {
            case code, target, progress, earned, family, tier, earnedAt = "earned_at"
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
        // Added by migration 179; nil from an older server.
        var kind: String?
        var status: String?
        var id: String { code }
        enum CodingKeys: String, CodingKey { case code, price, unlocked, designId = "design_id", kind, status }
    }
    /// A partner offer (migration 179). Display only: there is no redemption path yet.
    struct Offer: Decodable, Equatable, Identifiable {
        var code: String
        var price: Int?
        var titleVi: String?, titleEn: String?, descVi: String?, descEn: String?
        var status: String?
        var id: String { code }
        enum CodingKeys: String, CodingKey {
            case code, price, status, titleVi = "title_vi", titleEn = "title_en", descVi = "desc_vi", descEn = "desc_en"
        }
    }
    /// Added by migration 177; absent from an older server (decodes to nil).
    struct TimezoneSettings: Decodable, Equatable {
        var effectiveTz: String
        var chosen: Bool?
        var pendingTz: String?
        var changesLeft: Int?
        var nextChangeAt: String?
        enum CodingKeys: String, CodingKey {
            case effectiveTz = "effective_tz", chosen, pendingTz = "pending_tz", changesLeft = "changes_left", nextChangeAt = "next_change_at"
        }
    }
    /// Rewards v2 (migration 192): weekly streak, derived on the server.
    struct WeekStreak: Decodable, Equatable {
        struct Repair: Decodable, Equatable { var weeks: Int; var until: String }
        var current = 0, longest = 0
        var thisWeekActive = false
        var weekStart: String?
        var graceHeld = 0, graceMax = 0, graceEvery = 0, graceUsed = 0
        var nextGraceIn: Int?
        var repair: Repair?
        var repaired = 0
        var timezone: String?
        enum CodingKeys: String, CodingKey {
            case unit, current, longest, repair, repaired, timezone
            case thisWeekActive = "this_week_active", weekStart = "week_start", graceHeld = "grace_held", graceMax = "grace_max"
            case graceEvery = "grace_every", graceUsed = "grace_used", nextGraceIn = "next_grace_in"
        }
        init(current: Int = 0, longest: Int = 0, thisWeekActive: Bool = false, weekStart: String? = nil, graceHeld: Int = 0, graceMax: Int = 2,
             graceEvery: Int = 4, graceUsed: Int = 0, nextGraceIn: Int? = 4, repair: Repair? = nil, repaired: Int = 0, timezone: String? = nil) {
            self.current = current; self.longest = longest; self.thisWeekActive = thisWeekActive; self.weekStart = weekStart
            self.graceHeld = graceHeld; self.graceMax = graceMax; self.graceEvery = graceEvery; self.graceUsed = graceUsed
            self.nextGraceIn = nextGraceIn; self.repair = repair; self.repaired = repaired; self.timezone = timezone
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard (try c.decodeIfPresent(String.self, forKey: .unit)) == "week" else {
                throw DecodingError.dataCorruptedError(forKey: .unit, in: c, debugDescription: "not a week streak")
            }
            current = (try? c.decode(Int.self, forKey: .current)) ?? 0
            longest = (try? c.decode(Int.self, forKey: .longest)) ?? 0
            thisWeekActive = (try? c.decode(Bool.self, forKey: .thisWeekActive)) ?? false
            weekStart = try? c.decode(String.self, forKey: .weekStart)
            graceHeld = (try? c.decode(Int.self, forKey: .graceHeld)) ?? 0
            graceMax = (try? c.decode(Int.self, forKey: .graceMax)) ?? 0
            graceEvery = (try? c.decode(Int.self, forKey: .graceEvery)) ?? 0
            graceUsed = (try? c.decode(Int.self, forKey: .graceUsed)) ?? 0
            nextGraceIn = try? c.decode(Int.self, forKey: .nextGraceIn)
            repair = try? c.decode(Repair.self, forKey: .repair)
            repaired = (try? c.decode(Int.self, forKey: .repaired)) ?? 0
            timezone = try? c.decode(String.self, forKey: .timezone)
        }
    }
    /// The visible badge closest to done (migration 192).
    struct NextBadge: Decodable, Equatable {
        var code: String
        var family: String?
        var tier: Int?
        var progress: Int
        var target: Int
        var remaining: Int
        var titleVi: String?, titleEn: String?
        enum CodingKeys: String, CodingKey { case code, family, tier, progress, target, remaining, titleVi = "title_vi", titleEn = "title_en" }
    }
    /// Self-chosen monthly outing goal (migration 192). target nil = no goal.
    struct Goal: Decodable, Equatable {
        var target: Int?
        var progress: Int
        var month: String?
        var done: Bool { if let t = target { return progress >= t }; return false }
        enum CodingKeys: String, CodingKey { case target, progress, month }
        init(target: Int?, progress: Int, month: String? = nil) { self.target = target; self.progress = progress; self.month = month }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let t = try? c.decode(Int.self, forKey: .target)
            target = t.flatMap { RewardsLogic.goalChoices.contains($0) ? $0 : nil }
            progress = (try? c.decode(Int.self, forKey: .progress)) ?? 0
            month = try? c.decode(String.self, forKey: .month)
        }
    }
    var success: Bool
    var balance: Int
    var rules: Rules
    var streak: Streak
    var badges: [Badge]
    var history: [Entry]
    var catalog: [Item]
    var timezoneSettings: TimezoneSettings?
    /// Partner offers (migration 179). [] from an older server and while the partner_offers flag is off.
    var offers: [Offer] = []
    /// Rewards v2 (migration 192); nil from an older server.
    var weekStreak: WeekStreak? = nil
    var nextBadge: NextBadge? = nil
    var goal: Goal? = nil
    enum CodingKeys: String, CodingKey {
        case success, balance, rules, streak, badges, history, catalog, offers, timezoneSettings = "timezone_settings"
        case weekStreak = "week_streak", nextBadge = "next_badge", goal
    }
}

/// Decodes an array one element at a time and drops the ones that fail, so a single row this build cannot read
/// never makes the whole Rewards screen fail.
private struct LossyArray<T: Decodable>: Decodable {
    var elements: [T]
    private struct Skip: Decodable {}
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        var out: [T] = []
        while !c.isAtEnd {
            if let e = try? c.decode(T.self) { out.append(e) } else { _ = try? c.decode(Skip.self) }
        }
        elements = out
    }
}

extension RewardsPayload {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decode(Bool.self, forKey: .success)
        balance = try c.decode(Int.self, forKey: .balance)
        rules = try c.decode(Rules.self, forKey: .rules)
        streak = try c.decode(Streak.self, forKey: .streak)
        badges = try c.decode([Badge].self, forKey: .badges)
        history = try c.decode([Entry].self, forKey: .history)
        // Keychain designs only: a row without a design_id (an offer) is skipped, never a decode failure.
        catalog = (try c.decode(LossyArray<Item>.self, forKey: .catalog)).elements.filter { $0.kind == nil || $0.kind == "keychain_design" }
        timezoneSettings = try c.decodeIfPresent(TimezoneSettings.self, forKey: .timezoneSettings)
        offers = (try c.decodeIfPresent(LossyArray<Offer>.self, forKey: .offers))?.elements ?? []
        // v2 keys are optional extras: anything this build can't read is dropped, never a failed screen.
        weekStreak = try? c.decodeIfPresent(WeekStreak.self, forKey: .weekStreak)
        nextBadge = try? c.decodeIfPresent(NextBadge.self, forKey: .nextBadge)
        goal = try? c.decodeIfPresent(Goal.self, forKey: .goal)
    }
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

    /// The Offers section is shown only when the server sent at least one offer (old server / flag off => hidden).
    static func showsOffersSection(_ p: RewardsPayload) -> Bool { !p.offers.isEmpty }

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
        case "off_window": base = T("Tham dự sự kiện (điểm danh ngoài khung giờ sự kiện, không tính xu)", "Attended an event (checked in outside the event time, no coins)")
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
        if let b = r.attendanceWindowBeforeHours, let a = r.attendanceWindowAfterHours {
            out.append(T("Xu được tính khi người tổ chức điểm danh bạn trong khoảng \(b) giờ trước đến \(a) giờ sau giờ bắt đầu. Ngoài khoảng đó vẫn được tính huy hiệu và chuỗi, nhưng không có xu.",
                         "Coins are paid when the host checks you in between \(b) hours before and \(a) hours after the start. Outside that you still progress badges and your streak, without coins."))
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
            T("Ngày và tháng được tính theo múi giờ \(zone), mỗi ngày tối đa một lần.", "Days and months follow the \(zone) time zone, at most once per day."),
        ]
    }

    /// Zones offered in the picker (suggestions only; nothing is assigned automatically — a user who never chooses
    /// keeps Asia/Ho_Chi_Minh, the original behaviour).
    static let suggestedTimezones: [(id: String, vi: String, en: String)] = [
        ("Asia/Ho_Chi_Minh", "Việt Nam (UTC+7)", "Vietnam (UTC+7)"),
        ("America/Los_Angeles", "Mỹ – Thái Bình Dương", "US – Pacific"),
        ("America/Denver", "Mỹ – Miền núi", "US – Mountain"),
        ("America/Chicago", "Mỹ – Trung tâm", "US – Central"),
        ("America/New_York", "Mỹ – Miền Đông", "US – Eastern"),
    ]

    static func deviceTimezoneHint(_ id: String = TimeZone.current.identifier) -> String? {
        suggestedTimezones.contains { $0.id == id } ? id : nil
    }

    static func timezoneErrorMessage(_ code: String?, T: (String, String) -> String) -> String {
        switch code ?? "" {
        case "INVALID_TIMEZONE": return T("Múi giờ không hợp lệ.", "That time zone is not valid.")
        case "TZ_CHANGE_LIMIT": return T("Bạn đã đổi múi giờ 2 lần trong 30 ngày. Vui lòng thử lại sau.", "You changed your time zone twice in the last 30 days. Please try again later.")
        default: return T("Lỗi mạng. Chưa thay đổi gì.", "Network error. Nothing was changed.")
        }
    }

    static func termsLines(weekly: Bool = false, T: (String, String) -> String) -> [String] {
        [
            T("Xu không thể mua, chuyển nhượng hay đổi thành tiền. Không có rút thăm hay giải thưởng ngẫu nhiên.", "Coins cannot be bought, transferred or cashed out. There are no random prizes or draws."),
            T("Xu và huy hiệu không ảnh hưởng đến việc đặt chỗ, thứ tự ưu tiên hay điều kiện tham gia.", "Coins and badges never affect booking, priority or eligibility."),
            T("Đổi thưởng chỉ mở khoá mẫu móc khoá (tuỳ chọn). Các mẫu miễn phí luôn dùng được.", "Redeeming only unlocks an optional keychain design. The free charms always stay available."),
            T("Nếu một lần điểm danh bị huỷ sau khi bạn đã dùng xu, số xu đó vẫn bị trừ lại, số dư có thể âm cho tới khi bạn kiếm lại. Phần thưởng đã mở khoá không bị thu hồi.",
              "If a check-in is undone after you spent those coins, the coins are still reversed and your balance can go negative until you earn it back. Unlocked rewards are never taken away."),
            weekly
                ? T("Chuỗi tuần chỉ là thống kê: bỏ lỡ một tuần không bao giờ bị trừ xu hay khoá tính năng.", "Your streak is just a counter: missing a week never costs coins or blocks anything.")
                : T("Chuỗi ngày chỉ là thống kê: bỏ lỡ ngày nào cũng không bị trừ xu hay khoá tính năng.", "Your streak is just a counter: missing a day never costs coins or blocks anything."),
        ]
    }

    static func redeemErrorMessage(_ code: String?, T: (String, String) -> String) -> String {
        switch code ?? "" {
        case "INSUFFICIENT_BALANCE": return T("Chưa đủ xu để đổi phần thưởng này.", "You don't have enough coins for this reward yet.")
        case "ITEM_NOT_FOUND": return T("Phần thưởng này không còn nữa.", "This reward is no longer available.")
        case "NETWORK": return T("Lỗi mạng. Chưa trừ xu. Vui lòng thử lại.", "Network error. No coins were spent. Please try again.")
        case "NOT_AVAILABLE": return T("Đổi thưởng đang tạm tắt. Chưa trừ xu.", "Redeeming is switched off right now. No coins were spent.")
        default: return T("Vui lòng thử lại.", "Please try again.")
        }
    }

    // MARK: Rewards v2 (migration 192) — mirrors src/lib/rewards.js; shared vectors in tests/fixtures/rewards-v2-week-streak.json.
    // Copy rules: no guilt, no fake urgency, no "you'll lose"; a repair date is shown only because it is real.

    static let goalChoices = [1, 2, 4]
    static let weekMilestones = [4, 8, 12, 26, 52]

    /// The Home capsule shows weeks under v2 when the server sent them, else days.
    static func capsuleStreak(_ s: RewardSummary?, weekly: Bool) -> (value: Int, weekly: Bool) {
        if weekly, let w = s?.weekStreak { return (w, true) }
        return (s?.streak ?? 0, false)
    }

    /// "Oct 25" / "25 thg 10" for a YYYY-MM-DD date, no timezone shift.
    static func shortDate(_ iso: String, en: Bool) -> String {
        let parts = iso.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return "" }
        if !en { return "\(parts[2]) thg \(parts[1])" }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        guard (1...12).contains(parts[1]) else { return "" }
        return "\(months[parts[1] - 1]) \(parts[2])"
    }

    static func weekStreakHint(_ ws: RewardsPayload.WeekStreak, en: Bool, T: (String, String) -> String) -> (status: String, how: String) {
        if ws.thisWeekActive {
            return (T("✓ Tuần này đã được tính", "✓ This week counts"),
                    T("Tuần sau: lưu 1 sự kiện hoặc đi 1 sự kiện là đủ.", "Next week: one save or one event is all it takes."))
        }
        if ws.current == 0, let rep = ws.repair {
            let d = shortDate(rep.until, en: en)
            return (T("Lấy lại chuỗi \(rep.weeks) tuần", "Bring back your \(rep.weeks)-week streak"),
                    T("Tham dự một sự kiện trước hết ngày \(d) để khôi phục.", "Attend an event by \(d) to restore it."))
        }
        if ws.current > 0 {
            return (T("Tuần này vẫn đang mở", "This week is still open"),
                    ws.graceHeld > 0
                    ? T("Lưu hoặc đi 1 sự kiện trước Chủ nhật để thêm 1 tuần. Lỡ tuần này cũng không sao: bạn có tuần nghỉ.", "Save or attend an event before Sunday to add a week. Missing it is fine too: you have a grace week.")
                    : T("Lưu hoặc đi 1 sự kiện trước Chủ nhật để thêm 1 tuần.", "Save or attend an event before Sunday to add a week."))
        }
        return (T("Bắt đầu chuỗi tuần này", "Start a streak this week"),
                T("Một tuần chỉ cần 1 lần lưu hoặc 1 sự kiện. Chỉ mở app thì chưa tính.", "A week needs just one save or one event. Opening the app alone does not count."))
    }

    static func graceLine(_ ws: RewardsPayload.WeekStreak, T: (String, String) -> String) -> String {
        guard ws.graceMax > 0 else { return "" }
        let held = T("Tuần nghỉ: \(ws.graceHeld)/\(ws.graceMax)", "Grace weeks: \(ws.graceHeld)/\(ws.graceMax)")
        guard let n = ws.nextGraceIn else { return "\(held) ▪︎ \(T("đã đầy", "full"))" }
        return "\(held) ▪︎ \(T("thêm 1 sau \(n) tuần hoạt động", "next after \(n) more active \(n == 1 ? "week" : "weeks")"))"
    }

    static func weekStreakLines(_ ws: RewardsPayload.WeekStreak?, T: (String, String) -> String) -> [String] {
        let zone = ws?.timezone ?? "Asia/Ho_Chi_Minh"
        let every = (ws?.graceEvery ?? 0) > 0 ? ws!.graceEvery : 4
        let max = (ws?.graceMax ?? 0) > 0 ? ws!.graceMax : 2
        return [
            T("Một tuần (thứ Hai–Chủ nhật) được tính khi bạn lưu một sự kiện (máy chủ xác minh) hoặc được xác nhận tham dự ít nhất một lần.",
              "A week (Monday–Sunday) counts when you save an event (verified by the server) or are confirmed as attending at least once."),
            T("Cứ \(every) tuần hoạt động bạn nhận 1 tuần nghỉ (giữ tối đa \(max)). Tuần nghỉ tự che một tuần bạn bỏ lỡ. Không thể mua.",
              "Every \(every) active weeks earn a grace week (hold up to \(max)). It covers a week you miss, automatically. It can't be bought."),
            T("Nếu chuỗi từ 4 tuần trở lên bị ngắt, tham dự một sự kiện trong 14 ngày sau đó sẽ khôi phục chuỗi.",
              "If a streak of 4 weeks or more breaks, attending an event within 14 days brings it back."),
            T("Tuần được tính theo múi giờ \(zone). Chuỗi và mục tiêu không bao giờ tạo ra xu.", "Weeks follow the \(zone) time zone. Streaks and goals never pay coins."),
        ]
    }

    static func familyTitle(_ family: String, T: (String, String) -> String) -> String? {
        switch family {
        case "start": return T("Bắt đầu", "Getting started")
        case "outings": return T("Sự kiện đã tham dự", "Events attended")
        case "explorer": return T("Khám phá danh mục", "Categories explored")
        case "months": return T("Tháng có sự kiện", "Months out")
        case "host": return T("Người tổ chức", "Hosting")
        case "season": return T("Theo mùa", "Seasonal")
        default: return nil
        }
    }

    struct BadgeGroup: Identifiable, Equatable {
        var family: String
        var badges: [RewardsPayload.Badge]
        var id: String { family }
        var earnedCount: Int { badges.filter(\.earned).count }
        var next: RewardsPayload.Badge? { badges.first { !$0.earned } }
        var top: RewardsPayload.Badge? { badges.last { $0.earned } }
    }

    /// Groups by family, tiers in order. A badge without a family (older server) gets its own group.
    static func groupBadgesByFamily(_ badges: [RewardsPayload.Badge]) -> [BadgeGroup] {
        var order: [String] = []
        var map: [String: [RewardsPayload.Badge]] = [:]
        for b in badges {
            let key = b.family ?? "solo:\(b.code)"
            if map[key] == nil { order.append(key); map[key] = [] }
            map[key]?.append(b)
        }
        return order.map { BadgeGroup(family: $0, badges: (map[$0] ?? []).sorted { ($0.tier ?? 0) < ($1.tier ?? 0) }) }
    }

    static func nextBadgeLine(_ nb: RewardsPayload.NextBadge, en: Bool, T: (String, String) -> String) -> String {
        let title = (en ? nb.titleEn : nb.titleVi) ?? nb.titleEn ?? nb.code
        let n = nb.remaining
        switch nb.family ?? "" {
        case "outings", "season":
            return n == 1 ? T("Còn 1 sự kiện nữa là đạt “\(title)”", "One event away from “\(title)”")
                          : T("Còn \(n) sự kiện nữa là đạt “\(title)”", "\(n) events away from “\(title)”")
        case "explorer": return T("Thêm \(n) danh mục mới để đạt “\(title)”", "\(n) new \(n == 1 ? "category" : "categories") to “\(title)”")
        case "months": return T("Thêm \(n) tháng có sự kiện để đạt “\(title)”", "\(n) more \(n == 1 ? "month" : "months") with an event to “\(title)”")
        case "host": return T("Thêm \(n) sự kiện hoàn thành để đạt “\(title)”", "\(n) more completed \(n == 1 ? "event" : "events") to “\(title)”")
        case "start": return T("Trả lời câu hỏi sở thích để đạt “\(title)”", "Answer the preference questions to earn “\(title)”")
        default: return T("Còn \(n) bước nữa là đạt “\(title)”", "\(n) to go for “\(title)”")
        }
    }

    static func goalLine(_ g: RewardsPayload.Goal?, T: (String, String) -> String) -> String {
        guard let g, let target = g.target else {
            return T("Chọn số sự kiện bạn muốn đi mỗi tháng. Không có xu, chỉ để bạn theo dõi.", "Pick how many events you want to go to each month. No coins, just for you.")
        }
        if g.done { return T("Đã đạt mục tiêu tháng này (\(g.progress)/\(target)) ✓", "Goal met for this month (\(g.progress)/\(target)) ✓") }
        let left = target - g.progress
        return T("\(g.progress)/\(target) sự kiện tháng này ▪︎ còn \(left)", "\(g.progress) of \(target) events this month ▪︎ \(left) to go")
    }

    static func goalErrorMessage(_ code: String?, T: (String, String) -> String) -> String {
        switch code ?? "" {
        case "NOT_AVAILABLE": return T("Tính năng này đang tắt.", "This is switched off right now.")
        case "INVALID_GOAL": return T("Mục tiêu không hợp lệ.", "That goal is not valid.")
        default: return T("Lỗi mạng. Chưa thay đổi gì.", "Network error. Nothing was changed.")
        }
    }

    enum Celebration: Equatable { case badge(code: String), weeks(Int) }

    /// What to celebrate now, once per account per device. `celebrated == nil` = first time on this device: celebrate
    /// nothing, only remember what is already there. Mirrors celebrationDiff in src/lib/rewards.js (same keys).
    static func celebrationDiff(badges: [RewardsPayload.Badge], week: RewardsPayload.WeekStreak?, celebrated: [String]?) -> (show: [Celebration], keys: [String]) {
        var items: [(Celebration, String)] = badges.compactMap { b in
            guard b.earned, let at = b.earnedAt else { return nil }
            return (.badge(code: b.code), "b:\(b.code):\(at)")
        }
        if let ws = week, ws.current > 0, let start = ws.weekStart, let m = weekMilestones.last(where: { ws.current >= $0 }) {
            // Key = the Monday the run started, so a later run reaching the same milestone celebrates again.
            var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
            let f = DateFormatter(); f.calendar = cal; f.timeZone = cal.timeZone; f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
            if let d = f.date(from: String(start.prefix(10))), let runStart = cal.date(byAdding: .day, value: -(ws.current - 1) * 7, to: d) {
                items.append((.weeks(m), "w:\(m):\(f.string(from: runStart))"))
            }
        }
        let all = items.map(\.1)
        guard let celebrated else { return ([], all) }
        let seen = Set(celebrated)
        var keys = celebrated
        for k in all where !keys.contains(k) { keys.append(k) }
        return (items.filter { !seen.contains($0.1) }.map(\.0), Array(keys.suffix(200)))
    }

    static func celebratedKey(_ uid: String) -> String { "banbe.rewards.celebrated.v1.\(uid)" }
    static func readCelebrated(_ uid: String, _ d: UserDefaults = .standard) -> [String]? { d.stringArray(forKey: celebratedKey(uid)) }
    static func writeCelebrated(_ uid: String, _ keys: [String], _ d: UserDefaults = .standard) { d.set(keys, forKey: celebratedKey(uid)) }
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
        #if DEBUG
        if UITestFixture.isActive { return } // fixtures seed the summary themselves
        #endif
        guard let uid = userID, rewardsEnabled else { return } // an admin has hidden Rewards & badges (migration 187)
        if rewardsOwnerID != uid { rewardsOwnerID = uid }
        struct Env: Decodable {
            var success: Bool?
            var balance: Int?
            var streak: Int?
            var activeToday: Bool?
            var weekStreak: Int?
            var weekActive: Bool?
            enum CodingKeys: String, CodingKey { case success, balance, streak, activeToday = "active_today", weekStreak = "week_streak", weekActive = "week_active" }
        }
        do {
            let env: Env = try await SupabaseService.client.rpc("get_my_reward_summary").execute().value
            guard userID == uid else { return }
            guard env.success == true else { rewardsSummaryStatus = .error; return }
            rewardsSummary = RewardSummary(balance: env.balance ?? 0, streak: env.streak ?? 0, activeToday: env.activeToday ?? false,
                                           weekStreak: env.weekStreak, weekActive: env.weekActive ?? false)
            rewardsSummaryStatus = .loaded
        } catch {
            guard userID == uid else { return }
            rewardsSummaryStatus = RewardsLogic.isFunctionMissing(error) ? .unavailable : .error
            if rewardsSummaryStatus == .error { print("loadRewardsSummary failed:", error) }
        }
    }

    func loadRewards() async {
        guard let uid = userID, rewardsEnabled else { return }
        if rewardsStatus != .loaded { rewardsStatus = .loading }
        do {
            let payload: RewardsPayload = try await SupabaseService.client.rpc("get_my_rewards").execute().value
            guard userID == uid else { return }
            guard payload.success else { rewardsStatus = .error; return }
            rewards = payload
            rewardsStatus = .loaded
            rewardsSummary = RewardSummary(balance: payload.balance, streak: payload.streak.current, activeToday: payload.streak.activeToday ?? false,
                                           weekStreak: payload.weekStreak?.current, weekActive: payload.weekStreak?.thisWeekActive ?? false)
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

    /// Chooses the zone for streak days and the monthly cap. Effective from the next local day (server rule).
    /// Returns nil on success, otherwise the server error code.
    func setRewardTimezone(_ tz: String) async -> String? {
        guard let uid = userID else { return "AUTH_REQUIRED" }
        struct Env: Decodable { var success: Bool?; var error: String? }
        var failure: String?
        do {
            let env: Env = try await SupabaseService.client.rpc("set_my_reward_timezone", params: ["p_tz": tz]).execute().value
            if env.success != true { failure = env.error ?? "ERROR" }
        } catch { failure = "NETWORK" }
        guard userID == uid else { return failure }
        await loadRewards()
        return failure
    }

    /// Monthly outing goal (1, 2 or 4; 0 clears). No coins. Returns nil on success, otherwise the error code.
    func setOutingGoal(_ goal: Int) async -> String? {
        guard let uid = userID, rewardsV2Enabled else { return "NOT_AVAILABLE" }
        struct Env: Decodable { var success: Bool?; var error: String? }
        var failure: String?
        do {
            let env: Env = try await SupabaseService.client.rpc("set_my_outing_goal", params: ["p_goal": goal]).execute().value
            if env.success != true { failure = env.error ?? "ERROR" }
        } catch { failure = "NETWORK" }
        guard userID == uid else { return failure }
        await loadRewards()
        if failure == nil { Analytics.track(.rewardsGoalSet(goal: goal)) }
        return failure
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
        guard userID != nil, rewardsEnabled, rewardsSummaryStatus != .unavailable else { return }
        struct Env: Decodable { var success: Bool? }
        if let env: Env = try? await SupabaseService.client
            .rpc("record_active_day", params: ["p_source": "save", "p_ref": eventKey]).execute().value, env.success == true {
            await loadRewardsSummary()
        }
    }
}
