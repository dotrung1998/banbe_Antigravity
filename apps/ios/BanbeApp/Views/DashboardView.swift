import SwiftUI

/// Port of src/screens/Dashboard.jsx — the organizer's own page: verify
/// badge, upcoming events each with a check-in button, past events, and
/// "create new event" pinned at the bottom.
struct DashboardView: View {
    @EnvironmentObject var app: AppState

    /// Branded from one of this account's real events when it owns any
    /// (myOrgEventKeys), falling back to the open event otherwise.
    private var event: CatalogEvent {
        if let key = app.myOrgEventKeys.first, let owned = EventCatalog.find(key) { return owned }
        return app.currentEvent
    }

    private var myEvents: [CatalogEvent] {
        app.myOrgEventKeys.isEmpty
            ? EventCatalog.all.filter { $0.orgName == event.orgName }
            : EventCatalog.all.filter { app.myOrgEventKeys.contains($0.key) }
    }
    private var upcoming: [CatalogEvent] {
        myEvents.filter { $0.isOpen }.sorted { ($0.until ?? 999) < ($1.until ?? 999) }
    }
    private var past: [CatalogEvent] {
        myEvents.filter { !$0.cancelled && $0.endedHoursAgo != nil }
            .sorted { ($0.endedHoursAgo ?? 0) < ($1.endedHoursAgo ?? 0) }
    }

    private var verifyLabel: String {
        if event.orgTrusted { return app.T("Đã xác minh", "Verified") }
        return app.orgVerifyRequested ? app.T("Đang xác minh", "Verifying")
                                      : app.T("Chưa xác minh", "Not verified")
    }

    var body: some View {
        ZStack {
            app.palette.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Button { app.backFromDashboard() } label: {
                                HStack(spacing: 6) {
                                    Text("‹").font(.system(size: 14))
                                    BanbeLogo(kind: .mark, height: 34)
                                }
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            Button(app.T("Xem như khách", "View as goer")) { app.switchToGoer() }
                                .font(.system(size: 11.5))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .overlay(Capsule().stroke(app.palette.rule, lineWidth: 1))
                                .buttonStyle(.plain)
                        }

                        HStack(spacing: 14) {
                            CatalogPhoto(path: event.img, height: 56, width: 56, cornerRadius: 28)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(event.orgName).font(BanbeTheme.display(24))
                                Text(verifyLabel)
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 11).padding(.vertical, 5)
                                    .overlay(Capsule().stroke(
                                        event.orgTrusted || app.orgVerifyRequested ? app.palette.ink : app.palette.rule,
                                        lineWidth: 1))
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.top, 16)

                        Text(app.T(
                            "Tổ chức từ \(event.orgSince) ▪︎ \(event.orgCount) sự kiện",
                            "Hosting since \(event.orgSince) ▪︎ \(event.orgCount) events"
                        ))
                        .font(.system(size: 12.5))
                        .padding(.top, 14)

                        if !event.orgTrusted && !app.orgVerifyRequested {
                            HStack(spacing: 12) {
                                Text(app.T("Xác minh hồ sơ để khách tin tưởng hơn.",
                                           "Get verified so guests trust you faster."))
                                    .font(.system(size: 12.5))
                                    .lineSpacing(3)
                                Spacer(minLength: 0)
                                Button(app.T("Yêu cầu xác minh", "Request")) { app.requestVerify() }
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(app.palette.paper)
                                    .padding(.horizontal, 16).padding(.vertical, 9)
                                    .background(app.palette.ink, in: Capsule())
                                    .buttonStyle(.plain)
                            }
                            .padding(16)
                            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.top, 16)
                        }

                        HStack(alignment: .firstTextBaseline) {
                            Text(app.T("Sự kiện sắp tới", "Upcoming events"))
                                .font(.system(size: 11.5, weight: .semibold))
                            Spacer()
                            Text("\(upcoming.count)" + app.T(" sự kiện", upcoming.count == 1 ? " event" : " events"))
                                .font(.system(size: 10.5))
                        }
                        .padding(.top, 24)

                        VStack(spacing: 0) {
                            if upcoming.isEmpty {
                                Text(app.T("Bạn chưa có sự kiện nào sắp tới. Tạo bên dưới.",
                                           "No upcoming events yet. Create one below."))
                                    .font(.system(size: 12.5))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(16)
                            }
                            ForEach(upcoming) { item in
                                HStack(spacing: 12) {
                                    Button { app.goEvent(item.key) } label: {
                                        HStack(spacing: 12) {
                                            CatalogPhoto(path: item.img, height: 52, width: 52)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(item.name).font(BanbeTheme.display(15)).lineLimit(1)
                                                Text(app.trStatus(app.stripKm(item.meta, event: item)))
                                                    .font(.system(size: 11.5)).lineLimit(1)
                                            }
                                            Spacer(minLength: 0)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    Button(app.T("Điểm danh", "Check-in")) { app.openAttendance(item.key) }
                                        .font(.system(size: 11, weight: .semibold))
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(app.palette.rule, lineWidth: 1))
                                        .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 13)
                                if item.key != upcoming.last?.key { Divider().overlay(app.palette.rule) }
                            }
                        }
                        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.top, 10)

                        Text(app.T("Sự kiện đã qua", "Past events"))
                            .font(.system(size: 11.5, weight: .semibold))
                            .padding(.top, 22)

                        VStack(spacing: 0) {
                            if past.isEmpty {
                                Text(app.T("Chưa có sự kiện nào đã qua.", "No past events yet."))
                                    .font(.system(size: 12.5))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(16)
                            }
                            ForEach(past) { item in
                                Button { app.goEvent(item.key) } label: {
                                    HStack(spacing: 12) {
                                        CatalogPhoto(path: item.img, height: 52, width: 52)
                                            .saturation(0.5)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.name).font(BanbeTheme.display(15)).lineLimit(1)
                                            Text(app.trStatus(app.stripKm(item.meta, event: item))
                                                 + " ▪︎ " + app.trStatus(EventLabels.ago(item.endedHoursAgo ?? 0)))
                                                .font(.system(size: 11.5)).lineLimit(1)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 13)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if item.key != past.last?.key { Divider().overlay(app.palette.rule) }
                            }
                        }
                        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.top, 10)
                    }
                    .foregroundStyle(app.palette.ink)
                    .padding(.horizontal, 22)
                    .padding(.top, 16)
                    .padding(.bottom, 30)
                }

                InkButton(title: app.T("+ Tạo sự kiện mới", "+ Create new event"), cornerRadius: 0) {
                    app.goCreate()
                }
            }
        }
        .task { await app.loadMyEvents() }
    }
}

/// Port of src/screens/HostIntro.jsx — what an organizer's page will look
/// like before they've posted anything.
struct HostIntroView: View {
    @EnvironmentObject var app: AppState

    private var points: [(String, String)] {
        [
            (app.T("Nhận thanh toán", "Take payments"), app.T("MoMo ▪︎ VNPay ▪︎ chuyển khoản", "MoMo ▪︎ VNPay ▪︎ bank transfer")),
            (app.T("Danh sách khách", "Guest list"), app.T("Điểm danh ngay tại cửa", "Check in at the door")),
            (app.T("Tin nhắn", "Messages"), app.T("Khách nhắn trực tiếp cho bạn", "Guests message you directly")),
            (app.T("Chi phí", "Cost"), app.T("Không phí đăng, không phí giao dịch", "No listing fee, no transaction fee")),
        ]
    }

    var body: some View {
        ZStack {
            app.palette.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        BackLink(label: app.T("Tài khoản", "Account")) { app.goProfile() }

                        Text(app.T("Dành cho người tổ chức", "For organizers"))
                            .font(.system(size: 11.5))
                            .padding(.top, 16)
                        Text(app.T("Trang tổ chức của bạn, trước khi bạn đăng gì",
                                   "Your organizer page, before you post anything"))
                            .font(BanbeTheme.display(27))
                            .padding(.top, 8)
                        Text(app.T(
                            "Đây là trang khách sẽ thấy khi họ bấm vào tên bạn. Sự kiện, ảnh và số liệu sẽ tự điền vào sau mỗi lần bạn tổ chức.",
                            "This is what guests see when they tap your name. Events, photos and numbers fill in as you host."
                        ))
                        .font(.system(size: 13.5))
                        .lineSpacing(3)
                        .padding(.top, 10)

                        VStack(alignment: .leading, spacing: 0) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(app.T("Khách sẽ thấy", "Guests will see")).font(.system(size: 10.5))
                                Spacer()
                                Text("banbe").font(.system(size: 10.5))
                            }
                            HStack(alignment: .firstTextBaseline, spacing: 9) {
                                Text(app.orgRegName.isEmpty ? "Bếp Nhỏ" : app.orgRegName)
                                    .font(BanbeTheme.display(24))
                                Text(app.T("Mới", "New"))
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 10).padding(.vertical, 3)
                                    .background(app.palette.ink.opacity(0.1), in: Capsule())
                            }
                            .padding(.top, 12)
                            Text(app.orgRegIg.isEmpty ? "@bepnho.saigon" : app.orgRegIg)
                                .font(.system(size: 12.5))
                                .padding(.top, 5)
                            Text(app.orgRegDesc.isEmpty
                                 ? app.T("Mình nấu cho người lạ từ 2021…", "I cook for strangers since 2021…")
                                 : app.orgRegDesc)
                                .font(.system(size: 13))
                                .lineSpacing(3)
                                .padding(.top, 12)
                            HStack(spacing: 14) {
                                BanbeLogo(kind: .mark, width: 38, height: 38)
                                    .opacity(0.75)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(app.T("Chưa có sự kiện nào", "No events yet"))
                                        .font(.system(size: 13.5, weight: .semibold))
                                    Text(app.T("Sự kiện đầu tiên của bạn sẽ nằm ở đây.", "Your first event will sit here."))
                                        .font(.system(size: 11.5))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(.top, 18)
                        }
                        .padding(18)
                        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.top, 22)

                        VStack(spacing: 0) {
                            ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                                HStack(alignment: .firstTextBaseline, spacing: 16) {
                                    Text(point.0).font(.system(size: 13.5, weight: .semibold))
                                    Spacer(minLength: 0)
                                    Text(point.1).font(.system(size: 12.5)).multilineTextAlignment(.trailing)
                                }
                                .padding(.vertical, 13)
                                if index < points.count - 1 { Divider().overlay(app.palette.rule) }
                            }
                        }
                        .padding(.top, 26)

                        Text(app.T("banbe duyệt sự kiện đầu tiên trong 48 giờ. Sau đó bạn đăng trực tiếp.",
                                   "banbe reviews your first event within 48 hours. After that you post directly."))
                            .font(.system(size: 11.5))
                            .lineSpacing(3)
                            .padding(.top, 16)
                    }
                    .foregroundStyle(app.palette.ink)
                    .padding(.horizontal, 22)
                    .padding(.top, 16)
                    .padding(.bottom, 30)
                }

                InkButton(title: app.T("Tạo sự kiện đầu tiên", "Create your first event"), cornerRadius: 999) {
                    app.goCreate()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
    }
}
