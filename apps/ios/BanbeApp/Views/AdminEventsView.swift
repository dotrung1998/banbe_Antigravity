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
///
/// TASK 3 (event creation validation pass) — each event is now a compact
/// identifying summary (name/organizer/status/submitted date/price) plus an
/// expandable detailed section, reusing the SAME fold pattern Reports
/// already established (ReportsView's own "Mở tất cả"/"Thu gọn tất cả" +
/// per-card toggle) — a local `Set` of expanded keys here instead, since
/// this screen's own expand state has nothing to do with Reports' own and
/// doesn't need to survive a navigation away. Keyed by the event's own
/// stable `id` (never row index), so approving/rejecting one row (which
/// re-fetches and re-orders the list) never silently expands/collapses a
/// DIFFERENT row that happened to land on the same index.
struct AdminEventsView: View {
    @EnvironmentObject private var app: AppState
    @State private var reasonByEvent: [String: String] = [:]
    @State private var expanded: Set<String> = []
    @State private var galleryByEvent: [String: [URL]] = [:]

    private func loadGallery(_ eventID: String) {
        guard galleryByEvent[eventID] == nil else { return }
        Task {
            let urls = await app.loadEventGalleryURLs(eventID: eventID)
            galleryByEvent[eventID] = urls
        }
    }

    private func toggleExpanded(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id); loadGallery(id) }
    }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.T("Tài khoản", "Account")) { app.screen = .profile }
                    .padding(.top, 8)
                    .accessibilityIdentifier("adminEvents.back")

                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(app.T("Sự kiện chờ duyệt", "Pending events"))
                            .font(BanbeTheme.display(24))
                            .accessibilityIdentifier("adminEvents.title")
                        Text(app.T("Sự kiện chỉ hiển thị công khai sau khi được duyệt ở đây.", "An event only shows publicly once approved here."))
                            .font(.system(size: 12.5)).foregroundStyle(app.palette.ink.opacity(0.75))
                    }
                    Spacer()
                    if !app.adminEvents.isEmpty {
                        VStack(alignment: .trailing, spacing: 6) {
                            Button(app.T("Mở tất cả", "Expand all")) {
                                expanded = Set(app.adminEvents.map(\.id))
                                app.adminEvents.forEach { loadGallery($0.id) }
                            }
                            Button(app.T("Thu gọn tất cả", "Collapse all")) { expanded.removeAll() }
                        }
                        .font(.system(size: 11.5, weight: .semibold))
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 14)

                if !app.adminEventError.isEmpty {
                    Text(app.adminEventError)
                        .font(.system(size: 11.5)).foregroundStyle(BanbeTheme.alert)
                        .padding(.top, 10)
                        .accessibilityIdentifier("adminEvents.error")
                }

                VStack(spacing: 12) {
                    ForEach(app.adminEvents, id: \.id) { row in
                        eventCard(row, isOpen: expanded.contains(row.id), gallery: galleryByEvent[row.id] ?? [])
                    }

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

    @ViewBuilder
    private func eventCard(_ row: RealEventSummary, isOpen: Bool, gallery: [URL]) -> some View {
        let busy = app.adminEventBusy == row.id
        VStack(alignment: .leading, spacing: 10) {
            // Compact identifying summary — always visible.
            Button { toggleExpanded(row.id) } label: {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.name).font(BanbeTheme.display(16))
                            .accessibilityIdentifier("adminEvents.name.\(row.id)")
                        Text(row.organizerName.isEmpty ? app.T("Không rõ người tổ chức", "Unknown host") : row.organizerName)
                            .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.7))
                        Text("\(app.T("Mã", "ID")) \(row.id) ▪︎ \(app.T("Gửi lúc", "Submitted")) \(row.submittedAt.map { $0.formatted() } ?? app.T("Không rõ", "Unknown"))")
                            .font(.system(size: 10.5)).foregroundStyle(app.palette.ink.opacity(0.55))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text((row.priceVnd ?? 0) > 0 ? EventLabels.vnd(row.priceVnd!) : app.T("Miễn phí", "Free"))
                            .font(BanbeTheme.display(19))
                        Text(isOpen ? app.T("Thu gọn", "Collapse") : app.T("Mở rộng", "Expand"))
                            .font(.system(size: 11, weight: .semibold)).underline()
                    }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(app.palette.ink)
            .accessibilityIdentifier("adminEvents.toggle.\(row.id)")

            if isOpen {
                if !gallery.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(gallery, id: \.self) { url in
                                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.1) }
                                    .frame(width: 120, height: 90)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(app.palette.field)
                        .frame(height: 100)
                        .overlay(Text(app.T("Chưa có ảnh", "No photo yet")).font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.55)))
                }

                VStack(alignment: .leading, spacing: 4) {
                    line(app.T("Trạng thái", "Status"), row.status)
                    line(app.T("Danh mục", "Category"), row.catLabel?.isEmpty == false ? row.catLabel! : (row.catKey ?? "—"))
                    line(app.T("Từ khoá", "Keywords"), row.keywords?.isEmpty == false ? row.keywords!.joined(separator: ", ") : "—")
                    line(app.T("Ngày", "Date"), row.eventDate.map { "\($0)\(row.eventTime.map { " ▪︎ \(String($0.prefix(5)))" } ?? "")" } ?? app.T("Chưa đặt", "Not set"))
                    line(app.T("Sức chứa", "Capacity"), row.capacity.map(String.init) ?? "—")
                    line(app.T("Hiển thị", "Visibility"), row.visibility)
                    line(app.T("Chế độ duyệt vé", "Booking approval"), row.approval?.isEmpty == false ? row.approval! : "—")
                    line(app.T("Mô tả", "Description"), row.description?.isEmpty == false ? row.description! : "—")
                    line(app.T("Bao gồm", "Included"), row.includedItems?.isEmpty == false ? row.includedItems!.map(\.label).joined(separator: " ▪︎ ") : "—")
                }
                .padding(10)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    line(app.T("Địa chỉ", "Address"), [row.addressLine, row.area, row.city].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: ", ").isEmpty ? "—" : [row.addressLine, row.area, row.city].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: ", "))
                    line(app.T("Đã xác minh (chủ nhà tự khai)", "Address confirmed (host-provided)"), (row.addressVerified ?? false) ? app.T("Có", "Yes") : app.T("Không", "No"))
                    if let lat = row.lat, let lng = row.lng, let url = URL(string: "https://www.google.com/maps/search/?api=1&query=\(lat),\(lng)") {
                        Link(app.T("Mở trên Google Maps", "Open in Google Maps") + " (\(String(format: "%.5f", lat)), \(String(format: "%.5f", lng)))", destination: url)
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                }
                .padding(10)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityIdentifier("adminEvents.address.\(row.id)")

                if let intro = row.intro, !intro.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.T("Giới thiệu sự kiện", "Event introduction")).font(.system(size: 10.5)).foregroundStyle(app.palette.ink.opacity(0.65))
                        Text(intro).font(.system(size: 12.5)).lineSpacing(3)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                // Host/organizer identity — self-declared fields only.
                // `organizerVerified` has NO real write path anywhere in
                // this schema (migration 109's own comment) — labelled
                // "Not verified" always, never implied otherwise. Never
                // shows bank/payout details here.
                VStack(alignment: .leading, spacing: 4) {
                    line(app.T("Loại người tổ chức (tự khai)", "Organizer type (self-declared)"), row.organizerType == "business" ? app.T("Doanh nghiệp", "Business") : app.T("Cá nhân", "Individual"))
                    line(app.T("Đăng ký kinh doanh", "Business registration"), row.organizerHasTaxCode ? app.T("Đã cung cấp mã số thuế (chưa xác minh)", "Tax code provided (not verified)") : app.T("Chưa cung cấp", "Not provided"))
                    line(app.T("Xác minh nền tảng", "Platform verification"), app.T("Chưa xác minh", "Not verified"))
                }
                .padding(10)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityIdentifier("adminEvents.organizer.\(row.id)")

                if (row.rejectionReason?.isEmpty == false) || (row.withdrawalReason?.isEmpty == false) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let reason = row.rejectionReason, !reason.isEmpty {
                            line(app.T("Lý do từ chối trước đó", "Previous rejection reason"), reason)
                        }
                        if let reason = row.withdrawalReason, !reason.isEmpty {
                            line(app.T("Lý do rút lại trước đó", "Previous withdrawal reason"), reason)
                        }
                    }
                    .padding(10)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityIdentifier("adminEvents.history.\(row.id)")
                }

                TextField(app.T("Lý do từ chối (bắt buộc nếu từ chối)", "Rejection reason (required if rejecting)"),
                          text: Binding(get: { reasonByEvent[row.id] ?? "" }, set: { reasonByEvent[row.id] = $0 }))
                    .font(.system(size: 13))
                    .padding(11)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityIdentifier("adminEvents.reason.\(row.id)")

                HStack(spacing: 8) {
                    Button {
                        guard !busy else { return }
                        Task { await app.reviewEvent(row.id, approve: true, reason: "") }
                    } label: {
                        Text(busy ? app.T("Đang lưu…", "Saving…") : app.T("Duyệt ▪︎ đăng công khai", "Approve ▪︎ publish"))
                            .font(.system(size: 12.5, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .foregroundStyle(app.palette.paper)
                            .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 12))
                            .opacity(busy ? 0.6 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                    .accessibilityIdentifier("adminEvents.approve.\(row.id)")

                    Button {
                        guard !busy else { return }
                        let reason = reasonByEvent[row.id] ?? ""
                        guard !reason.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        Task { await app.reviewEvent(row.id, approve: false, reason: reason) }
                    } label: {
                        Text(app.T("Từ chối", "Reject"))
                            .font(.system(size: 12.5, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .foregroundStyle(app.palette.ink)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(app.palette.rule, lineWidth: 1))
                            .opacity(busy ? 0.6 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                    .accessibilityIdentifier("adminEvents.reject.\(row.id)")
                }
            }
        }
        .padding(16)
        .background(app.palette.field.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .foregroundStyle(app.palette.ink)
        .accessibilityIdentifier("adminEvents.row.\(row.id)")
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.system(size: 11)).foregroundStyle(app.palette.ink.opacity(0.65))
            Spacer()
            Text(value).font(.system(size: 12, weight: .semibold)).multilineTextAlignment(.trailing)
        }
    }
}
