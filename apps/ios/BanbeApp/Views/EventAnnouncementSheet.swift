import SwiftUI

/// Host "announce to guests" sheet (migration 166). Mirrors src/components/AnnouncementSheet.jsx.
/// Top to bottom: message box (what will be sent) → one-tap quick picks → search + category
/// chips → template list → sticky Send with a two-step confirm.
struct EventAnnouncementSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let eventKey: String
    let eventName: String

    @State private var text = ""
    @State private var templateID: String?
    @State private var category = "all"
    @State private var query = ""
    @State private var confirming = false
    @State private var busy = false
    @State private var error = ""
    @State private var sent: Int?

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var tooLong: Bool { trimmed.count > EventAnnouncements.maxLength }
    private var canSend: Bool { !trimmed.isEmpty && !tooLong && !busy }
    private var list: [AnnouncementTemplate] { EventAnnouncements.filter(query: query, category: category) }
    private func body(of t: AnnouncementTemplate) -> String { app.isEN ? t.en : t.vi }

    private func pick(_ t: AnnouncementTemplate) {
        text = body(of: t); templateID = t.id; confirming = false; error = ""
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("📣 " + app.T("Thông báo cho khách", "Announce to guests")).font(BanbeTheme.display(21))
                    Text(eventName).font(.system(size: 11.5)).opacity(0.65).lineLimit(1)
                }
                Spacer()
                Button(sent != nil ? app.T("Xong", "Done") : app.T("Đóng", "Close")) { dismiss() }
                    .font(.system(size: 12.5)).buttonStyle(.plain)
                    .accessibilityIdentifier("announcement.close")
            }
            .padding(.horizontal, 22).padding(.top, 20)

            if let sent {
                VStack(spacing: 8) {
                    Text("✓").font(.system(size: 34)).foregroundStyle(BanbeTheme.alert)
                    Text(sent == 0 ? app.T("Chưa có khách nào khác để gửi", "No other ticket holders to notify") : app.T("Đã gửi cho \(sent) khách", "Sent to \(sent) guest\(sent == 1 ? "" : "s")")).font(.system(size: 15, weight: .semibold))
                    Text(sent == 0 ? app.T("Thông báo chỉ gửi cho người giữ vé khác bạn (bạn không tự nhận thông báo của mình).", "Announcements go to ticket holders other than you; you don't receive your own.") : app.T("Khách nhận thông báo và tin nhắn nổi bật màu đỏ trong chat.", "Guests get a notification and a red-highlighted chat message."))
                        .font(.system(size: 12.5)).opacity(0.7).multilineTextAlignment(.center)
                }
                .padding(.vertical, 40).padding(.horizontal, 22)
                .accessibilityIdentifier("announcement.sent")
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        TextField(app.T("Chọn mẫu bên dưới hoặc tự viết tin nhắn…", "Pick a template below or write your own…"), text: $text, axis: .vertical)
                            .lineLimit(3...6)
                            .font(.system(size: 14))
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(BanbeTheme.alert, lineWidth: 1))
                            .onChange(of: text) { _, _ in confirming = false }
                            .accessibilityIdentifier("announcement.text")
                        HStack {
                            Text(templateID != nil ? app.T("Từ mẫu — bạn có thể sửa", "From a template — you can edit it") : app.T("Tin nhắn tuỳ chỉnh", "Custom message"))
                            Spacer()
                            Text("\(trimmed.count)/\(EventAnnouncements.maxLength)").foregroundStyle(tooLong ? BanbeTheme.alert : app.palette.ink)
                        }
                        .font(.system(size: 11)).opacity(0.65).padding(.top, 4).padding(.horizontal, 2)

                        Text(app.T("Gửi nhanh", "Quick send")).font(.system(size: 11.5, weight: .semibold)).padding(.top, 14).padding(.bottom, 8)
                        FlowChips {
                            ForEach(EventAnnouncements.quickIDs, id: \.self) { id in
                                if let t = EventAnnouncements.templates.first(where: { $0.id == id }) {
                                    chip(quickLabel(t), active: templateID == t.id) { pick(t) }
                                        .accessibilityIdentifier("announcement.quick.\(t.id)")
                                }
                            }
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").opacity(0.55)
                            TextField(app.T("Tìm mẫu thông báo…", "Search templates…"), text: $query)
                                .font(.system(size: 14)).autocorrectionDisabled()
                                .accessibilityIdentifier("announcement.search")
                            if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark").opacity(0.55) }.buttonStyle(.plain) }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.top, 16)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                chip(app.T("Tất cả", "All"), active: category == "all") { category = "all" }
                                ForEach(EventAnnouncements.categories) { c in
                                    chip(app.isEN ? c.en : c.vi, active: category == c.id) { category = c.id }
                                        .accessibilityIdentifier("announcement.cat.\(c.id)")
                                }
                            }
                            .padding(.vertical, 10)
                        }

                        VStack(spacing: 8) {
                            if list.isEmpty {
                                Text(app.T("Không có mẫu phù hợp. Bạn có thể tự viết ở khung trên.", "No matching template. Write your own in the box above."))
                                    .font(.system(size: 12.5)).opacity(0.7).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                            }
                            ForEach(list) { t in
                                Button { pick(t) } label: {
                                    Text(body(of: t)).font(.system(size: 13.5)).multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 14).padding(.vertical, 12)
                                        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(templateID == t.id ? BanbeTheme.alert : .clear, lineWidth: 1.5))
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("announcement.template.\(t.id)")
                            }
                        }
                    }
                    .padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 8)
                }
                .scrollDismissesKeyboard(.interactively)

                VStack(spacing: 8) {
                    Divider().overlay(app.palette.rule)
                    if !error.isEmpty {
                        Text(error).font(.system(size: 12)).foregroundStyle(BanbeTheme.alert).frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("announcement.error")
                    }
                    if confirming {
                        HStack(spacing: 12) {
                            Text(app.T("Gửi cho tất cả người giữ vé?", "Send to all ticket holders?")).font(.system(size: 12.5, weight: .semibold))
                            Spacer()
                            Button(app.T("Huỷ", "Cancel")) { if !busy { confirming = false } }.font(.system(size: 13)).buttonStyle(.plain)
                            Button { Task { await send() } } label: {
                                Text(busy ? app.T("Đang gửi…", "Sending…") : app.T("Gửi ngay", "Send now"))
                                    .font(.system(size: 13.5, weight: .bold)).foregroundStyle(BanbeTheme.onAlert)
                                    .padding(.horizontal, 20).padding(.vertical, 11)
                                    .background(BanbeTheme.alert, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain).disabled(busy)
                            .accessibilityIdentifier("announcement.confirm")
                        }
                    } else {
                        Button { if canSend { confirming = true } } label: {
                            Text(app.T("Gửi thông báo", "Send announcement"))
                                .font(.system(size: 14.5, weight: .bold)).foregroundStyle(BanbeTheme.onAlert)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(BanbeTheme.alert, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain).opacity(canSend ? 1 : 0.4)
                        .accessibilityIdentifier("announcement.send")
                    }
                }
                .padding(.horizontal, 22).padding(.bottom, 14).padding(.top, 4)
            }
        }
        .foregroundStyle(app.palette.ink)
        .background(app.palette.paper.ignoresSafeArea())
    }

    /// Short chip label: first clause of the template, without trailing punctuation.
    private func quickLabel(_ t: AnnouncementTemplate) -> String {
        let s = body(of: t)
        let first = s.split(separator: ",", maxSplits: 1).first.map(String.init) ?? s
        return first.trimmingCharacters(in: CharacterSet(charactersIn: "!. "))
    }

    private func chip(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                .foregroundStyle(active ? BanbeTheme.onAlert : app.palette.ink)
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background(active ? BanbeTheme.alert : .clear, in: Capsule())
                .overlay(Capsule().stroke(active ? BanbeTheme.alert : app.palette.rule, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func send() async {
        busy = true; error = ""
        let tplCategory = templateID.flatMap { id in EventAnnouncements.templates.first { $0.id == id }?.category }
        let res = await app.sendEventAnnouncement(eventKey: eventKey, category: tplCategory ?? "custom", body: trimmed, templateID: templateID)
        busy = false
        if let n = res.sent { sent = n } else { error = res.error ?? ""; confirming = false }
    }
}

/// Minimal wrapping row for the three quick-pick chips.
private struct FlowChips<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { content }
            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) { content } }
        }
    }
}
