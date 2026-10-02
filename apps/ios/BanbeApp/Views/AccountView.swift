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
    "adminTeam": ProfilePalette.all.first { $0.key == "ink" }!.color,
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
    private var actionItems: [ActionCenterItem] {
        var goer = buildActionCenterItems(ActionCenterInputs(
            role: .goer, now: Date(),
            myHolding: app.myHolding, myPendingVerification: app.myPendingVerification, myRefunds: app.myRefunds,
            onOpenPayment: { app.openPaymentDetails($0, back: .profile) },
            onOpenMyRefunds: { app.openMyRefunds(back: .profile) },
            T: app.T
        ))
        if app.canHost {
            goer += buildActionCenterItems(ActionCenterInputs(
                role: .host, now: Date(),
                verifications: app.verifications, refundQueue: app.refundQueue, orgHolding: app.organizerHoldingSummary,
                onOpenVerifications: { app.openVerifications(back: .profile) },
                onOpenRefundCenter: { app.openVerifications(back: .profile) },
                onOpenDashboard: { app.goDashboard() },
                T: app.T
            ))
        }
        return sortActionCenterItems(goer)
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
            accountTabsBar
            ScreenScaffold(tracksBottomBarScroll: true, scrollPositionID: accountScrollAnchorBinding, refreshIndicatorTopPadding: 24, onRefresh: {
                guard app.userID != nil else { return }
                await app.loadPaymentBookings()
                await app.loadMyRefunds()
                if app.canHost {
                    await app.loadVerifications()
                    await app.loadOrganizerHoldingSummary()
                    await app.loadRefundQueue()
                    if app.myOrganizerID != nil { await app.loadMyOrgStats() }
                }
            }) {
                accountContent
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
        // Stage 1 — re-run whenever this account's organizer id becomes
        // known (session restore, or right after creating a first event)
        // so the host card's real published-event stats reflect the
        // latest admin approval/cancellation, not a stale snapshot.
        .task(id: app.myOrganizerID) {
            if app.canHost, app.myOrganizerID != nil { await app.loadMyOrgStats() }
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
            BanbeLogo(kind: .wordmark, width: BanbeLogo.headerWordmarkWidth)
            Text(app.T("Tài khoản", "Account")).font(BanbeTheme.display(27))
            Spacer()
            Button(app.T("Xong", "Done")) { app.goHome() }
                .font(.system(size: 12)).buttonStyle(.plain)
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
                // Task 3.3 (07-notifications.md) — story ring: bright
                // while an active, not-fully-viewed story exists;
                // subdued once every active story has been viewed; no
                // ring with no active story. Tap opens the viewer only
                // when there's something to view.
                Button {
                    if let g = myStoryGroup { app.openStoryViewer(g.organizerId) }
                } label: {
                    ZStack {
                        if let g = myStoryGroup {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .strokeBorder(g.allViewed ? Color.clear : BanbeTheme.alert, lineWidth: 2.5)
                                .background(
                                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                                        .strokeBorder(g.allViewed ? app.palette.rule : .clear, lineWidth: 2.5)
                                )
                                .frame(width: 64, height: 64)
                        }
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
                }
                .buttonStyle(.plain)
                .disabled(myStoryGroup == nil)
                .accessibilityIdentifier("account.storyRing")
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(app.displayName).font(BanbeTheme.display(22)).lineLimit(1)
                        if app.isSignedIn {
                            Button {
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
                    // Task 3.2 — story creation entry point, hosts only.
                    // TASK B (2026-10-03) — host-only action, hidden
                    // while organizerMode is off (current mode, not
                    // eligibility).
                    if app.organizerMode {
                        Menu {
                            // Task 1 — icons on each row, matching the
                            // chat composer's "+" menu exactly (same SF
                            // Symbols) so the two read as one family.
                            Button {
                                app.storyLibraryPickerOpen = true
                            } label: {
                                Label(app.T("Thư Viện Ảnh", "Photo Library"), systemImage: "photo.on.rectangle")
                            }
                            Button {
                                app.storyCameraOpen = true
                            } label: {
                                Label(app.T("Camera", "Camera"), systemImage: "camera")
                            }
                        } label: {
                            Text(app.T("▪︎ Đăng story", "▪︎ Post story"))
                                .font(.system(size: 11.5))
                                .foregroundStyle(app.palette.ink.opacity(0.65))
                        }
                        .accessibilityIdentifier("account.postStory")
                    }
                }
                Spacer(minLength: 0)
                if app.isSignedIn {
                    // iPhone fix pass — this used to open EditProfile
                    // directly; it now opens the same public profile
                    // page anyone else sees at this account's own
                    // handle (`isOwnProfile` there is what surfaces its
                    // own "Chỉnh sửa hồ sơ" row) — editing is one tap
                    // further in, not the arrow's own destination.
                    Button {
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
            groupCard(groupKey: "activity", icon: "calendar.badge.checkmark", label: app.T("Vé & Đặt Chỗ", "Tickets & Bookings"), badge: AccountBadges.myTicketsActionCount(paymentBookings: app.paymentBookings), topPadding: 14)

            HStack(spacing: 10) {
                counter(value: app.goingEventsCount, label: app.T("Đang tham gia", "Going"), icon: "calendar.badge.checkmark", identifier: "account.goingCard") { app.goGoingList() }
                // Relabeled "Đã lưu"/"Saved" (generic) -> "Sự Kiện Đã Lưu"/
                // "Saved Events"; destination/identifier unchanged.
                counter(value: app.favorites.count, label: app.T("Sự Kiện Đã Lưu", "Saved Events"), icon: "bookmark", identifier: "account.savedCard") { app.goSavedList() }
            }
            .padding(.top, 14)
            .id("account-stats")

            groupCard(groupKey: "payments", icon: "banknote", label: app.T("Thanh Toán & Giấy Tờ", "Payments & Documents"), topPadding: 14)

            reportsRow(app.T("Số Liệu & Báo Cáo", "Metrics & Reports"), identifier: "account.reportsPersonal") {
                app.openReports(scope: "personal", back: .profile)
            }

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

            Button {
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
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.top, 14)
            .accessibilityIdentifier("account.personalProfile")

            // Relabeled "Tùy Chỉnh"/"Preferences" -> "Cài Đặt"/"Settings"
            // (reads more accurately for its actual contents). `groupKey`/
            // identifier/route unchanged.
            groupCard(groupKey: "preferences", icon: "slider.horizontal.3", label: app.T("Cài Đặt", "Settings"))
            // "Help & Legal" — no dedicated in-app Help/Support screen
            // exists anywhere in this codebase (searched for one); only the
            // real, already-wired Policy screen (`app.openPolicy()`/
            // `PolicyView.swift`, the same bilingual policy text used at
            // signup consent, reachable read-only here — its own "‹ Back"
            // returns to `app.policyBackScreen`, set to whichever screen
            // opened it). This row is therefore the Legal half only — the "Help"
            // half has no real destination yet, a genuine gap flagged in
            // 09-auth-onboarding.md's dated fix-pass section, not
            // fabricated here.
            Button { app.openPolicy() } label: {
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
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.top, 8)
            .accessibilityIdentifier("account.helpLegal")

            // The lightweight conditional invite row described above. Same
            // badge SOURCE as the Host-tab "team" card (myOrganizerInvites
            // [+ myEventCredits]) — never a second independently-derived
            // count, never shown at the same time as that card.
            if !app.organizerMode && !app.myOrganizerInvites.isEmpty {
                Button { app.accountGroupKey = "team"; app.screen = .accountGroup } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.3").font(.system(size: 16, weight: .medium)).frame(width: 30, height: 30)
                            .background((ROW_ACCENT_COLORS["team"] ?? .clear).opacity(0.33), in: Circle())
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
                Button { app.accountGroupKey = "adminTeam"; app.screen = .accountGroup } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.shield").font(.system(size: 16, weight: .medium)).frame(width: 30, height: 30)
                            .background((ROW_ACCENT_COLORS["adminTeam"] ?? .clear).opacity(0.33), in: Circle())
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
            hostManagementRows
            // Account IA reorder pass — actionable content first: Reports
            // moved AFTER the group cards (was: identity card, Reports,
            // then the group card). Same destination/identifier, only
            // position changed.
            if app.myOrganizerID != nil {
                reportsRow(app.T("Số Liệu & Báo Cáo", "Metrics & Reports"), identifier: "account.reportsHost") {
                    app.openReports(scope: "host", organizerID: app.myOrganizerID, back: .profile)
                }
            }
            } // app.accountTab == "host"

            if app.accountTab == "admin" {
            // No header existed here before ("nothing to group"); now
            // there is: this header plus the reorder below justifies it.
            sectionHeader(app.T("Quản Trị", "Administration"))
                .accessibilityIdentifier("account.section.admin")
            adminSection
            reportsRow(app.T("Số Liệu & Báo Cáo", "Metrics & Reports"), identifier: "account.reportsAdmin") {
                app.openReports(scope: "admin", back: .profile)
            }
            } // app.accountTab == "admin"


            // Bandwidth pass (2026-10-01) — lets anyone stuck with a stale
            // cached cover (or just wanting the disk space back) reclaim it
            // without affecting drafts/sessions/tickets, which PhotoLoader's
            // caches never touch in the first place. See
            // .claude/notes/22-supabase-bandwidth-optimization.md.
            Button {
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

            Button {
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
        var tabs: [(String, String, Int)] = [("personal", app.T("Cá Nhân", "Personal"), 0)]
        if app.organizerMode {
            let hostBadge = AccountBadges.hostActionCount(organizerMode: app.organizerMode, verificationsCount: app.verifications.count, refundQueue: app.refundQueue)
            tabs.append(("host", app.T("Tổ Chức", "Host"), hostBadge))
        }
        if app.accountType == "admin" {
            let adminBadge = AccountBadges.adminModerationCount(accountType: app.accountType, pendingEventsCount: app.pendingEventsCount)
            tabs.append(("admin", app.T("Quản Trị", "Admin"), adminBadge))
        }
        return tabs
    }

    @ViewBuilder
    private func accountTabButton(key: String, label: String, badge: Int = 0) -> some View {
        Button { app.accountTab = key } label: {
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
                .background(app.accountTab == key ? app.palette.ink : .clear, in: Capsule())
                .overlay(Capsule().stroke(app.accountTab == key ? .clear : app.palette.rule, lineWidth: 1))
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
        .highPriorityGesture(TapGesture().onEnded { app.accountTab = key })
        .accessibilityIdentifier("account.tab.\(key)")
    }

    // TASK 3C (2026-09-22 twenty-first follow-up) — leading icon on every
    // Account action row/card, one coherent SF Symbols language (16pt
    // medium weight, 22x22 container, 0.72 opacity — matches the ink/rule/
    // paper tokens already in use here, no new colors).
    private func counter(value: Int, label: String, icon: String, identifier: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 20, height: 20)
                    .opacity(0.72)
                Text("\(value)").font(BanbeTheme.display(24))
                Text(label).font(.system(size: 11))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .foregroundStyle(app.palette.ink)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier ?? label)
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
        Button(action: action) {
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
    private func groupCard(groupKey: String, icon: String, label: String, badge: Int = 0, topPadding: CGFloat = 8) -> some View {
        Button { app.accountGroupKey = groupKey; app.screen = .accountGroup } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 30, height: 30)
                    .background((ROW_ACCENT_COLORS[groupKey] ?? .clear).opacity(0.33), in: Circle())
                Text(label).font(.system(size: 14))
                Spacer()
                // TASK 5 (Account badges pass) — "99+" display, same cap
                // convention BottomTabBar.swift's own Notifications badge
                // already uses, with the real count kept in the
                // accessibility label (never lost, just not rendered).
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
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, topPadding)
        .accessibilityIdentifier("account.group.\(groupKey)")
    }

    private func row(_ title: String, identifier: String? = nil, icon: String, trailing: String,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
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
                        Button(app.T("Từ chối", "Decline")) { Task { await app.respondToOrganizerInvite(membershipID: inv.id, accept: false) } }
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
                        Button(app.T("Từ chối", "Decline")) { Task { await app.respondToEventCredit(creditID: c.id, accept: false) } }
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

        Button { app.toggleOrganizerMode() } label: {
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
                // TASK B (2026-10-03 fix pass) — THE visual bug:
                // this switch was bound to canHost (eligibility,
                // permanently true once a real host), never
                // organizerMode (the actual current preference) —
                // so it visually looked stuck "on" for any real
                // host regardless of what the toggle really did
                // underneath. See AppState+Data.swift's
                // applyOrganizerMode for the matching state-side
                // root cause.
                ZStack(alignment: app.organizerMode ? .trailing : .leading) {
                    Capsule()
                        .fill(app.organizerMode ? app.palette.ink : app.palette.ink.opacity(0.18))
                        .frame(width: 44, height: 26)
                    Circle().fill(app.palette.paper).frame(width: 20, height: 20).padding(3)
                }
                .animation(.easeInOut(duration: 0.15), value: app.organizerMode)
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
            if app.canHost {
                groupCard(
                    groupKey: "hostOps", icon: "checklist",
                    label: app.T("Vận Hành & Thanh Toán Tổ Chức", "Event Operations & Payments"),
                    // Stale-badge fix pass — was a raw `refundQueue.count`,
                    // bypassing `AccountBadges.hostActionCount` entirely
                    // (the one place this app already decides what's
                    // actually host-actionable) — same staleness bug every
                    // other raw-count call site this pass fixes.
                    badge: AccountBadges.hostActionCount(organizerMode: app.organizerMode, verificationsCount: app.verifications.count, refundQueue: app.refundQueue),
                    topPadding: 22
                )
                // Account IA reorder pass (2026-09-30 second) — the Host
                // tab's own entry point into the SAME "team" screen the
                // Personal tab's conditional invite row also opens (see
                // that row's own comment for the full "two doors, one
                // destination" reasoning — mirrors the Payment Disputes
                // row's existing pattern). Gated `canHost`, matching
                // hostOps above.
                groupCard(
                    groupKey: "team", icon: "person.3",
                    label: app.T("Hồ Sơ & Team Tổ Chức", "Organizer Profile & Team"),
                    badge: app.myOrganizerInvites.count + app.myEventCredits.count,
                    topPadding: 8
                )
                // Interest surveys (Slice B) — a standalone screen
                // (SurveysHostingView), not a case inside AccountGroupView's
                // switch, since it has its own tabs (Active/Closed/
                // Suggested Drafts) and a create form, not a simple flat
                // list. Badge honestly 0 for now — the unseen/actionable
                // candidate count this badge is meant to carry (candidate
                // generation) is not implemented yet.
                Button { app.screen = .surveysHosting } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "checklist")
                            .font(.system(size: 16, weight: .medium))
                            .frame(width: 30, height: 30)
                            .background((ROW_ACCENT_COLORS["hostOps"] ?? .clear).opacity(0.33), in: Circle())
                        Text(app.T("Khảo Sát & Ý Tưởng Sự Kiện", "Surveys & Event Ideas")).font(.system(size: 14))
                        Spacer()
                        Text("›").font(.system(size: 15))
                    }
                    .foregroundStyle(app.palette.ink)
                    .padding(16)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .accessibilityIdentifier("account.group.surveys")
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
        VStack(spacing: 0) {
            groupCard(groupKey: "adminReview", icon: "exclamationmark.shield", label: app.T("Duyệt & Kiểm Duyệt", "Review & Moderation"), badge: app.pendingEventsCount, topPadding: 22)
            // Admin Team pass (2026-10-02) — reachable to every admin (a
            // permission-less admin can at least see who the team is /
            // why they can't manage it, AccountGroupView's own gate
            // decides what renders inside); badge only ever counts real,
            // still-pending invites (adminInvites is only populated for a
            // canManageAdmins account — RLS denies the read otherwise, so
            // a non-manager's badge is honestly 0, never a guessed number).
            groupCard(groupKey: "adminTeam", icon: "person.3", label: app.T("Đội Ngũ Quản Trị", "Admin Team"), badge: app.adminInvites.filter { $0.status == "pending" }.count, topPadding: 10)
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
            Button {
                app.goDashboard(back: .profile)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 14) {
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
        return try? SupabaseService.client.storage.from("organizer-photos").getPublicURL(path: app.myOrganizerAvatarPath)
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
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                if let image = app.storyCreatePreviewImage {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                HStack(spacing: 10) {
                    Button {
                        app.storyCreatePreviewImage = nil
                        app.storyCameraOpen = true
                    } label: {
                        Text(app.T("Chụp lại", "Retake"))
                            .font(.system(size: 13.5, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .foregroundStyle(.white)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.35)))
                    }
                    .accessibilityIdentifier("story.retake")
                    Button {
                        Task { _ = await app.publishStory() }
                    } label: {
                        Text(app.storyCreateBusy ? app.T("Đang đăng…", "Posting…") : app.T("Dùng ảnh", "Use photo"))
                            .font(.system(size: 13.5, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .foregroundStyle(.black)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                            .opacity(app.storyCreateBusy ? 0.6 : 1)
                    }
                    .disabled(app.storyCreateBusy)
                    .accessibilityIdentifier("story.usePhoto")
                }
                .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 34)
            }
        }
    }
}
