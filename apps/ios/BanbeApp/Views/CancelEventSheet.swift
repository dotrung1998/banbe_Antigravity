import SwiftUI
import MessageUI

/// Host flow, two phases. Mirrors src/components/CancelEventModal.jsx.
///
///   plan  pick an apology template, preview it, confirm → cancel_event RPC
///         (cancels every ticket, opens the refund claims).
///   send  one personalised draft per ticket holder, each opened in the HOST'S
///         OWN mail app so they press Send from their own mailbox. banbe sends
///         nothing; each guest sees only their own address.
///
/// A cancelled event opens straight into `send`, so the host can leave and come
/// back to finish. Which guests they've already drafted is remembered on this device.
struct CancelEventSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let eventKey: String
    let eventName: String
    let eventDate: String
    let eventPlace: String
    let organizerName: String
    var alreadyCancelled = false
    /// Called when the host is done after cancelling (go back to the dashboard).
    let onFinished: () -> Void

    private enum Phase { case plan, send }

    @State private var phase: Phase = .plan
    @State private var holders: [AppState.TicketHolder] = []
    @State private var loading = true
    @State private var loadFailed = false
    @State private var selected = EventCancellationTemplates.all[0]
    @State private var confirming = false
    @State private var busy = false
    @State private var error = ""
    @State private var mail: MailDraft?
    @State private var drafted: Set<String> = []

    struct MailDraft: Identifiable {
        let id = UUID()
        let subject: String
        let body: String
        let to: [String]
        let bcc: [String]
    }

    private var draftedKey: String { "cancelDrafts.\(eventKey)" }

    private func draft(for name: String?, group: Bool = false) -> CancellationDraft {
        EventCancellationTemplates.draft(selected, isEN: app.isEN, guestName: group ? nil : (name ?? ""),
                                         guestNames: holders.map(\.name), eventName: eventName, eventDate: eventDate,
                                         eventPlace: eventPlace, organizerName: organizerName)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if phase == .plan { planContent } else { sendContent }
                }
                .padding(20)
                .foregroundStyle(app.palette.ink)
            }
            .background(app.palette.paper.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if phase == .plan {
                        Button(app.T("Đóng", "Close")) { dismiss() }.disabled(busy)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if phase == .send {
                        Button(app.T("Xong", "Done")) { finish() }.accessibilityIdentifier("cancelEvent.done")
                    }
                }
            }
        }
        .interactiveDismissDisabled(busy)
        .task {
            phase = alreadyCancelled ? .send : .plan
            drafted = Set(UserDefaults.standard.stringArray(forKey: draftedKey) ?? [])
            await load()
        }
        .confirmationDialog(app.T("Huỷ sự kiện này?", "Cancel this event?"), isPresented: $confirming, titleVisibility: .visible) {
            Button(app.T("Có, huỷ sự kiện", "Yes, cancel the event"), role: .destructive) { Task { await cancel() } }
            Button(app.T("Giữ sự kiện", "Keep the event"), role: .cancel) {}
        } message: {
            Text(holders.isEmpty
                 ? app.T("Sự kiện sẽ bị huỷ.", "The event will be cancelled.")
                 : app.T("\(holders.count) người giữ vé sẽ bị huỷ vé.", "\(holders.count) ticket holder(s) will lose their tickets."))
        }
        .sheet(item: $mail) { item in
            MailComposer(subject: item.subject, body: item.body, to: item.to, bcc: item.bcc) { opened in
                if opened { (item.to + item.bcc).forEach(markDrafted) }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: Phase 1 — plan

    @ViewBuilder private var planContent: some View {
        Text(app.T("Huỷ sự kiện \"\(eventName)\"", "Cancel \"\(eventName)\"")).font(BanbeTheme.display(22))
        Text(app.T("Tất cả vé sẽ bị huỷ và các khoản đã thanh toán được chuyển vào mục hoàn tiền. Việc này không thể hoàn tác.",
                   "Every ticket will be cancelled and paid tickets move to refunds. This can't be undone."))
            .font(.system(size: 12.5)).opacity(0.75)

        if loading {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
        } else if loadFailed {
            loadError
        } else {
            Text(holders.isEmpty
                 ? app.T("Chưa có người giữ vé nào để gửi thư.", "No ticket holders to email.")
                 : app.T("Sau khi huỷ, bạn sẽ soạn thư xin lỗi riêng cho \(holders.count) người giữ vé, gửi từ email của bạn.",
                         "After cancelling you'll draft a separate apology to each of \(holders.count) ticket holder(s), sent from your own email."))
                .font(.system(size: 12.5))
            templatePicker
            preview
        }

        if !error.isEmpty { Text(error).font(.system(size: 12)).foregroundStyle(BanbeTheme.alert) }

        Button { confirming = true } label: {
            HStack {
                if busy { ProgressView().tint(.white) }
                Text(app.T("Huỷ sự kiện", "Cancel event")).font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 15)
            .background(BanbeTheme.alert, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .foregroundStyle(BanbeTheme.onAlert)
        }
        .disabled(busy || loading || loadFailed)
        .accessibilityIdentifier("cancelEvent.confirm")
    }

    // MARK: Phase 2 — send

    @ViewBuilder private var sendContent: some View {
        Text(app.T("Gửi thư cho khách", "Email your guests")).font(BanbeTheme.display(22))
        Text(app.T("Mỗi thư mở trong ứng dụng email của bạn, gửi riêng cho từng khách. Bạn tự bấm Gửi từ hộp thư của mình.",
                   "Each email opens in your own mail app, addressed to one guest. You press Send from your own mailbox."))
            .font(.system(size: 12.5)).opacity(0.75)

        if loading {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
        } else if loadFailed {
            loadError
        } else {
            templatePicker
            preview
            Text(holders.isEmpty
                 ? app.T("Không có người giữ vé nào để gửi thư.", "No ticket holders to email.")
                 : app.T("Đã mở thư cho \(draftedCount)/\(holders.count) khách", "\(draftedCount) of \(holders.count) guests drafted"))
                .font(.system(size: 11.5, weight: .semibold)).padding(.top, 4)

            VStack(spacing: 0) {
                ForEach(Array(holders.enumerated()), id: \.element.email) { i, h in
                    holderRow(h)
                    if i < holders.count - 1 { Divider().overlay(app.palette.rule) }
                }
            }
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if holders.count > 1 {
                Button(app.T("Hoặc soạn một thư chung cho tất cả (BCC)", "Or draft one email to everyone (BCC)")) {
                    let d = draft(for: nil, group: true)
                    mail = MailDraft(subject: d.subject, body: d.body, to: [], bcc: holders.map(\.email))
                }
                .font(.system(size: 12)).buttonStyle(.plain).underline()
                .accessibilityIdentifier("cancelEvent.draftGroup")
            }
        }
    }

    private func holderRow(_ h: AppState.TicketHolder) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(h.name.isEmpty ? app.T("Khách", "Guest") : h.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(h.email).font(.system(size: 11.5)).opacity(0.7).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                let d = draft(for: h.name)
                mail = MailDraft(subject: d.subject, body: d.body, to: [h.email], bcc: [])
            } label: {
                Text(drafted.contains(h.email) ? app.T("Đã mở ✓", "Drafted ✓") : app.T("Soạn thư", "Draft email"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .overlay(Capsule().stroke(app.palette.rule))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("cancelEvent.draftOne")
        }
        .padding(14)
    }

    // MARK: Shared pieces

    private var draftedCount: Int { holders.filter { drafted.contains($0.email) }.count }

    private var loadError: some View {
        Text(app.T("Không tải được danh sách người giữ vé. Hãy thử lại.", "Couldn't load the ticket holders. Please try again."))
            .font(.system(size: 12.5)).foregroundStyle(BanbeTheme.alert)
    }

    private var templatePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(app.T("Chọn mẫu thư xin lỗi", "Choose an apology template")).font(.system(size: 11.5, weight: .semibold)).padding(.top, 4)
            ForEach(EventCancellationTemplates.all) { template in
                Button { selected = template } label: {
                    HStack {
                        Image(systemName: selected == template ? "checkmark.circle.fill" : "circle")
                        Text(template.title(isEN: app.isEN)).font(.system(size: 14))
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(selected == template ? app.palette.ink : .clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("cancelEvent.template.\(template.key)")
            }
        }
    }

    private var preview: some View {
        let sample = draft(for: holders.first?.name)
        return VStack(alignment: .leading, spacing: 8) {
            Text(holders.first.map { app.T("Xem trước · ví dụ cho \($0.name)", "Preview · as sent to \($0.name)") } ?? app.T("Xem trước", "Preview"))
                .font(.system(size: 11.5, weight: .semibold))
            VStack(alignment: .leading, spacing: 8) {
                Text(sample.subject).font(.system(size: 13, weight: .semibold))
                Divider().overlay(app.palette.rule)
                Text(sample.body).font(.system(size: 12.5)).lineSpacing(3)
            }
            .padding(14)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityIdentifier("cancelEvent.preview")
        }
    }

    // MARK: Actions

    private func load() async {
        loading = true
        defer { loading = false }
        if let list = await app.loadTicketHolders(eventKey: eventKey) { holders = list } else { loadFailed = true }
    }

    private func cancel() async {
        busy = true
        error = ""
        defer { busy = false }
        let outcome = await app.hostCancelEvent(eventKey: eventKey, reason: draft(for: nil).reason)
        if let outcome { error = outcome; return }
        phase = .send
    }

    private func markDrafted(_ email: String) {
        drafted.insert(email)
        UserDefaults.standard.set(Array(drafted), forKey: draftedKey)
    }

    private func finish() {
        onFinished()
        dismiss()
    }
}

/// System mail composer, with a mailto: fallback for a device that has no Mail
/// account set up (then the draft opens in whatever mail app handles mailto).
/// `onFinish(true)` means a draft was sent or saved (or handed to another mail app).
struct MailComposer: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let subject: String
    let body: String
    let to: [String]
    let bcc: [String]
    let onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        guard MFMailComposeViewController.canSendMail() else {
            return FallbackMailtoController(subject: subject, body: body, to: to, bcc: bcc) { opened in
                onFinish(opened); dismiss()
            }
        }
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        vc.setToRecipients(to)
        vc.setBccRecipients(bcc)
        return vc
    }

    func updateUIViewController(_ vc: UIViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(finish: { opened in onFinish(opened); dismiss() }) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let finish: (Bool) -> Void
        init(finish: @escaping (Bool) -> Void) { self.finish = finish }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            // Cancelled-and-deleted means nothing was drafted; sent/saved/failed all did something.
            finish(result != .cancelled)
        }
    }
}

private final class FallbackMailtoController: UIViewController {
    private let subject: String, body: String, to: [String], bcc: [String], done: (Bool) -> Void
    init(subject: String, body: String, to: [String], bcc: [String], done: @escaping (Bool) -> Void) {
        self.subject = subject; self.body = body; self.to = to; self.bcc = bcc; self.done = done
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = to.joined(separator: ",")
        var items = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: body)]
        if !bcc.isEmpty { items.insert(URLQueryItem(name: "bcc", value: bcc.joined(separator: ",")), at: 0) }
        c.queryItems = items
        if let url = c.url {
            UIApplication.shared.open(url) { [done] ok in done(ok) }
        } else {
            done(false)
        }
    }
}
