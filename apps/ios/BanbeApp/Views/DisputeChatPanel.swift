import SwiftUI

/// The temporary chat for an escalated dispute — shared between the guest's
/// side (PaymentDetailsView, while paymentState == .disputed) and the
/// organizer's side (VerificationsView, in the "awaiting banbe's decision"
/// list). Deliberately its own small table (dispute_messages), not the
/// ordinary booking thread — purged once resolve_dispute() closes it out.
struct DisputeChatPanel: View {
    @EnvironmentObject private var app: AppState
    let bookingID: UUID
    @State private var pollTask: Task<Void, Never>?

    private var messages: [DisputeMessage] {
        app.disputeChatBookingId == bookingID ? app.disputeChatMessages : []
    }

    // No realtime subscription exists anywhere in this app (no Supabase
    // Realtime channel usage, and dispute_messages was never added to the
    // supabase_realtime publication) — without this poll, the party who
    // didn't just send a message never sees a new one until they leave and
    // reopen this view. 4s, matching the web counterpart.
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if Task.isCancelled { return }
                await app.loadDisputeChat(bookingID)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(app.T("Trao đổi trực tiếp về tranh chấp này", "Direct chat about this dispute"))
                .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(app.palette.ink)
            Text(app.T("Cuộc trò chuyện này là tạm thời — sẽ bị xoá sau khi banbe đưa ra quyết định, và bản ghi được gửi qua email cho cả hai bên.",
                       "This conversation is temporary — it is deleted once banbe rules on the dispute, and a copy is emailed to both of you."))
                .font(.system(size: 11)).foregroundStyle(app.palette.ink.opacity(0.7))

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if app.disputeChatLoading && messages.isEmpty {
                        Text(app.T("Đang tải…", "Loading…"))
                            .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.6))
                    } else if messages.isEmpty && app.disputeChatError.isEmpty {
                        Text(app.T("Chưa có tin nhắn nào.", "No messages yet."))
                            .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.6))
                            .accessibilityIdentifier("disputeChat.empty")
                    }
                    ForEach(messages) { m in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(senderLabel(m.senderRole) + " ▪︎ " + m.createdAt.formatted())
                                .font(.system(size: 10)).foregroundStyle(app.palette.ink.opacity(0.55))
                            Text(m.body).font(.system(size: 13)).foregroundStyle(app.palette.ink)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityIdentifier("disputeChat.message")
                    }
                }
            }
            .frame(maxHeight: 220)

            HStack(spacing: 8) {
                TextField(app.T("Nhắn gì đó…", "Say something…"), text: $app.disputeChatDraft)
                    .font(.system(size: 13)).padding(10)
                    .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityIdentifier("disputeChat.input")
                    .onSubmit { Task { await app.sendDisputeMessage(bookingID) } }
                Button {
                    Task { await app.sendDisputeMessage(bookingID) }
                } label: {
                    Text(app.T("Gửi", "Send"))
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(app.disputeChatDraft.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? app.palette.ink.opacity(0.35) : app.palette.ink,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .foregroundStyle(app.palette.paper)
                }
                .buttonStyle(.plain)
                .disabled(app.disputeChatDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("disputeChat.send")
            }

            if !app.disputeChatError.isEmpty {
                Text(app.disputeChatError)
                    .font(.system(size: 11.5)).foregroundStyle(BanbeTheme.alert)
                    .accessibilityIdentifier("disputeChat.error")
            }
        }
        .padding(14)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task { await app.loadDisputeChat(bookingID) }
        .onAppear { startPolling() }
        .onDisappear { pollTask?.cancel() }
        .accessibilityIdentifier("disputeChat.panel")
    }

    private func senderLabel(_ role: String) -> String {
        switch role {
        case "organizer": return app.T("Người tổ chức", "Organizer")
        case "guest": return app.T("Khách", "Guest")
        case "admin": return "banbe"
        default: return app.T("Hệ thống", "System")
        }
    }
}
