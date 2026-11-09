import Foundation

/// The guided tour over the real app (note 64), in short forward-only chapters since onboarding v5 (note 80).
/// Web twin: src/data/onboardingTour.js — tests/unit/onboardingTour.test.mjs parses this file and checks ids,
/// targets, screens and order match (the copy and the chapters are iOS-only for now).
/// Targets are published by the real controls with `.tourTarget(_:)`; a target that is not on screen after a short
/// wait (no events yet, no For You matches) is skipped. `requires: "organizerMode"` drops a step for non-hosts.
struct TourStep: Identifiable, Equatable {
    let id: String
    let target: String
    let screen: String
    let below: Bool
    var requires: String? = nil
    let vi: (title: String, body: String)
    let en: (title: String, body: String)
    let short: (vi: String, en: String)

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
    static let steps: [TourStep] = [
        TourStep(id: "home.search", target: "tour.home.search", screen: "home", below: true,
                 vi: ("Tìm kiếm và khu vực", "Tìm sự kiện, host hay địa điểm. Mọi danh sách trên Trang chính đều theo khu vực bạn chọn."),
                 en: ("Search and area", "Search events, hosts or places. Every list on Home follows the area you pick."),
                 short: ("Tìm kiếm", "Search")),
        TourStep(id: "home.forYou", target: "tour.home.forYou", screen: "home", below: true,
                 vi: ("Gợi ý Dành cho bạn", "Làm từ câu trả lời bạn vừa chọn. Chấm vàng nghĩa là có gợi ý mới."),
                 en: ("Your For You picks", "Built from the answers you just gave. A gold dot means there are new picks."),
                 short: ("Dành cho bạn", "For You")),
        TourStep(id: "home.eventCard", target: "tour.home.eventCard", screen: "home", below: true,
                 vi: ("Mở một sự kiện", "Chạm vào thẻ để xem chi tiết, giữ chỗ hoặc nhắn host. Giữ chỗ miễn phí trong 30 phút."),
                 en: ("Open an event", "Tap a card to see details, hold a seat or message the host. A hold is free for 30 minutes."),
                 short: ("Sự kiện", "Event")),
        TourStep(id: "dock.map", target: "tour.dock.map", screen: "home", below: false,
                 vi: ("Bản đồ", "Xem sự kiện quanh bạn, theo khu phố và theo giờ."),
                 en: ("Map", "See what's on around you, by neighbourhood and by time."),
                 short: ("Bản đồ", "Map")),
        TourStep(id: "dock.schedule", target: "tour.dock.schedule", screen: "home", below: false,
                 vi: ("Lịch", "Mọi vé và buổi bạn đã lưu, xếp theo ngày."),
                 en: ("Schedule", "Every ticket and saved plan, day by day."),
                 short: ("Lịch", "Schedule")),
        TourStep(id: "dock.inbox", target: "tour.dock.inbox", screen: "home", below: false,
                 vi: ("Tin nhắn", "Trò chuyện với host và đội sự kiện, cùng cập nhật về vé của bạn. Huy hiệu đếm tin chưa đọc."),
                 en: ("Messages", "Conversations with hosts and event teams, and updates about your tickets. The badge counts what's unread."),
                 short: ("Tin nhắn", "Messages")),
        TourStep(id: "account.organizerMode", target: "tour.account.organizerMode", screen: "profile", below: true,
                 vi: ("Chế độ tổ chức", "Đang tắt, như bạn đã chọn. Bật lúc nào bạn muốn tổ chức một sự kiện."),
                 en: ("Hosting mode", "Off, as you chose. Turn it on any time you want to run an event."),
                 short: ("Tổ chức", "Host")),
        TourStep(id: "dock.create", target: "tour.dock.create", screen: "profile", below: false, requires: "organizerMode",
                 vi: ("Tạo sự kiện", "Nút + này mở trình tạo sự kiện 5 bước. Mất khoảng 5 phút."),
                 en: ("Create an event", "This + opens the 5-step event builder. It takes about 5 minutes."),
                 short: ("Tạo", "Create")),
    ]

    /// Three short chapters. A chapter whose steps are all ineligible is dropped.
    static let chapters: [TourChapter] = [
        TourChapter(id: "discover", name: ("Khám phá", "Discover"),
                    stepIDs: ["home.search", "home.forYou", "home.eventCard", "dock.map"]),
        TourChapter(id: "plans", name: ("Lịch và tin nhắn", "Plans and messages"),
                    stepIDs: ["dock.schedule", "dock.inbox"]),
        TourChapter(id: "you", name: ("Tài khoản của bạn", "Your account"),
                    stepIDs: ["account.organizerMode", "dock.create"]),
    ]

    static let doIt: [String: TourDoIt] = [
        "home.forYou": TourDoIt(vi: "Chạm Dành cho bạn", en: "Tap For You"),
    ]

    /// The hosting step speaks to what the person chose during setup.
    static let hostingOnCopy = (
        vi: (title: "Chế độ tổ chức", body: "Bạn đã bật lúc thiết lập. Nó thêm công cụ tổ chức: tạo sự kiện, check-in khách và nhận tiền."),
        en: (title: "Hosting mode", body: "You turned this on during setup. It adds the hosting tools: create events, check guests in and get paid.")
    )

    static func eligible(organizerMode: Bool) -> [TourStep] {
        steps.filter { $0.requires == nil || ($0.requires == "organizerMode" && organizerMode) }
    }

    /// Simple Shell (note 66, switch simple_shell): the same 8 steps, retargeted. Map is a Home view (the map layout
    /// toggle), the organizer-mode step points at Home's mode switch, and "+" is in the dock for everyone. Built from
    /// `steps` (not new literals) so the web/iOS parity test keeps reading one list.
    static func simpleShellSteps() -> [TourStep] {
        steps.map { s in
            switch s.id {
            case "dock.map":
                return TourStep(id: s.id, target: "tour.home.mapView", screen: "home", below: true, requires: s.requires,
                                vi: s.vi, en: s.en, short: s.short)
            case "account.organizerMode":
                return TourStep(id: s.id, target: "tour.home.modeSwitch", screen: "home", below: true, requires: s.requires,
                                vi: ("Muốn tổ chức?", "Chuyển sang Tổ chức ở đây để tạo sự kiện của riêng bạn. Chuyển lại lúc nào cũng được."),
                                en: ("Want to host?", "Switch to Hosting here to create your own events. Switch back any time."),
                                short: s.short)
            case "dock.create":
                return TourStep(id: s.id, target: s.target, screen: "home", below: false, requires: nil,
                                vi: ("Nút +", "Thêm vào lịch, mời bạn bè, hoặc tạo sự kiện khi bạn tổ chức."),
                                en: ("The + button", "Add to your schedule, invite friends, or create an event when you host."),
                                short: s.short)
            default:
                return s
            }
        }
    }

    static func eligible(organizerMode: Bool, simpleShell: Bool) -> [TourStep] {
        simpleShell ? simpleShellSteps() : eligible(organizerMode: organizerMode)
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
