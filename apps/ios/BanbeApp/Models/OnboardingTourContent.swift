import Foundation

/// The guided tour over the real app (note 64), in short forward-only chapters since onboarding v5 (note 80).
/// Web twin: src/data/onboardingTour.js (ids, targets, copy and chapters mirror it; the web test no longer parses this file).
/// Targets are published by the real controls with `.tourTarget(_:)`; a target that is not on screen after a short
/// wait (no events yet, no For You matches) is skipped. `requires: "organizerMode"` drops a step for non-hosts.
struct TourStep: Identifiable, Equatable {
    let id: String
    let target: String
    let screen: String // "home", "inbox" or "profile"
    let below: Bool
    var requires: String? = nil
    let vi: (title: String, body: String)
    let en: (title: String, body: String)
    /// Copy used instead of `vi`/`en` while the admin Rewards switch is OFF (web twin: `copyWhenRewardsOff`).
    var copyWhenRewardsOff: (vi: (title: String, body: String), en: (title: String, body: String))? = nil

    /// Resolved at display time from the app's current Rewards flag, so it follows the switch live.
    func copy(rewardsOn: Bool, english: Bool) -> (title: String, body: String) {
        if !rewardsOn, let off = copyWhenRewardsOff { return english ? off.en : off.vi }
        return english ? en : vi
    }

    static func == (a: TourStep, b: TourStep) -> Bool { a.id == b.id }
}

/// A run of steps with a break after it. Only the break (or End tour) lets the person stop.
struct TourChapter: Identifiable, Equatable {
    let id: String
    let name: (vi: String, en: String)
    let stepIDs: [String]

    static func == (a: TourChapter, b: TourChapter) -> Bool { a.id == b.id && a.stepIDs == b.stepIDs }
}

/// A "do it" step only moves on when the highlighted control is tapped. The overlay then runs that control's own
/// action itself (`OnboardingTourController.perform`): the real control underneath is never pressed.
struct TourDoIt: Equatable {
    let vi: String
    let en: String
}

enum OnboardingTourContent {
    /// Follows the web tour (src/data/onboardingTour.js, v5 prototype). Targets a screen has not published yet
    /// (hero tabs, browse row, filter summary, Activity tabs/gear, Account tiles, host hero/quick) are skipped after
    /// the usual short wait, so the tour still runs on a build that lacks them.
    static let steps: [TourStep] = [
        TourStep(id: "home.forYou", target: "tour.home.forYou", screen: "home", below: true,
                 vi: ("Gợi ý Dành cho bạn", "Làm từ câu trả lời bạn vừa chọn. Vuốt ngang để xem thêm, chạm vào thẻ để mở sự kiện."),
                 en: ("Your For You picks", "Built from the answers you just gave. Swipe sideways for more, and tap a card to open the event.")),
        TourStep(id: "home.tonight", target: "tour.home.tonight", screen: "home", below: true,
                 vi: ("Ba cách vào xem", "Dành cho bạn là của riêng bạn. Tối nay là mọi thứ diễn ra hôm nay. Cuối tuần gồm thứ Bảy và Chủ nhật."),
                 en: ("Three ways in", "For You is yours. Tonight is everything on today. Weekend covers Saturday and Sunday.")),
        TourStep(id: "home.tabPicks", target: "tour.home.rail", screen: "home", below: true,
                 vi: ("Danh sách theo tab", "Các gợi ý bên dưới đổi theo tab bạn chọn. Hôm nay chưa có gì thì tab sẽ báo trống."),
                 en: ("Picks follow the tab", "The picks below change with the tab you choose. If nothing is on, the tab says so.")),
        TourStep(id: "home.search", target: "tour.home.search", screen: "home", below: true,
                 vi: ("Tìm kiếm và khu vực", "Tìm sự kiện, host hay địa điểm. Chấm ghim đặt khu vực, và mọi danh sách trên Trang chính đều theo khu vực đó."),
                 en: ("Search and area", "Search events, hosts or places. The pin sets your area, and every list on Home follows it.")),
        TourStep(id: "home.browse", target: "tour.home.browse", screen: "home", below: true,
                 vi: ("Duyệt theo loại", "Năm loại phổ biến, cùng Tìm một loại để tìm theo tên, như rượu vang hay phim."),
                 en: ("Browse by type", "Five popular types, plus Find a type to search all of them by name, like wine or film.")),
        TourStep(id: "home.filters", target: "tour.home.filters", screen: "home", below: false,
                 vi: ("Bộ lọc, đặt một lần", "Dòng này cho biết bộ lọc của bạn. Chạm để đổi ngày, giá, chỗ hoặc khu vực. Bộ lọc áp dụng cho mọi danh sách."),
                 en: ("Filters, set once", "This line shows your filters. Tap it to change date, price, seats or area. The same filters apply on every list.")),
        TourStep(id: "dock.schedule", target: "tour.dock.schedule", screen: "home", below: false,
                 vi: ("Lịch", "Mọi vé và buổi bạn đã lưu, xếp theo ngày."),
                 en: ("Schedule", "Every ticket and saved plan, day by day.")),
        TourStep(id: "dock.activity", target: "tour.dock.inbox", screen: "home", below: false,
                 vi: ("Hoạt động", "Tin nhắn với host và cập nhật về vé, thanh toán của bạn, gom một chỗ. Huy hiệu đếm những gì chưa đọc."),
                 en: ("Activity", "Messages with hosts and updates about your tickets and payments, in one place. The badge counts what's unread.")),
        TourStep(id: "activity.tabs", target: "tour.activity.tabs", screen: "inbox", below: true,
                 vi: ("Tin nhắn và Thông báo", "Tin nhắn là các cuộc trò chuyện: host, đội sự kiện, tranh chấp. Thông báo là cập nhật: vé, thanh toán, sự kiện. Không có gì hiện hai lần."),
                 en: ("Messages and Notifications", "Messages are conversations: hosts, event teams, disputes. Notifications are updates: tickets, payments, events. Nothing shows up twice.")),
        TourStep(id: "activity.gear", target: "tour.activity.gear", screen: "inbox", below: true,
                 vi: ("Cài đặt tin nhắn", "Hội thoại đã lưu trữ và phản hồi nằm sau nút này. Công tắc thông báo ở Tài khoản › Cài đặt."),
                 en: ("Messaging settings", "Archived conversations and feedback live behind this gear. Notification switches are in Account › Settings.")),
        TourStep(id: "dock.account", target: "tour.dock.profile", screen: "inbox", below: false,
                 vi: ("Tài khoản", "Hồ sơ, vé, ví và cài đặt của bạn."),
                 en: ("Account", "Your profile, tickets, wallet and settings.")),
        TourStep(id: "account.shortcuts", target: "tour.account.shortcuts", screen: "profile", below: true,
                 vi: ("Bốn lối tắt hay dùng", "Vé kèm mã QR, Ví cho thông tin thanh toán, sự kiện Đã lưu và Phần thưởng."),
                 en: ("The four you’ll use most", "Tickets with their QR codes, Wallet for payment details, Saved events, and Rewards."),
                 copyWhenRewardsOff: (
                    vi: ("Bốn lối tắt hay dùng", "Vé kèm mã QR, Ví cho thông tin thanh toán, sự kiện Đã lưu và Trợ giúp."),
                    en: ("The four you’ll use most", "Tickets with their QR codes, Wallet for payment details, Saved events, and Help."))),
        TourStep(id: "account.organizerMode", target: "tour.account.organizerMode", screen: "profile", below: true,
                 vi: ("Chế độ tổ chức", "Đang tắt, như bạn đã chọn. Bật lúc nào bạn muốn tổ chức một sự kiện. Nó thêm Hosting ở Trang chính và tab Host ở đây."),
                 en: ("Hosting mode", "Off, as you chose. Turn it on any time you want to run an event. It adds Hosting on Home and the Host tab here.")),
        TourStep(id: "account.settings", target: "tour.account.settings", screen: "profile", below: false,
                 vi: ("Cài đặt", "Thông báo, gợi ý Dành cho bạn, giao diện và ngôn ngữ đều ở đây. Xem lại hướng dẫn này trong Trợ giúp."),
                 en: ("Settings", "Notifications, For You preferences, appearance and language are all here. Replay this tour from Help.")),
        TourStep(id: "host.tab", target: "tour.home.hosting", screen: "home", below: true, requires: "organizerMode",
                 vi: ("Trang Hosting của bạn", "Chế độ tổ chức đã thêm tab này. Nó chứa mọi thứ về các sự kiện bạn tổ chức."),
                 en: ("Your Hosting home", "Hosting mode added this tab. It holds everything about the events you run.")),
        TourStep(id: "host.hero", target: "tour.host.hero", screen: "home", below: true, requires: "organizerMode",
                 vi: ("Lên kế hoạch sự kiện tiếp theo", "Tạo sự kiện mở trình tạo 5 bước. Mất khoảng 5 phút và lần sau sẽ sao chép sự kiện gần nhất."),
                 en: ("Plan your next event", "Create opens a 5-step builder. It takes about 5 minutes and copies your last event next time.")),
        TourStep(id: "host.quick", target: "tour.host.quick", screen: "home", below: true, requires: "organizerMode",
                 vi: ("Công cụ tổ chức", "Khách và check-in, hoàn tiền, story, khảo sát, hồ sơ host và báo cáo."),
                 en: ("Host tools", "Guests and check-in, refunds, stories, surveys, your host profile and reports.")),
    ]

    /// Four chapters (the last one only for hosts). A chapter whose steps are all ineligible is dropped.
    static let chapters: [TourChapter] = [
        TourChapter(id: "discover", name: ("Khám phá", "Discover"),
                    stepIDs: ["home.forYou", "home.tonight", "home.tabPicks", "home.search", "home.browse", "home.filters"]),
        TourChapter(id: "plans", name: ("Lịch và tin nhắn", "Plans and messages"),
                    stepIDs: ["dock.schedule", "dock.activity", "activity.tabs", "activity.gear"]),
        TourChapter(id: "you", name: ("Tài khoản của bạn", "Your account"),
                    stepIDs: ["dock.account", "account.shortcuts", "account.organizerMode", "account.settings"]),
        TourChapter(id: "host", name: ("Tổ chức", "Hosting"),
                    stepIDs: ["host.tab", "host.hero", "host.quick"]),
    ]

    /// The prototype's taps: Tonight or Weekend, Activity, Account, Hosting.
    static let doIt: [String: TourDoIt] = [
        "home.tonight": TourDoIt(vi: "Chạm Tối nay hoặc Cuối tuần", en: "Tap Tonight or Weekend"),
        "dock.activity": TourDoIt(vi: "Chạm Hoạt động", en: "Tap Activity"),
        "dock.account": TourDoIt(vi: "Chạm Tài khoản", en: "Tap Account"),
        "host.tab": TourDoIt(vi: "Chạm Hosting", en: "Tap Hosting"),
    ]

    /// The hosting step speaks to what the person chose during setup.
    static let hostingOnCopy = (
        vi: (title: "Chế độ tổ chức", body: "Bạn đã bật lúc thiết lập. Nó thêm công cụ tổ chức: tạo sự kiện, check-in khách và nhận tiền."),
        en: (title: "Hosting mode", body: "You turned this on during setup. It adds the hosting tools: create events, check guests in and get paid.")
    )

    static func eligible(organizerMode: Bool) -> [TourStep] {
        steps.filter { $0.requires == nil || ($0.requires == "organizerMode" && organizerMode) }
    }

    static func eligible(organizerMode: Bool, simpleShell: Bool) -> [TourStep] {
        eligible(organizerMode: organizerMode) // simpleShell no longer changes the tour (web parity)
    }

    /// The eligible steps grouped into their chapters, in tour order.
    static func plan(organizerMode: Bool, simpleShell: Bool) -> [(chapter: TourChapter, steps: [TourStep])] {
        let byID = Dictionary(eligible(organizerMode: organizerMode, simpleShell: simpleShell).map { ($0.id, $0) },
                              uniquingKeysWith: { a, _ in a })
        return chapters.compactMap { c in
            let s = c.stepIDs.compactMap { byID[$0] }
            return s.isEmpty ? nil : (c, s)
        }
    }

    static func doneKey(_ uid: UUID) -> String { "banbe.tour.v3.done.\(uid.uuidString.lowercased())" }
}

/// Note 80: a logged-out visitor sees onboarding once per device (local only; no server marker exists without an account).
enum GuestOnboarding {
    private static let key = "banbe.guestOnboarding.v1"
    static var seen: Bool { UserDefaults.standard.bool(forKey: key) }
    static func markSeen() { UserDefaults.standard.set(true, forKey: key) }
}
