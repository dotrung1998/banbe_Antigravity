import Foundation

/// Apology templates for the host's "Cancel event" flow. Mirrors
/// src/lib/eventCancellationTemplates.js — keep the two in step.
///
/// Placeholders: {{guest_name}} {{event_name}} {{event_date}} {{event_place}}
/// {{organizer_name}}. The host sends from their OWN mailbox, one email per
/// guest, so {{guest_name}} is that guest's own name. (The optional single BCC
/// draft greets everyone together: "An, Bình and Chi".)
struct CancellationTemplate: Identifiable, Equatable {
    let key: String
    let titleVI: String, titleEN: String
    let reasonVI: String, reasonEN: String
    let subjectVI: String, subjectEN: String
    let bodyVI: String, bodyEN: String
    var id: String { key }

    func title(isEN: Bool) -> String { isEN ? titleEN : titleVI }
}

struct CancellationDraft: Equatable {
    let subject: String
    let body: String
    let reason: String
}

enum EventCancellationTemplates {
    static let maxNames = 6

    static let all: [CancellationTemplate] = [
        CancellationTemplate(
            key: "unforeseen",
            titleVI: "Lý do bất khả kháng", titleEN: "Unforeseen circumstances",
            reasonVI: "Sự kiện bị huỷ do hoàn cảnh bất khả kháng", reasonEN: "Cancelled due to unforeseen circumstances",
            subjectVI: "Thông báo huỷ sự kiện {{event_name}}", subjectEN: "Cancellation of {{event_name}}",
            bodyVI: """
            Kính gửi {{guest_name}},

            Chúng tôi vô cùng tiếc phải thông báo rằng sự kiện "{{event_name}}" dự kiến diễn ra vào {{event_date}} tại {{event_place}} đã phải huỷ do những hoàn cảnh bất khả kháng ngoài khả năng kiểm soát của chúng tôi.

            Chúng tôi chân thành xin lỗi vì sự bất tiện này và biết ơn sự quan tâm của bạn. Toàn bộ số tiền vé bạn đã thanh toán sẽ được hoàn lại đầy đủ. Vui lòng mở ứng dụng banbe và thêm tài khoản nhận hoàn tiền để chúng tôi chuyển khoản cho bạn.

            Một lần nữa, thành thật xin lỗi. Hy vọng sớm được gặp bạn ở một sự kiện khác.

            Trân trọng,
            {{organizer_name}}
            """,
            bodyEN: """
            Dear {{guest_name}},

            We are very sorry to let you know that "{{event_name}}", planned for {{event_date}} at {{event_place}}, has had to be cancelled because of circumstances beyond our control.

            Please accept our sincere apologies for the disruption, and our thanks for your support. Every ticket you paid for will be refunded in full. Please open the banbe app and add the account you'd like your refund sent to, and we will transfer it to you.

            Once again, we are truly sorry, and we hope to welcome you at a future event.

            Kind regards,
            {{organizer_name}}
            """),
        CancellationTemplate(
            key: "venue",
            titleVI: "Địa điểm không còn khả dụng", titleEN: "Venue no longer available",
            reasonVI: "Sự kiện bị huỷ vì địa điểm không còn khả dụng", reasonEN: "Cancelled because the venue is no longer available",
            subjectVI: "Về sự kiện {{event_name}}: địa điểm không còn khả dụng", subjectEN: "About {{event_name}}: venue unavailable",
            bodyVI: """
            Kính gửi {{guest_name}},

            Rất tiếc, địa điểm của sự kiện "{{event_name}}" ({{event_place}}) không còn khả dụng vào {{event_date}} và chúng tôi chưa tìm được địa điểm thay thế phù hợp, nên buổi gặp mặt buộc phải huỷ.

            Chúng tôi thành thật xin lỗi vì đã làm thay đổi kế hoạch của bạn. Số tiền vé bạn đã thanh toán sẽ được hoàn lại đầy đủ; vui lòng mở ứng dụng banbe và thêm tài khoản nhận hoàn tiền.

            Nếu sau này có địa điểm mới, chúng tôi sẽ báo cho bạn đầu tiên.

            Trân trọng,
            {{organizer_name}}
            """,
            bodyEN: """
            Dear {{guest_name}},

            Unfortunately the venue for "{{event_name}}" ({{event_place}}) is no longer available on {{event_date}}, and we have not been able to secure a suitable alternative, so we have to cancel the event.

            We are sincerely sorry for upsetting your plans. Every ticket you paid for will be refunded in full; please open the banbe app and add the account you'd like your refund sent to.

            If we find a new venue, you will be the first to hear about it.

            Kind regards,
            {{organizer_name}}
            """),
        CancellationTemplate(
            key: "low_turnout",
            titleVI: "Chưa đủ số lượng đăng ký", titleEN: "Not enough sign-ups",
            reasonVI: "Sự kiện bị huỷ vì chưa đủ số lượng đăng ký", reasonEN: "Cancelled because there were not enough sign-ups",
            subjectVI: "Thông báo huỷ {{event_name}}", subjectEN: "Update on {{event_name}}",
            bodyVI: """
            Kính gửi {{guest_name}},

            Cảm ơn bạn đã đăng ký tham gia "{{event_name}}" vào {{event_date}}. Rất tiếc, số lượng đăng ký chưa đủ để chúng tôi tổ chức sự kiện với chất lượng như đã hứa, nên chúng tôi quyết định huỷ.

            Chúng tôi xin lỗi vì quyết định này đến muộn hơn mong muốn và vì sự bất tiện bạn gặp phải. Toàn bộ số tiền vé sẽ được hoàn lại; vui lòng mở ứng dụng banbe và thêm tài khoản nhận hoàn tiền.

            Chúng tôi rất trân trọng sự ủng hộ của bạn và hy vọng sẽ sớm tổ chức lại.

            Trân trọng,
            {{organizer_name}}
            """,
            bodyEN: """
            Dear {{guest_name}},

            Thank you for signing up for "{{event_name}}" on {{event_date}}. Unfortunately, not enough people have registered for us to run the event to the standard we promised, so we have decided to cancel it.

            We apologise that this decision comes later than we would have liked, and for the inconvenience. All ticket payments will be refunded in full; please open the banbe app and add the account you'd like your refund sent to.

            We truly appreciate your support and hope to run this again soon.

            Kind regards,
            {{organizer_name}}
            """),
        CancellationTemplate(
            key: "safety",
            titleVI: "An toàn hoặc thời tiết", titleEN: "Safety or weather",
            reasonVI: "Sự kiện bị huỷ vì lý do an toàn hoặc thời tiết", reasonEN: "Cancelled for safety or weather reasons",
            subjectVI: "{{event_name}} bị huỷ vì lý do an toàn", subjectEN: "{{event_name}} cancelled for safety reasons",
            bodyVI: """
            Kính gửi {{guest_name}},

            Vì sự an toàn của tất cả mọi người, chúng tôi buộc phải huỷ sự kiện "{{event_name}}" dự kiến vào {{event_date}} tại {{event_place}} do điều kiện thời tiết hoặc an toàn không đảm bảo.

            Chúng tôi rất tiếc và xin lỗi vì sự thay đổi này. Số tiền vé bạn đã thanh toán sẽ được hoàn lại đầy đủ. Vui lòng mở ứng dụng banbe và thêm tài khoản nhận hoàn tiền.

            Cảm ơn bạn đã thông cảm. Chúc bạn bình an.

            Trân trọng,
            {{organizer_name}}
            """,
            bodyEN: """
            Dear {{guest_name}},

            For everyone's safety, we have had to cancel "{{event_name}}", planned for {{event_date}} at {{event_place}}, because of unsafe weather or conditions.

            We are very sorry for the change. Every ticket you paid for will be refunded in full. Please open the banbe app and add the account you'd like your refund sent to.

            Thank you for your understanding. Please stay safe.

            Kind regards,
            {{organizer_name}}
            """),
    ]

    /// "An, Bình and Chi"; past `maxNames` it names the first few and counts the rest.
    static func joinNames(_ names: [String], isEN: Bool) -> String {
        let list = names.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if list.isEmpty { return isEN ? "everyone" : "các bạn" }
        let and = isEN ? "and" : "và"
        if list.count == 1 { return list[0] }
        if list.count <= maxNames { return list.dropLast().joined(separator: ", ") + " \(and) " + list[list.count - 1] }
        let rest = list.count - maxNames
        return list.prefix(maxNames).joined(separator: ", ") + " \(and) \(rest) " + (isEN ? "others" : "bạn khác")
    }

    /// Replaces {{placeholders}}; an unknown or empty one stays visible instead
    /// of silently vanishing from a message that is about to be sent.
    static func fill(_ text: String, _ values: [String: String]) -> String {
        var out = text
        for (key, value) in values where !value.isEmpty {
            out = out.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return out
    }

    /// `guestName` set → an individual email to that person. nil → the group
    /// draft, greeted with everyone's names (used for the single BCC draft).
    static func draft(_ template: CancellationTemplate, isEN: Bool, guestName: String? = nil, guestNames: [String] = [],
                      eventName: String, eventDate: String, eventPlace: String, organizerName: String) -> CancellationDraft {
        let greeting: String
        if let guestName {
            let trimmed = guestName.trimmingCharacters(in: .whitespaces)
            greeting = trimmed.isEmpty ? (isEN ? "there" : "bạn") : trimmed
        } else {
            greeting = joinNames(guestNames, isEN: isEN)
        }
        let values: [String: String] = [
            "guest_name": greeting,
            "event_name": eventName,
            "event_date": eventDate,
            "event_place": eventPlace.isEmpty ? (isEN ? "the venue" : "địa điểm đã thông báo") : eventPlace,
            "organizer_name": organizerName,
        ]
        return CancellationDraft(
            subject: fill(isEN ? template.subjectEN : template.subjectVI, values),
            body: fill(isEN ? template.bodyEN : template.bodyVI, values),
            reason: isEN ? template.reasonEN : template.reasonVI)
    }
}
