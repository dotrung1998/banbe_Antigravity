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
    /// Bumped whenever Account becomes visible; replays the host card's reminder halo.
    @State private var hostHaloTrigger = 0
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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

    // note 66 — the Personal/Host/Admin tabs are gone: the content follows `app.organizerMode`.
    // `app.accountTab` stays on AppState for compatibility but is never rendered or read here.

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
            myHolding: app.myHolding, myPendingVerification: app.myPendingVerification, myAdminInvite: app.myAdminInvite, myRefunds: app.myRefunds,
            refundDestinations: app.refundDestinationsLoaded ? app.refundDestinations : nil,
            onOpenPayment: { app.openPaymentDetails($0, back: .profile) },
            onOpenMyRefunds: { app.openMyRefunds(back: .profile) },
            onOpenAdminInvite: { app.accountGroupKey = "adminTeam"; app.screen = .accountGroup },
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
            onOpenDashboard: { app.goDashboard(back: .profile) },
            onOpenAttendance: { key in app.openAttendance(key, back: .profile) },
            // Same single-dispute shortcut as the goer half, so the host's own
            // link reaches the same dispute the goer's does.
            onOpenRefundDispute: { claimID, back in app.openRefundDisputeFromActionCenter(claimID: claimID, back: back) },
            T: app.T
        )))
    }

    /// note 66 — one list in both modes (goer + host duties), so nothing owed hides behind the mode switch.
    private var actionItems: [ActionCenterItem] {
        sortActionCenterItems(goerActionItems + hostActionItems)
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
        // note 66 — no tab swipe any more: a horizontal swipe on Account belongs to the dock again.
        }
        .task { if app.userID != nil { await app.loadHomeStories() } }
        .task { if app.userID != nil { await app.loadMyOrganizerMemberships() } }
        // Admin Team pass (2026-10-02) — this account's own pending admin
        // invite (reachable regardless of role) and, for a manage-admins-
        // capable admin, the roster/invites source for the Admin-tab
        // badge — same "load it here so the badge is real, not stale"
        // reasoning as pendingEventsCount below.
        // .task(id:) re-runs when the signed-in user resolves — a plain .task ran
        // once on first appear and was skipped for good if the session was
        // still restoring (userID nil) at that moment.
        .task(id: app.userID) { if app.userID != nil { await app.loadMyAdminInvite() } }
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
        .task(id: app.organizerMode) {
            guard app.userID != nil, app.canHost, app.organizerMode else { return }
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
        .onAppear { hostHaloTrigger += 1; retryScrollRestoreIfNeeded(); consumeTeamHighlightsIfNeeded() }
        // note 66 — the rewards strip reads the same summary as Home's streak/coins capsule.
        .task(id: app.rewardsEnabled) {
            if app.userID != nil, app.rewardsEnabled, app.rewardsSummaryStatus != .loaded { await app.loadRewardsSummary() }
        }
        .onChange(of: app.screen) { _, new in if new == .profile { hostHaloTrigger += 1 } }
        .onChange(of: app.teamInviteHighlightOrganizerId) { _, _ in consumeTeamHighlightsIfNeeded() }
        .onChange(of: app.eventCreditHighlightId) { _, _ in consumeTeamHighlightsIfNeeded() }
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
                    // Note 53: same focus ring as every other field (clay border + soft halo) while typing.
                    .fieldChrome(focused: searchFocused, cornerRadius: 20, bordered: false)
                    .foregroundStyle(app.palette.ink)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("account.searchInput")
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                // Note 53: the shared dock header (same logo, gap and title as Home/Schedule/Messages).
                DockHeaderTitle(title: app.T("Tài khoản", "Account"), identifier: "account.title")
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
        .frame(height: DockHeaderTitle.rowHeight)  // note 53: same row height on every dock tab
        .padding(.horizontal, DockHeaderTitle.horizontalPadding)
        .padding(.top, 16)
    }

    /// note 66 (Simple Shell phase 2) — Account has no tabs: its content follows the mode. Goer: profile card,
    /// four tiles, rewards strip, Action Center, team-invite banner, More, Host-your-first-event, Sign out.
    /// Host: organizer card, four host tiles, rewards strip, Action Center, More, Sign out. Admin tools are a
    /// row in More (the 'admin' AccountGroup). Sign out renders once, at the very bottom.
    private var isHostMode: Bool { app.organizerMode && app.canHost }

    /// Keys the scroll anchor and the content identity (was `app.accountTab`).
    private var modeKey: String { isHostMode ? "host" : "personal" }

    private var accountContent: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if isHostMode {
                hostIdentity
            } else {
                personalProfileCard
            }

            AccountTilesGrid(tiles: isHostMode ? hostTiles : goerTiles)
                .padding(.top, 16)
                .id("account-tiles")

            if app.rewardsEnabled { rewardsStrip.padding(.top, 12) }

            // Same canonical Action Center as Home; only when it has items. Goer and host duties are shown
            // together in both modes so owed money is never hidden behind a mode switch.
            if !actionItems.isEmpty {
                ActionCenterView(items: actionItems, onSeeAll: { app.openVerifications(back: .profile) })
                    .padding(.top, 6)
            }

            if !isHostMode && !app.myOrganizerInvites.isEmpty { teamInviteBanner }

            sectionHeader(app.T("Thêm", "More"), topPadding: 24)
                .accessibilityIdentifier("account.section.more")
            moreCard.padding(.top, 10)
            if !app.organizerModeError.isEmpty {
                Text(app.organizerModeError)
                    .font(.system(size: 12))
                    .foregroundStyle(BanbeTheme.alert)
                    .padding(.top, 10)
            }

            if !isHostMode && !app.canHost { hostFirstEventCard }

            signOutButton
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        // A mode switch swaps the whole body (and its own scroll anchor), like a tab switch used to.
        .id(modeKey)
        .transition(.opacity)
        .sheet(isPresented: $shareCardOpen) { shareCardSheet }
        .sheet(isPresented: $eventStoryPickerOpen) { eventStoryPicker }
    }

    // MARK: Identity

    /// The goer identity card (unchanged: KeychainFrame charm, rename, › to the public profile).
    private var personalProfileCard: some View {
        HStack(spacing: 14) {
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
            }
            Spacer(minLength: 0)
            if app.isSignedIn {
                SwipeSafeButton {
                    openOwnPublicProfile()
                } label: {
                    Image(systemName: "chevron.right").font(.system(size: 16)).foregroundStyle(app.palette.ink.opacity(0.55))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(app.T("Hồ sơ cá nhân", "Personal profile"))
                .accessibilityIdentifier("account.editProfile")
            }
        }
        .keychainProfileCharm(handle: app.user?.handle, layout: .leading, outset: 16)
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
    }

    /// Host mode: the organizer card (or its ensure card), plus a small link to the personal public profile.
    @ViewBuilder
    private var hostIdentity: some View {
        orgProfileCard()
        if let handle = app.user?.handle, !handle.isEmpty {
            SwipeSafeButton { openOwnPublicProfile() } label: {
                HStack(spacing: 4) {
                    Text(app.T("Hồ sơ cá nhân", "Personal profile"))
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(app.palette.ink2)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(app.T("Hồ sơ cá nhân", "Personal profile"))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("account.switchIdentity")
        }
    }

    private func openOwnPublicProfile() {
        if let handle = app.user?.handle, !handle.isEmpty {
            app.openPublicProfile(handle: handle, back: .profile)
        }
    }

    // MARK: Tiles

    private var goerTiles: [AccountTile] {
        let going = app.goingEventsCount
        let saved = app.favorites.count
        return [
            AccountTile(key: "tickets", symbol: "ticket", title: app.T("Vé & đặt chỗ", "Tickets"),
                        value: app.T("\(going) sắp tới", "\(going) upcoming"),
                        badge: AccountBadges.myTicketsActionCount(paymentBookings: app.paymentBookings)) { openGroup("activity") },
            AccountTile(key: "wallet", symbol: "creditcard", title: app.T("Ví & chứng từ", "Wallet"),
                        value: app.T("Hoá đơn, biên nhận, hoàn tiền", "Invoices, receipts, refunds"),
                        badge: AccountBadges.myRefundActionCount(myRefunds: app.myRefunds)) { openGroup("payments") },
            AccountTile(key: "saved", symbol: "heart", title: app.T("Đã lưu", "Saved"),
                        value: app.T("\(saved) sự kiện", saved == 1 ? "1 event" : "\(saved) events")) { app.goSavedList() },
            AccountTile(key: "help", symbol: "questionmark.circle", title: app.T("Trợ giúp", "Help"),
                        value: app.T("Hướng dẫn, điều khoản, Q&A", "Guides, terms, Q&A")) { openGroup("helpLegal") },
        ]
    }

    private var hostTiles: [AccountTile] {
        let opsBadge = AccountBadges.hostActionCount(organizerMode: app.organizerMode, verificationsCount: app.verifications.count, refundQueue: app.refundQueue)
        let teamBadge = app.myOrganizerInvites.count + app.myEventCredits.count
        let eventsValue: String = {
            if submittedTotal > 0 { return app.T("\(submittedTotal) chờ duyệt", "\(submittedTotal) in review") }
            if let n = app.myOrgPublishedEventCount { return app.T("\(n) đã đăng", n == 1 ? "1 published" : "\(n) published") }
            return app.T("Quản lý & điểm danh", "Manage & check in")
        }()
        return [
            AccountTile(key: "events", symbol: "calendar", title: app.T("Sự kiện", "Events"),
                        value: eventsValue, badge: submittedTotal) { app.goDashboard(back: .profile) },
            AccountTile(key: "getpaid", symbol: "banknote", title: app.T("Nhận tiền", "Get paid"),
                        value: opsBadge > 0 ? app.T("\(opsBadge) việc cần làm", "\(opsBadge) to do")
                                            : app.T("Xác nhận, hoàn tiền, chứng từ", "Verify, refunds, documents"),
                        badge: opsBadge) { openGroup("hostOps") },
            AccountTile(key: "team", symbol: "person.3", title: app.T("Đội ngũ", "Team"),
                        value: app.T("Thành viên & lời mời", "Members & invites"), badge: teamBadge) { openGroup("team") },
            AccountTile(key: "reports", symbol: "chart.bar.doc.horizontal", title: app.T("Báo cáo", "Reports"),
                        value: app.T("Số liệu & xuất file", "Metrics & exports")) { openHostReports() },
        ]
    }

    /// Host reports need an organizer; without one, the ensure (host setup) flow opens instead.
    private func openHostReports() {
        if let id = app.myOrganizerID {
            app.openReports(scope: "host", organizerID: id, back: .profile)
        } else {
            app.hostSetupOpen = true
        }
    }

    // MARK: Rewards strip

    private var rewardsStrip: some View {
        let summary = app.rewardsSummaryStatus == .loaded ? app.rewardsSummary : nil
        let text: String
        let spoken: String
        if let sum = summary {
            let streak = RewardsLogic.capsuleStreak(sum, weekly: app.rewardsV2Enabled)
            text = streak.weekly
                ? app.T("🔥 Chuỗi \(streak.value) tuần · \(RewardsLogic.compactCoins(sum.balance)) xu", "🔥 \(streak.value)-week streak · \(RewardsLogic.compactCoins(sum.balance)) coins")
                : app.T("🔥 Chuỗi \(streak.value) ngày · \(RewardsLogic.compactCoins(sum.balance)) xu", "🔥 \(streak.value)-day streak · \(RewardsLogic.compactCoins(sum.balance)) coins")
            spoken = app.T("Phần thưởng & huy hiệu, ", "Rewards & badges, ") + text.replacingOccurrences(of: "🔥 ", with: "")
        } else {
            text = app.T("Phần thưởng & huy hiệu", "Rewards & badges")
            spoken = text
        }
        return SwipeSafeButton { app.openRewards(from: .profile) } label: {
            HStack(spacing: 10) {
                if summary == nil {
                    Image(systemName: "circle.hexagongrid.circle").font(.system(size: 16, weight: .medium)).accessibilityHidden(true)
                }
                Text(text).font(.subheadline.weight(.semibold)).monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(app.palette.ink3)
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(app.palette.surface1, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("account.rewards")
    }

    // MARK: Team invite banner (goer only)

    private var teamInviteBanner: some View {
        SwipeSafeButton { openGroup("team") } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.3").font(.system(size: 16, weight: .medium)).frame(width: 22, height: 22).opacity(0.72)
                Text(app.T("Bạn có lời mời Team", "You have a team invite")).font(.system(size: 14))
                Spacer()
                Text("\(app.myOrganizerInvites.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(BanbeTheme.onAlert)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(BanbeTheme.alert, in: Capsule())
                    .accessibilityIdentifier("account.teamInviteBanner.badge")
                Text("›").font(.system(size: 15))
            }
            .foregroundStyle(app.palette.ink)
            .padding(16)
            .background(app.palette.surface1, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
        .accessibilityIdentifier("account.teamInviteBanner")
    }

    // MARK: More

    @ViewBuilder
    private var moreCard: some View {
        VStack(spacing: 0) {
            moreRow(app.T("Thông báo", "Notifications"), icon: "bell", identifier: "account.notifications",
                    badge: app.unreadNotifications) { app.goNotifications(back: .profile) }
            if isHostMode {
                moreDivider()
                postStoryRow
                if app.myOrganizerID != nil {
                    moreDivider()
                    moreRow(app.T("Chia sẻ thẻ tổ chức", "Share host card"), icon: "qrcode", identifier: "account.shareHostCard") {
                        shareCardForHost = true; shareCardOpen = true
                    }
                }
                moreDivider()
                moreRow(app.T("Khảo sát & ý tưởng sự kiện", "Surveys & event ideas"), icon: "lightbulb", identifier: "account.group.surveys") {
                    app.screen = .surveysHosting
                }
                moreDivider()
                moreRow(app.T("Hồ sơ tổ chức", "Organizer profile"), icon: "storefront", identifier: "account.organizerProfile") {
                    if let id = app.myOrganizerID { app.openOrganizerProfile(organizerID: id, back: .profile) } else { app.hostSetupOpen = true }
                }
            } else {
                moreDivider()
                moreRow(app.T("Đang theo dõi", "Following"), icon: "person.crop.circle.badge.checkmark", identifier: "account.following",
                        trailing: app.followedStatus == .loaded ? "\(app.followedOrgIDs.count)" : nil) { app.screen = .following }
                if app.referralLink != nil {
                    moreDivider()
                    moreRow(app.T("Mời bạn bè", "Invite friends"), icon: "person.2", identifier: "account.inviteFriends") { app.shareReferral() }
                }
                if let handle = app.user?.handle, !handle.isEmpty {
                    moreDivider()
                    moreRow(app.T("Chia sẻ thẻ của bạn", "Share your card"), icon: "qrcode", identifier: "account.shareProfileCard") {
                        shareCardForHost = false; shareCardOpen = true
                    }
                }
                moreDivider()
                moreRow(app.T("Báo cáo", "Reports"), icon: "chart.bar.doc.horizontal", identifier: "account.reportsPersonal") {
                    app.openReports(scope: "personal", back: .profile)
                }
            }
            moreDivider()
            moreRow(app.T("Cài đặt", "Settings"), icon: "gearshape", identifier: "account.group.preferences") { openGroup("preferences") }
            moreDivider()
            moreRow(imageCacheClearedAt == nil ? app.T("Xoá bộ nhớ đệm hình ảnh", "Clear image cache")
                                               : app.T("Đã xoá bộ nhớ đệm hình ảnh", "Image cache cleared"),
                    icon: "photo.stack", identifier: "account.clearImageCache", chevron: false) {
                PhotoLoader.clearCache()
                imageCacheClearedAt = Date()
            }
            moreDivider()
            hostingToggleRow
            if app.isAdmin {
                moreDivider()
                moreRow(app.T("Công cụ quản trị", "Admin tools"), icon: "checkmark.shield", identifier: "account.adminTools",
                        badge: AccountBadges.adminModerationCount(accountType: app.accountType, pendingEventsCount: app.pendingEventsCount)
                            + app.adminInvites.filter { $0.status == "pending" }.count) { openGroup("admin") }
            }
        }
        .background(app.palette.surface1, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func moreDivider() -> some View {
        Rectangle().fill(app.palette.divider).frame(height: 1 / UIScreen.main.scale).padding(.leading, 50)
    }

    private func moreRowLabel(_ title: String, icon: String, badge: Int = 0, trailing: String? = nil, chevron: Bool = true) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 22, height: 22)
                .foregroundStyle(app.palette.ink2)
                .accessibilityHidden(true)
            Text(title).font(.body).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if badge > 0 {
                Text(AccountBadges.format(badge))
                    .font(.caption2.weight(.bold)).monospacedDigit()
                    .padding(.horizontal, 6)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(BanbeTheme.alert, in: Capsule())
                    .foregroundStyle(BanbeTheme.onAlert)
            }
            if let trailing { Text(trailing).font(.subheadline).foregroundStyle(app.palette.ink2) }
            if chevron {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(app.palette.ink3)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func moreRow(_ title: String, icon: String, identifier: String, badge: Int = 0, trailing: String? = nil,
                         chevron: Bool = true, action: @escaping () -> Void) -> some View {
        SwipeSafeButton(action: action) {
            moreRowLabel(title, icon: icon, badge: badge, trailing: trailing, chevron: chevron)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(badge > 0 ? app.T("\(title), \(badge) mục mới", "\(title), \(badge) new item(s)")
                                      : (trailing.map { "\(title), \($0)" } ?? title))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
    }

    /// Host mode: Post a story (same menu as before, incl. "Share one of my events").
    private var postStoryRow: some View {
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
            moreRowLabel(app.T("Đăng story", "Post a story"), icon: "plus.circle", chevron: false)
                .overlay(alignment: .trailing) {
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 12)).foregroundStyle(app.palette.ink3)
                        .padding(.trailing, 16).accessibilityHidden(true)
                }
        }
        .accessibilityIdentifier("account.postStory")
    }

    /// Hosting mode on/off (the same toggle as before; keeps the tour target).
    private var hostingToggleRow: some View {
        SwipeSafeButton { app.toggleOrganizerMode() } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.2.badge.gearshape")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 22, height: 22)
                    .foregroundStyle(app.palette.ink2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.T("Chế độ tổ chức", "Hosting mode")).font(.body)
                    Text(app.T("Bật để tạo và quản lý sự kiện.", "Turn on to create and manage events."))
                        .font(.footnote)
                        .foregroundStyle(app.palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
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
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(app.organizerModeBusy)
        .opacity(app.organizerModeBusy ? 0.55 : 1)
        .accessibilityIdentifier("account.organizerToggle")
        .tourTarget("tour.account.organizerMode")
        .id("account-hosting-toggle")
    }

    /// Goer who has never hosted: a compact pitch.
    private var hostFirstEventCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(app.T("Tổ chức sự kiện đầu tiên", "Host your first event"))
                .font(BanbeTheme.display(17))
            Text(app.T("Miễn phí khi banbe còn mới. Không phí đăng, không phí giao dịch.",
                       "Free while banbe is new. No listing or transaction fees."))
                .font(.footnote)
                .foregroundStyle(app.palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
            InkButton(title: app.T("Bắt đầu tổ chức ▪︎ miễn phí", "Start hosting ▪︎ free")) {
                app.toggleOrganizerMode()
            }
        }
        .foregroundStyle(app.palette.ink)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(app.palette.surface1, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.top, 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("account.hostFirstEvent")
    }

    /// Rendered once, at the very bottom (it used to render under every tab).
    private var signOutButton: some View {
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
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .font(.system(size: 14))
        .foregroundStyle(app.palette.ink)
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)   // one element (the Label's icon was a second "button")
        .accessibilityIdentifier(app.isSignedIn ? "account.signOut" : "account.signIn")
        .padding(.top, 20)
        .padding(.bottom, BottomTabBar.contentClearance)
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
            highlightedTeamInviteOrganizerId = target
            app.teamInviteHighlightOrganizerId = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                if highlightedTeamInviteOrganizerId == target { highlightedTeamInviteOrganizerId = nil }
            }
        }
        if let target = app.eventCreditHighlightId,
           app.myEventCredits.contains(where: { $0.id == target }) || app.myConfirmedEventCredits.contains(where: { $0.id == target }) {
            highlightedEventCreditId = target
            app.eventCreditHighlightId = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                if highlightedEventCreditId == target { highlightedEventCreditId = nil }
            }
        }
    }

    // MARK: Search

    private func openGroup(_ key: String) {
        app.accountGroupParentKey = nil   // note 66: opened straight from Account
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
        // note 66 — sections follow the new layout: the top tiles ("Account") and the More card ("More").
        let actVi = "Tài khoản", actEn = "Account"
        let setVi = "Thêm", setEn = "More"
        var list: [AccountSearchEntry] = [
            e("tickets", "personal", actVi, actEn, "Vé & đặt chỗ", "Tickets", "ticket",
              "vé ticket booking đặt chỗ giữ chỗ hold qr check-in đã hủy hết hạn cancelled expired my tickets vé của tôi bookings") { openGroup("activity") },
            e("going", "personal", actVi, actEn, "Đang tham gia", "Going", "checkmark.circle",
              "attending sắp tham gia sự kiện của tôi my events upcoming sắp tới") { app.goGoingList() },
            e("schedule", "personal", actVi, actEn, "Lịch của tôi", "My schedule", "calendar",
              "lịch schedule calendar agenda kế hoạch plans hôm nay today tuần week") { app.goSchedule() },
            e("saved", "personal", actVi, actEn, "Đã lưu", "Saved", "heart",
              "lưu yêu thích favorites favourite bookmark wishlist saved events sự kiện đã lưu") { app.goSavedList() },
            e("past", "personal", actVi, actEn, "Sự Kiện Quá Khứ", "Past Events", "calendar.badge.checkmark",
              "đã hoàn thành completed ended lịch sử history đã qua") { app.goCompletedList(back: .profile) },
            e("payments", "personal", actVi, actEn, "Ví & chứng từ", "Wallet", "creditcard",
              "ví wallet thanh toán payment payments documents tiền money giấy tờ chứng từ") { openGroup("payments") },
            e("invoices", "personal", actVi, actEn, "Hoá đơn", "Invoices", "doc.text",
              "hóa đơn invoice bill tài liệu pdf ví wallet") { app.openDocuments(kind: "invoice", role: "guest", back: .profile) },
            e("receipts", "personal", actVi, actEn, "Biên nhận", "Receipts", "receipt",
              "receipt biên lai chứng từ pdf ví wallet") { app.openDocuments(kind: "receipt", role: "guest", back: .profile) },
            e("refundAccounts", "personal", actVi, actEn, "Tài khoản thanh toán & nhận hoàn tiền", "Payment & refund accounts", "banknote",
              "ngân hàng bank tài khoản account số tài khoản momo chuyển khoản hoàn tiền refund destination") { app.openRefundAccounts(back: .profile) },
            e("refunds", "personal", actVi, actEn, "Hoàn tiền", "Refunds", "checklist",
              "refund hoàn trả trả lại tiền hủy sự kiện tranh chấp dispute") { app.openMyRefunds(back: .profile) },
            e("help", "personal", actVi, actEn, "Trợ giúp", "Help", "questionmark.circle",
              "help trợ giúp hỗ trợ support policy chính sách điều khoản terms privacy quyền riêng tư pháp lý legal liên hệ contact hướng dẫn guide hỏi đáp faq q&a câu hỏi questions") { openGroup("helpLegal") },
            e("rewards", "personal", actVi, actEn, "Phần thưởng & huy hiệu", "Rewards & badges", "circle.hexagongrid.circle",
              "rewards phần thưởng huy hiệu badges coin xu streak chuỗi ngày milestone thành tích") { app.openRewards(from: .profile) },
            e("profile", "personal", actVi, actEn, "Hồ sơ cá nhân", "Personal profile", "person.crop.circle",
              "profile hồ sơ tên name avatar ảnh đại diện handle chỉnh sửa edit public trang cá nhân") { openOwnPublicProfile() },
            e("notifications", "personal", setVi, setEn, "Thông báo", "Notifications", "bell",
              "thông báo notifications chuông bell alerts cập nhật updates") { app.goNotifications(back: .profile) },
            e("following", "personal", setVi, setEn, "Đang theo dõi", "Following", "person.crop.circle.badge.checkmark",
              "following theo dõi follow host tổ chức organizer followed unfollow bỏ theo dõi") { app.screen = .following },
            e("reportsPersonal", "personal", setVi, setEn, "Báo cáo", "Reports", "chart.bar.doc.horizontal",
              "thống kê statistics analytics báo cáo report số liệu insights metrics") { app.openReports(scope: "personal", back: .profile) },
            e("preferences", "personal", setVi, setEn, "Cài đặt", "Settings", "gearshape",
              "settings cài đặt tùy chỉnh preferences app preferences") { openGroup("preferences") },
            e("language", "personal", setVi, setEn, "Ngôn ngữ & Hiển thị", "Language & Appearance", "slider.horizontal.3",
              "ngôn ngữ language tiếng việt english vn en theme giao diện sáng tối dark light mode hiển thị appearance kính glass độ trong suốt") { app.openPreferences() },
            e("security", "personal", setVi, setEn, "Bảo mật", "Security", "lock.shield",
              "security mật khẩu password face id sinh trắc biometric đăng nhập login khóa lock đổi mật khẩu") { app.openSecurity() },
            e("organizerMode", "personal", setVi, setEn, "Chế độ tổ chức", "Hosting mode", "person.2.badge.gearshape",
              "host tổ chức organizer mode bật tắt toggle tạo sự kiện create event quản lý manage") { app.toggleOrganizerMode() },
            e("clearCache", "personal", setVi, setEn, "Xoá bộ nhớ đệm hình ảnh", "Clear image cache", "photo.stack",
              "cache bộ nhớ đệm dung lượng storage ảnh hình image xóa clear") { PhotoLoader.clearCache(); imageCacheClearedAt = Date() },
            e("signOut", "personal", setVi, setEn, app.isSignedIn ? "Đăng xuất" : "Đăng nhập", app.isSignedIn ? "Sign out" : "Sign in", "rectangle.portrait.and.arrow.right",
              "logout log out thoát đăng xuất đăng nhập sign in login tài khoản account") {
                  if app.isSignedIn { Task { await app.signOut() } } else { app.goLogin() }
              },
        ]
        if app.referralLink != nil {
            list.append(e("inviteFriends", "personal", setVi, setEn, "Mời bạn bè", "Invite friends", "person.2",
                          "mời invite bạn bè friends giới thiệu referral link chia sẻ share") { app.shareReferral() })
        }
        if let handle = app.user?.handle, !handle.isEmpty {
            list.append(e("shareCard", "personal", setVi, setEn, "Chia sẻ thẻ của bạn", "Share your card", "qrcode",
                          "thẻ card qr chia sẻ share hồ sơ profile") { shareCardForHost = false; shareCardOpen = true })
        }
        if app.organizerMode && app.canHost {
            let hVi = "Tổ Chức", hEn = "Host"
            list += [
                e("hostEvents", "host", hVi, hEn, "Sự kiện", "Events", "calendar",
                  "sự kiện events quản lý manage điểm danh check-in chờ duyệt submitted pending dashboard") { app.goDashboard(back: .profile) },
                e("hostOps", "host", hVi, hEn, "Nhận tiền", "Get paid", "banknote",
                  "nhận tiền get paid vận hành operations thanh toán payments tổ chức host sự kiện") { openGroup("hostOps") },
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
                e("team", "host", hVi, hEn, "Đội ngũ", "Team", "person.3",
                  "team đội nhóm thành viên member mời invite đóng góp contribution credit") { openGroup("team") },
                e("reportsHost", "host", hVi, hEn, "Báo cáo", "Reports", "chart.bar.doc.horizontal",
                  "thống kê statistics analytics báo cáo report số liệu doanh thu metrics") { openHostReports() },
                e("surveys", "host", hVi, hEn, "Khảo sát & ý tưởng sự kiện", "Surveys & event ideas", "lightbulb",
                  "survey khảo sát ý tưởng idea góp ý feedback câu hỏi form") { app.screen = .surveysHosting },
                e("organizerProfile", "host", hVi, hEn, "Hồ sơ tổ chức", "Organizer profile", "storefront",
                  "hồ sơ tổ chức organizer profile trang tổ chức host page") {
                      if let id = app.myOrganizerID { app.openOrganizerProfile(organizerID: id, back: .profile) } else { app.hostSetupOpen = true }
                  },
            ]
            if app.myOrganizerID != nil {
                list.append(e("shareHostCard", "host", hVi, hEn, "Chia sẻ thẻ tổ chức", "Share host card", "qrcode",
                              "thẻ card qr chia sẻ share tổ chức host") { shareCardForHost = true; shareCardOpen = true })
            }
        }
        if app.accountType == "admin" {
            let aVi = "Quản Trị", aEn = "Administration"
            // note 66 — the two admin groups open nested under Administration, so Back returns there.
            list += [
                e("adminTools", "admin", aVi, aEn, "Công cụ quản trị", "Admin tools", "checkmark.shield",
                  "admin quản trị công cụ tools administration") { openGroup("admin") },
                e("adminReview", "admin", aVi, aEn, "Duyệt & Kiểm Duyệt", "Review & Moderation", "exclamationmark.shield",
                  "duyệt review kiểm duyệt moderation approve phê duyệt") {
                      app.accountGroupKey = "adminReview"; app.screen = .accountGroup; app.accountGroupParentKey = "admin"
                  },
                e("disputes", "admin", aVi, aEn, "Tranh Chấp Thanh Toán", "Payment Disputes", "exclamationmark.bubble",
                  "tranh chấp dispute khiếu nại escalation thanh toán payment dashboard bảng điều khiển bảng quản trị admin panel") { app.openAdminDashboard() },
                e("pendingEvents", "admin", aVi, aEn, "Sự Kiện Chờ Duyệt", "Pending Events", "exclamationmark.shield",
                  "sự kiện chờ duyệt pending events approve từ chối reject") { app.openAdminEvents() },
                e("adminTeam", "admin", aVi, aEn, "Đội Ngũ Quản Trị", "Admin Team", "person.3.fill",
                  "admin quản trị viên mời invite thành viên team đội ngũ") {
                      app.accountGroupKey = "adminTeam"; app.screen = .accountGroup; app.accountGroupParentKey = "admin"
                  },
                e("reportsAdmin", "admin", aVi, aEn, "Số Liệu & Báo Cáo", "Metrics & Reports", "chart.bar.doc.horizontal",
                  "thống kê statistics analytics báo cáo report số liệu") { app.openReports(scope: "admin", back: .profile) },
                e("adminGuide", "admin", aVi, aEn, "Hướng Dẫn Quản Trị", "Admin Guide", "checklist",
                  "admin guide hướng dẫn quản trị help trợ giúp") { app.accountGroupKey = nil; app.helpGuideKey = "admin"; app.screen = .helpGuide },
            ]
        }
        // Rewards & badges can be hidden by an admin (migration 187): its search entry goes with the row.
        return list.filter { $0.id != "rewards" || app.rewardsEnabled }
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
                            // Keep the search open with its query, so swiping back
                            // from the result returns to these same results.
                            searchFocused = false
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
        .padding(.bottom, BottomTabBar.contentClearance)
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

    @State private var shareCardOpen = false
    @State private var eventStoryPickerOpen = false
    @State private var eventStoryBusyKey: String?
    @State private var eventStoryLoaded = false
    @State private var eventStoryMessage: String?
    @State private var shareCardForHost = false

    private var submittedTotal: Int { app.myPendingEvents.count + app.myNeedsFixEvents.count }

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
        if app.canHost, app.organizerMode, app.myOrganizerID == nil, !app.hostSetupOpen {
            // No organizer yet (setup skipped, or it could not finish): offer the setup sheet again.
            VStack(alignment: .leading, spacing: 10) {
                Text(app.T("Hoàn tất hồ sơ tổ chức", "Finish your host profile")).font(BanbeTheme.display(18))
                Text(app.T("Chọn ảnh bìa, đặt tên và viết vài dòng giới thiệu để khách biết bạn là ai.",
                           "Pick a cover, name it and add a short intro so guests know who you are."))
                    .font(.system(size: 12.5)).opacity(0.75)
                InkButton(title: app.T("Thiết lập hồ sơ", "Set up profile")) { app.hostSetupOpen = true }
                    .accessibilityIdentifier("account.setupHostProfile")
            }
            .foregroundStyle(app.palette.ink)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.top, 22)
            .accessibilityIdentifier("account.ensureOrganizer")
        } else if app.canHost, app.myOrganizerID != nil {
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
                        if app.hostReminderPhase != nil {
                            // An event is starting soon / in progress: tell the host where this card goes.
                            Text(app.T("Điểm danh", "Check-in"))
                                .font(.system(size: 12, weight: .bold)).foregroundStyle(Color(hex: 0x7A5200))
                                .accessibilityIdentifier("org.profile.checkinHint")
                        }
                        Text("›").font(.system(size: 20)).opacity(app.hostReminderPhase != nil ? 1 : 0.55)
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
            .overlay {
                if app.hostReminderPhase != nil { EventReminderHalo(trigger: hostHaloTrigger, cornerRadius: 14) }
            }
            // Where the host-setup reveal's dots assemble.
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { app.hostCardFrame = g.frame(in: .global) }
                    .onChange(of: g.frame(in: .global)) { _, f in app.hostCardFrame = f }
            })
            .padding(.top, 22)
            .id("account-host-card") // scroll target: the host-setup reveal brings the whole card into view
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
        guard !didAttemptScrollRestore, let target = app.accountScrollAnchorIDByTab[modeKey] else { return }
        didAttemptScrollRestore = true
        let tab = modeKey
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
            get: { app.accountScrollAnchorIDByTab[modeKey] },
            set: { app.accountScrollAnchorIDByTab[modeKey] = $0 }
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
