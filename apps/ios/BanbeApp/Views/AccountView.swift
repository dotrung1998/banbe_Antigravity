import SwiftUI
import PhotosUI

/// Color-as-wayfinding pass (2026-09-27) — a restrained accent, reusing
/// the SAME existing profile-palette tokens (`ProfilePalette`,
/// EditProfileView.swift — already how the personal/organizer card washes
/// tell those two apart) rather than a new/arbitrary color set. Mirrors
/// web's `ROW_ACCENT_COLORS` (Account.jsx) value-for-value. Not `private`
/// — AccountGroupView.swift's own title icon reads this too.
let ROW_ACCENT_COLORS: [String: Color] = [
    "team": ProfilePalette.all.first { $0.key == "moss" }!.color,
    "activity": ProfilePalette.all.first { $0.key == "rose" }!.color,
    "payments": ProfilePalette.all.first { $0.key == "sand" }!.color,
    "preferences": ProfilePalette.all.first { $0.key == "ink" }!.color,
    "hostOps": ProfilePalette.all.first { $0.key == "moss" }!.color,
    "adminReview": ProfilePalette.all.first { $0.key == "rose" }!.color,
    // 2026-10-02 fix — standalone screens reached from an Account row but
    // not themselves an `accountGroupKey` (Reports, Getting Paid, Refunds/
    // refund accounts, Security, Organizer Team) each get the SAME accent
    // their own entry row already uses, so their own header icon (added
    // below) reads as part of one consistent color scheme, never a new
    // ad-hoc color per screen.
    "reports": ProfilePalette.all.first { $0.key == "moss" }!.color,
    // 2026-10-02 fix — was "ink" (a dark neutral), which at 0.33 opacity
    // renders as a plain GRAY circle — reading as "no color"/missing,
    // not a real accent. "sand" is a genuinely visible, distinct hue.
    "adminTeam": ProfilePalette.all.first { $0.key == "sand" }!.color,
]

/// Port of src/screens/Account.jsx — profile header with rename, the
/// going/saved counters, links to messages and preferences, the organizer
/// mode switch, and sign in/out.
struct AccountView: View {
    @EnvironmentObject var app: AppState
    // Task 3 (07-notifications.md) — story creation, hosts only.
    // TASK 1 (dock "+" native-menu pass) — the three trigger flags this
    // used to own as local @State (storyPhotoItem/storyCameraOpen/
    // storyLibraryPickerOpen) moved to AppState (see its own comment)
    // so the dock "+" menu can drive the same picker/camera/preview
    // pipeline from a different screen entirely. The "PhotosPicker inside
    // Menu swallowing taps" constraint that originally motivated the
    // flag-flip indirection (below, `account.postStory`'s Menu rows just
    // set `app.storyLibraryPickerOpen`/`app.storyCameraOpen`) still holds
    // — only WHERE the flags live changed, not how they're used.
    // iPhone fix pass (2026-09-27), Issue 1 — same "flash the one row a
    // notification pointed at" convention AttendanceView's own
    // highlightedGuestID already establishes (app.attendanceHighlightBookingID).
    // Local, view-only flash state; app.teamInviteHighlightOrganizerId/
    // eventCreditHighlightId (AppState.swift) are cleared the instant
    // they're consumed here so a later, unrelated visit never re-triggers.
    @State private var highlightedTeamInviteOrganizerId: String?
    @State private var highlightedEventCreditId: UUID?

    // Stage D (2026-09-26) — Cá nhân/Tổ chức top-level tabs. Purely a
    // display switch (`if app.accountTab == ...` below) — never calls
    // toggleOrganizerMode or any hosting-mode side effect by itself.
    // Simplification disclosed vs. web: each tab does NOT get its own
    // independently-preserved scroll position here — this screen's
    // existing scroll-restore mechanism (`accountScrollAnchorID`, see its
    // own doc comment above) is a single shared anchor across the whole
    // LazyVStack, and giving each tab its own would mean a second,
    // parallel scroll-tracking system; not built this pass.
    // Lifted to AppState — see its own `app.accountTab` doc comment.

    private var myStoryGroup: StoryGroup? {
        app.homeStories.first { g in app.myOrganizerIdsCache.contains(g.organizerId) }
    }

    /// TASK A (2026-10-01 UX foundation pass) — mirrors HomeView's own
    /// `actionItems`; Account loads the same canonical sources independently
    /// (see the `.task` below) so this reflects live server state even when
    /// opened without visiting Home first this session.
    /// Goer-side items belong to Personal; host-side items belong to the
    /// Host tab. While the Host tab is hidden (organizerMode off) they stay
    /// on Personal so owed money is never silently hidden.
    private var goerActionItems: [ActionCenterItem] {
        sortActionCenterItems(buildActionCenterItems(ActionCenterInputs(
            role: .goer, now: Date(),
            myHolding: app.myHolding, myPendingVerification: app.myPendingVerification, myRefunds: app.myRefunds,
            refundDestinations: app.refundDestinationsLoaded ? app.refundDestinations : nil,
            onOpenPayment: { app.openPaymentDetails($0, back: .profile) },
            onOpenMyRefunds: { app.openMyRefunds(back: .profile) },
            onOpenRefundAccounts: { app.openRefundAccounts(back: .profile) },
            // "Refund dispute open › View" goes to the booking conversation
            // that dispute actually belongs to, with its card expanded.
            onOpenRefundDispute: { claimID, back in app.openRefundDisputeFromActionCenter(claimID: claimID, back: back) },
            T: app.T
        )))
    }

    private var hostActionItems: [ActionCenterItem] {
        guard app.canHost else { return [] }
        return sortActionCenterItems(buildActionCenterItems(ActionCenterInputs(
            role: .host, now: Date(),
            verifications: app.verifications, refundQueue: app.refundQueue, orgHolding: app.organizerHoldingSummary,
            onOpenVerifications: { app.openVerifications(back: .profile) },
            onOpenRefundCenter: { app.openVerifications(back: .profile) },
            onOpenDashboard: { app.goDashboard() },
            onOpenAttendance: { key in app.openAttendance(key, back: .profile) },
            // Same single-dispute shortcut as the goer half, so the host's own
            // link reaches the same dispute the goer's does.
            onOpenRefundDispute: { claimID, back in app.openRefundDisputeFromActionCenter(claimID: claimID, back: back) },
            T: app.T
        )))
    }

    private var actionItems: [ActionCenterItem] {
        app.organizerMode ? goerActionItems : sortActionCenterItems(goerActionItems + hostActionItems)
    }

    // TASK B (2026-10-03 fix pass) — current UI mode (organizerMode), not
    // eligibility (canHost) — see AppState+Data.swift's applyOrganizerMode
    // doc comment for the full root-cause writeup.
    private var subtitle: String {
        if app.accountType == "admin" { return app.T("Quản trị viên", "Admin") }
        return app.organizerMode ? app.T("Người tham gia ▪︎ Người tổ chức", "Goer ▪︎ Host")
                           : app.T("Người tham gia", "Goer")
    }

    // TASK C — reuses the exact same mechanism HomeView already established
    // (ScreenScaffold's own scrollPositionID binding, see its doc comment)
    // rather than a second, incompatible scroll-tracking system: a
    // `@Published` id binding on AppState survives this View being torn
    // down/recreated on navigation, and `.scrollPosition(id:)` is
    // bidirectional — it both records which id is at top as the user
    // scrolls AND scrolls back to it once a non-nil binding is set again.
    // First-open-at-top happens for free: the binding starts `nil` and is
    // only ever set by the user's own scrolling, never by any of this
    // screen's data loads.
    @State private var didAttemptScrollRestore = false
    // Search state lives on AppState (not here): this screen is rebuilt when you
    // come back from a result, and going back must land on the same results.
    private var searchOpen: Bool { app.accountSearchOpen }
    private var searchQuery: String { app.accountSearchQuery }
    @FocusState private var searchFocused: Bool
    @State private var imageCacheClearedAt: Date?

    var body: some View {
        // Pull-to-refresh header fix (2026-09-29 follow-up) — Messages'
        // header (title + icon buttons) never moves during a pull-to-refresh,
        // only its List shifts/reveals the indicator underneath; Account's
        // title row used to be the FIRST item inside `accountContent`, i.e.
        // inside the very content `ScreenScaffold` offsets while pulling, so
        // it visibly slid down too. `accountHeader` is now a true sibling,
        // above `ScreenScaffold` entirely, exactly like InboxView's own
        // `VStack { header; List {...} }` shape — only the Personal/Host/
        // Admin tab pills and everything below now belong to the scrollable,
        // offsettable content.
        // Opaque-header fix (2026-09-29 follow-up, real-device report:
        // overlapping headers during a swipe-back transition) — see
        // HomeView's own identical fix for the full explanation:
        // `accountHeader` lost the opaque `app.palette.paper` background it
        // used to inherit for free from being inside `ScreenScaffold`.
        ZStack {
            app.palette.paper.ignoresSafeArea()
        VStack(alignment: .leading, spacing: 0) {
            accountHeader
            // Fixed-header pass (2026-10-02) — tabs used to be the FIRST
            // row inside `accountContent`'s own LazyVStack, i.e. inside the
            // scrollable `ScreenScaffold` content: scrolling the Personal/
            // Host/Admin body carried the tab pills away with it, so
            // switching tabs required scrolling back to the top first.
            // Pulled out as a second fixed sibling (same mechanism/doc
            // comment as `accountHeader` just above) — only the selected
            // tab's own body, inside ScreenScaffold, scrolls now.
            // Search spans every tab, so the tab pills are hidden while it's open.
            if !searchOpen { accountTabsBar }
            ScreenScaffold(tracksBottomBarScroll: true, scrollPositionID: accountScrollAnchorBinding, refreshIndicatorTopPadding: 24, onRefresh: {
                guard app.userID != nil else { return }
                await app.loadPaymentBookings()
                await app.loadMyRefunds()
                if app.canHost {
                    await app.loadVerifications()
                    await app.loadMyOrgEventSummaries()   // for the "Submitted events" card
                    await app.loadOrganizerHoldingSummary()
                    await app.loadRefundQueue()
                    if app.myOrganizerID != nil { await app.loadMyOrgStats() }
                }
            }) {
                if searchOpen { accountSearchResults } else { accountContent }
            }
        }
        }
        .task { if app.userID != nil { await app.loadHomeStories() } }
        .task { if app.userID != nil { await app.loadMyOrganizerMemberships() } }
        // Admin Team pass (2026-10-02) — this account's own pending admin
        // invite (reachable regardless of role) and, for a manage-admins-
        // capable admin, the roster/invites source for the Admin-tab
        // badge — same "load it here so the badge is real, not stale"
        // reasoning as pendingEventsCount below.
        .task { if app.userID != nil { await app.loadMyAdminInvite() } }
        .task { if app.canManageAdmins { await app.loadAdminTeam() } }
        .task { if app.userID != nil { await app.loadMyEventCredits() } }
        .task { if app.userID != nil { await app.loadMyConfirmedEventCredits() } }
        // TASK A (2026-10-01 UX foundation pass) — same canonical loaders
        // HomeView's own `.task` calls.
        .task {
            guard app.userID != nil else { return }
            await app.loadPaymentBookings()
            await app.loadMyRefunds()
            await app.loadRefundDestinations()
            if app.canHost {
                await app.loadVerifications()
                await app.loadOrganizerHoldingSummary()
                await app.loadRefundQueue()
            }
            // TASK 5 (Account badges pass) — same "load it here so the
            // group-entry badge is real, not stale" reasoning as
            // verifications/refundQueue above, gated on the actual admin
            // role (RLS-backed), not a UI toggle.
            if app.isAdmin { await app.loadPendingEventsCount() }
        }
        // Host duties (held seats, verifications, refunds) are re-read every time
        // the Host tab is shown, so a seat the goer lost or the host cancelled
        // stops showing without a manual pull to refresh.
        .task(id: app.accountTab) {
            guard app.userID != nil, app.canHost, app.accountTab == "host" else { return }
            await app.loadMyOrgEventSummaries()   // for the "Submitted events" card
            await app.loadOrganizerHoldingSummary()
            await app.loadVerifications()
            await app.loadRefundQueue()
        }
        // Stage 1 — re-run whenever this account's organizer id becomes
        // known (session restore, or right after creating a first event)
        // so the host card's real published-event stats reflect the
        // latest admin approval/cancellation, not a stale snapshot.
        .task(id: app.myOrganizerID) {
            if app.canHost, app.myOrganizerID != nil { await app.loadMyOrgStats(); await app.loadMyOrgEventSummaries() }   // summaries feed the Host tab's badge
        }
        .onAppear { retryScrollRestoreIfNeeded(); syncAccountTabToRole(); consumeTeamHighlightsIfNeeded() }
        .onChange(of: app.teamInviteHighlightOrganizerId) { _, _ in consumeTeamHighlightsIfNeeded() }
        .onChange(of: app.eventCreditHighlightId) { _, _ in consumeTeamHighlightsIfNeeded() }
        // Account extension (2026-09-27, Stage 1/2) — a role change
        // (organizer mode toggled off elsewhere, an admin demoted, an
        // account switch) can leave `app.accountTab` pointing at a tab
        // that's no longer in `accountTabs`; the toggle's own redirect
        // (AppState+Data.swift, applyOrganizerMode) covers the direct
        // toggle path, this is the general safety net for every other one.
        .onChange(of: app.organizerMode) { _, _ in syncAccountTabToRole() }
        .onChange(of: app.accountType) { _, _ in syncAccountTabToRole() }
        // TASK 1 (dock "+" native-menu pass) — the `.photosPicker`/
        // `.fullScreenCover` presentation for story creation (and the
        // BottomTabBarOverlay force-hide while any of it is up) is now
        // centralized in RootView, since the dock "+" menu can trigger the
        // same flags from outside this screen. See RootView's own comment.
    }

    /// Pulled out of `accountContent` (2026-09-29 follow-up) so it's a fixed
    /// sibling above `ScreenScaffold`, not part of the content that shifts
    /// during a pull-to-refresh. Carries its own copy of `accountContent`'s
    /// shared `foregroundStyle`/`padding` since it's no longer inside that
    /// modifier chain.
    private var accountHeader: some View {
        // Alignment changed from `.firstTextBaseline` to `.center`
        // (2026-09-29 follow-up, wordmark doubled in size) — baseline
        // alignment anchors the wordmark's bottom to the title's text
        // baseline, so a taller wordmark pushes upward and can clip
        // against the row's top; centering keeps the title and "Done"
        // button fully visible at any wordmark size, matching
        // Messages/Notifications which already use `.center` here.
        HStack(alignment: .center) {
            // "banbe" wordmark parity fix (2026-09-29, follow-up:
            // placed BEFORE the title, inline in the same row — not
            // as its own row above it) — matches Home's own header
            // wordmark (HomeView.swift); Notifications/Messages got
            // the same addition in this pass.
            if searchOpen {
                TextField(app.T("Tìm trong tài khoản…", "Search Account…"), text: $app.accountSearchQuery)
                    .font(.system(size: 13.5))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(app.palette.field, in: Capsule())
                    .foregroundStyle(app.palette.ink)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("account.searchInput")
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                BanbeLogo(kind: .wordmark, width: BanbeLogo.headerWordmarkWidth)
                Text(app.T("Tài khoản", "Account")).font(BanbeTheme.display(27))
                Spacer()
            }
            // Search (replaces "Done") — same icon-over-label button as
            // Messages/Notifications.
            SwipeSafeButton {
                if app.accountSearchOpen { app.accountSearchQuery = "" }
                withAnimation(.easeInOut(duration: 0.22)) { app.accountSearchOpen.toggle() }
                searchFocused = app.accountSearchOpen
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: searchOpen ? "xmark" : "magnifyingglass")
                        .font(.system(size: 14))
                        .frame(width: 34, height: 34)
                        .background(app.palette.field, in: Circle())
                    Text(searchOpen ? app.T("Đóng", "Close") : app.T("Tìm", "Search"))
                        .font(.system(size: 9.5)).opacity(0.7)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("account.searchToggle")
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    /// Fixed-header pass (2026-10-02) — extracted out of `accountContent`
    /// (see `body`'s own call-site comment) so switching tabs never
    /// requires scrolling back to the top first. Same tab-button model
    /// (`accountTabs`/`accountTabButton`) and `app.accountTab` state,
    /// unchanged — purely a layout move, no new tab/navigation system.
    private var accountTabsBar: some View {
        HStack(spacing: 6) {
            ForEach(accountTabs, id: \.0) { key, label, badge in
                accountTabButton(key: key, label: label, badge: badge)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(app.palette.paper)
    }

    private var accountContent: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            // iPhone fix pass (2026-09-26) — this personal identity
            // card (and its story ring/"Đổi tên") used to render
            // regardless of `app.accountTab`, so it also showed on Tổ chức,
            // right above that tab's own separate organizer card — two
            // profile cards on one screen. Scoped to the Cá nhân tab
            // only, matching the web fix.
            if app.accountTab == "personal" {
            // Account IA pass (2026-09-27) — identity card FIRST under
            // the tab pills (was: reports row, then Team invites/
            // memberships/event-credit content, THEN this card). Those
            // moved into the "team"/"activity" AccountGroupView children
            // below — only their pending COUNTS surface here now
            // (groupCard's `badge`).
            // TASK D (2026-10-01 UX foundation pass) — the header is
            // now a tappable rounded profile card (editorial style:
            // soft gradient wash from the account's own chosen
            // palette). The story ring/post-story menu keep their own
            // existing nested tap targets unchanged — a separate
            // trailing chevron (not the whole card) opens EditProfile.
            HStack(spacing: 14) {
                // The story ring lives on the Host card (stories are a host
                // feature) — this personal avatar is just the picture.
                Group {
                    if let urlStr = app.user?.avatarURL, let url = URL(string: urlStr) {
                        AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                            .frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        Text(String(app.displayName.prefix(1)).uppercased())
                            .font(BanbeTheme.display(22))
                            .frame(width: 56, height: 56)
                            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(app.displayName).font(BanbeTheme.display(22)).lineLimit(1)
                        if app.isSignedIn {
                            SwipeSafeButton {
                                app.goEditName()
                            } label: {
                                Label(app.T("Đổi tên", "Rename"), systemImage: "pencil")
                                    .labelStyle(.titleAndIcon)
                            }
                            .font(.system(size: 11.5))
                            .foregroundStyle(app.palette.ink.opacity(0.65))
                            .buttonStyle(.plain)
                        }
                    }
                    if let handle = app.user?.handle, !handle.isEmpty {
                        Text("@\(handle)").font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.7))
                    }
                    Text(subtitle).font(.system(size: 11)).kerning(0.6)
                    // Story posting moved to the Host tab (hostStoryAndShareCard).
                }
                Spacer(minLength: 0)
                if app.isSignedIn {
                    // iPhone fix pass — this used to open EditProfile
                    // directly; it now opens the same public profile
                    // page anyone else sees at this account's own
                    // handle (`isOwnProfile` there is what surfaces its
                    // own "Chỉnh sửa hồ sơ" row) — editing is one tap
                    // further in, not the arrow's own destination.
                    SwipeSafeButton {
                        if let handle = app.user?.handle, !handle.isEmpty {
                            app.openPublicProfile(handle: handle, back: .profile)
                        }
                    } label: {
                        Image(systemName: "chevron.right").font(.system(size: 16)).foregroundStyle(app.palette.ink.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("account.editProfile")
                }
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: [(ProfilePalette.all.first { $0.key == (app.user?.profileTheme ?? "default") }?.color ?? ProfilePalette.all[0].color).opacity(0.35), .clear],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(app.palette.rule, lineWidth: 1))
            .padding(.top, 22)
            .accessibilityIdentifier("account.profileCard")
            shareCardCTA(host: false)
            } // app.accountTab == "personal" (profile card)

            if app.accountTab == "personal" {
            // Account IA reorder pass (2026-09-30 second) — mirrors web's
            // Account.jsx target order exactly: same product hypothesis on
            // common task frequency (ticket/booking access, then payments,
            // then settings, then hosting, then admin) — NOT measured
            // banbe usage data, none exists to cite.
            sectionHeader(app.T("Hoạt Động Của Bạn", "Your Activity"))
                .accessibilityIdentifier("account.section.activity")

            // TASK A (2026-10-01 UX foundation pass) — same canonical
            // Action Center Home/Dashboard show; Account is one of its
            // three placements.
            ActionCenterView(items: actionItems, onSeeAll: { app.openVerifications(back: .profile) })

            // Relabeled "Vé & Hoạt Động"/"Tickets & Activity" -> "Vé & Đặt
            // Chỗ"/"Tickets & Bookings"; `groupKey` stays "activity" (route/
            // identifier unchanged). Badge is now the real count of this
            // account's own holding/awaiting-payment/pending-verification
            // bookings (`AccountBadges.myTicketsActionCount`, reading the
            // SAME `paymentBookings` array already loaded for the Action
            // Center above — no new query).
            // 2026-10-02 fix — these four used to be four separate floating
            // cards with gaps between them; same grouping styling as
            // "Event Operations & Payments" now applies here too — one
            // contiguous container, same content/order/routes/badges.
            groupedContainer {
                groupCardRow(groupKey: "activity", icon: "calendar.badge.checkmark", label: app.T("Vé & Đặt Chỗ", "Tickets & Bookings"), badge: AccountBadges.myTicketsActionCount(paymentBookings: app.paymentBookings))
                groupDivider()
                HStack(spacing: 0) {
                    // 2026-10-02 fix — was "calendar.badge.checkmark", the
                    // exact same glyph the "Tickets & Bookings" row directly
                    // above already uses in this same container; a distinct
                    // glyph instead (still legible as "confirmed/going").
                    counterGroupRow(value: app.goingEventsCount, label: app.T("Đang tham gia", "Going"), icon: "checkmark.circle", identifier: "account.goingCard") { app.goGoingList() }
                    groupDivider()
                    // Relabeled "Đã lưu"/"Saved" (generic) -> "Sự Kiện Đã Lưu"/
                    // "Saved Events"; destination/identifier unchanged.
                    counterGroupRow(value: app.favorites.count, label: app.T("Sự Kiện Đã Lưu", "Saved Events"), icon: "bookmark", identifier: "account.savedCard") { app.goSavedList() }
                }
                .id("account-stats")
                groupDivider()
                groupCardRow(groupKey: "payments", icon: "banknote", label: app.T("Thanh Toán & Giấy Tờ", "Payments & Documents"), badge: AccountBadges.myRefundActionCount(myRefunds: app.myRefunds))
                groupDivider()
                reportsGroupRow(app.T("Số Liệu & Báo Cáo", "Metrics & Reports"), identifier: "account.reportsPersonal") {
                    app.openReports(scope: "personal", back: .profile)
                }
            }
            .padding(.top, 14)

            // Account IA reorder pass (2026-09-30 second) — second cluster:
            // account-level settings. The `team` group card used to always
            // render here — REMOVED wholesale (not simply moved into
            // Hosting): a user can receive a co-organizer invite before
            // ever turning Hosting Mode on, and hiding the ONLY entry point
            // to that invite behind the Hosting toggle would strand them.
            // Instead: (a) the Host tab now has its own entry point into
            // the SAME "team" screen (see hostManagementRows below — same
            // "two doors, one destination" pattern already used for the
            // Payment Disputes row), and (b) the lightweight conditional
            // row below surfaces the SAME destination here ONLY when
            // there's a real pending invite AND Hosting is off — mutually
            // exclusive with the Host-tab card (accountTab can never be
            // "host" while organizerMode is false — see the tab-list
            // filter/redirect elsewhere in this file), so neither ever
            // double-counts.
            sectionHeader(app.T("Tài Khoản & Cài Đặt", "Account & Settings"), topPadding: 22)
                .accessibilityIdentifier("account.section.settings")

            // 2026-10-02 fix — same grouping as the Activity cluster above:
            // these three were separate floating cards, now one contiguous
            // container. Content/routes/identifiers unchanged.
            groupedContainer {
                SwipeSafeButton {
                    if let handle = app.user?.handle, !handle.isEmpty {
                        app.openPublicProfile(handle: handle, back: .profile)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle").font(.system(size: 16, weight: .medium)).frame(width: 22, height: 22).opacity(0.72)
                        Text(app.T("Hồ Sơ Cá Nhân", "Personal Profile")).font(.system(size: 14))
                        Spacer()
                        Text("›").font(.system(size: 15)).opacity(0.85)
                    }
                    .foregroundStyle(app.palette.ink)
                    .padding(.horizontal, 16).padding(.vertical, 15)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("account.personalProfile")
                groupDivider()
                // App Preferences is the destination name for language,
                // appearance, and Liquid Glass controls.
                // (reads more accurately for its actual contents). `groupKey`/
                // identifier/route unchanged.
                groupCardRow(groupKey: "preferences", icon: "slider.horizontal.3", label: app.T("Tùy Chỉnh", "App Preferences"))
                groupDivider()
                SwipeSafeButton { openGroup("helpLegal") } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield").font(.system(size: 16, weight: .medium)).frame(width: 22, height: 22).opacity(0.72)
                        Text(app.T("Trợ Giúp & Pháp Lý", "Help & Legal")).font(.system(size: 14))
                        Spacer()
                        Text("›").font(.system(size: 15)).opacity(0.85)
                    }
                    .foregroundStyle(app.palette.ink)
                    .padding(.horizontal, 16).padding(.vertical, 15)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("account.helpLegal")
            }
            .padding(.top, 14)
            // "Help & Legal" (grouped above) — no dedicated in-app Help/
            // Support screen exists anywhere in this codebase (searched for
            // one); only the real, already-wired Policy screen
            // (`app.openPolicy()`/`PolicyView.swift`, the same bilingual
            // policy text used at signup consent, reachable read-only here
            // — its own "‹ Back" returns to `app.policyBackScreen`, set to
            // whichever screen opened it). That row is therefore the Legal
            // half only — the "Help" half has no real destination yet, a
            // genuine gap flagged in 09-auth-onboarding.md's dated fix-pass
            // section, not fabricated here.

            // The lightweight conditional invite row described above. Same
            // badge SOURCE as the Host-tab "team" card (myOrganizerInvites
            // [+ myEventCredits]) — never a second independently-derived
            // count, never shown at the same time as that card.
            if !app.organizerMode && !app.myOrganizerInvites.isEmpty {
                SwipeSafeButton { app.accountGroupKey = "team"; app.screen = .accountGroup } label: {
                    HStack(spacing: 12) {
                        // 2026-10-02 fix — size/no-background standardized
                        // to match every other row icon on this screen.
                        Image(systemName: "person.3").font(.system(size: 16, weight: .medium)).frame(width: 22, height: 22).opacity(0.72)
                        Text(app.T("Bạn có lời mời Team", "You have a team invite")).font(.system(size: 14))
                        Spacer()
                        Text("\(app.myOrganizerInvites.count)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(app.palette.paper)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(BanbeTheme.alert, in: Capsule())
                            .accessibilityIdentifier("account.teamInviteBanner.badge")
                        Text("›").font(.system(size: 15))
                    }
                    .foregroundStyle(app.palette.ink)
                    .padding(16)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .accessibilityIdentifier("account.teamInviteBanner")
            }

            // Admin Team pass (2026-10-02) — same banner shape as the Team
            // invite above, reachable regardless of current role (the
            // invitee isn't an admin yet).
            if let invite = app.myAdminInvite {
                SwipeSafeButton { app.accountGroupKey = "adminTeam"; app.screen = .accountGroup } label: {
                    HStack(spacing: 12) {
                        // 2026-10-02 fix — was "exclamationmark.shield", a
                        // duplicate of the UNRELATED "adminReview" row's own
                        // icon elsewhere on this tab, and didn't match this
                        // banner's real destination (adminTeam, same as the
                        // Admin Team row/"person.3.fill" below) — also
                        // standardized to size/no-background like every
                        // other row icon here.
                        Image(systemName: "person.3.fill").font(.system(size: 16, weight: .medium)).frame(width: 22, height: 22).opacity(0.72)
                        Text(app.T("Bạn có lời mời quản trị", "You have an admin invite")).font(.system(size: 14))
                        Spacer()
                        Text("›").font(.system(size: 15))
                    }
                    .foregroundStyle(app.palette.ink)
                    .padding(16)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .accessibilityIdentifier("account.adminInviteBanner")
                .id(invite.id)
            }

            // Account extension (2026-09-27, Stage 1) — "organizer mode
            // OFF means host UI is OFF": the whole Tổ chức tab disappears
            // while this is off, so the ON/OFF control itself (and any
            // actionable host duty) can't live there any more — moved
            // here, into Cá nhân, which is always reachable. The Tổ chức
            // tab (when it does show) now holds only the organizer
            // identity card + its management entry point (orgProfileCard).
            hostingSection
            } // app.accountTab == "personal"

            if app.accountTab == "host" {
            // Account IA pass (2026-09-27) — identity card FIRST (was:
            // reports row, then this card).
            orgProfileCard()
            postStoryCTA
            shareCardCTA(host: true)
            ActionCenterView(items: hostActionItems, onSeeAll: { app.openVerifications(back: .profile) })
            hostManagementRows
            // Metrics & Reports now lives as the last row INSIDE
            // `hostManagementRows`' grouped card (same pattern as Personal's
            // "Your Activity"), under its own "Host Management" header.
            } // app.accountTab == "host"

            if app.accountTab == "admin" {
            // No header existed here before ("nothing to group"); now
            // there is: this header plus the reorder below justifies it.
            sectionHeader(app.T("Quản Trị", "Administration"))
                .accessibilityIdentifier("account.section.admin")
            adminSection
            } // app.accountTab == "admin"


            // Bandwidth pass (2026-10-01) — lets anyone stuck with a stale
            // cached cover (or just wanting the disk space back) reclaim it
            // without affecting drafts/sessions/tickets, which PhotoLoader's
            // caches never touch in the first place. See
            // .claude/notes/22-supabase-bandwidth-optimization.md.
            SwipeSafeButton {
                PhotoLoader.clearCache()
                imageCacheClearedAt = Date()
            } label: {
                Label(
                    imageCacheClearedAt == nil
                        ? app.T("Xoá bộ nhớ đệm hình ảnh", "Clear Image Cache")
                        : app.T("Đã xoá bộ nhớ đệm hình ảnh", "Image cache cleared"),
                    systemImage: "photo.stack"
                )
                .labelStyle(.titleAndIcon)
            }
            .font(.system(size: 13))
            .foregroundStyle(app.palette.ink)
            .buttonStyle(.plain)
            .accessibilityIdentifier("account.clearImageCache")
            .padding(.top, 24)

            SwipeSafeButton {
                if app.isSignedIn { Task { await app.signOut() } } else { app.goLogin() }
            } label: {
                Label(
                    app.isSignedIn
                        ? app.T("Đăng xuất", "Sign out")
                        : app.T("Đăng nhập để lưu sự kiện và nhắn tin", "Sign in to save events and message hosts"),
                    systemImage: app.isSignedIn ? "rectangle.portrait.and.arrow.right" : "arrow.right.to.line"
                )
                .labelStyle(.titleAndIcon)
            }
            .font(.system(size: 13))
            .foregroundStyle(app.palette.ink)
            .buttonStyle(.plain)
            .accessibilityIdentifier(app.isSignedIn ? "account.signOut" : "account.signIn")
            .padding(.top, 12)
            .padding(.bottom, 100)
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        // Fixed-header pass (2026-10-02) — each tab's body is now a
        // distinctly-identified subtree, so switching tabs tears down and
        // recreates it (standard SwiftUI "new identity resets scroll
        // offset" behavior) instead of silently keeping whatever physical
        // scroll offset the PREVIOUS tab's (now-replaced) content happened
        // to be at. Combined with `accountScrollAnchorBinding`'s own
        // per-tab dictionary, a tab with a previously-stored anchor still
        // restores to it on this same re-creation — same mechanism
        // `retryScrollRestoreIfNeeded` already uses for a full screen
        // return, just re-keyed per tab instead of per screen visit.
        .id(app.accountTab)
        .sheet(isPresented: $shareCardOpen) { shareCardSheet }
        .sheet(isPresented: $eventStoryPickerOpen) { eventStoryPicker }
    }

    // iPhone fix pass (2026-09-27), Issue 1 — consumes whichever highlight
    // AppState's own organizer_invite/event_credit_invite notification
    // cases set (AppState+Data.swift's openNotification()), the instant
    // this view actually has the matching row mounted (myOrganizerInvites/
    // myEventCredits load asynchronously — Account's own `.task`s above —
    // so a highlight set before that load resolves needs re-checking on
    // change too, hence this also runs from the two `.onChange`s above).
    private func consumeTeamHighlightsIfNeeded() {
        if let target = app.teamInviteHighlightOrganizerId,
           app.myOrganizerInvites.contains(where: { $0.organizerId == target }) {
            app.accountTab = "personal"
            highlightedTeamInviteOrganizerId = target
            app.teamInviteHighlightOrganizerId = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                if highlightedTeamInviteOrganizerId == target { highlightedTeamInviteOrganizerId = nil }
            }
        }
        if let target = app.eventCreditHighlightId,
           app.myEventCredits.contains(where: { $0.id == target }) || app.myConfirmedEventCredits.contains(where: { $0.id == target }) {
            app.accountTab = "personal"
            highlightedEventCreditId = target
            app.eventCreditHighlightId = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                if highlightedEventCreditId == target { highlightedEventCreditId = nil }
            }
        }
    }

    // MARK: Search

    private func openGroup(_ key: String) {
        app.accountGroupKey = key
        app.screen = .accountGroup
    }

    /// Every destination reachable from Account, tagged with its tab
    /// (Personal / Host / Admin) and the section it lives under. Host and
    /// Admin entries only exist for accounts that actually have those tabs.
    /// `keywords` adds the words people might type that the title alone
    /// wouldn't match (both languages, any diacritics — matching ignores
    /// accents and case).
    private var accountSearchEntries: [AccountSearchEntry] {
        func e(_ id: String, _ tab: String, _ secVi: String, _ secEn: String, _ vi: String, _ en: String, _ icon: String, _ kw: String, _ action: @escaping () -> Void) -> AccountSearchEntry {
            AccountSearchEntry(id: id, tab: tab, secVi: secVi, secEn: secEn, vi: vi, en: en, icon: icon, keywords: kw, action: action)
        }
        let actVi = "Hoạt Động Của Bạn", actEn = "Your Activity"
        let setVi = "Tài Khoản & Cài Đặt", setEn = "Account & Settings"
        var list: [AccountSearchEntry] = [
            e("tickets", "personal", actVi, actEn, "Vé & Đặt Chỗ", "Tickets & Bookings", "calendar.badge.checkmark",
              "vé ticket booking đặt chỗ giữ chỗ hold qr check-in đã hủy hết hạn cancelled expired my tickets vé của tôi") { openGroup("activity") },
            e("going", "personal", actVi, actEn, "Đang tham gia", "Going", "checkmark.circle",
              "attending sắp tham gia sự kiện của tôi my events upcoming") { app.goGoingList() },
            e("saved", "personal", actVi, actEn, "Sự Kiện Đã Lưu", "Saved Events", "bookmark",
              "lưu yêu thích favorites favourite bookmark wishlist") { app.goSavedList() },
            e("past", "personal", actVi, actEn, "Sự Kiện Quá Khứ", "Past Events", "calendar.badge.checkmark",
              "đã hoàn thành completed ended lịch sử history đã qua") { app.goCompletedList(back: .profile) },
            e("payments", "personal", actVi, actEn, "Thanh Toán & Giấy Tờ", "Payments & Documents", "banknote",
              "thanh toán payment tiền money giấy tờ documents") { openGroup("payments") },
            e("invoices", "personal", actVi, actEn, "Hoá đơn", "Invoices", "doc.text",
              "hóa đơn invoice bill tài liệu pdf") { app.openDocuments(kind: "invoice", role: "guest", back: .profile) },
            e("receipts", "personal", actVi, actEn, "Biên nhận", "Receipts", "receipt",
              "receipt biên lai chứng từ pdf") { app.openDocuments(kind: "receipt", role: "guest", back: .profile) },
            e("refundAccounts", "personal", actVi, actEn, "Tài khoản thanh toán & nhận hoàn tiền", "Payment & refund accounts", "banknote",
              "ngân hàng bank tài khoản account số tài khoản momo chuyển khoản hoàn tiền refund destination") { app.openRefundAccounts(back: .profile) },
            e("refunds", "personal", actVi, actEn, "Hoàn tiền", "Refunds", "checklist",
              "refund hoàn trả trả lại tiền hủy sự kiện tranh chấp dispute") { app.openMyRefunds(back: .profile) },
            e("reportsPersonal", "personal", actVi, actEn, "Số Liệu & Báo Cáo", "Metrics & Reports", "chart.bar.doc.horizontal",
              "thống kê statistics analytics báo cáo report số liệu insights") { app.openReports(scope: "personal", back: .profile) },
            e("profile", "personal", setVi, setEn, "Hồ Sơ Cá Nhân", "Personal Profile", "person.crop.circle",
              "profile hồ sơ tên name avatar ảnh đại diện handle chỉnh sửa edit public trang cá nhân") {
                  if let handle = app.user?.handle, !handle.isEmpty { app.openPublicProfile(handle: handle, back: .profile) }
              },
            e("preferences", "personal", setVi, setEn, "Tùy Chỉnh", "App Preferences", "slider.horizontal.3",
              "settings cài đặt tùy chỉnh preferences") { openGroup("preferences") },
            e("language", "personal", setVi, setEn, "Ngôn ngữ & Hiển thị", "Language & Appearance", "slider.horizontal.3",
              "ngôn ngữ language tiếng việt english vn en theme giao diện sáng tối dark light mode hiển thị appearance kính glass độ trong suốt") { app.openPreferences() },
            e("security", "personal", setVi, setEn, "Bảo mật", "Security", "lock.shield",
              "security mật khẩu password face id sinh trắc biometric đăng nhập login khóa lock đổi mật khẩu") { app.openSecurity() },
            e("help", "personal", setVi, setEn, "Trợ Giúp & Pháp Lý", "Help & Legal", "lock.shield",
              "help trợ giúp hỗ trợ support policy chính sách điều khoản terms privacy quyền riêng tư pháp lý legal liên hệ contact hướng dẫn guide hỏi đáp faq q&a câu hỏi questions") { openGroup("helpLegal") },
            e("organizerMode", "personal", "Tổ Chức", "Hosting", "Chế độ tổ chức", "Organizer mode", "person.2.badge.gearshape",
              "host tổ chức organizer bật tắt toggle tạo sự kiện create event quản lý manage") { app.toggleOrganizerMode() },
            e("clearCache", "personal", setVi, setEn, "Xoá bộ nhớ đệm hình ảnh", "Clear Image Cache", "photo.stack",
              "cache bộ nhớ đệm dung lượng storage ảnh hình image xóa clear") { PhotoLoader.clearCache(); imageCacheClearedAt = Date() },
            e("signOut", "personal", setVi, setEn, app.isSignedIn ? "Đăng xuất" : "Đăng nhập", app.isSignedIn ? "Sign out" : "Sign in", "rectangle.portrait.and.arrow.right",
              "logout log out thoát đăng xuất đăng nhập sign in login tài khoản account") {
                  if app.isSignedIn { Task { await app.signOut() } } else { app.goLogin() }
              },
        ]
        if app.organizerMode && app.canHost {
            let hVi = "Tổ Chức", hEn = "Host"
            list += [
                e("hostOps", "host", hVi, hEn, "Vận Hành & Thanh Toán Tổ Chức", "Event Operations & Payments", "checklist",
                  "vận hành operations thanh toán payments tổ chức host sự kiện") { openGroup("hostOps") },
                e("verifications", "host", hVi, hEn, "Chờ xác nhận thanh toán", "Awaiting Verification", "checklist",
                  "xác nhận verify verification thanh toán chờ pending người mua guest bằng chứng proof chuyển khoản") { app.openVerifications(back: .profile) },
                e("hostRefunds", "host", hVi, hEn, "Hoàn tiền", "Refunds", "banknote",
                  "refund hoàn trả hủy sự kiện cancel batch đã gửi mark sent tranh chấp dispute") { app.openVerificationsRefunds(back: .profile) },
                e("payout", "host", hVi, hEn, "Nhận thanh toán", "Getting Paid", "creditcard",
                  "payout nhận tiền ngân hàng bank thanh toán doanh thu revenue rút tiền") { app.openPayout() },
                e("invoicesIssued", "host", hVi, hEn, "Hoá đơn đã phát hành", "Invoices Issued", "doc.text",
                  "hóa đơn invoice phát hành tải lên upload tài liệu") { app.openDocuments(kind: "invoice", role: "host", back: .profile) },
                e("receiptsIssued", "host", hVi, hEn, "Biên nhận đã phát hành", "Receipts Issued", "receipt",
                  "biên lai receipt phát hành tải lên upload tài liệu") { app.openDocuments(kind: "receipt", role: "host", back: .profile) },
                e("team", "host", hVi, hEn, "Hồ Sơ & Team Tổ Chức", "Organizer Profile & Team", "person.3",
                  "team đội nhóm thành viên member mời invite hồ sơ tổ chức organizer profile đóng góp contribution credit") { openGroup("team") },
                e("surveys", "host", hVi, hEn, "Khảo Sát & Ý Tưởng Sự Kiện", "Surveys & Event Ideas", "lightbulb",
                  "survey khảo sát ý tưởng idea góp ý feedback câu hỏi form") { app.screen = .surveysHosting },
                e("reportsHost", "host", hVi, hEn, "Số Liệu & Báo Cáo", "Metrics & Reports", "chart.bar.doc.horizontal",
                  "thống kê statistics analytics báo cáo report số liệu doanh thu") { app.openReports(scope: "host", organizerID: app.myOrganizerID, back: .profile) },
            ]
        }
        if app.accountType == "admin" {
            let aVi = "Quản Trị", aEn = "Administration"
            list += [
                e("adminReview", "admin", aVi, aEn, "Duyệt & Kiểm Duyệt", "Review & Moderation", "exclamationmark.shield",
                  "duyệt review kiểm duyệt moderation approve phê duyệt") { openGroup("adminReview") },
                e("disputes", "admin", aVi, aEn, "Tranh Chấp Thanh Toán", "Payment Disputes", "exclamationmark.bubble",
                  "tranh chấp dispute khiếu nại escalation thanh toán payment dashboard bảng điều khiển bảng quản trị admin panel") { app.openAdminDashboard() },
                e("pendingEvents", "admin", aVi, aEn, "Sự Kiện Chờ Duyệt", "Pending Events", "exclamationmark.shield",
                  "sự kiện chờ duyệt pending events approve từ chối reject") { app.openAdminEvents() },
                e("adminTeam", "admin", aVi, aEn, "Đội Ngũ Quản Trị", "Admin Team", "person.3.fill",
                  "admin quản trị viên mời invite thành viên team đội ngũ") { openGroup("adminTeam") },
                e("reportsAdmin", "admin", aVi, aEn, "Số Liệu & Báo Cáo", "Metrics & Reports", "chart.bar.doc.horizontal",
                  "thống kê statistics analytics báo cáo report số liệu") { app.openReports(scope: "admin", back: .profile) },
                e("adminGuide", "admin", aVi, aEn, "Hướng Dẫn Quản Trị", "Admin Guide", "checklist",
                  "admin guide hướng dẫn quản trị help trợ giúp") { app.helpGuideKey = "admin"; app.screen = .helpGuide },
            ]
        }
        return list
    }

    /// Search results, grouped under the tab they belong to (Personal /
    /// Host / Admin) in the same section-header + grouped-card style as
    /// "Your Activity" / "Account & Settings".
    private var accountSearchResults: some View {
        let entries = accountSearchEntries
        let tabTitles: [(key: String, vi: String, en: String)] = [
            ("personal", "Cá Nhân", "Personal"), ("host", "Tổ Chức", "Host"), ("admin", "Quản Trị", "Admin"),
        ]
        let groups: [(title: String, items: [AccountSearchEntry])] = tabTitles.compactMap { t in
            let items = entries.filter { $0.tab == t.key && $0.matches(searchQuery, tabVi: t.vi, tabEn: t.en) }
            return items.isEmpty ? nil : (app.T(t.vi, t.en), items)
        }
        return VStack(alignment: .leading, spacing: 0) {
            if groups.isEmpty {
                Text(app.T("Không tìm thấy kết quả phù hợp.", "No matching results."))
                    .font(.system(size: 13))
                    .opacity(0.7)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                    .accessibilityIdentifier("account.search.empty")
            }
            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                sectionHeader(group.title, topPadding: index == 0 ? 14 : 22)
                    .accessibilityIdentifier("account.search.section")
                groupedContainer {
                    ForEach(Array(group.items.enumerated()), id: \.element.id) { i, entry in
                        SwipeSafeButton {
                            let tab = entry.tab
                            // Keep the search open with its query, so swiping back
                            // from the result returns to these same results.
                            searchFocused = false
                            app.accountTab = tab
                            app.accountSearchReturn = true
                            entry.action()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: entry.icon)
                                    .font(.system(size: 16, weight: .medium))
                                    .frame(width: 22, height: 22)
                                    .opacity(0.72)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.T(entry.vi, entry.en)).font(.system(size: 14))
                                    Text(app.T(entry.secVi, entry.secEn))
                                        .font(.system(size: 11)).opacity(0.55)
                                }
                                Spacer()
                                Text("›").font(.system(size: 15)).opacity(0.85)
                            }
                            .foregroundStyle(app.palette.ink)
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("account.search.\(entry.id)")
                        if i < group.items.count - 1 { groupDivider() }
                    }
                }
                .padding(.top, 10)
            }
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 20)
        .padding(.bottom, 100)
    }

    private func syncAccountTabToRole() {
        if app.accountTab == "host" && !app.organizerMode { app.accountTab = "personal" }
        else if app.accountTab == "admin" && app.accountType != "admin" { app.accountTab = "personal" }
    }

    // Personal-vs-organizer hierarchy pass (2026-09-27) — extracted out of
    // `body`'s own `ForEach` (a real Swift type-checker timeout once this
    // ScreenScaffold call gained an `onRefresh:` closure alongside
    // everything already in `body` — same "unable to type-check this
    // expression in reasonable time" class of bug BottomTabBar.swift's own
    // `tabItem` extraction already fixed once).
    // Account extension (2026-09-27, Stage 1) — Tổ chức only while
    // `organizerMode` is actually on (never `canHost`/eligibility); Admin
    // (Stage 2) only for a server-confirmed admin, independent of
    // `organizerMode` entirely.
    // FIX PASS (2026-09-30) — badges propagated from the SAME sources as
    // each tab's own group card below (host: "Vận hành & thanh toán tổ
    // chức"; admin: "Duyệt & kiểm duyệt") — see Lib/Badges.swift.
    private var accountTabs: [(String, String, Int)] {
        var tabs: [(String, String, Int)] = [("personal", app.T("Cá Nhân", "Personal"), AccountBadges.personalActionCount(paymentBookings: app.paymentBookings, myRefunds: app.myRefunds))]
        if app.organizerMode {
            let hostBadge = AccountBadges.hostActionCount(organizerMode: app.organizerMode, verificationsCount: app.verifications.count, refundQueue: app.refundQueue, holdingCount: app.organizerHoldingSummary?.count ?? 0)
            // Events waiting for Banbe's review (or sent back for fixing) count too.
            tabs.append(("host", app.T("Tổ Chức", "Host"), hostBadge + submittedTotal))
        }
        if app.accountType == "admin" {
            let adminBadge = AccountBadges.adminModerationCount(accountType: app.accountType, pendingEventsCount: app.pendingEventsCount)
            tabs.append(("admin", app.T("Quản Trị", "Admin"), adminBadge))
        }
        return tabs
    }

    /// Same Liquid Glass capsule as Home's header buttons (`homeGlassCapsule`
    /// in HomeView), so Account's tab pills match them.
    @ViewBuilder
    private func accountGlassCapsule(active: Bool) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer {
                Capsule()
                    .fill(active
                          ? app.palette.ink.opacity(0.92)
                          : app.palette.ink.opacity(0.04 + 0.20 * app.glassOpacity))
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .opacity(active ? 1 : app.glassOpacity)
            }
        } else if active {
            Capsule().fill(app.palette.ink)
        } else {
            Capsule()
                .fill(app.palette.ink.opacity(0.04 + 0.20 * app.glassOpacity))
                .background(.thinMaterial, in: Capsule())
                .opacity(app.glassOpacity)
        }
    }

    @ViewBuilder
    private func accountTabButton(key: String, label: String, badge: Int = 0) -> some View {
        SwipeSafeButton {
            if app.accountTab != key { Haptics.selection(); app.accountScrollAnchorIDByTab[key] = nil }   // a tab you switch TO opens at its top
            app.accountTab = key
        } label: {
            HStack(spacing: 6) {
                Text(label).font(.system(size: 13, weight: .semibold))
                if badge > 0 {
                    Text(AccountBadges.format(badge))
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 4)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(app.accountTab == key ? app.palette.paper : BanbeTheme.alert, in: Capsule())
                        .foregroundStyle(app.accountTab == key ? app.palette.ink : .white)
                        .accessibilityIdentifier("account.tab.\(key).badge")
                        .accessibilityLabel(app.T("\(badge) mục mới", "\(badge) new item(s)"))
                }
            }
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background { accountGlassCapsule(active: app.accountTab == key) }
                .foregroundStyle(app.accountTab == key ? app.palette.paper : app.palette.ink)
        }
        .buttonStyle(.plain)
        // iPhone fix pass (2026-09-27, post-ec06c78), Issue 3 — Account
        // (`.profile`) is a root dock screen, so RootView's own
        // `tabSwipeGesture` (`DragGesture(minimumDistance: 8)`) is attached
        // as a `.simultaneousGesture` across this ENTIRE screen, including
        // this tab row. A `.simultaneousGesture` ancestor and a descendant
        // Button are each supposed to recognize independently, but a real
        // tap's own small incidental finger movement — worse mid an active
        // root-tab cross-fade `.animation`, when SwiftUI is already busy
        // resolving this same drag recognizer for the transition itself —
        // can leave the Button's own tap waiting on that ancestor gesture
        // to first conclude "not a drag" before committing, reading as a
        // dropped or delayed tap. `.highPriorityGesture(TapGesture())`
        // gives this row's own tap unconditional priority the instant a
        // touch ends without crossing tabSwipeGesture's own commit
        // distance — the same "more specific interaction wins outright"
        // precedence this file's `edgeSwipe` already establishes over
        // whatever's underneath it. Assigning the same `app.accountTab`
        // value the Button's own action also sets is idempotent — never a
        // double-toggle — so both handlers safely agree.
        .highPriorityGesture(TapGesture().onEnded {
            if !app.isRootSwipeActive {
                if app.accountTab != key { Haptics.selection(); app.accountScrollAnchorIDByTab[key] = nil }
                app.accountTab = key
            }
        })
        .accessibilityIdentifier("account.tab.\(key)")
    }

    // Account extension (2026-09-27, Stage 3) — the one recognizable "Số
    // liệu & báo cáo" entry point every visible tab gets, near its own top.
    // Account IA reorder pass (2026-09-30 second) — mirrors web's
    // `SectionHeader` (Account.jsx) value-for-value: same 11.5pt/semibold
    // style already used by "Tổ Chức" above, factored out so every cluster
    // in Personal/Host/Admin reads as one consistent convention. Purely
    // presentational — never changes a groupKey/identifier/route.
    private func sectionHeader(_ label: String, topPadding: CGFloat = 22) -> some View {
        Text(label)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(app.palette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, topPadding)
    }

    private func reportsRow(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        SwipeSafeButton(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 22, height: 22)
                    .opacity(0.72)
                Text(title).font(.system(size: 14))
                Spacer()
                Text("›").font(.system(size: 15))
            }
            .foregroundStyle(app.palette.ink)
            .padding(16)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 22)
        .accessibilityIdentifier(identifier)
    }

    // Account IA pass (2026-09-27) — a grouped entry card: icon (accented,
    // ROW_ACCENT_COLORS) + title + optional badge (a real, un-derived
    // urgent pending-action COUNT — never buried inside the child screen
    // only, per this ticket's "preserve urgent pending-action visibility
    // ... at the group entry" instruction) + chevron, opening the shared
    // AccountGroupView. `groupKey` doubles as the accent-color lookup AND
    // the accessibility identifier/route id both platforms share.
    // 2026-10-02 fix — "connected account row groups": the top-level
    // Personal-tab cards (Tickets & Bookings / Going-Saved stats /
    // Payments & Documents / Metrics & Reports, then Personal Profile /
    // Settings / Help & Legal) each had their OWN separate rounded
    // `.background(...)` with a gap before it — N floating cards instead
    // of ONE contiguous grouped container, unlike "Event Operations &
    // Payments" (`hostManagementRows`/`AccountGroupView.hostOpsContent`),
    // which this reuses as its styling source exactly: one shared
    // background, internal `Divider()`s, same row padding/corner radius/
    // tap targets — not a new visual language. `groupedContainer` wraps
    // any number of these bare row-content builders (below) in that one
    // shared surface; `groupCard`/`reportsRow`/`counter` above are
    // UNCHANGED and still used as-is everywhere else (Host/Admin tabs),
    // so nothing there is touched by this.
    private func groupedContainer<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func groupDivider() -> some View { Divider().overlay(app.palette.rule) }

    /// Same content as `groupCard` below, minus the background/top-padding
    /// a `groupedContainer` already supplies once for the whole group.
    // 2026-10-02 fix — "icons inconsistent in size, some duplication":
    // this used to be its own 30x30 frame with a `ROW_ACCENT_COLORS`-
    // tinted circle behind it — the ONE outlier size/treatment on this
    // whole screen (every other row icon here — `row`/`reportsRow`/
    // `reportsGroupRow`/the inline Personal Profile & Help & Legal
    // buttons — is a plain 22x22/16pt/0.72-opacity glyph with no
    // background of its own, since the row already sits on the group's
    // shared container background). Standardized to that same size/
    // treatment; distinctness now comes only from each icon's own glyph,
    // not a second, redundant color layer.
    private func groupCardRow(groupKey: String, icon: String, label: String, badge: Int = 0) -> some View {
        return SwipeSafeButton { app.accountGroupKey = groupKey; app.screen = .accountGroup } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 22, height: 22)
                    .opacity(0.72)
                Text(label).font(.system(size: 14))
                Spacer()
                if badge > 0 {
                    Text(badge > 99 ? "99+" : "\(badge)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(app.palette.paper)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(BanbeTheme.alert, in: Capsule())
                        .accessibilityIdentifier("account.group.\(groupKey).badge")
                        .accessibilityLabel(app.T("\(badge) mục mới", "\(badge) new item(s)"))
                }
                Text("›").font(.system(size: 15))
            }
            .foregroundStyle(app.palette.ink)
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("account.group.\(groupKey)")
    }

    /// Same content as `reportsRow` below, minus its own background/padding.
    private func reportsGroupRow(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        SwipeSafeButton(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 22, height: 22)
                    .opacity(0.72)
                Text(title).font(.system(size: 14))
                Spacer()
                Text("›").font(.system(size: 15))
            }
            .foregroundStyle(app.palette.ink)
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    /// Same content as `counter` below, minus its own background — used
    /// side by side inside `groupedContainer`, where a `Divider()` between
    /// them (SwiftUI renders it vertical inside an `HStack`) stands in for
    /// the group's usual horizontal separator.
    // 2026-10-02 fix — size standardized to the same 22x22/16pt every
    // other row icon on this screen now uses (was 20x20/15pt, its own
    // third size on top of the 30x30-with-circle outlier fixed above).
    private func counterGroupRow(value: Int, label: String, icon: String, identifier: String? = nil, action: @escaping () -> Void) -> some View {
        SwipeSafeButton(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 22, height: 22)
                    .opacity(0.72)
                Text("\(value)").font(BanbeTheme.display(24))
                Text(label).font(.system(size: 11))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .foregroundStyle(app.palette.ink)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier ?? label)
    }

    private func row(_ title: String, identifier: String? = nil, icon: String, trailing: String,
                     action: @escaping () -> Void) -> some View {
        SwipeSafeButton(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 22, height: 22)
                    .opacity(0.72)
                Text(title).font(.system(size: 14))
                Spacer()
                Text(trailing).font(.system(size: 13))
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 16).padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier ?? title)
    }

    // Account extension (2026-09-27, Stage 1) — extracted out of `body`'s
    // own Cá nhân branch (a real Swift type-checker timeout, same class of
    // bug `accountContent`'s own extraction already fixed once). Formerly
    // lived inside `app.accountTab == "host"`; moved here (rendered from
    // Cá nhân, unconditionally reachable) per "organizer mode OFF means
    // host UI is OFF": the Tổ chức tab itself is gone while it's off, so
    // the ON/OFF control and any actionable host duty can't live there.
    // Organizer Team pass (2026-09-27, Stage 1) — a real, pending invite
    // this account was actually sent (organizer_members, migration 098).
    // Accepting does NOT turn on public visibility — that's the separate
    // switch on each accepted membership below.
    @ViewBuilder
    private var teamInvitesAndMemberships: some View {
        if !app.myOrganizerInvites.isEmpty {
            Text(app.T("Lời mời Team", "Team invites")).font(.system(size: 11.5, weight: .semibold)).padding(.top, 18)
            ForEach(app.myOrganizerInvites) { inv in
                VStack(alignment: .leading, spacing: 8) {
                    Text(app.T("\(inv.organizers?.name ?? "Một tổ chức") mời bạn làm \(inv.publicRole)", "\(inv.organizers?.name ?? "An organizer") invited you as \(inv.publicRole)"))
                        .font(.system(size: 13))
                    HStack(spacing: 8) {
                        InkButton(title: app.T("Chấp nhận", "Accept")) { Task { await app.respondToOrganizerInvite(membershipID: inv.id, accept: true) } }
                        SwipeSafeButton { Task { await app.respondToOrganizerInvite(membershipID: inv.id, accept: false) } } label: { Text(app.T("Từ chối", "Decline")) }
                            .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(app.palette.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(app.palette.rule))
                    }
                }
                .padding(14)
                .background(
                    highlightedTeamInviteOrganizerId == inv.organizerId ? BanbeTheme.alert.opacity(0.14) : app.palette.field,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .padding(.top, 8)
                .accessibilityIdentifier("team.invite.\(inv.id)")
            }
        }
        if !app.myTeamMemberships.isEmpty {
            Text(app.T("Đội ngũ của tôi", "My teams")).font(.system(size: 11.5, weight: .semibold)).padding(.top, 18)
            ForEach(app.myTeamMemberships) { m in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.organizers?.name ?? app.T("Một tổ chức", "An organizer")).font(.system(size: 13))
                        Text(m.publicRole).font(.system(size: 11)).opacity(0.65)
                    }
                    Spacer()
                    SwipeSafeButton {
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
        // Organizer Team pass (2026-09-27, Stage 2) — a real, explicit,
        // owner-assigned event-organizing credit this account was
        // actually sent. Never derived from bookings/check-ins.
        // iPhone fix pass (2026-09-27), Issue 5 — header now explicitly
        // says "pending" and this is followed by a SEPARATE confirmed
        // section (myConfirmedEventCredits) below, per this ticket's own
        // "pending invites separately from confirmed credits" ask.
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
                        SwipeSafeButton { Task { await app.respondToEventCredit(creditID: c.id, accept: false) } } label: { Text(app.T("Từ chối", "Decline")) }
                            .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(app.palette.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(app.palette.rule))
                    }
                }
                .padding(14)
                .background(
                    highlightedEventCreditId == c.id ? BanbeTheme.alert.opacity(0.14) : app.palette.field,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .padding(.top, 8)
                .accessibilityIdentifier("eventCredit.\(c.id)")
            }
        }
        // iPhone fix pass (2026-09-27), Issue 5 — the CONFIRMED half; this
        // account's own PRIVATE view (always visible here to its owner,
        // regardless of the separate public_visible opt-in that only ever
        // gates the PUBLIC profile's own credited_events, get_public_profile
        // migration 100). Read-only (no Accept/Decline — already resolved),
        // tappable straight to the event.
        if !app.myConfirmedEventCredits.isEmpty {
            Text(app.T("Đóng góp sự kiện: đã xác nhận", "Event contributions: confirmed")).font(.system(size: 11.5, weight: .semibold)).padding(.top, 18)
            ForEach(app.myConfirmedEventCredits) { c in
                SwipeSafeButton { app.goEvent(c.eventId) } label: {
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
                .background(
                    highlightedEventCreditId == c.id ? BanbeTheme.alert.opacity(0.14) : app.palette.field,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .padding(.top, 8)
                .accessibilityIdentifier("eventCreditConfirmed.\(c.id)")
            }
        }
    }

    @ViewBuilder
    private var hostingSection: some View {
        Text(app.T("Tổ Chức", "Hosting"))
            .font(.system(size: 11.5, weight: .semibold))
            .padding(.top, 22)

        SwipeSafeButton { app.toggleOrganizerMode() } label: {
            // TASK 2 (2026-10-05 fix pass) — `.opacity`, not a
            // spinner: this toggle's own round-trip is already
            // near-instant on a normal connection, and a flashing
            // spinner for that would read as jankier than a brief
            // dim. `.disabled` below is what actually matters —
            // it's the real guard against the double-tap race
            // (see toggleOrganizerMode()'s own comment).
            HStack(spacing: 12) {
                Image(systemName: "person.2.badge.gearshape")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 22, height: 22)
                    .opacity(0.72)
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.T("Chế độ tổ chức", "Organizer mode")).font(.system(size: 14))
                    Text(app.T("Bật để tạo và quản lý sự kiện. Tắt lúc nào cũng được.",
                               "Turn on to create and manage events. Turn it off any time."))
                        .font(.system(size: 11.5))
                        .foregroundStyle(app.palette.ink.opacity(0.7))
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: Binding(
                    get: { app.organizerMode },
                    set: { enabled in
                        guard enabled != app.organizerMode else { return }
                        app.toggleOrganizerMode()
                    }
                ))
                .labelsHidden()
                .toggleStyle(BanbeLiquidToggleStyle())
            }
            .foregroundStyle(app.palette.ink)
            .padding(16)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(app.organizerModeBusy)
        .opacity(app.organizerModeBusy ? 0.55 : 1)
        .accessibilityIdentifier("account.organizerToggle")
        .padding(.top, 10)
        .id("account-hosting-toggle")

        if !app.organizerModeError.isEmpty {
            Text(app.organizerModeError)
                .font(.system(size: 12))
                .foregroundStyle(BanbeTheme.alert)
                .padding(.top, 10)
        }

        // Account regression fix pass (2026-09-27), Item 1 — the real
        // host-management rows (verifications/payout/invoices/receipts)
        // used to live here too, so Cá nhân showed the full old
        // "Tổ chức" management menu underneath a toggle that was supposed
        // to be the ONLY thing here. They moved to `hostManagementRows`
        // (Tổ chức tab, below) — reachable ONLY while organizerMode is
        // actually on. Any genuinely urgent outstanding duty still
        // surfaces here via ActionCenterView (gated on `canHost`, not
        // `organizerMode`) — a neutral actionable notice, never the full
        // menu.

        // No separate "Xem trang tổ chức của bạn" card here — orgProfileCard()
        // (Tổ chức tab, once organizerMode is on) is the single entry into
        // that management page now. This pitch is for an account that has
        // never hosted (`canHost` false always implies `organizerMode`
        // false too, so it can only ever show in the true "never hosted"
        // case).
        if !app.canHost {
            VStack(alignment: .leading, spacing: 10) {
                Text(app.T("Tổ chức sự kiện đầu tiên", "Host your first event"))
                    .font(BanbeTheme.display(19))
                Text(app.T(
                    "Miễn phí hoàn toàn khi banbe còn mới — không phí đăng, không phí giao dịch. Tạo sự kiện đầu tiên để mở trang tổ chức.",
                    "Completely free while banbe is new — no listing or transaction fees. Create your first event to unlock your host page."
                ))
                .font(.system(size: 12.5))
                .lineSpacing(3)
                InkButton(title: app.T("Bắt đầu tổ chức ▪︎ miễn phí", "Start hosting ▪︎ free")) {
                    app.toggleOrganizerMode()
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(16)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.top, 10)
        }
    }

    // Account regression fix pass (2026-09-27), Item 1 — moved out of
    // Cá nhân's `hostingSection`: real host-management rows, only ever
    // reachable while organizerMode is on (this whole tab's own
    // visibility rule) — never duplicated in both tabs.
    @ViewBuilder
    // Account IA pass (2026-09-27) — was an inline 4-row "Quản lý thanh
    // toán" list; now ONE grouped entry card opening AccountGroupView's
    // "hostOps" content (same exact child actions/identifiers). Badge =
    // real outstanding host duties (verifications + refund queue), never
    // invented.
    private var hostManagementRows: some View {
        Group {
            // 2026-10-02 fix — "connected account row groups": these three
            // were separate floating cards; grouped into one contiguous
            // container, same styling source as before (this group WAS
            // already the reference — now actually applied to itself too).
            if app.canHost {
                sectionHeader(app.T("Quản Lý Tổ Chức", "Host Management"), topPadding: 22)
                    .accessibilityIdentifier("account.section.hostManagement")
                groupedContainer {
                    groupCardRow(
                        groupKey: "hostOps", icon: "checklist",
                        label: app.T("Vận Hành & Thanh Toán Tổ Chức", "Event Operations & Payments"),
                        // Stale-badge fix pass — was a raw `refundQueue.count`,
                        // bypassing `AccountBadges.hostActionCount` entirely
                        // (the one place this app already decides what's
                        // actually host-actionable) — same staleness bug every
                        // other raw-count call site this pass fixes.
                        badge: AccountBadges.hostActionCount(organizerMode: app.organizerMode, verificationsCount: app.verifications.count, refundQueue: app.refundQueue)
                    )
                    groupDivider()
                    submittedEventsRow
                    groupDivider()
                    // Account IA reorder pass (2026-09-30 second) — the Host
                    // tab's own entry point into the SAME "team" screen the
                    // Personal tab's conditional invite row also opens (see
                    // that row's own comment for the full "two doors, one
                    // destination" reasoning — mirrors the Payment Disputes
                    // row's existing pattern). Gated `canHost`, matching
                    // hostOps above.
                    groupCardRow(
                        groupKey: "team", icon: "person.3",
                        label: app.T("Hồ Sơ & Team Tổ Chức", "Organizer Profile & Team"),
                        badge: app.myOrganizerInvites.count + app.myEventCredits.count
                    )
                    groupDivider()
                    // Interest surveys (Slice B) — a standalone screen
                    // (SurveysHostingView), not a case inside AccountGroupView's
                    // switch, since it has its own tabs (Active/Closed/
                    // Suggested Drafts) and a create form, not a simple flat
                    // list. Badge honestly 0 for now — the unseen/actionable
                    // candidate count this badge is meant to carry (candidate
                    // generation) is not implemented yet.
                    SwipeSafeButton { app.screen = .surveysHosting } label: {
                        HStack(spacing: 12) {
                            // 2026-10-02 fix — was "checklist", a duplicate
                            // of this SAME container's own "Event
                            // Operations & Payments" row above; "lightbulb"
                            // fits "Event Ideas" literally and is distinct.
                            // Size/no-background standardized too.
                            Image(systemName: "lightbulb")
                                .font(.system(size: 16, weight: .medium))
                                .frame(width: 22, height: 22)
                                .opacity(0.72)
                            Text(app.T("Khảo Sát & Ý Tưởng Sự Kiện", "Surveys & Event Ideas")).font(.system(size: 14))
                            Spacer()
                            Text("›").font(.system(size: 15))
                        }
                        .foregroundStyle(app.palette.ink)
                        .padding(16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("account.group.surveys")
                    if app.myOrganizerID != nil {
                        groupDivider()
                        reportsGroupRow(app.T("Số Liệu & Báo Cáo", "Metrics & Reports"), identifier: "account.reportsHost") {
                            app.openReports(scope: "host", organizerID: app.myOrganizerID, back: .profile)
                        }
                    }
                }
                .padding(.top, 14)
            }
        }
    }

    // Stage 2 — Admin is its own top-level tab now, independent of
    // organizerMode: these two rows used to sit inside the Tổ chức pane,
    // so an admin who never turned organizer mode on (or turned it off)
    // lost them entirely once that tab started hiding itself for Stage 1.
    // Same actions, same RLS-enforced screens — moved, not cloned.
    @ViewBuilder
    // Account IA pass (2026-09-27) — same "Bảng quản trị"/"Sự kiện chờ
    // duyệt" actions, now one grouped entry card. Admin Panel is still
    // visible only to accountType == "admin" (banbetestadmin@gmail.com,
    // migration 040) — RLS is the real backstop; openAdminDashboard()
    // guards again regardless.
    private var adminSection: some View {
        // 2026-10-02 fix — "connected account row groups": these two were
        // still two separate floating cards despite already being stacked
        // in one VStack (each kept its OWN background/top-padding) — now
        // one contiguous container with an internal divider.
        groupedContainer {
            groupCardRow(groupKey: "adminReview", icon: "exclamationmark.shield", label: app.T("Duyệt & Kiểm Duyệt", "Review & Moderation"), badge: app.pendingEventsCount)
            groupDivider()
            // Admin Team pass (2026-10-02) — reachable to every admin (a
            // permission-less admin can at least see who the team is /
            // why they can't manage it, AccountGroupView's own gate
            // decides what renders inside); badge only ever counts real,
            // still-pending invites (adminInvites is only populated for a
            // canManageAdmins account — RLS denies the read otherwise, so
            // a non-manager's badge is honestly 0, never a guessed number).
            // 2026-10-02 fix — "person.3.fill" (was "person.3", the exact
            // same glyph the Host tab's UNRELATED "Organizer Profile &
            // Team" row uses) — distinct glyph for a distinct destination.
            groupCardRow(groupKey: "adminTeam", icon: "person.3.fill", label: app.T("Đội Ngũ Quản Trị", "Admin Team"), badge: app.adminInvites.filter { $0.status == "pending" }.count)
            groupDivider()
            reportsGroupRow(app.T("Số Liệu & Báo Cáo", "Metrics & Reports"), identifier: "account.reportsAdmin") {
                app.openReports(scope: "admin", back: .profile)
            }
            groupDivider()
            // Concise admin-only guide (Help & Legal holds the user guides).
            SwipeSafeButton { app.helpGuideKey = "admin"; app.screen = .helpGuide } label: {
                HStack(spacing: 12) {
                    Image(systemName: "checklist").font(.system(size: 16, weight: .medium)).frame(width: 22, height: 22).opacity(0.72)
                    Text(app.T("Hướng Dẫn Quản Trị", "Admin Guide")).font(.system(size: 14))
                    Spacer()
                    Text("›").font(.system(size: 15))
                }
                .foregroundStyle(app.palette.ink)
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("account.adminGuide")
        }
        .padding(.top, 14)
    }

    @State private var shareCardOpen = false
    @State private var eventStoryPickerOpen = false
    @State private var eventStoryBusyKey: String?
    @State private var eventStoryLoaded = false
    @State private var eventStoryMessage: String?
    @State private var shareCardForHost = false

    /// Prominent entry point to the shareable profile card (Personal + Host).
    private func shareCardCTA(host: Bool) -> some View {
        Button {
            shareCardForHost = host
            shareCardOpen = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "qrcode").font(.system(size: 22, weight: .semibold)).foregroundStyle(app.palette.honey)
                VStack(alignment: .leading, spacing: 2) {
                    Text(host ? app.T("Chia sẻ thẻ tổ chức của bạn", "Share your host card")
                              : app.T("Chia sẻ thẻ hồ sơ của bạn", "Share your profile card"))
                        .font(.system(size: 15, weight: .semibold))
                    Text(app.T("Thẻ có mã QR, tuỳ chỉnh màu và ảnh nền", "A card with a QR code — pick your colours and background"))
                        .font(.system(size: 11.5)).opacity(0.8)
                }
                Spacer(minLength: 0)
                Image(systemName: "square.and.arrow.up").font(.system(size: 16, weight: .semibold)).foregroundStyle(app.palette.honey)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .foregroundStyle(app.palette.ink)
            .background(app.palette.honeyBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(app.palette.honey.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.top, 14)
        .accessibilityIdentifier(host ? "account.shareHostCard" : "account.shareProfileCard")
    }

    @State private var submittedExpandedOverride: Bool?

    private var submittedTotal: Int { app.myPendingEvents.count + app.myNeedsFixEvents.count }

    private var submittedExpanded: Bool { submittedExpandedOverride ?? false }

    /// "Submitted Events" row in Host Management: the red number says how many are waiting;
    /// tapping it expands the events right here (View / Withdraw event on each).
    private var submittedEventsRow: some View {
        VStack(spacing: 0) {
            SwipeSafeButton {
                withAnimation(.easeInOut(duration: 0.2)) { submittedExpandedOverride = !submittedExpanded }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 22, height: 22)
                        .opacity(0.72)
                    Text(app.T("Sự Kiện Đã Gửi Chờ Duyệt", "Submitted Events")).font(.system(size: 14))
                    Spacer()
                    if submittedTotal > 0 {
                        Text(submittedTotal > 99 ? "99+" : "\(submittedTotal)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(app.palette.paper)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(BanbeTheme.alert, in: Capsule())
                            .accessibilityIdentifier("account.group.submittedEvents.badge")
                            .accessibilityLabel(app.T("\(submittedTotal) mục mới", "\(submittedTotal) new item(s)"))
                    }
                    Text("›").font(.system(size: 15))
                        .rotationEffect(.degrees(submittedExpanded ? 90 : 0))
                }
                .foregroundStyle(app.palette.ink)
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("account.group.submittedEvents")

            if submittedExpanded {
                if submittedTotal == 0 {
                    Text(app.T("Không có sự kiện nào đang chờ duyệt.", "No events are waiting for review."))
                        .font(.system(size: 12)).opacity(0.65)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.bottom, 14)
                }
                ForEach(app.myPendingEvents, id: \.id) { row in
                    Divider().overlay(app.palette.rule)
                    PendingEventRow(row: row)
                }
                if !app.myNeedsFixEvents.isEmpty {
                    Divider().overlay(app.palette.rule)
                    Button { app.goDashboard(back: .profile) } label: {
                        HStack {
                            Text(app.T("\(app.myNeedsFixEvents.count) sự kiện cần chỉnh sửa — sửa & gửi lại", "\(app.myNeedsFixEvents.count) event(s) need fixing — fix & resubmit"))
                                .font(.system(size: 12.5, weight: .semibold)).underline().foregroundStyle(BanbeTheme.alert)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 11)).opacity(0.5)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 13).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Story posting is a host action — lives on the Host tab.
    private var postStoryCTA: some View {
        Menu {
            Button { app.storyLibraryPickerOpen = true } label: {
                Label(app.T("Thư Viện Ảnh", "Photo Library"), systemImage: "photo.on.rectangle")
            }
            Button { app.storyCameraOpen = true } label: {
                Label(app.T("Camera", "Camera"), systemImage: "camera")
            }
            Button { eventStoryPickerOpen = true } label: {
                Label(app.T("Chọn từ sự kiện của tôi", "Share one of my events"), systemImage: "calendar")
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill").font(.system(size: 22))
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.T("Đăng story", "Post a story")).font(.system(size: 15, weight: .semibold))
                    Text(app.T("Thêm chữ và liên kết, sửa hoặc xóa sau khi đăng", "Add text and a link; edit or delete after posting"))
                        .font(.system(size: 11.5)).opacity(0.65)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 12)).opacity(0.5)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .foregroundStyle(app.palette.ink)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(.top, 14)
        .accessibilityIdentifier("account.postStory")
    }

    /// Pick one of the host's own live events to post as a story (the same
    /// server-checked `create_event_share_story` the Event Detail button uses).
    private var eventStoryPicker: some View {
        let events = app.myOrgEvents.filter { $0.isOpen }
        return NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    if let msg = eventStoryMessage {
                        Text(msg).font(.system(size: 12.5, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !eventStoryLoaded {
                        ProgressView().padding(.top, 40)
                    } else if events.isEmpty {
                        Text(app.T("Bạn chưa có sự kiện nào đang mở để đăng.", "You have no live events to post yet."))
                            .font(.system(size: 13)).opacity(0.7).padding(.top, 40)
                    }
                    ForEach(events, id: \.key) { ev in
                        Button {
                            guard eventStoryBusyKey == nil else { return }
                            eventStoryBusyKey = ev.key
                            Task {
                                // Open the story editor on this event's card — nothing
                                // is published until the host taps "Post story".
                                eventStoryPickerOpen = false
                                try? await Task.sleep(nanoseconds: 450_000_000)   // let the sheet finish closing
                                await app.beginEventStory(ev)
                                eventStoryBusyKey = nil
                            }
                        } label: {
                            HStack(spacing: 12) {
                                CatalogPhoto(path: ev.img, height: 52, width: 52, cornerRadius: 10)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ev.name).font(BanbeTheme.display(15)).lineLimit(1)
                                    Text(ev.when).font(.system(size: 11.5)).opacity(0.7).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                if eventStoryBusyKey == ev.key { ProgressView() }
                                else { Image(systemName: "chevron.right").font(.system(size: 12)).opacity(0.4) }
                            }
                            .padding(12)
                            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("account.eventStory.\(ev.key)")
                    }
                    Text(app.T("Bạn có thể thêm chữ và liên kết trước khi đăng. Story hiển thị trong 24 giờ.", "You can add text and a link before posting. The story stays up for 24 hours."))
                        .font(.system(size: 11)).opacity(0.6).padding(.top, 6)
                }
                .padding(20)
            }
            .foregroundStyle(app.palette.ink)
            .background(app.palette.paper.ignoresSafeArea())
            // The host's event list is only loaded on screens that need it —
            // load it here so the picker never shows an empty list just
            // because Account hadn't fetched it yet.
            .task {
                eventStoryLoaded = false
                await app.loadMyOrgEventSummaries()
                eventStoryLoaded = true
            }
            .navigationTitle(app.T("Đăng sự kiện lên story", "Post an event to your story"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(app.T("Đóng", "Close")) { eventStoryPickerOpen = false } } }
        }
    }

    @ViewBuilder
    private var shareCardSheet: some View {
        if shareCardForHost, let id = app.myOrganizerID, let link = URL(string: "banbe://org/\(id)") {
            ProfileShareSheet(
                kindLabel: app.T("Tổ chức", "Host"),
                name: app.orgRegName.isEmpty ? app.T("Chưa đặt tên", "Unnamed host") : app.orgRegName,
                subtitle: app.myOrgPublishedEventCount.map { app.T("\($0) sự kiện", "\($0) events") } ?? "",
                detail: app.orgRegDesc,
                avatarURL: organizerAvatarURL, roundAvatar: false, link: link, idPrefix: "account.host",
                cardKind: "host", cardID: id, isOwner: true)
        } else if !shareCardForHost, let u = app.user, let handle = u.handle, !handle.isEmpty,
                  let link = URL(string: "banbe://u/\(handle)") {
            ProfileShareSheet(
                kindLabel: app.T("Thành viên", "Member"),
                name: u.displayName, subtitle: "@\(handle)", detail: "",
                avatarURL: u.avatarURL.flatMap(URL.init(string:)), roundAvatar: true, link: link, idPrefix: "account.personal",
                cardKind: "member", cardID: handle, isOwner: true)
        } else {
            Text(app.T("Chưa thể tạo thẻ.", "The card isn't available yet.")).padding(40)
        }
    }

    /// Host tab's OWN rounded profile card (Stage D) — organizer avatar/
    /// name/introduction, stored on `organizers` (migration 090), never
    /// profiles.display_name. Only shown once this account has ever
    /// hosted; a never-hosted account instead sees the "Host your first
    /// event" pitch further down (unchanged).
    // Profile-nav fix pass (2026-09-27) — the whole card is now the single
    // tap target, opening the real organizer management page
    // (DashboardView, real upcoming/past events + check-in), NOT the
    // public profile — visiting the public page is Dashboard's own "Xem
    // như khách" button.
    @ViewBuilder
    private func orgProfileCard() -> some View {
        if app.canHost, app.myOrganizerID != nil {
            SwipeSafeButton {
                app.goDashboard(back: .profile)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 14) {
                        // Story ring (host feature): bright while there's an
                        // unviewed active story, subdued once all are viewed,
                        // none without a story. Tapping opens the viewer; the
                        // rest of the card still opens the dashboard.
                        SwipeSafeButton {
                            if let g = myStoryGroup { app.openStoryViewer(g.organizerId) }
                            else { app.goDashboard(back: .profile) }
                        } label: {
                            ZStack {
                                if let g = myStoryGroup {
                                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                                        .strokeBorder(g.allViewed ? app.palette.rule : BanbeTheme.alert, lineWidth: 2.5)
                                        .frame(width: 66, height: 66)
                                }
                                ZStack {
                                    if let url = organizerAvatarURL {
                                        AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { app.palette.field }
                                    } else {
                                        Text((app.orgRegName.first.map(String.init) ?? "B").uppercased())
                                            .font(BanbeTheme.display(20))
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                            .background(app.palette.field)
                                    }
                                }
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .frame(width: 66, height: 66)
                        }
                        .accessibilityIdentifier("account.storyRing")

                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.orgRegName.isEmpty ? app.T("Chưa đặt tên", "Unnamed host") : app.orgRegName)
                                .font(BanbeTheme.display(18))
                            // Same published-events-only rule as
                            // get_public_profile's event_count/
                            // hosting_since_year (migration 091,
                            // loadMyOrgStats), so this card and the
                            // public page never disagree. nil = not
                            // loaded yet.
                            if let count = app.myOrgPublishedEventCount {
                                Text(app.myOrgHostingSinceYear.map { year in
                                    app.T("Tổ chức từ \(year) ▪︎ \(count) sự kiện", "Hosting since \(year) ▪︎ \(count) events")
                                } ?? app.T("Chưa có sự kiện công khai nào", "No published events yet"))
                                    .font(.system(size: 11)).opacity(0.7)
                            }
                        }
                        Spacer(minLength: 0)
                        Text("›").font(.system(size: 20)).opacity(0.55)
                            .accessibilityIdentifier("org.profile.viewPublic")
                    }
                    if !app.orgRegDesc.isEmpty {
                        Text(app.orgRegDesc).font(.system(size: 12.5)).opacity(0.85)
                    }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(app.palette.ink)
            .padding(16)
            // Account regression fix pass (2026-09-27), Item 4 — same
            // visual quality as the personal card's own gradient wash
            // (account.profileCard, above), but a deliberately DIFFERENT
            // palette (moss, never the account's own chosen profileTheme)
            // so this always reads as a distinct organization identity,
            // never a second copy of the personal card.
            .background(
                LinearGradient(
                    colors: [(ProfilePalette.all.first { $0.key == "moss" }?.color ?? ProfilePalette.all[0].color).opacity(0.4), .clear],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(app.palette.rule, lineWidth: 1))
            .padding(.top, 22)
            .accessibilityIdentifier("org.profile.card")
        }
    }

    private var organizerAvatarURL: URL? {
        guard !app.myOrganizerAvatarPath.isEmpty else { return nil }
        return MediaURLs.organizerAvatar(path: app.myOrganizerAvatarPath, r2Ref: app.myOrganizerAvatarR2Ref, variant: .card)
    }

    // TASK C — mirrors HomeView's own retryScrollRestoreIfNeeded() exactly
    // (see that one's doc comment for the full "why a nil-then-reassign" —
    // SwiftUI's `.scrollPosition(id:)` won't re-trigger a scroll if the
    // binding is set to the SAME id it already holds, so this is a real
    // requirement, not defensive padding). No data-readiness branch is
    // needed here the way Home's has one: every section id above renders
    // from state that's already in hand by the time this View exists (no
    // equivalent async "feed" gate its own content is waiting on), so this
    // never needs to fall back to a delayed retry.
    private func retryScrollRestoreIfNeeded() {
        guard !didAttemptScrollRestore, let target = app.accountScrollAnchorIDByTab[app.accountTab] else { return }
        didAttemptScrollRestore = true
        let tab = app.accountTab
        app.accountScrollAnchorIDByTab[tab] = nil
        DispatchQueue.main.async {
            app.accountScrollAnchorIDByTab[tab] = target
        }
    }

    /// Fixed-header pass (2026-10-02) — per-tab scroll anchor (see
    /// `AppState.accountScrollAnchorIDByTab`'s own doc comment), so
    /// switching Personal/Host/Admin and coming back preserves EACH tab's
    /// own position independently instead of one shared anchor.
    private var accountScrollAnchorBinding: Binding<String?> {
        Binding(
            get: { app.accountScrollAnchorIDByTab[app.accountTab] },
            set: { app.accountScrollAnchorIDByTab[app.accountTab] = $0 }
        )
    }
}

/// TASK 1 (dock "+" native-menu pass) — extracted out of AccountView (it
/// used to be a private `var` there) since the story picker/preview
/// presentation it's part of is now centralized in RootView (any screen's
/// "Post a story" action can trigger it, not just AccountView's own).
/// Retake re-opens the camera directly, matching AccountView's own
/// original behavior, regardless of whether library or camera was the
/// original source.
struct StoryCreatePreviewView: View {
    var body: some View { StoryEditorView() }
}


/// One searchable destination in the Account area. `vi`/`en` are the
/// visible titles; matching looks at BOTH languages plus `keywords`, the
/// section and the tab's own title, ignoring case and diacritics, so e.g.
/// "hoa don", "Hóa đơn" and "invoice" all find Invoices.
struct AccountSearchEntry: Identifiable {
    let id: String
    let tab: String
    let secVi: String
    let secEn: String
    let vi: String
    let en: String
    let icon: String
    let keywords: String
    let action: () -> Void

    /// Lowercased, accent-stripped (including Vietnamese "đ").
    static func fold(_ s: String) -> String {
        s.replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "d")
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "vi_VN"))
    }

    /// Every word typed must appear somewhere in the entry's text; an empty
    /// query matches everything.
    func matches(_ query: String, tabVi: String, tabEn: String) -> Bool {
        let tokens = Self.fold(query).split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard !tokens.isEmpty else { return true }
        let haystack = Self.fold([vi, en, secVi, secEn, tabVi, tabEn, keywords].joined(separator: " "))
        return tokens.allSatisfy { haystack.contains($0) }
    }
}
