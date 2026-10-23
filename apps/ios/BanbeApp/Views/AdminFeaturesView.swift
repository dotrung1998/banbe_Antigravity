import SwiftUI

/// Admin > Feature switches (migration 187, note 51) — the iOS counterpart of src/screens/AdminFeatures.jsx. One row
/// per platform feature flag. Turning a switch off hides the feature everywhere (web + iOS, signed in and signed
/// out) without a release; turning it on shows it again. The server decides who may flip it (is_platform_admin()
/// inside admin_set_feature_flag, audited); this view only calls it, and the switch moves only after the server
/// accepted the change.
struct AdminFeaturesView: View {
    @EnvironmentObject private var app: AppState
    @State private var error = ""

    private struct Flag: Identifiable {
        let key: String, vi: String, en: String, hintVi: String, hintEn: String
        var onVi = "Đang hiện cho mọi người", onEn = "Visible to everyone"
        var offVi = "Đang ẩn với mọi người", offEn = "Hidden from everyone"
        var id: String { key }
    }
    private let flags = [
        Flag(key: "rewards", vi: "Phần thưởng & huy hiệu", en: "Rewards & badges",
             hintVi: "Ẩn xu, chuỗi ngày, huy hiệu và mẫu móc khoá thưởng khỏi toàn bộ ứng dụng. Dữ liệu không bị xoá.",
             hintEn: "Hides coins, streaks, badges and reward keychain designs everywhere in the app. No data is deleted."),
        Flag(key: "rewards_v2", vi: "Phần thưởng v2: chuỗi tuần, cấp huy hiệu, mục tiêu", en: "Rewards v2: week streak, badge tiers, goals",
             hintVi: "Chuỗi theo tuần với tuần nghỉ và khôi phục, huy hiệu nhiều cấp, huy hiệu tiếp theo và mục tiêu tháng (migration 192). Mặc định tắt. Cần bật Phần thưởng.",
             hintEn: "Weekly streak with grace weeks and repair, tiered badges, next badge and a monthly goal (migration 192). Off by default. Needs Rewards on.",
             onVi: "Đang hiện cho mọi người", onEn: "Visible to everyone", offVi: "Đang tắt", offEn: "Off"),
        Flag(key: "push_enabled", vi: "Thông báo đẩy (iPhone)", en: "Push notifications (iPhone)",
             hintVi: "Gửi thông báo đẩy qua Apple cho người đã cho phép, ngoài giờ yên lặng 22:00–07:00. Cần khoá APNs; khi chưa có khoá, hệ thống chỉ chạy thử và không gửi gì (migration 194). Mặc định tắt.",
             hintEn: "Sends push notifications through Apple to people who allowed them, outside quiet hours 22:00–07:00. Needs the APNs key; without it the server only does a dry run and sends nothing (migration 194). Off by default.",
             onVi: "Đang bật", onEn: "On", offVi: "Đang tắt", offEn: "Off"),
        Flag(key: "app_events", vi: "Đo lường sản phẩm (của banbe)", en: "Product measurement (first-party)",
             hintVi: "Ghi nhận ẩn danh hoá các thao tác chính (mở ứng dụng, mở sự kiện, mở vé…) vào cơ sở dữ liệu của banbe để đo tỉ lệ quay lại. Không dùng công cụ bên thứ ba, không ghi nội dung trò chuyện, ngân hàng hay câu trả lời. Mặc định tắt.",
             hintEn: "Records key actions (app opened, event opened, ticket opened…) in banbe's own database to measure how often people come back. No third-party tools; never chat, bank or answer content. Off by default.",
             onVi: "Đang bật", onEn: "On", offVi: "Đang tắt", offEn: "Off"),
        Flag(key: "event_reminders", vi: "Nhắc lịch sự kiện", en: "Event reminders",
             hintVi: "Nhắc người có vé một ngày trước và khoảng 3 giờ trước sự kiện, trong ứng dụng (và thông báo đẩy khi đã bật). Người dùng tắt được từng loại. Mặc định bật.",
             hintEn: "Reminds ticket holders the day before and about 3 hours before their event, in the app (and by push when push is on). People can mute each kind. On by default.",
             onVi: "Đang bật", onEn: "On", offVi: "Đang tắt", offEn: "Off"),
        Flag(key: "event_recap", vi: "Tổng kết cho khách + cảm nhận riêng", en: "Guest recap + private feedback",
             hintVi: "Sau khi sự kiện kết thúc, khách có vé nhận một thông báo tổng kết và có thể gửi cảm nhận riêng cho host (host chỉ thấy khi có từ 3 người trả lời). Thu thập dữ liệu mới: cần quyết định về đồng ý lại theo Điều B12 trước khi bật. Mặc định tắt.",
             hintEn: "After an event ends, ticket holders get a recap and can send private feedback to the host (shown to the host only from 3 answers). Collects new data: needs the B12 re-consent decision before turning on. Off by default.",
             onVi: "Đang bật", onEn: "On", offVi: "Đang tắt", offEn: "Off"),
        Flag(key: "host_recap", vi: "Tổng kết cho host", en: "Host recap",
             hintVi: "Host nhận tổng kết sau sự kiện: số chỗ, số người vào cửa, người theo dõi mới, khách quay lại, cảm nhận (từ 3 người), và nút Tổ chức lại. Mặc định tắt.",
             hintEn: "Hosts get a recap after the event: seats, check-ins, new followers, returning guests, feedback (from 3 answers) and Run it again. Off by default.",
             onVi: "Đang bật", onEn: "On", offVi: "Đang tắt", offEn: "Off"),
        Flag(key: "follow_alerts", vi: "Báo sự kiện mới từ host đang theo dõi", en: "Alerts from followed hosts",
             hintVi: "Tối đa một thông báo gộp mỗi ngày, 09:00–20:00 giờ của người dùng, khi host họ theo dõi đăng sự kiện mới. Người dùng tắt được. Mặc định tắt.",
             hintEn: "At most one bundled notice a day, 09:00–20:00 on the person's clock, when hosts they follow publish. People can mute it. Off by default.",
             onVi: "Đang bật", onEn: "On", offVi: "Đang tắt", offEn: "Off"),
        Flag(key: "weekly_digest", vi: "Bản tin cuối tuần (quảng bá)", en: "Weekly digest (promotional)",
             hintVi: "Chỉ gửi cho người tự bật đồng ý, thứ Năm 18:00 giờ của họ, không gửi khi không có sự kiện. Là tin quảng bá: cần rà soát pháp lý (Nghị định 91/2020, CAN-SPAM) trước khi bật. Mặc định tắt.",
             hintEn: "Sent only to people who opted in, Thursday 18:00 on their clock, never when there is nothing to show. Promotional: needs legal review (Decree 91/2020, CAN-SPAM) before turning on. Off by default.",
             onVi: "Đang bật", onEn: "On", offVi: "Đang tắt", offEn: "Off"),
        Flag(key: "intent_foryou", vi: "Dành cho bạn theo mục tiêu", en: "For You by goal",
             hintVi: "Tiêu đề và lời giải thích của mục Dành cho bạn theo mục tiêu người dùng đã chọn khi bắt đầu (chỉ câu trả lời họ tự chọn). Mặc định tắt.",
             hintEn: "For You title and explanation follow the goal people chose in onboarding (their own answers only). Off by default.",
             onVi: "Đang bật", onEn: "On", offVi: "Đang tắt", offEn: "Off"),
        Flag(key: "live_activity", vi: "Thẻ ngày sự kiện trên Màn hình khoá (iPhone)", en: "Event-day Lock Screen card (iPhone)",
             hintVi: "Vào ngày sự kiện, iPhone hiện tên, giờ và địa điểm trên Màn hình khoá cho người có vé. Tạo ngay trên máy. Cần kiểm tra trên thiết bị thật trước khi bật. Mặc định tắt.",
             hintEn: "On event day, the iPhone shows the event name, time and place on the Lock Screen for ticket holders. Created on the device. Check on a real device before turning on. Off by default.",
             onVi: "Đang bật", onEn: "On", offVi: "Đang tắt", offEn: "Off"),
        Flag(key: "market_share", vi: "Chia sẻ qua Zalo / Nhắn tin", en: "Share via Zalo / Text",
             hintVi: "Thêm nút chia sẻ qua Zalo (sự kiện ở Việt Nam) và Nhắn tin cho bạn (sự kiện ở Mỹ) cạnh nút chia sẻ của hệ thống. Mặc định tắt.",
             hintEn: "Adds Share via Zalo (Vietnam events) and Text a friend (US events) next to the system share. Off by default.",
             onVi: "Đang bật", onEn: "On", offVi: "Đang tắt", offEn: "Off"),
        // TESTING-PHASE (note 54): remove this row with the wipe tool before public release.
        Flag(key: "admin_event_wipe", vi: "Xoá sự kiện thử nghiệm (giai đoạn thử)", en: "Test event wipe (testing phase)",
             hintVi: "Cho admin xoá vĩnh viễn bất kỳ sự kiện nào cùng mọi dữ liệu liên quan, không cần lý do, trong Quản lý sự kiện (chỉ iOS). Chỉ dùng cho dữ liệu thử nghiệm.",
             hintEn: "Lets admins permanently wipe any event and everything tied to it, no reason needed, from Manage events (iOS only). For test data only.",
             onVi: "Đang bật. Admin có thể xoá vĩnh viễn", onEn: "On. Admins can wipe permanently",
             offVi: "Đang tắt", offEn: "Off"),
    ]

    private func message(_ code: String?) -> String {
        switch code ?? "" {
        case "NOT_AUTHORIZED": return app.T("Bạn không có quyền.", "You are not allowed to do this.")
        case "INVALID_VALUE": return app.T("Giá trị không hợp lệ.", "Invalid value.")
        case "NOT_DEPLOYED": return app.T("Máy chủ chưa có công tắc này (chạy migration 187).", "The server does not have this switch yet (apply migration 187).")
        case "BUSY": return app.T("Đang xử lý…", "Working…")
        default: return app.T("Không kết nối được. Thử lại nhé.", "Couldn't reach the server. Try again.")
        }
    }

    private func flip(_ key: String, to enabled: Bool) async {
        error = ""
        let r = await app.setFeatureFlag(key, enabled: enabled)
        if !r.ok {
            error = message(r.error)
            await app.loadFeatureFlags(force: true)
        }
    }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.T("Duyệt & Kiểm Duyệt", "Review & Moderation")) { app.screen = .accountGroup }
                    .padding(.top, 8)
                    .accessibilityIdentifier("adminFeatures.back")
                Text(app.T("Công tắc tính năng", "Feature switches"))
                    .font(BanbeTheme.display(24)).padding(.top, 14)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("adminFeatures.title")
                Text(app.T("Bật hoặc tắt một tính năng cho mọi người dùng, không cần phát hành bản mới. Mọi thay đổi đều được ghi lại.",
                           "Turn a feature on or off for every user without a release. Every change is logged."))
                    .font(.system(size: 13.5)).foregroundStyle(app.palette.ink.opacity(0.75)).padding(.top, 8)

                VStack(spacing: 0) {
                    ForEach(flags) { f in
                        let on = FeatureFlags.isOn(app.featureFlags, f.key)
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(app.T(f.vi, f.en)).font(.system(size: 15.5, weight: .semibold))
                                Text(app.T(f.hintVi, f.hintEn)).font(.system(size: 12.5)).opacity(0.7)
                                Text(on ? app.T(f.onVi, f.onEn) : app.T(f.offVi, f.offEn))
                                    .font(.system(size: 12, weight: .semibold)).opacity(on ? 1 : 0.7).padding(.top, 3)
                                    .accessibilityIdentifier("adminFeatures.\(f.key).state")
                            }
                            Spacer(minLength: 0)
                            GlassSwitch(isOn: on, loading: app.featureFlagBusy == f.key, identifier: "adminFeatures.\(f.key).switch") {
                                Task { await flip(f.key, to: !on) }
                            }
                        }
                        .padding(.horizontal, 18).padding(.vertical, 16)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("adminFeatures.\(f.key)")
                    }
                }
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.top, 22)

                if !error.isEmpty {
                    Text(error).font(.system(size: 12.5)).foregroundStyle(BanbeTheme.alert).padding(.top, 12)
                        .accessibilityIdentifier("adminFeatures.error")
                }
            }
            .padding(.horizontal, 22)
        }
    }
}
