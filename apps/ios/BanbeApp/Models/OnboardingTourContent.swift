import Foundation

/// Onboarding Version 3: the guided tour over the real app (note 64). Web twin: src/data/onboardingTour.js —
/// tests/unit/onboardingTour.test.mjs parses this file and checks ids, targets, screens and order match.
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

enum OnboardingTourContent {
    static let steps: [TourStep] = [
        TourStep(id: "home.search", target: "tour.home.search", screen: "home", below: true,
                 vi: ("Tìm mọi thứ ở đây", "Gõ tên sự kiện, host hay khu vực. Kết quả hiện ngay khi bạn gõ."),
                 en: ("Find anything here", "Type an event, a host or an area. Results show up as you type."),
                 short: ("Tìm kiếm", "Search")),
        TourStep(id: "home.forYou", target: "tour.home.forYou", screen: "home", below: true,
                 vi: ("Dành cho bạn", "Lọc theo câu trả lời của bạn lúc bắt đầu. Chấm vàng nghĩa là có gợi ý mới."),
                 en: ("For You", "Filters by the answers you gave at the start. A gold dot means there are new picks."),
                 short: ("Dành cho bạn", "For You")),
        TourStep(id: "home.eventCard", target: "tour.home.eventCard", screen: "home", below: true,
                 vi: ("Một sự kiện", "Chạm vào thẻ để xem chi tiết, giữ chỗ hoặc nhắn host. Giữ chỗ miễn phí trong 30 phút."),
                 en: ("An event", "Tap a card to see details, hold a seat or message the host. A hold is free for 30 minutes."),
                 short: ("Sự kiện", "Event")),
        TourStep(id: "dock.map", target: "tour.dock.map", screen: "home", below: false,
                 vi: ("Bản đồ", "Xem sự kiện quanh bạn trên bản đồ."),
                 en: ("Map", "See what is on around you on a map."),
                 short: ("Bản đồ", "Map")),
        TourStep(id: "dock.schedule", target: "tour.dock.schedule", screen: "home", below: false,
                 vi: ("Lịch", "Vé và những buổi bạn đã lưu, xếp theo ngày."),
                 en: ("Schedule", "Your tickets and saved plans, day by day."),
                 short: ("Lịch", "Schedule")),
        TourStep(id: "dock.inbox", target: "tour.dock.inbox", screen: "home", below: false,
                 vi: ("Tin nhắn", "Trò chuyện với host và nhận cập nhật về vé của bạn."),
                 en: ("Messages", "Chat with hosts and get updates about your tickets."),
                 short: ("Tin nhắn", "Messages")),
        TourStep(id: "account.organizerMode", target: "tour.account.organizerMode", screen: "profile", below: true,
                 vi: ("Muốn tổ chức?", "Bật chế độ tổ chức ở đây để tạo sự kiện của riêng bạn. Tắt lúc nào cũng được."),
                 en: ("Want to host?", "Turn on organizer mode here to create your own events. Turn it off any time."),
                 short: ("Tổ chức", "Host")),
        TourStep(id: "dock.create", target: "tour.dock.create", screen: "profile", below: false, requires: "organizerMode",
                 vi: ("Tạo sự kiện", "Nút + này mở trình tạo sự kiện 5 bước."),
                 en: ("Create an event", "This + opens the 5-step event builder."),
                 short: ("Tạo", "Create")),
    ]

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

    static func doneKey(_ uid: UUID) -> String { "banbe.tour.v3.done.\(uid.uuidString.lowercased())" }
}
