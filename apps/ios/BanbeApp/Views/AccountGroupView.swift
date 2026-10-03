import SwiftUI

/// Account IA pass (2026-09-27) — the ONE shared child screen every
/// Account group entry card opens (`app.openAccountGroup(_:)`), keyed by
/// `app.accountGroupKey`. Mirrors web's `src/screens/AccountGroup.jsx`
/// exactly — same six group keys, same relocated rows/testids/routes, so
/// the two platforms can't drift on what a given group actually contains.
/// Never a separate screen per group: six near-identical files/screens
/// for what's really one layout (a title, a back-to-Account link, and a
/// handful of EXISTING rows) would just be repetition, not a real
/// architectural need.
struct AccountGroupView: View {
    @EnvironmentObject var app: AppState

    // Kept on AppState (`accountGroupTitle(for:)`) so back-button labels
    // elsewhere can show the same text without drifting from this title.
    private var title: String { app.accountGroupTitle(for: app.accountGroupKey) }

    private var titleIcon: String {
        switch app.accountGroupKey {
        case "team": return "person.3"
        case "activity": return "calendar.badge.checkmark"
        case "payments": return "banknote"
        case "preferences": return "slider.horizontal.3"
        case "hostOps": return "checklist"
        case "adminReview": return "exclamationmark.shield"
        // 2026-10-02 fix — was missing entirely, falling to the generic
        // "circle" placeholder below; matches the Admin Team row's own
        // icon (AccountView.swift's groupCardRow call).
        case "adminTeam": return "person.3.fill"
        default: return "circle"
        }
    }

    private var completedCount: Int {
        app.completedEventsCount
    }

    var body: some View {
        ScreenScaffold {
            LazyVStack(alignment: .leading, spacing: 0) {
                Button { app.goBack() } label: {
                    Text("‹ " + app.T("Tài khoản", "Account"))
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(app.palette.ink)
                .accessibilityIdentifier("accountGroup.back")

                HStack(spacing: 10) {
                    Image(systemName: titleIcon)
                        .font(.system(size: 20, weight: .medium))
                        .frame(width: 34, height: 34)
                        .background((ROW_ACCENT_COLORS[app.accountGroupKey ?? ""] ?? .clear).opacity(0.33), in: Circle())
                    Text(title).font(BanbeTheme.display(24))
                }
                .padding(.top, 10)
                .padding(.top, 16)

                Group {
                    switch app.accountGroupKey {
                    case "team": teamContent
                    case "activity": activityContent
                    case "payments": paymentsContent
                    case "preferences": preferencesContent
                    case "hostOps": hostOpsContent
                    case "adminReview": adminReviewContent
                    case "adminTeam": adminTeamContent
                    default: EmptyView()
                    }
                }
                .padding(.top, 22)
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 60)
        }
        // Safety net (mirrors AccountView's own accountTab role-sync) — a
        // role change while this happens to be open sends it back to
        // Account rather than showing a group its role no longer has.
        .onChange(of: app.organizerMode) { _, on in
            if app.accountGroupKey == "hostOps", !on { app.screen = .profile }
        }
        .onChange(of: app.accountType) { _, type in
            if app.accountGroupKey == "adminReview", type != "admin" { app.screen = .profile }
        }
        // Admin Team pass (2026-10-02) — a direct deep link straight into
        // `accountGroupKey: "adminTeam"` (e.g. from the admin_invite_
        // response notification case) bypasses AccountView's own `.task`s;
        // idempotent re-fetch, same reasoning as `activityContent`'s own
        // "loaded elsewhere too" sources.
        .onAppear {
            if app.accountGroupKey == "adminTeam" && app.canManageAdmins {
                Task { await app.loadAdminTeam() }
            }
        }
    }

    @ViewBuilder
    private var teamContent: some View {
        if !app.myOrganizerInvites.isEmpty {
            Text(app.T("Lời mời Team", "Team Invites")).font(.system(size: 11.5, weight: .semibold))
            ForEach(app.myOrganizerInvites) { inv in
                VStack(alignment: .leading, spacing: 8) {
                    Text(app.T("\(inv.organizers?.name ?? "Một tổ chức") mời bạn làm \(inv.publicRole)", "\(inv.organizers?.name ?? "An organizer") invited you as \(inv.publicRole)"))
                        .font(.system(size: 13))
                    HStack(spacing: 8) {
                        InkButton(title: app.T("Chấp nhận", "Accept")) { Task { await app.respondToOrganizerInvite(membershipID: inv.id, accept: true) } }
                        Button(app.T("Từ chối", "Decline")) { Task { await app.respondToOrganizerInvite(membershipID: inv.id, accept: false) } }
                            .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(app.palette.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(app.palette.rule))
                    }
                }
                .padding(14)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 8)
                .accessibilityIdentifier("team.invite.\(inv.id)")
            }
        }
        if !app.myTeamMemberships.isEmpty {
            Text(app.T("Đội ngũ của tôi", "My Teams")).font(.system(size: 11.5, weight: .semibold)).padding(.top, 18)
            ForEach(app.myTeamMemberships) { m in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.organizers?.name ?? app.T("Một tổ chức", "An organizer")).font(.system(size: 13))
                        Text(m.publicRole).font(.system(size: 11)).opacity(0.65)
                    }
                    Spacer()
                    Button {
                        Task { await app.setOrganizerMemberVisibility(membershipID: m.id, visible: !m.publicVisible) }
                    } label: {
                        HStack(spacing: 6) {
                            Text(app.T("Hiển thị tôi trong Team", "Show me in the Team")).font(.system(size: 10.5))
                            ZStack(alignment: m.publicVisible ? .trailing : .leading) {
                                Capsule().fill(m.publicVisible ? app.palette.ink : app.palette.ink.opacity(0.18)).frame(width: 38, height: 22)
                                Circle().fill(app.palette.paper).frame(width: 17, height: 17).padding(2.5)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("team.membership.visibility.\(m.id)")
                }
                .foregroundStyle(app.palette.ink)
                .padding(14)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 8)
            }
        }
        if app.myOrganizerInvites.isEmpty && app.myTeamMemberships.isEmpty {
            Text(app.T("Chưa có lời mời hay Team nào.", "No invites or teams yet."))
                .font(.system(size: 13)).opacity(0.65)
        }

        // Account IA reorg (2026-09-30) — event-credit invites (organizer-
        // collaboration credits, not attendee tickets) RELOCATED here from
        // the old `activityContent` — a deliberate reclassification, not a
        // silent drop: both this and Team invites/memberships above are
        // organizer-collaboration concerns, a better semantic fit than
        // sitting alongside real attendee bookings in "Tickets & Bookings".
        // Content/identifiers unchanged from their previous location.
        if !app.myEventCredits.isEmpty {
            Text(app.T("Đóng góp sự kiện: lời mời đang chờ", "Event contributions: pending invites")).font(.system(size: 11.5, weight: .semibold)).padding(.top, 18)
            ForEach(app.myEventCredits) { c in
                VStack(alignment: .leading, spacing: 8) {
                    Text(app.T(
                        "\(c.organizers?.name ?? "Một tổ chức") ghi nhận bạn đã tổ chức \"\(c.events?.name ?? "")\"",
                        "\(c.organizers?.name ?? "An organizer") credited you for organizing \"\(c.events?.name ?? "")\""
                    )).font(.system(size: 13))
                    HStack(spacing: 8) {
                        InkButton(title: app.T("Chấp nhận", "Accept")) { Task { await app.respondToEventCredit(creditID: c.id, accept: true) } }
                        Button(app.T("Từ chối", "Decline")) { Task { await app.respondToEventCredit(creditID: c.id, accept: false) } }
                            .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(app.palette.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(app.palette.rule))
                    }
                }
                .padding(14)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 8)
                .accessibilityIdentifier("eventCredit.\(c.id)")
            }
        }
        if !app.myConfirmedEventCredits.isEmpty {
            Text(app.T("Đóng góp sự kiện: đã xác nhận", "Event contributions: confirmed")).font(.system(size: 11.5, weight: .semibold)).padding(.top, 18)
            ForEach(app.myConfirmedEventCredits) { c in
                Button { app.goEvent(c.eventId) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.events?.name ?? app.T("Một sự kiện", "An event")).font(.system(size: 13, weight: .semibold))
                            Text(c.organizers?.name ?? app.T("Một tổ chức", "An organizer")).font(.system(size: 11)).opacity(0.65)
                        }
                        Spacer(minLength: 0)
                        Text("›").font(.system(size: 18)).opacity(0.5)
                    }
                    .foregroundStyle(app.palette.ink)
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 8)
                .accessibilityIdentifier("eventCreditConfirmed.\(c.id)")
            }
        }
    }

    // Account IA reorg (2026-09-30) — Task 2b: "My Tickets" is now REAL
    // DB-backed data, reusing `app.paymentBookings` (`loadPaymentBookings()`,
    // AppState+Payments.swift) — the exact same `bookings` query
    // AccountView's own Action Center already loads (`user_id`-scoped,
    // joined to `events`/`organizers` for the real event name), not the
    // static demo catalogue and not a second divergent query. Active
    // bookings (pending/confirmed/attended) tap into `openBookingConfirmed`
    // — the same booking-id-scoped helper Confirmed's own notification-
    // reopen path already uses — which self-gates the real QR
    // (`Booking.isTicket`) vs. the "awaiting payment" state, matching Event
    // Detail's reserve bar's `openHeld` routing for whichever booking
    // happens to be current, just generalized to any booking id.
    // Cancelled/expired/no_show bookings (real `bookings.status` values,
    // confirmed in the migrations — 069/070/072/011) get their own
    // clearly labeled, non-interactive section — no fabricated "refunded"
    // bucket, since `bookings.status` has no such value.
    // Known gap vs. web: `paymentBookings`'s own query does not currently
    // select `event_date`/`event_time` (only `events(name, ...)`), so this
    // row shows event name + status only, not a date — extending that
    // shared struct's decode/CodingKeys was judged out of scope for this
    // pass (it's used by several other payment screens); flagged, not
    // silently fixed.
    @ViewBuilder
    private var activityContent: some View {
        if app.paymentsLoading && app.paymentBookings.isEmpty {
            Text(app.T("Đang tải vé của bạn…", "Loading your tickets…"))
                .font(.system(size: 13)).opacity(0.65)
        } else if app.paymentBookings.isEmpty {
            Text(app.T("Bạn chưa có vé nào.", "You don't have any tickets yet."))
                .font(.system(size: 13)).opacity(0.65)
        } else {
            let active = app.paymentBookings.filter { ["pending", "confirmed", "attended"].contains($0.status) }
            let inactive = app.paymentBookings.filter { ["cancelled", "expired", "no_show"].contains($0.status) }
            // 2026-10-02 fix — "connected account row groups": these used
            // to be N separate rounded cards with gaps between them (one
            // `.background(_, in: RoundedRectangle)` per row); grouped into
            // ONE rounded tinted container per section with subtle
            // internal `Divider`s, matching `hostOpsContent`'s/
            // `paymentsContent`'s own established styling exactly — same
            // row padding/corner radius/tap targets, just contiguous.
            if !active.isEmpty {
                Text(app.T("Vé của tôi", "My Tickets")).font(.system(size: 11.5, weight: .semibold))
                VStack(spacing: 0) {
                    ForEach(Array(active.enumerated()), id: \.element.id) { i, b in
                        Button {
                            Task { _ = await app.openBookingConfirmed(bookingID: b.id, eventKey: b.eventKey, back: .accountGroup) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(b.eventName.isEmpty ? app.T("Một sự kiện", "An event") : b.eventName).font(.system(size: 13, weight: .semibold))
                                    Text(ticketStatusLabel(b)).font(.system(size: 11)).opacity(0.85)
                                }
                                Spacer(minLength: 0)
                                Text("›").font(.system(size: 18)).opacity(0.5)
                            }
                            .foregroundStyle(app.palette.ink)
                            .padding(14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("myTicket.\(b.id)")
                        if i < active.count - 1 { Divider().overlay(app.palette.rule) }
                    }
                }
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 8)
            }
            if !inactive.isEmpty {
                Text(app.T("Đã hủy / hết hạn", "Cancelled / expired")).font(.system(size: 11.5, weight: .semibold)).padding(.top, 18)
                VStack(spacing: 0) {
                    ForEach(Array(inactive.enumerated()), id: \.element.id) { i, b in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(b.eventName.isEmpty ? app.T("Một sự kiện", "An event") : b.eventName).font(.system(size: 13, weight: .semibold))
                                Text(terminalStatusLabel(b)).font(.system(size: 11))
                            }
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(app.palette.ink)
                        .padding(14)
                        .opacity(0.65)
                        .accessibilityIdentifier("myTicketInactive.\(b.id)")
                        if i < inactive.count - 1 { Divider().overlay(app.palette.rule).opacity(0.65) }
                    }
                }
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 8)
            }
        }

        // "Sự kiện đã hoàn thành" relabeled "Sự Kiện Quá Khứ"/"Past Events"
        // for clarity — same destination (`goCompletedList`), unchanged.
        VStack(spacing: 0) {
            row(app.T("Sự Kiện Quá Khứ", "Past Events"), identifier: "account.completedList", icon: "calendar.badge.checkmark", trailing: "\(completedCount) ›") { app.goCompletedList() }
        }
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.top, 18)
    }

    private func ticketStatusLabel(_ b: PayableBooking) -> String {
        if b.isTicket { return app.T("Vé đã sẵn sàng", "Ticket ready") }
        if b.status == "attended" { return app.T("Đã tham dự", "Attended") }
        if b.paymentState == .pendingVerification { return app.T("Chờ xác nhận thanh toán", "Awaiting Verification") }
        if b.status == "pending" { return app.T("Đang giữ chỗ", "Holding") }
        return app.T("Đang xử lý", "In progress")
    }

    // 2026-10-02 fix — "truthful refund status" requirement: refund status
    // describes MONEY, not ticket validity, so it's layered on top of (not
    // instead of) the plain terminal booking status. Reuses the SAME
    // active-claim list (`app.myRefunds`, already loaded by AccountView's
    // own `.task`s) and the exact copy `MyRefundsView.statusLabel(_:)`
    // already established — never a second, independently-worded set of
    // refund strings. `app.myRefunds` only ever holds ACTIVE claims
    // (owed/host_marked_sent/disputed — `loadMyRefunds()`'s own query
    // filter) — a cancelled booking with no matching entry here either
    // never needed a refund (free/no payment) or one already completed;
    // not fabricated as "Refunded" without a real signal to confirm which.
    private func terminalStatusLabel(_ b: PayableBooking) -> String {
        let base: String
        switch b.status {
        case "cancelled": base = app.T("Đã hủy", "Cancelled")
        case "expired": base = app.T("Đã hết hạn", "Expired")
        case "no_show": base = app.T("Không tham dự", "No-show")
        default: base = b.status
        }
        guard let claim = app.myRefunds.first(where: { $0.bookingId == b.id }) else { return base }
        let refundLabel: String
        switch claim.status {
        case "owed": refundLabel = app.T("Đang chờ hoàn tiền", "Refund Pending")
        case "host_marked_sent": refundLabel = app.T("Đang chờ bạn xác nhận đã nhận tiền", "Awaiting Refund Confirmation")
        case "disputed": refundLabel = app.T("Hoàn tiền đang tranh chấp", "Refund Disputed")
        default: return base
        }
        return "\(base) ▪︎ \(refundLabel)"
    }

    @ViewBuilder
    private var paymentsContent: some View {
        VStack(spacing: 0) {
            row(app.T("Hoá đơn", "Invoices"), identifier: "account.invoices", icon: "doc.text", trailing: "›") { app.openDocuments(kind: "invoice", role: "guest") }
            Divider().overlay(app.palette.rule)
            row(app.T("Biên nhận", "Receipts"), identifier: "account.receipts", icon: "receipt", trailing: "›") { app.openDocuments(kind: "receipt", role: "guest") }
            Divider().overlay(app.palette.rule)
            // Sub-section-of-a-group back-navigation fix (2026-09-29,
            // second pass) — was `back: .profile`, skipping this group
            // page (same class of bug as `.documents`'s own fix).
            row(app.T("Tài khoản thanh toán & nhận hoàn tiền", "Payment & refund accounts"), identifier: "account.refundAccounts", icon: "banknote", trailing: "›") { app.openRefundAccounts(back: .accountGroup) }
            Divider().overlay(app.palette.rule)
            row(app.T("Hoàn tiền", "Refunds"), identifier: "account.refunds", icon: "checklist", trailing: "›", badge: AccountBadges.myRefundActionCount(myRefunds: app.myRefunds)) { app.openMyRefunds(back: .accountGroup) }
            Divider().overlay(app.palette.rule)
            HStack(spacing: 12) {
                Image(systemName: "envelope.badge")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 22, height: 22)
                    .opacity(0.72)
                Text(app.T("Gửi email chứng từ thanh toán", "Email payment documents"))
                    .font(.system(size: 14))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { app.autoEmailDocuments },
                    set: { enabled in
                        if enabled != app.autoEmailDocuments { app.toggleAutoEmailDocuments() }
                    }
                ))
                .labelsHidden()
                .toggleStyle(BanbeLiquidToggleStyle())
                .accessibilityIdentifier("account.autoEmailDocuments")
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var preferencesContent: some View {
        VStack(spacing: 0) {
            row(app.T("Ngôn ngữ & Hiển thị", "Language & Appearance"),
                identifier: "account.preferences", icon: "slider.horizontal.3",
                trailing: "›") {
                app.openPreferences()
            }
            Divider().overlay(app.palette.rule)
            row(app.T("Bảo mật", "Security"), identifier: "account.security", icon: "lock.shield", trailing: "›") { app.openSecurity() }
        }
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

        // Account deletion (Task 2, Account/Settings pass) — a visually
        // separated "Account Management" subsection, per this ticket's own
        // placement instruction (distinct from the rows above and from
        // Sign Out on the parent AccountView). Reuses `BanbeTheme.alert` —
        // no new color introduced.
        VStack(alignment: .leading, spacing: 8) {
            Text(app.T("Quản Lý Tài Khoản", "Account Management"))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(app.palette.ink)
                .padding(.top, 24)

            Button { app.deleteAccountOpen = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.shield").font(.system(size: 16, weight: .medium)).frame(width: 22, height: 22)
                    Text(app.T("Xóa Tài Khoản", "Delete Account")).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text("›").font(.system(size: 15))
                }
                .foregroundStyle(BanbeTheme.alert)
                .padding(16)
                .background(BanbeTheme.alert.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(BanbeTheme.alert.opacity(0.35), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("account.deleteRow")
        }
    }

    @ViewBuilder
    private var hostOpsContent: some View {
        VStack(spacing: 0) {
            // Sub-section-of-a-group back-navigation fix (2026-09-29,
            // second pass) — was the default `back: .profile`, skipping
            // this group page.
            // FIX PASS (2026-09-30) — badge parity with this group's own
            // entry card (AccountView.swift's "Vận hành & thanh toán tổ
            // chức"), same rule the "Pending events" row below already
            // established: both verifications AND refundQueue land on
            // THIS exact screen (openVerifications), so this row's badge
            // is the same sum, not a second independently-derived count.
            row(app.T("Chờ xác nhận thanh toán", "Awaiting Verification"), identifier: "host.verifications", icon: "checklist", trailing: "›", badge: AccountBadges.hostActionCount(organizerMode: app.organizerMode, verificationsCount: app.verifications.count, refundQueue: app.refundQueue)) { app.openVerifications(back: .accountGroup) }
            Divider().overlay(app.palette.rule)
            // Refund-discoverability fix — refunds previously only lived
            // inside the row above, with no mention of the word "refund"
            // anywhere in this group's own labels. Same screen/data
            // (openVerificationsRefunds just adds a one-shot scroll flag to
            // the SAME openVerifications() call), own badge
            // (AccountBadges.refundActionCount — the same refundQueue.count
            // term the row above's own sum already includes).
            row(app.T("Hoàn tiền", "Refunds"), identifier: "host.refunds", icon: "banknote", trailing: "›", badge: AccountBadges.refundActionCount(organizerMode: app.organizerMode, refundQueue: app.refundQueue)) { app.openVerificationsRefunds(back: .accountGroup) }
            Divider().overlay(app.palette.rule)
            // 2026-10-02 fix — was "banknote", a duplicate of "Refunds"
            // directly above in this SAME container; a distinct glyph.
            row(app.T("Nhận thanh toán", "Getting Paid"), identifier: "host.payout", icon: "creditcard", trailing: "›") { app.openPayout() }
            Divider().overlay(app.palette.rule)
            row(app.T("Hoá đơn đã phát hành", "Invoices Issued"), identifier: "host.invoices", icon: "doc.text", trailing: "›") { app.openDocuments(kind: "invoice", role: "host") }
            Divider().overlay(app.palette.rule)
            row(app.T("Biên nhận đã phát hành", "Receipts Issued"), identifier: "host.receipts", icon: "receipt", trailing: "›") { app.openDocuments(kind: "receipt", role: "host") }
        }
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // Parity fix (2026-09-30) — web has a dedicated "Tranh chấp thanh
    // toán"/"Payment disputes" row (`openDisputes`, routing to
    // `Disputes.jsx`); iOS never had a standalone disputes screen or
    // `openDisputes` action at all — its dispute desk has always lived
    // INSIDE `AdminDashboardView` (see that file's own "iOS counterpart of
    // src/screens/Disputes.jsx" comment, `app.adminDisputes`/
    // `loadAdminDisputes()`). Rather than inventing a new `openDisputes`
    // action or a second dispute-viewing screen, this row reuses the
    // EXACT existing destination (`app.openAdminDashboard()`) — the real
    // screen where iOS disputes already live — closing the visible-row
    // parity gap without adding new dispute logic. "Bảng quản trị"/"Admin
    // Panel" below still opens the same screen for its other admin tools;
    // both rows are legitimately two doors into one destination, not a
    // duplicate feature.
    // 2026-10-02 fix — all three rows used the identical "exclamationmark.
    // shield" glyph, with no visual way to tell them apart at a glance;
    // each now has its own distinct icon (destinations/badges unchanged).
    @ViewBuilder
    private var adminReviewContent: some View {
        VStack(spacing: 0) {
            row(app.T("Tranh Chấp Thanh Toán", "Payment Disputes"), identifier: "admin.disputes", icon: "exclamationmark.bubble", trailing: "›") { app.openAdminDashboard() }
            Divider().overlay(app.palette.rule)
            row(app.T("Sự Kiện Chờ Duyệt", "Pending Events"), identifier: "admin.events", icon: "exclamationmark.shield", trailing: "›", badge: app.pendingEventsCount) { app.openAdminEvents() }
        }
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // Admin Team pass (2026-10-02, migration 121) — reusing proven
    // organizer-invitation MECHANICS (accept/decline shape straight above,
    // `teamContent`) but NOT its permissions: this view never lets a
    // client write `role`/`can_manage_admins` directly — every control
    // below calls a server RPC that enforces its own authorization, this
    // UI only reflects the result.
    @ViewBuilder
    private var adminTeamContent: some View {
        if let invite = app.myAdminInvite {
            Text(app.T("Lời mời quản trị", "Admin Invite")).font(.system(size: 11.5, weight: .semibold))
            VStack(alignment: .leading, spacing: 8) {
                Text(app.T("Bạn được mời trở thành quản trị viên banbe.", "You've been invited to become a banbe admin."))
                    .font(.system(size: 13))
                HStack(spacing: 8) {
                    InkButton(title: app.T("Chấp nhận", "Accept")) { Task { await app.respondToAdminInvite(inviteID: invite.id, accept: true) } }
                    Button(app.T("Từ chối", "Decline")) { Task { await app.respondToAdminInvite(inviteID: invite.id, accept: false) } }
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(app.palette.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(app.palette.rule))
                }
            }
            .padding(14)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.top, 8)
            .accessibilityIdentifier("adminInvite.\(invite.id)")
        }

        if app.accountType == "admin" && !app.canManageAdmins {
            Text(app.T("Bạn không có quyền quản lý đội ngũ quản trị.", "You don't have permission to manage the admin team."))
                .font(.system(size: 13)).opacity(0.65).padding(.top, 18)
                .accessibilityIdentifier("adminTeam.noPermission")
        }

        if app.canManageAdmins {
            Text(app.T("Mời Quản Trị Viên", "Invite Admin")).font(.system(size: 11.5, weight: .semibold)).padding(.top, 18)
            VStack(alignment: .leading, spacing: 8) {
                TextField(app.T("Email người được mời", "Invitee's email"), text: $app.adminInviteEmailDraft)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.system(size: 13.5)).padding(10)
                    .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(app.palette.rule))
                    .accessibilityIdentifier("adminTeam.emailInput")
                if !app.adminInviteError.isEmpty {
                    Text(app.adminInviteError).font(.system(size: 12)).foregroundStyle(BanbeTheme.alert)
                }
                if let confirmEmail = app.adminInviteConfirmEmail {
                    Text(app.T("Mời \(confirmEmail) làm quản trị viên banbe?", "Invite \(confirmEmail) as a banbe admin?"))
                        .font(.system(size: 12.5))
                    HStack(spacing: 8) {
                        InkButton(title: app.adminInviteBusy ? app.T("Đang gửi…", "Sending…") : app.T("Xác nhận mời", "Confirm invite")) {
                            Task { await app.confirmAdminInvite() }
                        }
                        .opacity(app.adminInviteBusy ? 0.6 : 1)
                        .disabled(app.adminInviteBusy)
                        Button(app.T("Huỷ", "Cancel")) { app.cancelAdminInviteConfirm() }
                            .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(app.palette.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(app.palette.rule))
                    }
                } else {
                    InkButton(title: app.T("Mời", "Invite")) { app.requestAdminInviteConfirm() }
                        .accessibilityIdentifier("adminTeam.inviteSubmit")
                }
            }
            .padding(14)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.top, 8)

            let pendingInvites = app.adminInvites.filter { $0.status == "pending" }
            if !pendingInvites.isEmpty {
                Text(app.T("Lời Mời Đang Chờ", "Pending Invites")).font(.system(size: 11.5, weight: .semibold)).padding(.top, 18)
                ForEach(pendingInvites) { inv in
                    HStack {
                        Text(inv.invitedEmail).font(.system(size: 13)).lineLimit(1)
                        Spacer(minLength: 8)
                        if app.revokeAdminInviteConfirmID == inv.id {
                            HStack(spacing: 8) {
                                Button(app.T("Thu hồi?", "Revoke?")) { Task { await app.confirmRevokeAdminInvite() } }
                                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(BanbeTheme.alert)
                                Button(app.T("Huỷ", "Cancel")) { app.cancelRevokeAdminInviteConfirm() }
                                    .font(.system(size: 12)).foregroundStyle(app.palette.ink.opacity(0.6))
                            }
                        } else {
                            Button(app.T("Thu hồi", "Revoke")) { app.requestRevokeAdminInviteConfirm(inv.id) }
                                .font(.system(size: 12)).foregroundStyle(app.palette.ink.opacity(0.6))
                        }
                    }
                    .foregroundStyle(app.palette.ink)
                    .padding(14)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.top, 8)
                    .accessibilityIdentifier("adminInviteRow.\(inv.id)")
                }
            }

            Text(app.T("Quản Trị Viên Hiện Tại", "Current Admins")).font(.system(size: 11.5, weight: .semibold)).padding(.top, 18)
            ForEach(app.adminRoster) { a in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text((a.displayName?.isEmpty == false ? a.displayName! : app.T("(Chưa đặt tên)", "(No name set)")) + (a.isSelf ? app.T(" (bạn)", " (you)") : ""))
                            .font(.system(size: 13))
                        if a.canManageAdmins {
                            Text(app.T("Có quyền quản lý đội ngũ", "Can manage the admin team")).font(.system(size: 10.5)).opacity(0.6)
                        }
                    }
                    Spacer(minLength: 8)
                    if !a.isSelf {
                        if app.revokeAdminConfirmID == a.id {
                            HStack(spacing: 8) {
                                Button(app.T("Thu hồi?", "Revoke?")) { Task { await app.confirmRevokeAdmin() } }
                                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(BanbeTheme.alert)
                                Button(app.T("Huỷ", "Cancel")) { app.cancelRevokeAdminConfirm() }
                                    .font(.system(size: 12)).foregroundStyle(app.palette.ink.opacity(0.6))
                            }
                        } else {
                            Button(app.T("Thu hồi quyền", "Revoke")) { app.requestRevokeAdminConfirm(a.id) }
                                .font(.system(size: 12)).foregroundStyle(app.palette.ink.opacity(0.6))
                        }
                    }
                }
                .foregroundStyle(app.palette.ink)
                .padding(14)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 8)
                .accessibilityIdentifier("adminRosterRow.\(a.id)")
            }
        }

        if app.myAdminInvite == nil && app.accountType != "admin" {
            Text(app.T("Không có gì ở đây.", "Nothing here.")).font(.system(size: 13)).opacity(0.65)
        }
    }

    // TASK 5 real-device follow-up — `badge` (0 = hidden) so a child row
    // (e.g. "Pending events") can show the SAME real count its own
    // group-entry card already does — same capsule style `groupCard`
    // (AccountView.swift) uses, capped at "99+" with the full count kept
    // in the accessibility label.
    private func row(_ title: String, identifier: String? = nil, icon: String, trailing: String, badge: Int = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 22, height: 22)
                    .opacity(0.72)
                Text(title).font(.system(size: 14))
                Spacer()
                if badge > 0 {
                    Text(badge > 99 ? "99+" : "\(badge)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(app.palette.paper)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(BanbeTheme.alert, in: Capsule())
                        .accessibilityLabel(app.T("\(badge) mục mới", "\(badge) new item(s)"))
                }
                Text(trailing).font(.system(size: 13))
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 16).padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier ?? title)
    }
}
