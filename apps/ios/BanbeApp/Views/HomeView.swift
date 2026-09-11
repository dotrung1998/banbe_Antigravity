import SwiftUI

/// The feed — a port of src/screens/Home.jsx: header (wordmark, language
/// toggle, area picker, notification bell, messages, account), the held-spot
/// banner, the "Your events" strip, category filters, and the photo cards.
struct HomeView: View {
    @EnvironmentObject var app: AppState

    private let filters: [(key: String, vi: String, en: String)] = [
        ("all", "Tất cả", "All"),
        ("supper", "Supper club", "Supper club"),
        ("fashion", "Thời trang", "Fashion"),
        ("gallery", "Phòng tranh", "Gallery"),
        ("music", "Nhạc", "Music"),
    ]

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                header
                if let held = app.heldEvent { heldBanner(held) }
                if !app.savedStrip.isEmpty { savedStrip }
                filterTabs
                if app.feed.isEmpty {
                    emptyState
                } else {
                    ForEach(app.feed) { event in
                        EventCard(event: event)
                    }
                    footer
                }
                hostLink
            }
            .padding(.bottom, 40)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("banbe")
                .font(BanbeTheme.display(28))
                .foregroundStyle(app.palette.ink)
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 10) {
                    Button(app.T("English", "Tiếng Việt")) { app.toggleLang() }
                        .font(.system(size: 11))
                        .accessibilityIdentifier("header.lang")
                    Button("banbe ▪︎ \(app.currentArea.key == "all" ? "Sài Gòn" : app.currentArea.label) ▾") {
                        app.openArea()
                    }
                    .font(.system(size: 11))
                    .accessibilityIdentifier("header.area")
                }
                HStack(spacing: 12) {
                    if app.isSignedIn {
                        Button { app.goNotifications() } label: {
                            ZStack(alignment: .topTrailing) {
                                Text("🔔").font(.system(size: 15))
                                if app.unreadNotifications > 0 {
                                    Text(app.unreadNotifications > 9 ? "9+" : "\(app.unreadNotifications)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(app.palette.paper)
                                        .padding(.horizontal, 4)
                                        .frame(minWidth: 14, minHeight: 14)
                                        .background(app.palette.ink, in: Capsule())
                                        .offset(x: 7, y: -5)
                                }
                            }
                        }
                        Button(app.T("Tin nhắn", "Messages")) { app.goInbox() }
                            .font(.system(size: 12))
                            .accessibilityIdentifier("header.messages")
                    }
                    Button(app.T("Tài khoản", "Account")) { app.goProfile() }
                        .font(.system(size: 12))
                        .accessibilityIdentifier("header.account")
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(app.palette.ink)
        // The web header fits in a narrower face; scale rather than clip if
        // a longer area name (or English) pushes the row past the edge.
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: Held spot

    private func heldBanner(_ event: CatalogEvent) -> some View {
        Button { app.openHeld() } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.T("Đang giữ chỗ", "Holding your spot"))
                        .font(.system(size: 11.5, weight: .semibold))
                    Text(event.name + (app.qty > 1 ? " ▪︎ \(app.qty)" + app.T(" vé", " tix") : "")
                         + app.T(" ▪︎ trả để xác nhận", " ▪︎ pay to confirm"))
                        .font(.system(size: 12.5))
                        .lineLimit(1)
                }
                Spacer()
                Text(countdown)
                    .font(BanbeTheme.display(18))
                    .monospacedDigit()
            }
            .foregroundStyle(app.palette.ink)
            .padding(14)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
            .padding(.horizontal, 20)
            .padding(.top, 14)
        }
        .buttonStyle(.plain)
    }

    private var countdown: String {
        guard let deadline = app.holdDeadline else { return "00:00:00" }
        let remaining = max(0, Int(deadline.timeIntervalSince(app.now)))
        return String(format: "%02d:%02d:%02d", remaining / 3600, (remaining % 3600) / 60, remaining % 60)
    }

    // MARK: Your events

    private var savedStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(app.T("Sự kiện của bạn", "Your events")).font(BanbeTheme.display(15))
                Spacer()
                Text(app.T("Tự xóa sau 48 giờ", "Clears after 48h")).font(.system(size: 11.5))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(app.savedStrip) { event in
                        Button { app.goEvent(event.key) } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                ZStack(alignment: .topLeading) {
                                    CatalogPhoto(path: event.img, height: 96, width: 152, cornerRadius: 12)
                                    PhotoChip(text: app.trStatus(savedTag(event).0), background: savedTag(event).1)
                                        .padding(6)
                                }
                                Text(event.name)
                                    .font(BanbeTheme.display(15))
                                    .lineLimit(1)
                                Text(app.trStatus(savedStatus(event)))
                                    .font(.system(size: 11))
                            }
                            .frame(width: 152, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(app.palette.rule).frame(height: 1) }
    }

    /// Matches the web strip's tag rules: cancelled / past / on hold /
    /// paid / saved, each with its own chip colour.
    private func savedTag(_ event: CatalogEvent) -> (String, Color) {
        if event.cancelled { return ("Đã hủy", BanbeTheme.Chip.cancelled) }
        if event.endedHoursAgo != nil { return ("Đã diễn ra", BanbeTheme.Chip.past) }
        if event.key == app.heldEvent?.key { return ("Đang giữ", BanbeTheme.Chip.hold) }
        if app.isGoing(event.key) { return ("Đã thanh toán", BanbeTheme.Chip.going) }
        return ("Đã lưu", BanbeTheme.Chip.saved)
    }

    private func savedStatus(_ event: CatalogEvent) -> String {
        let tix = app.tickets[event.key] ?? 1
        let suffix = tix > 1 ? " ▪︎ \(tix) vé" : ""
        if event.cancelled { return "Đã hoàn tiền" }
        if let ended = event.endedHoursAgo { return EventLabels.ago(ended) }
        if event.key == app.heldEvent?.key { return "Trả để xác nhận" + suffix }
        if app.isGoing(event.key) { return event.untilLabel + suffix }
        return event.untilLabel
    }

    // MARK: Filters

    private var filterTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(filters, id: \.key) { filter in
                    let active = app.filter == filter.key
                    Button { app.pickFilter(filter.key) } label: {
                        VStack(spacing: 6) {
                            Text(app.T(filter.vi, filter.en))
                                .font(.system(size: 12.5, weight: active ? .semibold : .regular))
                            Rectangle()
                                .fill(active ? app.palette.ink : .clear)
                                .frame(height: 2)
                        }
                        .fixedSize()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("filter.\(filter.key)")
                }
            }
            .padding(.horizontal, 20)
        }
        .foregroundStyle(app.palette.ink)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    // MARK: Empty / footer

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text(app.T(
                "Chưa có buổi nào ở \(app.currentArea.key == "all" ? "mục này" : app.currentArea.label) tuần này, thử mục khác xem sao!",
                "Nothing in \(app.currentArea.key == "all" ? "this category" : app.currentArea.label) this week, try another one!"
            ))
            .font(.system(size: 14))
            .multilineTextAlignment(.center)
            Button(app.T("Xem tất cả", "See all")) { app.clearFilters() }
                .font(.system(size: 12.5))
                .buttonStyle(.plain)
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 40)
        .padding(.vertical, 60)
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(app.palette.rule).frame(height: 1)
            Text(app.T("Hết rồi, ra ngoài chơi thôi!", "That's it, go have fun!"))
                .font(BanbeTheme.display(11.5))
                .padding(.top, 34)
            Text(app.T(
                "Vài buổi vui dành cho riêng bạn tuần này. Không xếp hạng, không quảng cáo, không lướt vô tận.",
                "A few fun gatherings made just for you this week. No ratings, no ads, no endless scrolling."
            ))
            .font(.system(size: 11))
            .padding(.top, 12)
            .padding(.horizontal, 20)
        }
        .foregroundStyle(app.palette.ink)
        .multilineTextAlignment(.center)
    }

    private var hostLink: some View {
        Button {
            if app.hasHosted { app.switchToHost() } else { app.goHostIntro() }
        } label: {
            Text((app.hasHosted
                  ? app.T("Trang tổ chức của bạn", "Your host page")
                  : app.T("Dành cho người tổ chức ▪︎ hoàn toàn miễn phí", "For organizers ▪︎ completely free")) + " ›")
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(app.palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)
        }
        .buttonStyle(.plain)
    }
}

/// One feed card — hero photo with the Save/Going chips over it, then the
/// name, meta line and price/seats, as on the web feed.
struct EventCard: View {
    let event: CatalogEvent
    @EnvironmentObject private var app: AppState

    var body: some View {
        Button { app.goEvent(event.key) } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    CatalogPhoto(path: event.img, height: 272, cornerRadius: 14)
                        .overlay(alignment: .bottom) {
                            LinearGradient(
                                colors: [app.palette.paper.opacity(0), app.palette.paper],
                                startPoint: .top, endPoint: .bottom
                            )
                            .frame(height: 58)
                        }
                    Button { app.toggleFavorite(event.key) } label: {
                        PhotoChip(
                            text: app.isSaved(event.key) ? app.T("Đã lưu", "Saved") : app.T("Lưu", "Save"),
                            background: app.isSaved(event.key) ? BanbeTheme.Chip.going : app.palette.paper.opacity(0.62),
                            foreground: app.isSaved(event.key) ? .white : app.palette.ink
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(12)

                    if app.isGoing(event.key) && event.isOpen {
                        PhotoChip(text: app.trStatus("Đang tham gia"), background: BanbeTheme.Chip.going)
                            .padding(12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(event.name).font(BanbeTheme.display(22))
                        Text(app.metaLine(for: event)).font(.system(size: 12.5))
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(app.trStatus(event.price)).font(.system(size: 13))
                        Text(app.seatsLabel(for: event))
                            .font(.system(size: 11.5))
                            .multilineTextAlignment(.trailing)
                    }
                }
                .foregroundStyle(app.palette.ink)
                .padding(.top, 14)
                .padding(.bottom, 18)
            }
            .padding(.horizontal, 20)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("card.\(event.key)")
    }
}
