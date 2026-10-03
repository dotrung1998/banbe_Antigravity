import SwiftUI
import MessageUI

/// Host-side "text a promo" flow: ONE consenting recipient at a time, shown by
/// first name only. The recipient's phone is revealed by the server only when
/// the host taps "Open Messages" — after it rechecks consent, audience and the
/// host's permission. The host then sends (or cancels) the text themselves in
/// the Messages composer; banbe never sends, never sends in bulk, and can't
/// confirm delivery (it may travel as SMS or iMessage).
struct HostPromoSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    let eventKey: String

    private enum Phase: Equatable {
        case loading
        case recipient(PromoRecipient)
        case none
        case failed(String)
        case finished(String)
    }

    @State private var phase: Phase = .loading
    @State private var busy = false
    @State private var composing: PromoCompose?
    @State private var notice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(app.T("Nhắn tin quảng bá", "Text a promo")).font(BanbeTheme.display(22))
                Spacer()
                Button(app.T("Đóng", "Close")) { dismiss() }.font(.system(size: 13)).buttonStyle(.plain)
            }
            Text(app.T("Chỉ những người đã bật “Tin nhắn quảng bá từ host” và từng đặt chỗ, theo dõi hoặc lưu sự kiện của bạn. Tin mở trong ứng dụng Tin nhắn — bạn tự bấm gửi hoặc huỷ. banbe không gửi hộ và không xác nhận tin đã được nhận.",
                       "Only people who turned on “Host promotional messages” and have booked, followed or saved one of your events. The text opens in Messages — you send or cancel it yourself. banbe doesn't send for you and can't confirm delivery."))
                .font(.system(size: 12)).foregroundStyle(app.palette.ink.opacity(0.75))

            switch phase {
            case .loading:
                ProgressView().frame(maxWidth: .infinity).padding(.top, 20)
            case .recipient(let r):
                VStack(alignment: .leading, spacing: 12) {
                    Text(r.displayName).font(BanbeTheme.display(20))
                    Text(app.T("Đã đồng ý nhận tin quảng bá.", "Has opted in to promotional texts."))
                        .font(.system(size: 12)).foregroundStyle(app.palette.ink.opacity(0.7))
                    InkButton(title: busy ? app.T("Đang chuẩn bị…", "Preparing…") : app.T("Mở Tin nhắn", "Open Messages"),
                              enabled: !busy) { prepare(r) }
                        .accessibilityIdentifier("promo.open")
                }
                .padding(16)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            case .none:
                Text(app.T("Hiện chưa có ai khác đủ điều kiện nhận tin quảng bá cho sự kiện này.",
                           "No one else is eligible for a promo about this event right now."))
                    .font(.system(size: 13))
            case .failed(let text):
                Text(text).font(.system(size: 13)).foregroundStyle(BanbeTheme.alert)
            case .finished(let text):
                VStack(alignment: .leading, spacing: 12) {
                    Text(text).font(.system(size: 13))
                    InkButton(title: app.T("Người tiếp theo", "Next recipient")) { Task { await loadNext() } }
                        .accessibilityIdentifier("promo.next")
                }
            }
            if let notice {
                Text(notice).font(.system(size: 12.5)).foregroundStyle(BanbeTheme.alert)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(app.palette.ink)
        .padding(24)
        .background(app.palette.paper.ignoresSafeArea())
        .task { await loadNext() }
        .sheet(item: $composing) { c in
            MessageComposer(phone: c.phone, body: Self.body(for: c)) { result in
                composing = nil
                let outcome: String
                switch result {
                case .sent: outcome = "sent"
                case .cancelled: outcome = "cancelled"
                default: outcome = "failed"
                }
                Task { await app.finishPromoCompose(logID: c.logId, result: outcome) }
                phase = .finished(finishText(outcome))
            }
            .ignoresSafeArea()
        }
    }

    private func finishText(_ outcome: String) -> String {
        switch outcome {
        case "sent": return app.T("Tin nhắn đã được chuyển cho ứng dụng Tin nhắn để gửi. banbe không xác nhận được người nhận đã nhận.", "The text was handed to Messages to send. banbe can't confirm the recipient received it.")
        case "cancelled": return app.T("Bạn đã huỷ — không có tin nào được gửi.", "You cancelled — nothing was sent.")
        default: return app.T("Ứng dụng Tin nhắn không gửi được tin này.", "Messages couldn't send this text.")
        }
    }

    private func loadNext() async {
        notice = nil
        phase = .loading
        let (recipient, error) = await app.nextPromoRecipient(eventKey: eventKey)
        if let error { phase = .failed(errorText(error)); return }
        phase = recipient.map { .recipient($0) } ?? .none
    }

    private func prepare(_ r: PromoRecipient) {
        notice = nil
        // Check the device FIRST so a phone that can't text doesn't use up the
        // recipient.
        guard MFMessageComposeViewController.canSendText() else {
            notice = app.T("Thiết bị này không gửi được tin nhắn văn bản.", "This device can't send text messages.")
            return
        }
        busy = true
        Task {
            defer { busy = false }
            let (compose, error) = await app.beginPromoCompose(eventKey: eventKey, recipientID: r.id)
            if let error {
                // e.g. they withdrew consent a moment ago.
                if error == .notEligible {
                    notice = app.T("Người này không còn đủ điều kiện nhận tin. Chuyển sang người tiếp theo.", "This person is no longer eligible. Moving on.")
                    await loadNext()
                } else {
                    notice = errorText(error)
                }
                return
            }
            composing = compose
        }
    }

    private func errorText(_ e: PromoError) -> String {
        switch e {
        case .notAuthorized: return app.T("Bạn không có quyền gửi tin quảng bá cho sự kiện này.", "You aren't allowed to send promos for this event.")
        case .rateLimited: return app.T("Bạn đã đạt giới hạn tin quảng bá hôm nay. Thử lại sau.", "You've reached today's promo limit. Try again later.")
        case .notEligible: return app.T("Người này không đủ điều kiện nhận tin.", "This person isn't eligible.")
        case .gate: return app.T("Hãy hoàn tất xác nhận tài khoản trước.", "Finish confirming your account first.")
        case .other: return app.T("Chưa thực hiện được. Thử lại sau.", "That didn't work. Please try again later.")
        }
    }

    /// Short text in the RECIPIENT's language, with the host's page link.
    static func body(for c: PromoCompose) -> String {
        let link = "https://banbe.app/org/\(c.organizerId)"
        let host = c.organizerName.isEmpty ? "banbe" : c.organizerName
        if c.locale == "en" {
            return "Hi \(c.displayName)! \(host) has an event: “\(c.eventName)”. Details: \(link)"
        }
        return "Chào \(c.displayName)! \(host) có sự kiện “\(c.eventName)”. Xem chi tiết: \(link)"
    }
}

extension PromoCompose: Identifiable { var id: UUID { logId } }

/// The system Messages composer for ONE recipient. The user sends or cancels.
struct MessageComposer: UIViewControllerRepresentable {
    let phone: String
    let body: String
    let onFinish: (MessageComposeResult) -> Void

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.recipients = [phone]
        vc.body = body
        vc.messageComposeDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: (MessageComposeResult) -> Void
        init(onFinish: @escaping (MessageComposeResult) -> Void) { self.onFinish = onFinish }
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            onFinish(result)
        }
    }
}
