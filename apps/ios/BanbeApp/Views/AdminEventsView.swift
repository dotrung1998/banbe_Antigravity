import SwiftUI

/// Event submission -> admin review -> publish — the iOS counterpart of
/// src/screens/AdminEvents.jsx. A SEPARATE desk from AdminDashboardView
/// (payment disputes) — reviewing a new event submission is not the same
/// job as ruling on a payment dispute, even though both are gated the same
/// way server-side (is_platform_admin(), migrations 026/085).
///
/// Reachable only via AccountView's admin-gated "Sự kiện chờ duyệt" row
/// (app.isAdmin), and openAdminEvents() itself guards again before
/// switching screens — RLS (events_select_admin) and admin_review_event's
/// own SECURITY DEFINER check are the real backstop either way.
struct AdminEventsView: View {
    @EnvironmentObject private var app: AppState
    @State private var reasonByEvent: [String: String] = [:]

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.T("Tài khoản", "Account")) { app.screen = .profile }
                    .padding(.top, 8)
                    .accessibilityIdentifier("adminEvents.back")

                Text(app.T("Sự kiện chờ duyệt", "Pending events"))
                    .font(BanbeTheme.display(24)).padding(.top, 14)
                    .accessibilityIdentifier("adminEvents.title")
                Text(app.T("Sự kiện chỉ hiển thị công khai sau khi được duyệt ở đây.", "An event only shows publicly once approved here."))
                    .font(.system(size: 12.5)).foregroundStyle(app.palette.ink.opacity(0.75))
                    .padding(.top, 8)

                if !app.adminEventError.isEmpty {
                    Text(app.adminEventError)
                        .font(.system(size: 11.5)).foregroundStyle(BanbeTheme.alert)
                        .padding(.top, 10)
                        .accessibilityIdentifier("adminEvents.error")
                }

                VStack(spacing: 12) {
                    ForEach(app.adminEvents, id: \.id) { row in eventCard(row) }

                    if app.adminEvents.isEmpty {
                        Text(app.adminEventsLoading
                             ? app.T("Đang tải…", "Loading…")
                             : app.T("Không có sự kiện nào đang chờ duyệt.", "No pending events."))
                            .font(.system(size: 12.5)).foregroundStyle(app.palette.ink.opacity(0.75))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("adminEvents.empty")
                    }
                }
                .padding(.top, 18)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .task { await app.loadPendingEvents() }
    }

    private func eventCard(_ row: RealEventSummary) -> some View {
        let busy = app.adminEventBusy == row.id
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.name).font(BanbeTheme.display(16))
                        .accessibilityIdentifier("adminEvents.name.\(row.id)")
                    Text(row.organizerName.isEmpty ? app.T("Không rõ người tổ chức", "Unknown host") : row.organizerName)
                        .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.7))
                }
                Spacer()
                Text((row.priceVnd ?? 0) > 0 ? EventLabels.vnd(row.priceVnd!) : app.T("Miễn phí", "Free"))
                    .font(BanbeTheme.display(19))
            }

            if let url = row.photoURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.1)
                }
                .frame(height: 180)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(app.palette.field)
                    .frame(height: 100)
                    .overlay(Text(app.T("Chưa có ảnh", "No photo yet")).font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.55)))
            }

            VStack(alignment: .leading, spacing: 4) {
                line(app.T("Ngày", "Date"), row.eventDate.map { "\($0)\(row.eventTime.map { " ▪︎ \(String($0.prefix(5)))" } ?? "")" } ?? app.T("Chưa đặt", "Not set"))
                line(app.T("Địa điểm", "Location"), row.area?.isEmpty == false ? row.area! : "—")
                line(app.T("Sức chứa", "Capacity"), row.capacity.map(String.init) ?? "—")
                line(app.T("Mô tả", "Description"), row.description?.isEmpty == false ? row.description! : "—")
            }
            .padding(10)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            TextField(app.T("Lý do từ chối (bắt buộc nếu từ chối)", "Rejection reason (required if rejecting)"),
                      text: Binding(get: { reasonByEvent[row.id] ?? "" }, set: { reasonByEvent[row.id] = $0 }))
                .font(.system(size: 13))
                .padding(11)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityIdentifier("adminEvents.reason.\(row.id)")

            HStack(spacing: 8) {
                Button {
                    Task { await app.reviewEvent(row.id, approve: true, reason: "") }
                } label: {
                    Text(busy ? app.T("Đang lưu…", "Saving…") : app.T("Duyệt ▪︎ đăng công khai", "Approve ▪︎ publish"))
                        .font(.system(size: 12.5, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .foregroundStyle(app.palette.paper)
                        .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("adminEvents.approve.\(row.id)")

                Button {
                    let reason = reasonByEvent[row.id] ?? ""
                    guard !reason.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    Task { await app.reviewEvent(row.id, approve: false, reason: reason) }
                } label: {
                    Text(app.T("Từ chối", "Reject"))
                        .font(.system(size: 12.5, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .foregroundStyle(app.palette.ink)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(app.palette.rule, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("adminEvents.reject.\(row.id)")
            }
        }
        .padding(16)
        .background(app.palette.field.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .foregroundStyle(app.palette.ink)
        .accessibilityIdentifier("adminEvents.row.\(row.id)")
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundStyle(app.palette.ink.opacity(0.65))
            Spacer()
            Text(value).font(.system(size: 12, weight: .semibold)).multilineTextAlignment(.trailing)
        }
    }
}
