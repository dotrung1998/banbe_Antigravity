import Foundation

/// "What's next" strip copy (note 78), one language per call. Twin of src/lib/ticketCopy.js: the owner approved this
/// table on 2026-11-05, and tests/fixtures/ticket-copy.json (generated from the web module) is checked by both
/// platforms, so a copy change is made in both or neither. Every line is a plain fact about the booking or the meaning
/// of an existing app string (refund responsibility, expired hold, dispute); no time, door or reply-speed claim is made
/// that the data does not hold. A link names an EXISTING action; the screen wires it (and drops the link without data).
enum TicketCopy {
    struct Link: Equatable {
        enum Kind: String { case refunds, reserve, pay, chat, receipt, directions, calendar }
        let kind: Kind
        let label: String
    }

    struct Copy: Equatable {
        let label: String
        let heading: String
        let sub: String?
        let detail: String?
        let link: Link?
    }

    struct Context {
        var en = false
        var eventCancelled = false
        var dateText = ""
        var timeText = ""
        var areaText = ""
        var daysUntil: Int?
        var typicalWait: (vi: String, en: String)?
        var verifyOverdue = false
        var hasReceipt = false
        var hasRefund = false
        var hasDirections = false
    }

    static func copy(for key: TicketStatus.Key, _ c: Context) -> Copy {
        func T(_ vi: String, _ en: String) -> String { c.en ? en : vi }
        func link(_ kind: Link.Kind, _ vi: String, _ en: String) -> Link { Link(kind: kind, label: T(vi, en)) }
        let receipt: Link? = c.hasReceipt ? link(.receipt, "Xem biên nhận", "View receipt") : nil
        switch key {
        case .cancelled:
            return Copy(
                label: T("Đã hủy", "Cancelled"),
                heading: c.eventCancelled ? T("Sự kiện đã bị hủy", "This event was cancelled") : T("Đặt chỗ đã bị hủy", "This booking was cancelled"),
                sub: T("Vé không còn dùng để vào cửa", "This ticket no longer works for entry"),
                // Refund responsibility is about the HOST cancelling; a booking cancelled on its own does not get this sentence.
                detail: c.eventCancelled ? T("Nếu bạn đã chuyển tiền, người tổ chức có trách nhiệm hoàn tiền cho bạn.", "If you already paid, the organizer is responsible for your refund.") : nil,
                link: c.hasRefund ? link(.refunds, "Theo dõi hoàn tiền", "Track refund") : nil)
        case .expired:
            return Copy(
                label: T("Hết hạn", "Expired"),
                heading: T("Chỗ giữ đã hết hạn", "Your hold ran out"),
                sub: T("Chỗ đã được mở lại", "The seat was released"),
                detail: T("Bạn chưa chuyển khoản trước khi hết giờ giữ chỗ, nên chỗ đã được mở lại cho người khác. Bạn có thể giữ chỗ lại nếu vẫn còn chỗ trống.",
                          "You didn't complete payment before the hold ran out, so the seat was released back. You can reserve again if there's still room."),
                link: link(.reserve, "Đặt lại", "Reserve again"))
        case .review:
            return Copy(
                label: T("Đang xem xét", "Under review"),
                heading: T("banbe đang xem xét", "banbe is reviewing this"),
                sub: nil,
                detail: T("Chỗ của bạn vẫn được giữ trong lúc chờ xem xét.", "Your seat stays held while this is reviewed."),
                link: nil)
        case .holding:
            return Copy(
                label: T("Đang giữ chỗ", "Holding"),
                heading: T("Chuyển khoản trước khi hết giờ", "Pay before time runs out"),
                sub: nil,
                detail: T("Chuyển khoản trực tiếp cho người tổ chức theo hướng dẫn trong tin nhắn. Mã QR mở khi họ xác nhận.",
                          "Pay the organizer directly using the instructions in chat. Your QR unlocks once they confirm."),
                link: link(.pay, "Xem thông tin chuyển khoản", "See payment details"))
        case .awaiting:
            return Copy(
                label: T("Chờ host", "Awaiting host"),
                heading: T("Host đang kiểm tra chuyển khoản", "The host is checking your transfer"),
                sub: c.verifyOverdue
                    ? T("Người tổ chức đang xử lý, có thể mất thêm chút thời gian", "The organizer is on it, it may take a little longer")
                    : T("Bạn sẽ nhận thông báo khi vé sẵn sàng", "We'll notify you when your ticket is ready"),
                detail: c.typicalWait.map { T($0.vi, $0.en) },
                link: link(.chat, "Nhắn host", "Message host"))
        case .ended:
            return Copy(
                label: T("Đã kết thúc", "Ended"),
                heading: T("Sự kiện đã kết thúc", "This event has ended"),
                sub: T("Vé không còn dùng để vào cửa", "Ticket no longer valid for entry"),
                detail: T("Biên nhận (nếu có) vẫn nằm trong Thêm tuỳ chọn.", "Any receipt stays under More options."),
                link: receipt)
        case .checkedIn:
            return Copy(
                label: T("Đã check-in", "Checked in"),
                heading: T("Bạn đã vào cửa", "You're in"),
                sub: T("Chúc bạn một buổi vui", "Enjoy the event"),
                detail: nil,
                link: receipt)
        case .today:
            return Copy(
                label: T("Hôm nay", "Today"),
                heading: c.timeText.isEmpty ? T("Hôm nay", "Today") : T("Hôm nay lúc \(c.timeText)", "Today at \(c.timeText)"),
                sub: c.areaText.isEmpty ? nil : c.areaText,
                detail: T("Mở sẵn trang này tại cửa và tăng độ sáng màn hình.", "Keep this page open at the door and raise your screen brightness."),
                link: c.hasDirections ? link(.directions, "Chỉ đường", "Directions") : nil)
        case .upcoming:
            let days = c.daysUntil
            let sub = [c.dateText, c.timeText].filter { !$0.isEmpty }.joined(separator: " ▪︎ ")
            return Copy(
                label: T("Sắp diễn ra", "Upcoming"),
                heading: (days ?? 0) >= 1
                    ? T("Còn \(days!) ngày nữa", "\(days!) \(days == 1 ? "day" : "days") to go")
                    : T("Sắp diễn ra", "Upcoming"),
                sub: sub.isEmpty ? nil : sub,
                detail: T("Vé đã sẵn sàng. Mã QR dùng để vào cửa vào ngày diễn ra.", "Your ticket is ready. The QR is what you show at the door on the day."),
                link: link(.calendar, "Thêm vào lịch", "Add to calendar"))
        }
    }
}
