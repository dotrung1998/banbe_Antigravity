import SwiftUI

/// Port of src/screens/Splash.jsx — the wordmark, the tagline, and a
/// spinner; tapping (or waiting) moves on to the language picker.
struct SplashView: View {
    @EnvironmentObject var app: AppState
    @State private var spin = false

    var body: some View {
        ZStack {
            app.palette.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                Text("banbe")
                    .font(.system(size: 56, weight: .semibold, design: .rounded))
                    .foregroundStyle(app.palette.ink)
                Text("bạn mới mỗi tuần")
                    .font(.system(size: 14))
                    .foregroundStyle(app.palette.ink)
                    .padding(.top, 16)
                Circle()
                    .trim(from: 0, to: 0.5)
                    .stroke(app.palette.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 28, height: 28)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 1.7).repeatForever(autoreverses: false), value: spin)
                    .padding(.top, 34)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { app.dismissSplash() }
        .task {
            spin = true
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if app.screen == .splash { app.dismissSplash() }
        }
    }
}

/// Port of src/screens/LangPick.jsx.
struct LangPickView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                Text("Chào bạn").font(.system(size: 11.5))
                Text("Bạn muốn dùng banbe bằng tiếng nào?")
                    .font(BanbeTheme.display(27))
                    .padding(.top, 8)
                Text("You can change this anytime in your account.")
                    .font(.system(size: 13.5))
                    .padding(.top, 10)

                VStack(spacing: 10) {
                    choice(title: "Tiếng Việt", subtitle: "Mặc định", active: app.lang == "vi") {
                        app.pickLang("vi")
                    }
                    .accessibilityIdentifier("lang.vi")
                    choice(title: "English", subtitle: "Switch anytime", active: app.lang == "en") {
                        app.pickLang("en")
                    }
                    .accessibilityIdentifier("lang.en")
                }
                .padding(.top, 28)
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 30)
            .padding(.top, 80)
        }
    }

    private func choice(title: String, subtitle: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(BanbeTheme.display(19))
                    Text(subtitle).font(.system(size: 11.5))
                }
                Spacer()
                Text("›").font(.system(size: 15))
            }
            .foregroundStyle(app.palette.ink)
            .padding(18)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(active ? app.palette.ink : app.palette.rule, lineWidth: active ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }
}

/// Port of src/screens/ThemePick.jsx — the light/dark choice, previewed
/// live, then "Continue" into the feed.
struct ThemePickView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                Text(app.T("Hiển thị", "Appearance")).font(.system(size: 11.5))
                Text(app.T("Bạn thích nền sáng hay tối?", "Light or dark?"))
                    .font(BanbeTheme.display(27))
                    .padding(.top, 8)
                Text(app.T("Bạn có thể đổi lại bất cứ lúc nào trong Tài khoản.",
                           "You can change this anytime in your account."))
                    .font(.system(size: 13.5))
                    .padding(.top, 10)

                VStack(spacing: 10) {
                    choice(title: app.T("Sáng", "Light"), subtitle: app.T("Nền giấy ấm", "Warm paper"),
                           active: app.theme == "light") { app.pickTheme("light") }
                        .accessibilityIdentifier("theme.light")
                    choice(title: app.T("Tối", "Dark"), subtitle: app.T("Nền mực dịu mắt", "Soft ink background"),
                           active: app.theme == "dark") { app.pickTheme("dark") }
                        .accessibilityIdentifier("theme.dark")
                }
                .padding(.top, 28)

                InkButton(title: app.T("Tiếp tục", "Continue")) { app.finishOnboarding() }
                    .accessibilityIdentifier("onboarding.continue")
                    .padding(.top, 26)
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 30)
            .padding(.top, 80)
        }
    }

    private func choice(title: String, subtitle: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(BanbeTheme.display(19))
                    Text(subtitle).font(.system(size: 11.5))
                }
                Spacer()
                Text(active ? "✓" : "›").font(.system(size: 15))
            }
            .foregroundStyle(app.palette.ink)
            .padding(18)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(active ? app.palette.ink : app.palette.rule, lineWidth: active ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }
}

/// Port of src/screens/CreateEvent.jsx — the organizer profile fields, the
/// event fields, category pickers and the submit that calls
/// create_event_draft.
struct CreateEventView: View {
    @EnvironmentObject var app: AppState

    private let categories: [(key: String, vi: String, en: String)] = [
        ("supper", "Supper club", "Supper club"),
        ("fashion", "Thời trang", "Fashion"),
        ("gallery", "Phòng tranh", "Gallery"),
        ("music", "Nhạc", "Music"),
        ("popup", "Pop-up", "Pop-up"),
    ]

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.hasHosted
                         ? app.T("Trang tổ chức của bạn", "Your host page")
                         : app.T("Trang tổ chức của bạn sẽ trông thế nào", "Preview your organizer page")) {
                    app.createBack()
                }

                Text(app.T("Dành cho người tổ chức", "For organizers"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.top, 14)
                Text(app.T("Tạo sự kiện, hoàn toàn miễn phí", "Create an event, completely free"))
                    .font(BanbeTheme.display(26))
                    .padding(.top, 8)

                group(app.T("Hồ sơ người tổ chức", "Organizer profile")) {
                    BanbeField(label: app.T("Tên", "Name"), placeholder: "Bếp Nhỏ", text: $app.orgRegName)
                    BanbeField(label: "Instagram", placeholder: "@bepnho.saigon", text: $app.orgRegIg)
                    BanbeField(label: app.T("Giới thiệu", "About"),
                               placeholder: app.T("Mình nấu cho người lạ từ 2021…", "I cook for strangers since 2021…"),
                               text: $app.orgRegDesc)
                }

                group(app.T("Sự kiện", "Event")) {
                    BanbeField(label: app.T("Tên sự kiện", "Event name"),
                               placeholder: app.T("Tên sự kiện của bạn", "Your event name"), text: $app.createName)
                    BanbeField(label: app.T("Mô tả", "Description"),
                               placeholder: app.T("Buổi này có gì?", "What happens?"), text: $app.createDesc)
                    BanbeField(label: app.T("Địa điểm", "Location"), placeholder: "Bình Thạnh", text: $app.createLoc)
                    BanbeField(label: app.T("Ngày & giờ", "Date & time"), placeholder: "11.07 19:00", text: $app.createDate)
                    HStack(spacing: 10) {
                        BanbeField(label: app.T("Giá", "Price"), placeholder: "900.000", text: $app.createPrice,
                                   keyboard: .numberPad)
                        BanbeField(label: app.T("Số chỗ", "Seats"), placeholder: "14", text: $app.createSeats,
                                   keyboard: .numberPad)
                    }

                    Text(app.T("Hạng mục ▪︎ chọn tối đa 2", "Categories ▪︎ up to 2"))
                        .font(.system(size: 11.5))
                    FlowRow(spacing: 8) {
                        ForEach(categories, id: \.key) { category in
                            let active = app.createCats.contains(category.key)
                            Button { app.pickCreateCategory(category.key) } label: {
                                Text(app.T(category.vi, category.en))
                                    .font(.system(size: 12.5, weight: active ? .semibold : .regular))
                                    .foregroundStyle(active ? app.palette.paper : app.palette.ink)
                                    .padding(.horizontal, 14).padding(.vertical, 9)
                                    .background(active ? app.palette.ink : .clear, in: Capsule())
                                    .overlay(Capsule().stroke(active ? .clear : app.palette.rule, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                InkButton(title: app.createSent
                          ? app.T("Đã gửi ▪︎ banbe đang duyệt", "Submitted ▪︎ under review")
                          : (app.loading ? app.T("Đang gửi…", "Submitting…")
                                         : app.T("Gửi để duyệt", "Submit for review")),
                          enabled: !app.createName.trimmingCharacters(in: .whitespaces).isEmpty
                              && !app.createSent && !app.loading,
                          cornerRadius: 999) {
                    Task { await app.submitCreateEvent() }
                }
                .padding(.top, 26)

                if !app.createError.isEmpty {
                    Text(app.createError)
                        .font(.system(size: 12))
                        .foregroundStyle(BanbeTheme.alert)
                        .padding(.top, 12)
                }
                if app.createSent {
                    Text(app.T("banbe duyệt sự kiện đầu tiên trong 48 giờ. Sau đó bạn đăng trực tiếp.",
                               "banbe reviews your first event within 48 hours. After that you post directly."))
                        .font(.system(size: 11.5))
                        .padding(.top, 12)
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 11.5, weight: .semibold))
            content()
        }
        .padding(16)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.top, 22)
    }
}

/// Minimal wrapping row — SwiftUI has no stock flow layout before iOS 16's
/// Layout protocol, and the category chips need to wrap.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
