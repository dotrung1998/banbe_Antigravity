import SwiftUI

/// Port of src/screens/Policy.jsx — PLACEHOLDER CONTENT. banbe_User_Policy.md
/// (referenced by the ticket that asked for this screen) does not exist
/// anywhere in this repo. This is structurally where the real policy text
/// goes (linked from LoginView's consent checkbox, version-tracked via
/// profiles.policy_version), but the copy below is a stand-in only and
/// must be replaced with banbe's actual legal text before this ships —
/// flagged in the session report, not silently shipped as real.
struct PolicyView: View {
    @EnvironmentObject var app: AppState

    static let version = "2026-09-18" // keep in sync with src/lib/policy.js's POLICY_VERSION

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button(app.T("‹ Quay lại", "‹ Back")) { app.screen = app.policyBackScreen }
                        .font(.system(size: 12)).buttonStyle(.plain)
                    Spacer()
                    Text(app.T("Phiên bản", "Version") + " " + Self.version)
                        .font(.system(size: 11)).opacity(0.5)
                }
                .padding(.top, 8)

                Text(app.T("Điều khoản sử dụng và Thông báo quyền riêng tư", "Terms of Service and Privacy Notice"))
                    .font(BanbeTheme.display(24))
                    .padding(.top, 18)
                Text(app.T("⚠️ NỘI DUNG TẠM THỜI — chưa phải văn bản pháp lý chính thức của banbe.",
                           "⚠️ PLACEHOLDER CONTENT — not banbe's finalized legal text yet."))
                    .font(.system(size: 11.5)).opacity(0.55)
                    .padding(.top, 4).padding(.bottom, 16)

                section(app.T("1. Dữ liệu chúng tôi thu thập", "1. Data we collect"),
                        app.T("Email, tên hiển thị, và thông tin đặt chỗ/thanh toán bạn cung cấp khi sử dụng banbe.",
                              "Email, display name, and booking/payment details you provide while using banbe."))
                section(app.T("2. Mục đích sử dụng", "2. Why we use it"),
                        app.T("Để vận hành việc đặt chỗ, xác nhận thanh toán, xử lý tranh chấp, và liên lạc liên quan tới sự kiện bạn tham gia hoặc tổ chức.",
                              "To run bookings, confirm payments, resolve disputes, and communicate about events you attend or host."))
                section(app.T("3. Lưu trữ và xoá dữ liệu", "3. Retention and deletion"),
                        app.T("Đoạn chat tranh chấp bị xoá 72 giờ sau khi banbe ra quyết định. Dữ liệu tài khoản khác được giữ trong thời gian bạn còn sử dụng dịch vụ.",
                              "Dispute chat transcripts are deleted 72 hours after banbe rules on them. Other account data is kept while you continue using the service."))
                section(app.T("4. Quyền của bạn", "4. Your rights"),
                        app.T("Bạn có thể yêu cầu xem, sửa, hoặc xoá dữ liệu cá nhân của mình bất cứ lúc nào qua Tài khoản.",
                              "You can request to view, correct, or delete your personal data at any time from Account."))
                section(app.T("5. Đồng ý", "5. Consent"),
                        app.T("Bằng việc đánh dấu vào ô đồng ý khi đăng nhập/đăng ký, bạn xác nhận đã đọc và đồng ý với các điều khoản này.",
                              "By checking the consent box at sign-in/sign-up, you confirm you have read and agree to these terms."))
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 22)
            .padding(.bottom, 40)
        }
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(body).font(.system(size: 13)).lineSpacing(4).opacity(0.85)
        }
        .padding(.top, 14)
        .overlay(alignment: .top) { Rectangle().fill(app.palette.rule).frame(height: 1) }
    }
}
