import Foundation

/// System messages in a chat are written once, by SQL, and read by BOTH people in
/// the thread — so unlike a notification they can't be stored in "the
/// recipient's" language. Each viewer's app translates the known wordings at
/// display time instead, following their own language setting. Mirrors
/// src/lib/systemMessageLocale.js — keep the two in step. Anything unrecognised
/// (a person's own message, a future wording) is returned untouched.
enum SystemMessageLocale {
    private static let reasonPairs: [(vi: String, en: String)] = [
        ("Nhầm người", "Wrong person"), ("Bấm nhầm", "Tapped by mistake"),
        ("Khách chưa thực sự có mặt", "Guest hasn't actually arrived"), ("Khác", "Other"),
        ("Sự kiện đổi lịch hoặc huỷ", "Event rescheduled or cancelled"),
        ("Không thanh toán đúng hạn", "Payment not completed in time"), ("Vi phạm quy định", "Policy violation"),
        ("Hết chỗ thật sự", "Actually out of seats"), ("Không khớp với sao kê", "Doesn't match the statement"),
        ("Nghi ngờ gian lận", "Suspected fraud"),
        ("Sự kiện bị huỷ do hoàn cảnh bất khả kháng", "Cancelled due to unforeseen circumstances"),
        ("Sự kiện bị huỷ vì địa điểm không còn khả dụng", "Cancelled because the venue is no longer available"),
        ("Sự kiện bị huỷ vì chưa đủ số lượng đăng ký", "Cancelled because there were not enough sign-ups"),
        ("Sự kiện bị huỷ vì lý do an toàn hoặc thời tiết", "Cancelled for safety or weather reasons"),
        ("Không có lý do", "No reason provided"), ("Người tổ chức đã huỷ", "Cancelled by organizer"),
        ("chuyển khoản trực tiếp", "direct transfer"),
    ]

    private typealias Rule = (pattern: String, build: ([String]) -> String)

    private static func opt(_ g: [String], _ i: Int, prefix: String = "") -> String {
        i < g.count && !g[i].isEmpty ? prefix + g[i] : ""
    }

    private static let viToEN: [Rule] = [
        (#"^Khách báo đã chuyển khoản ▪︎ mã (.*), mã giao dịch (.*)\. Chỗ được giữ cho tới khi bạn xác nhận\.$"#,
         { "Guest reported a transfer ▪︎ code \($0[1]), transaction ID \($0[2]). The spot is held until you confirm." }),
        (#"^Người tổ chức chưa tìm thấy khoản chuyển khoản này(?:: (.*?))?\. Chỗ của bạn vẫn được giữ trong lúc banbe xem xét\.$"#,
         { "The organizer couldn't find this transfer\(opt($0, 1, prefix: ": ")). Your spot is still held while banbe reviews it." }),
        (#"^Người tổ chức chưa tìm thấy khoản chuyển khoản này(?:: (.*?))?\. Vui lòng kiểm tra lại thông tin chuyển khoản hoặc gửi thêm bằng chứng — chỗ của bạn vẫn được giữ\.$"#,
         { "The organizer couldn't find this transfer\(opt($0, 1, prefix: ": ")). Please re-check the transfer details or send more proof — your spot is still held." }),
        (#"^Người tổ chức và bạn chưa thống nhất được về khoản chuyển khoản này, nên đã chuyển cho banbe xem xét\. Chỗ của bạn vẫn được giữ trong lúc chờ\.$"#,
         { _ in "The organizer and you couldn't agree on this transfer, so it was passed to banbe for review. Your spot is still held meanwhile." }),
        (#"^Đã xác nhận thanh toán ▪︎ (tự động đối soát qua ngân hàng|người tổ chức xác nhận)(?:\. Biên nhận (.*))?\.$"#,
         { "Payment confirmed ▪︎ \($0[1] == "người tổ chức xác nhận" ? "confirmed by the organizer" : "automatically matched with the bank")\(opt($0, 2, prefix: ". Receipt "))." }),
        (#"^Người tổ chức không nhận yêu cầu đặt chỗ này(?:: (.*?))?\. Chỗ đã được mở lại cho người khác\.$"#,
         { "The organizer declined this booking request\(opt($0, 1, prefix: ": ")). The spot has been released to others." }),
        (#"^Đặt chỗ thành công ▪︎ số tiền cần thanh toán (\S+) \(mã (.+?)\)\. Người tổ chức sẽ gửi thông tin chuyển khoản sớm\.$"#,
         { "Reservation confirmed ▪︎ amount due \($0[1]) (code \($0[2])). The organizer will send the transfer details soon." }),
        (#"^Đặt chỗ thành công ▪︎ số tiền cần thanh toán (\S+) \(mã (.+?)\)\. Chuyển khoản tới: (.*?)Xem chi tiết và gửi ảnh xác nhận trong mục Thanh toán\.$"#,
         { "Reservation confirmed ▪︎ amount due \($0[1]) (code \($0[2])). Transfer to: "
            + $0[3].replacingOccurrences(of: "Ngân hàng:", with: "Bank:").replacingOccurrences(of: ", STK ", with: ", account no. ")
            + "See the details and upload your transfer proof under Payments." }),
    ]

    private static let enToVI: [Rule] = [
        (#"^Host marked payment received via (.*?)\.(?: Biên nhận ▪︎ Receipt (.*))?$"#,
         { "Người tổ chức đã xác nhận nhận thanh toán qua \($0[1]).\(opt($0, 2, prefix: " Biên nhận "))" }),
        (#"^Booking cancelled\. Reason: (.*)\.$"#, { "Đặt chỗ đã bị huỷ. Lý do: \($0[1])." }),
        (#"^Event was cancelled by host\. Reason: (.*)\.$"#, { "Sự kiện đã bị người tổ chức huỷ. Lý do: \($0[1])." }),
    ]

    /// Bodies the SQL wrote as "<vi> <separator> <en>": the viewer sees their half.
    private static let bilingual: [String] = [
        #"^(.*?) / (Dispute resolved.*)$"#,
        #"^(Khách báo đã chuyển khoản) ▪︎ (Guest reported a transfer for booking .*)$"#,
        #"^(Đặt chỗ thành công ▪︎ sự kiện miễn phí, không cần thanh toán\.) (Reservation confirmed ▪︎ this event is free, nothing to pay\.)$"#,
    ]

    private static func groups(_ pattern: String, in text: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: text).map { String(text[$0]) } ?? ""
        }
    }

    private static func swapReason(_ text: String, isEN: Bool) -> String {
        var out = text
        for pair in reasonPairs {
            let from = isEN ? pair.vi : pair.en, to = isEN ? pair.en : pair.vi
            for sep in [": ", "qua "] where out.contains(sep + from) {
                out = out.replacingOccurrences(of: sep + from, with: sep + to)
            }
        }
        return out
    }

    static func localize(_ body: String, isEN: Bool) -> String {
        for pattern in bilingual {
            if let g = groups(pattern, in: body) { return isEN ? g[2] : g[1] }
        }
        for rule in (isEN ? viToEN : enToVI) {
            if let g = groups(rule.pattern, in: body) { return swapReason(rule.build(g), isEN: isEN) }
        }
        return body
    }
}
