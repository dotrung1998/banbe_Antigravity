import SwiftUI

/// Admin > Feature switches (migration 187, note 51) — the iOS counterpart of src/screens/AdminFeatures.jsx. One row
/// per platform feature flag. Turning a switch off hides the feature everywhere (web + iOS, signed in and signed
/// out) without a release; turning it on shows it again. The server decides who may flip it (is_platform_admin()
/// inside admin_set_feature_flag, audited); this view only calls it, and the switch moves only after the server
/// accepted the change.
///
/// Note 64: rows are grouped into collapsible categories (Lib/FeatureFlagCategories.swift), all collapsed on open,
/// and onboarding is one Version 1/2/3 control (migration 202) instead of the old Version 2 switch.
struct AdminFeaturesView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var error = ""
    @State private var expanded: Set<String> = []
    /// Note 69: a switch that needs another one, turned on while that one is off ("Also turn on …?").
    @State private var pendingRequires: Flag?

    private struct Flag: Identifiable {
        let key: String, vi: String, en: String, hintVi: String, hintEn: String
        var onVi = "Đang hiện cho mọi người", onEn = "Visible to everyone"
        var offVi = "Đang ẩn với mọi người", offEn = "Hidden from everyone"
        /// Note 69: the switch that must also be on for this one to do anything (Rewards v2 needs Rewards).
        var requires: String? = nil
        var id: String { key }
    }
    private let flags = [
        Flag(key: "rewards", vi: "Phần thưởng & huy hiệu", en: "Rewards & badges",
             hintVi: "Ẩn xu, chuỗi ngày, huy hiệu và mẫu móc khoá thưởng khỏi toàn bộ ứng dụng. Dữ liệu không bị xoá.",
             hintEn: "Hides coins, streaks, badges and reward keychain designs everywhere in the app. No data is deleted."),
        Flag(key: "rewards_v2", vi: "Phần thưởng v2: chuỗi tuần, cấp huy hiệu, mục tiêu", en: "Rewards v2: week streak, badge tiers, goals",
             hintVi: "Chuỗi theo tuần với tuần nghỉ và khôi phục, huy hiệu nhiều cấp, huy hiệu tiếp theo và mục tiêu tháng (migration 192). Mặc định tắt. Cần bật Phần thưởng.",
             hintEn: "Weekly streak with grace weeks and repair, tiered badges, next badge and a monthly goal (migration 192). Off by default. Needs Rewards on.",
             onVi: "Đang hiện cho mọi người", onEn: "Visible to everyone", offVi: "Đang tắt", offEn: "Off", requires: "rewards"),
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
        // Migration 201, note 63: a version picker on top of a boolean switch (off = Version 1, on = Version 2).
        Flag(key: "onboarding_v2", vi: "Bản giới thiệu: Phiên bản 2", en: "Onboarding demo: Version 2",
             hintVi: "Tắt = Phiên bản 1: màn Chào mừng tĩnh và 4 trang chữ \"banbe hoạt động thế nào\". Bật = Phiên bản 2: màn Chào mừng có chuyển động và mỗi phần có các màn demo vuốt qua lại. Mặc định tắt.",
             hintEn: "Off = Version 1: still Welcome screen and the 4 text pages of \"How banbe works\". On = Version 2: animated Welcome entrance and swipeable demo screens in each section. Off by default.",
             onVi: "Đang dùng Phiên bản 2", onEn: "Showing Version 2", offVi: "Đang dùng Phiên bản 1", offEn: "Showing Version 1"),
        // Migration 203, note 65.
        Flag(key: "event_type_profiles", vi: "Biểu mẫu theo loại sự kiện", en: "Event-type forms",
             hintVi: "Màn tạo sự kiện, trang sự kiện và Trang chủ thay đổi theo loại sự kiện. Hiện có Supper club: chế độ ăn, mang đồ uống, trang phục, bộ lọc riêng trên Trang chủ. Mặc định tắt.",
             hintEn: "The create form, the event page and Home adapt to the kind of event. Supper club first: dietary options, BYO, dress code, its own Home filters. Off by default.",
             onVi: "Đang bật", onEn: "On", offVi: "Đang tắt", offEn: "Off"),
        // Migration 206, note 66.
        Flag(key: "simple_shell", vi: "Bố cục gọn (Simple Shell)", en: "Simple Shell layout",
             hintVi: "Trang chủ gọn: nút chuyển Đi chơi | Tổ chức luôn hiện, một khối chính ở trên cùng, bản đồ là một kiểu xem của Trang chủ. Thanh dưới có 5 ô với nút \"+\" ở giữa cho mọi người. Mặc định tắt.",
             hintEn: "Simpler Home: an always-visible Going out | Hosting switch, one main block at the top, and the map as a Home view. The dock has 5 slots with a \"+\" in the centre for everyone. Off by default.",
             onVi: "Đang bật", onEn: "On", offVi: "Đang tắt", offEn: "Off"),
        // Migration 208, note 71.
        Flag(key: "polaroid_cards", vi: "Thẻ sự kiện kiểu polaroid", en: "Polaroid event cards",
             hintVi: "Thẻ sự kiện trên Trang chủ có khung giấy quanh ảnh và chú thích bên dưới, như ảnh polaroid. Chỉ đổi kiểu xem thẻ, không đổi danh sách. Mặc định tắt.",
             hintEn: "Home event cards get a paper frame around the photo with the caption below, like a polaroid. Only the cards view changes, not the list. Off by default.",
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
        case "NOT_DEPLOYED": return app.T("Máy chủ chưa có công tắc này. Cần chạy migration mới nhất.", "The server doesn't have this switch yet. Apply the latest migrations.")
        case "BUSY": return app.T("Đang xử lý…", "Working…")
        default: return app.T("Không kết nối được. Thử lại nhé.", "Couldn't reach the server. Try again.")
        }
    }

    private func pickVersion(_ version: Int) async {
        error = ""
        let r = await app.setOnboardingVersion(version)
        if !r.ok {
            error = message(r.error)
            await app.loadFeatureFlags(force: true)
        }
    }

    /// Until migration 202 is on the server (no onboarding_v3 key comes back), keep the old Version 2 switch.
    private var versionDeployed: Bool { app.featureFlags["onboarding_v3"] != nil }

    @ViewBuilder private func categorySection(_ cat: FeatureFlagCategories.Category) -> some View {
        let isOpen = expanded.contains(cat.key)
        let switches = cat.flags.filter { $0 != FeatureFlagCategories.onboardingControl }
        let onCount = switches.filter { FeatureFlags.isOn(app.featureFlags, $0) }.count
        VStack(spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    if isOpen { expanded.remove(cat.key) } else { expanded.insert(cat.key) }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(app.T(cat.vi, cat.en)).font(.system(size: 15.5, weight: .bold))
                    Spacer(minLength: 0)
                    if !switches.isEmpty {
                        Text(app.T("\(onCount)/\(switches.count) bật", "\(onCount)/\(switches.count) on"))
                            .font(.system(size: 12.5)).monospacedDigit().opacity(0.65)
                    }
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).opacity(0.6)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .foregroundStyle(app.palette.ink)
                .padding(.horizontal, 18).frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(isOpen ? app.T("Đang mở", "Expanded") : app.T("Đang đóng", "Collapsed"))
            .accessibilityHint(app.T("Chạm hai lần để mở hoặc đóng nhóm", "Double-tap to expand or collapse"))
            .accessibilityIdentifier("adminFeatures.cat.\(cat.key)")

            if isOpen {
                Divider().overlay(app.palette.rule)
                ForEach(Array(cat.flags.enumerated()), id: \.element) { i, key in
                    if i > 0 { Divider().overlay(app.palette.rule) }
                    if key == FeatureFlagCategories.onboardingControl {
                        if versionDeployed { versionRow } else if let f = flags.first(where: { $0.key == "onboarding_v2" }) { flagRow(f) }
                    } else if let f = flags.first(where: { $0.key == key }) {
                        flagRow(f)
                    }
                }
            }
        }
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func flagTitle(_ key: String) -> String {
        flags.first { $0.key == key }.map { app.T($0.vi, $0.en) } ?? key
    }

    private func flagRow(_ f: Flag) -> some View {
        let on = FeatureFlags.isOn(app.featureFlags, f.key)
        // Note 69: on, but the switch it needs is off, so nobody sees it. Say so instead of "Visible to everyone".
        let blockedBy = f.requires.flatMap { FeatureFlags.isOn(app.featureFlags, $0) ? nil : $0 }
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(app.T(f.vi, f.en)).font(.system(size: 15.5, weight: .semibold))
                Text(app.T(f.hintVi, f.hintEn)).font(.system(size: 12.5)).opacity(0.7)
                if on, let parent = blockedBy {
                    Text(app.T("Chưa có tác dụng: hãy bật \"\(flagTitle(parent))\" trước", "No effect yet: turn on \"\(flagTitle(parent))\" first"))
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(app.palette.honey).padding(.top, 3)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("adminFeatures.\(f.key).state")
                    Button { Task { await flip(parent, to: true) } } label: {
                        Text(app.T("Bật \"\(flagTitle(parent))\"", "Turn on \"\(flagTitle(parent))\""))
                            .font(.system(size: 13, weight: .semibold)).underline()
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!app.featureFlagBusy.isEmpty)
                    .accessibilityIdentifier("adminFeatures.\(f.key).enableRequired")
                } else {
                    Text(on ? app.T(f.onVi, f.onEn) : app.T(f.offVi, f.offEn))
                        .font(.system(size: 12, weight: .semibold)).opacity(on ? 1 : 0.7).padding(.top, 3)
                        .accessibilityIdentifier("adminFeatures.\(f.key).state")
                }
            }
            Spacer(minLength: 0)
            GlassSwitch(isOn: on, loading: app.featureFlagBusy == f.key, identifier: "adminFeatures.\(f.key).switch") {
                if !on, blockedBy != nil { pendingRequires = f } else { Task { await flip(f.key, to: !on) } }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("adminFeatures.\(f.key)")
    }

    private var versionRow: some View {
        let v = app.onboardingVersion
        let busy = app.featureFlagBusy == FeatureFlagCategories.onboardingControl
        return VStack(alignment: .leading, spacing: 3) {
            Text(app.T("Bản giới thiệu", "Onboarding version")).font(.system(size: 15.5, weight: .semibold))
            Text(app.T("Phiên bản 1: màn Chào mừng tĩnh và 4 trang chữ \"banbe hoạt động thế nào\". Phiên bản 2: màn Chào mừng có chuyển động và các màn demo vuốt qua lại. Phiên bản 3: như Phiên bản 2, cộng thêm hướng dẫn trên giao diện thật ngay sau khi đăng nhập lần đầu.",
                       "Version 1: still Welcome screen and the 4 text pages of \"How banbe works\". Version 2: animated Welcome and swipeable demo screens. Version 3: Version 2 plus a guided tour over the real app right after the first sign-in."))
                .font(.system(size: 12.5)).opacity(0.7)
            HStack(spacing: 4) {
                ForEach(1...3, id: \.self) { n in
                    Button {
                        guard !busy, v != n else { return }
                        Task { await pickVersion(n) }
                    } label: {
                        Text(app.T("Phiên bản \(n)", "Version \(n)"))
                            .font(.system(size: 13.5, weight: v == n ? .bold : .medium))
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(v == n ? app.palette.paper : .clear, in: Capsule())
                            .shadow(color: .black.opacity(v == n ? 0.15 : 0), radius: 2, y: 1)
                            .foregroundStyle(app.palette.ink)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(v == n ? [.isSelected] : [])
                    .accessibilityIdentifier("adminFeatures.onboardingVersion.\(n)")
                }
            }
            .padding(3)
            .background(app.palette.ink.opacity(0.06), in: Capsule())
            .opacity(busy ? 0.6 : 1)
            .padding(.top, 8)
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("adminFeatures.onboardingVersion")
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

                ForEach(FeatureFlagCategories.all) { cat in
                    categorySection(cat).padding(.top, 14)
                }

                if !error.isEmpty {
                    Text(error).font(.system(size: 12.5)).foregroundStyle(BanbeTheme.alert).padding(.top, 12)
                        .accessibilityIdentifier("adminFeatures.error")
                }
            }
            .padding(.horizontal, 22)
        }
        // Note 69: turning on a switch whose required switch is off (Rewards v2 without Rewards) would show nothing.
        .confirmationDialog(
            pendingRequires.map { f in app.T("Bật cả \"\(flagTitle(f.requires ?? ""))\"?", "Also turn on \"\(flagTitle(f.requires ?? ""))\"?") } ?? "",
            isPresented: Binding(get: { pendingRequires != nil }, set: { if !$0 { pendingRequires = nil } }),
            titleVisibility: .visible,
            presenting: pendingRequires
        ) { f in
            Button(app.T("Bật cả hai", "Turn on both")) {
                Task {
                    if let parent = f.requires { await flip(parent, to: true) }
                    await flip(f.key, to: true)
                }
            }
            Button(app.T("Chỉ bật mục này", "Only this one")) { Task { await flip(f.key, to: true) } }
            Button(app.T("Huỷ", "Cancel"), role: .cancel) {}
        } message: { f in
            Text(app.T("\"\(app.T(f.vi, f.en))\" chỉ hiện khi \"\(flagTitle(f.requires ?? ""))\" đang bật.",
                       "\"\(app.T(f.vi, f.en))\" only shows while \"\(flagTitle(f.requires ?? ""))\" is on."))
        }
    }
}
