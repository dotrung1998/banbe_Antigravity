import SwiftUI

/// The feed — a port of src/screens/Home.jsx: header (wordmark, language
/// toggle, area picker, notification bell, messages, account), the held-spot
/// banner, the "Your events" strip, category filters, and the photo cards.
struct HomeView: View {
    @EnvironmentObject var app: AppState
    @State private var tickTask: Task<Void, Never>?
    @State private var tick = Date()

    private let filters: [(key: String, vi: String, en: String)] = [
        ("all", "Tất cả", "All"),
        ("supper", "Supper club", "Supper club"),
        ("fashion", "Thời trang", "Fashion"),
        ("gallery", "Phòng tranh", "Gallery"),
        ("music", "Nhạc", "Music"),
    ]

    /// Any of these showing is reason enough to tick every second; none of
    /// them showing means no clock runs at all.
    private var anyCountdownVisible: Bool {
        app.heldEvent != nil || app.myHolding != nil || app.myPendingVerification != nil
            || app.organizerPendingCount > 0 || app.organizerHoldingSummary != nil
    }

    var body: some View {
        ScreenScaffold {
            // Lazy, so only the cards actually on screen fetch their photo —
            // the eager VStack kicked off all ~21 hero downloads at launch
            // and they all fought for the same bandwidth.
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                // Supersedes the old single-booking heldBanner below: this
                // covers both payment phases, both roles, and every booking
                // this account has — not just the one most recently reserved
                // in the current session. heldEvent itself stays in use for
                // tagging the "Your events" strip further down.
                paymentBanners
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
        .task {
            guard app.userID != nil else { return }
            await app.loadPaymentBookings()
            if app.canHost {
                await app.loadVerifications()
                await app.loadOrganizerHoldingSummary()
            }
            // The data this decides on arrives asynchronously, after
            // .onAppear's own call below has almost certainly already run
            // and found nothing to show yet — without this, a countdown
            // could sit there never ticking at all, having missed its one
            // chance to start.
            startTickingIfNeeded()
        }
        .onAppear { startTickingIfNeeded() }
        .onDisappear { tickTask?.cancel() }
    }

    private func startTickingIfNeeded() {
        tickTask?.cancel()
        guard anyCountdownVisible else { return }
        tickTask = Task { @MainActor in
            while !Task.isCancelled {
                tick = Date()
                forfeitAnyJustLapsedHold()
                // Stop ticking once nothing is left to show — matches
                // useTicking()'s behaviour on the web side, and means a
                // countdown that just got forfeited above doesn't leave a
                // pointless per-second timer running forever afterward.
                if !anyCountdownVisible { break }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    /// Home is often the screen a buyer is sitting on when a hold's
    /// countdown reaches zero — not just the ticket screen. `app.myHolding`
    /// already excludes a lapsed row (that's what makes its banner
    /// disappear on time), which means it can't be used to notice the
    /// transition; this checks the raw list directly so Home can forfeit it
    /// the same instant the banner for it vanishes, rather than leaving
    /// that to whichever other screen the buyer happens to open next.
    private func forfeitAnyJustLapsedHold() {
        guard let justLapsed = app.paymentBookings.first(where: {
            $0.paymentState == .holding && $0.holdExpiresAt != nil
                && Countdown.secondsUntil($0.holdExpiresAt, now: tick) == 0
        }) else { return }
        app.forfeitExpiredHold(justLapsed)
    }

    @ViewBuilder
    private var paymentBanners: some View {
        // Both phases of the payment state machine, both roles this account
        // can hold: what I (as a buyer) am waiting on, and — separately —
        // what my own events' buyers are waiting on me for.
        if let holding = app.myHolding {
            PhaseBanner(
                label: app.T("Đang giữ chỗ", "Holding a seat"),
                detail: holding.eventName + (holding.qty > 1 ? " ▪︎ \(holding.qty)" + app.T(" vé", " tix") : "")
                    + app.T(" ▪︎ trả để xác nhận", " ▪︎ pay to confirm"),
                countdown: Countdown.format(Countdown.secondsUntil(holding.holdExpiresAt, now: tick))
            ) { app.openPaymentDetails(holding.id, back: .home) }
        }
        if let pending = app.myPendingVerification {
            PhaseBanner(
                label: app.T("Đang chờ xác nhận", "Awaiting confirmation"),
                detail: pending.eventName + app.T(" ▪︎ đồng hồ đã dừng, chỗ được khoá", " ▪︎ clock stopped, seat locked"),
                countdown: nil
            ) { app.openPaymentDetails(pending.id, back: .home) }
        }
        if app.organizerPendingCount > 0 {
            let soonest = app.organizerSoonestVerifyDue
            let secondsLeft = Countdown.secondsUntil(soonest, now: tick)
            PhaseBanner(
                label: app.T("Chờ bạn xác nhận thanh toán", "Payments awaiting your OK"),
                detail: "\(app.organizerPendingCount)" + app.T(" khoản", app.organizerPendingCount == 1 ? " payment" : " payments")
                    + (soonest != nil ? app.T(" ▪︎ sớm nhất còn", " ▪︎ soonest in") : ""),
                countdown: soonest != nil ? Countdown.format(secondsLeft) : nil,
                urgent: soonest != nil && secondsLeft == 0
            ) { app.openVerifications() }
        }
        if let orgHolding = app.organizerHoldingSummary {
            PhaseBanner(
                label: app.T("Khách đang giữ chỗ", "Guests holding seats"),
                detail: "\(orgHolding.count)" + app.T(" chỗ", orgHolding.count == 1 ? " seat" : " seats")
                    + app.T(" ▪︎ sớm nhất hết hạn trong", " ▪︎ soonest expires in"),
                countdown: orgHolding.soonestHoldExpiresAt.map { Countdown.format(Countdown.secondsUntil($0, now: tick)) }
            ) { app.goDashboard() }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            BanbeLogo(kind: .wordmark, width: 126)
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
                    Button { app.goMapExplore() } label: {
                        Text("🗺️").font(.system(size: 15))
                    }
                    .accessibilityIdentifier("header.mapExplore")
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

    // MARK: Your events

    private var savedStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(app.T("Sự kiện của bạn", "Your events")).font(BanbeTheme.display(15))
                Spacer()
                Text(app.T("Tự xóa sau 48 giờ", "Clears after 48h")).font(.system(size: 11.5))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 10) {
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

/// One row shape for every payment-phase banner Home shows, on either side
/// of the transaction. `countdown` is optional — PHASE 2 for a buyer has
/// nothing productive to count down (their clock already stopped), so that
/// row renders with no timer rather than a fake or misleading one.
private struct PhaseBanner: View {
    @EnvironmentObject private var app: AppState
    let label: String
    let detail: String
    let countdown: String?
    var urgent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label).font(.system(size: 11.5, weight: .semibold))
                    Text(detail).font(.system(size: 12.5)).lineLimit(1)
                }
                Spacer(minLength: 8)
                if let countdown {
                    Text(countdown)
                        .font(BanbeTheme.display(18))
                        .monospacedDigit()
                        .foregroundStyle(urgent ? BanbeTheme.alert : app.palette.ink)
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(14)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
        .buttonStyle(.plain)
    }
}
