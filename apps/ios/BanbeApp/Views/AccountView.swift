import SwiftUI
import PhotosUI

/// Port of src/screens/Account.jsx — profile header with rename, the
/// going/saved counters, links to messages and preferences, the organizer
/// mode switch, and sign in/out.
struct AccountView: View {
    @EnvironmentObject var app: AppState
    // Task 3 (07-notifications.md) — story creation, hosts only.
    @State private var storyPhotoItem: PhotosPickerItem?
    @State private var storyCameraOpen = false
    // 2026-09-21 follow-up (real-device report) — `PhotosPicker` nested
    // DIRECTLY as a Menu row's content is a known SwiftUI/real-device
    // reliability gap: `Menu` wraps each row as its own button and can
    // swallow the tap before PhotosPicker's own internal presentation
    // trigger ever fires — it can look fine in Xcode Previews/Simulator and
    // still silently do nothing on a real device (confirmed against this
    // exact symptom report). Fixed by moving the picker's PRESENTATION
    // (not the picker itself — still real `PhotosPicker`/`.photosPicker`,
    // not a replacement API) out of the Menu: a plain `Button` inside the
    // Menu just flips this flag, and `.photosPicker(isPresented:...)`
    // below is attached to the screen itself, same as `storyCameraOpen`'s
    // own `.fullScreenCover` already was.
    @State private var storyLibraryPickerOpen = false

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

    var body: some View {
        ScreenScaffold(tracksBottomBarScroll: true, scrollPositionID: $app.accountScrollAnchorID, onRefresh: {
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
        .task { if app.userID != nil { await app.loadHomeStories() } }
        .task { if app.userID != nil { await app.loadMyOrganizerMemberships() } }
        .task { if app.userID != nil { await app.loadMyEventCredits() } }
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
        }
        // Stage 1 — re-run whenever this account's organizer id becomes
        // known (session restore, or right after creating a first event)
        // so the host card's real published-event stats reflect the
        // latest admin approval/cancellation, not a stale snapshot.
        .task(id: app.myOrganizerID) {
            if app.canHost, app.myOrganizerID != nil { await app.loadMyOrgStats() }
        }
        .onAppear { retryScrollRestoreIfNeeded(); syncAccountTabToRole() }
        // Account extension (2026-09-27, Stage 1/2) — a role change
        // (organizer mode toggled off elsewhere, an admin demoted, an
        // account switch) can leave `app.accountTab` pointing at a tab
        // that's no longer in `accountTabs`; the toggle's own redirect
        // (AppState+Data.swift, applyOrganizerMode) covers the direct
        // toggle path, this is the general safety net for every other one.
        .onChange(of: app.organizerMode) { _, _ in syncAccountTabToRole() }
        .onChange(of: app.accountType) { _, _ in syncAccountTabToRole() }
        .photosPicker(isPresented: $storyLibraryPickerOpen, selection: $storyPhotoItem, matching: .images)
        .onChange(of: storyPhotoItem) { _, item in
            Task {
                guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                await MainActor.run { app.storyCreatePreviewImage = image }
                storyPhotoItem = nil
            }
        }
        .fullScreenCover(isPresented: $storyCameraOpen) {
            CameraPicker { image in
                storyCameraOpen = false
                app.storyCreatePreviewImage = image
            }
            .ignoresSafeArea()
        }
        // Task 3.2 — Retake / Use Photo preview before actually publishing.
        .fullScreenCover(isPresented: Binding(get: { app.storyCreatePreviewImage != nil }, set: { if !$0 { app.storyCreatePreviewImage = nil } })) {
            storyCreatePreview
        }
        // Task 1.3 (real-device report) — BottomTabBarOverlay is a SEPARATE,
        // always-on-top UIWindow (see that file's own doc comment) that sits
        // above ANY main-window content, including a `.photosPicker`/
        // `.fullScreenCover` presentation — `.profile` staying in
        // `visibleScreens` throughout means it was never hidden for any of
        // these three presentations, silently covering Retake/Use Photo.
        // Reuses the exact `setForcedHidden(_:)` mechanism InboxView already
        // established for its own settings sheet, ORing in all three
        // triggers here instead of inventing a second mechanism.
        .onChange(of: storyLibraryPickerOpen) { _, _ in syncDockHidden() }
        .onChange(of: storyCameraOpen) { _, _ in syncDockHidden() }
        .onChange(of: app.storyCreatePreviewImage != nil) { _, _ in syncDockHidden() }
        .onDisappear { BottomTabBarOverlay.shared.setForcedHidden(false) }
    }

    private var accountContent: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(app.T("Tài khoản", "Account")).font(BanbeTheme.display(27))
                Spacer()
                Button(app.T("Xong", "Done")) { app.goHome() }
                    .font(.system(size: 12)).buttonStyle(.plain)
            }

            // Account extension (2026-09-27, Stage 1) — "organizer mode
            // OFF means host UI is OFF": the Tổ chức tab itself is gone
            // while `organizerMode` is off, not just gated content inside
            // it — `canHost` (eligibility, e.g. `hasHosted`) intentionally
            // stays out of this condition, see applyOrganizerMode's own
            // doc comment for why conflating the two was the earlier bug.
            HStack(spacing: 6) {
                ForEach(accountTabs, id: \.0) { key, label in
                    accountTabButton(key: key, label: label)
                }
            }
            .padding(.top, 16)

            // iPhone fix pass (2026-09-26) — this personal identity
            // card (and its story ring/"Đổi tên") used to render
            // regardless of `app.accountTab`, so it also showed on Tổ chức,
            // right above that tab's own separate organizer card — two
            // profile cards on one screen. Scoped to the Cá nhân tab
            // only, matching the web fix.
            if app.accountTab == "personal" {
            reportsRow(app.T("Số liệu & báo cáo", "Metrics & reports"), identifier: "account.reportsPersonal") {
                app.openReports(scope: "personal", back: .profile)
            }
            teamInvitesAndMemberships
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
                                storyLibraryPickerOpen = true
                            } label: {
                                Label(app.T("Thư viện ảnh", "Photo library"), systemImage: "photo.on.rectangle")
                            }
                            Button {
                                storyCameraOpen = true
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
            HStack(spacing: 10) {
                counter(value: app.goingEventsCount, label: app.T("Đang tham gia", "Going"), icon: "calendar.badge.checkmark", identifier: "account.goingCard") { app.goGoingList() }
                counter(value: app.favorites.count, label: app.T("Đã lưu", "Saved"), icon: "bookmark", identifier: "account.savedCard") { app.goSavedList() }
            }
            .padding(.top, 22)
            .id("account-stats")

            // TASK A (2026-10-01 UX foundation pass) — same canonical
            // Action Center Home/Dashboard show; Account is one of its
            // three placements.
            ActionCenterView(items: actionItems, onSeeAll: { app.openVerifications(back: .profile) })

            // TASK 3A (2026-09-22 twenty-first follow-up) — the
            // "Tin nhắn"/Messages shortcut row removed entirely per this
            // ticket's own ask; Inbox stays reachable exactly as before
            // via the bottom dock (BottomTabBar.swift), untouched.
            VStack(spacing: 0) {
                row(app.T("Sự kiện đã hoàn thành", "Completed events"), identifier: "account.completedList", icon: "calendar.badge.checkmark", trailing: "\(app.completedEventsCount) ›") { app.goCompletedList() }
                Divider().overlay(app.palette.rule)
                // TASK 3B — broader, more accurate label: this screen
                // holds more than language/theme (see
                // PreferencesView.swift). Destination (`openPreferences`)
                // and the right-side summary are unchanged.
                row(app.T("Tùy chỉnh ứng dụng", "App preferences"),
                    identifier: "account.preferences", icon: "slider.horizontal.3",
                    trailing: (app.lang == "en" ? "English" : "Tiếng Việt") + " ▪︎ "
                        + (app.theme == "dark" ? app.T("Tối", "Dark") : app.T("Sáng", "Light"))) {
                    app.openPreferences()
                }
                Divider().overlay(app.palette.rule)
                row(app.T("Hoá đơn", "Invoices"),
                    identifier: "account.invoices", icon: "doc.text", trailing: "›") {
                    app.openDocuments(kind: "invoice", role: "guest")
                }
                Divider().overlay(app.palette.rule)
                row(app.T("Biên nhận", "Receipts"),
                    identifier: "account.receipts", icon: "receipt", trailing: "›") {
                    app.openDocuments(kind: "receipt", role: "guest")
                }
                Divider().overlay(app.palette.rule)
                // Refund MVP (product rule A) — a persistent entry
                // point, reachable regardless of whether a notification
                // was ever tapped.
                row(app.T("Tài khoản thanh toán & nhận hoàn tiền", "Payment & refund accounts"),
                    identifier: "account.refundAccounts", icon: "banknote", trailing: "›") {
                    app.openRefundAccounts(back: .profile)
                }
                Divider().overlay(app.palette.rule)
                row(app.T("Hoàn tiền", "Refunds"),
                    identifier: "account.refunds", icon: "checklist", trailing: "›") {
                    app.openMyRefunds(back: .profile)
                }
                Divider().overlay(app.palette.rule)
                row(app.T("Bảo mật", "Security"),
                    identifier: "account.security", icon: "lock.shield",
                    trailing: "›") {
                    app.openSecurity()
                }
            }
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.top, 20)
            .id("account-links")

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
            if app.myOrganizerID != nil {
                reportsRow(app.T("Số liệu & báo cáo", "Metrics & reports"), identifier: "account.reportsHost") {
                    app.openReports(scope: "host", organizerID: app.myOrganizerID, back: .profile)
                }
            }
            orgProfileCard()
            hostManagementRows
            } // app.accountTab == "host"

            if app.accountTab == "admin" {
            reportsRow(app.T("Số liệu & báo cáo", "Metrics & reports"), identifier: "account.reportsAdmin") {
                app.openReports(scope: "admin", back: .profile)
            }
            adminSection
            } // app.accountTab == "admin"


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
            .padding(.top, 24)
            .padding(.bottom, 100)
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private func syncAccountTabToRole() {
        if app.accountTab == "host" && !app.organizerMode { app.accountTab = "personal" }
        else if app.accountTab == "admin" && app.accountType != "admin" { app.accountTab = "personal" }
    }

    private func syncDockHidden() {
        BottomTabBarOverlay.shared.setForcedHidden(storyLibraryPickerOpen || storyCameraOpen || app.storyCreatePreviewImage != nil)
    }

    private var storyCreatePreview: some View {
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
                        storyCameraOpen = true
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
    private var accountTabs: [(String, String)] {
        var tabs: [(String, String)] = [("personal", app.T("Cá nhân", "Personal"))]
        if app.organizerMode { tabs.append(("host", app.T("Tổ chức", "Host"))) }
        if app.accountType == "admin" { tabs.append(("admin", app.T("Quản trị", "Admin"))) }
        return tabs
    }

    @ViewBuilder
    private func accountTabButton(key: String, label: String) -> some View {
        Button { app.accountTab = key } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(app.accountTab == key ? app.palette.ink : .clear, in: Capsule())
                .overlay(Capsule().stroke(app.accountTab == key ? .clear : app.palette.rule, lineWidth: 1))
                .foregroundStyle(app.accountTab == key ? app.palette.paper : app.palette.ink)
        }
        .buttonStyle(.plain)
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
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        if !app.myEventCredits.isEmpty {
            Text(app.T("Ghi nhận đóng góp sự kiện", "Event-organizing credits")).font(.system(size: 11.5, weight: .semibold)).padding(.top, 18)
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
    }

    @ViewBuilder
    private var hostingSection: some View {
        Text(app.T("Tổ chức", "Hosting"))
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
    private var hostManagementRows: some View {
        if app.canHost {
            Text(app.T("Quản lý thanh toán", "Payment management"))
                .font(.system(size: 11.5, weight: .semibold))
                .padding(.top, 22)
            VStack(spacing: 0) {
                row(app.T("Chờ xác nhận thanh toán", "Awaiting verification"),
                    identifier: "host.verifications", icon: "checklist", trailing: "›") { app.openVerifications() }
                Divider().overlay(app.palette.rule)
                row(app.T("Nhận thanh toán", "Getting paid"),
                    identifier: "host.payout", icon: "banknote", trailing: "›") { app.openPayout() }
                Divider().overlay(app.palette.rule)
                row(app.T("Hoá đơn đã phát hành", "Invoices issued"),
                    identifier: "host.invoices", icon: "doc.text", trailing: "›") {
                    app.openDocuments(kind: "invoice", role: "host")
                }
                Divider().overlay(app.palette.rule)
                row(app.T("Biên nhận đã phát hành", "Receipts issued"),
                    identifier: "host.receipts", icon: "receipt", trailing: "›") {
                    app.openDocuments(kind: "receipt", role: "host")
                }
            }
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.top, 10)
        }
    }

    // Stage 2 — Admin is its own top-level tab now, independent of
    // organizerMode: these two rows used to sit inside the Tổ chức pane,
    // so an admin who never turned organizer mode on (or turned it off)
    // lost them entirely once that tab started hiding itself for Stage 1.
    // Same actions, same RLS-enforced screens — moved, not cloned.
    @ViewBuilder
    private var adminSection: some View {
        // Admin Panel — visible only to accountType == "admin"
        // (banbetestadmin@gmail.com, migration 040), never to a
        // plain organizer. RLS (v_disputes, resolve_dispute,
        // payment_audit_log, the 'pay-proof' bucket) is the real
        // backstop; openAdminDashboard() guards again regardless.
        Text(app.T("Quản trị", "Admin"))
            .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(app.palette.ink)
            .padding(.top, 22)
        VStack(spacing: 0) {
            row(app.T("Bảng quản trị", "Admin Panel"),
                identifier: "admin.panel", icon: "exclamationmark.shield", trailing: "›") { app.openAdminDashboard() }
            // Event submission -> review -> publish — a separate
            // desk from the payment dispute one above.
            row(app.T("Sự kiện chờ duyệt", "Pending events"),
                identifier: "admin.events", icon: "exclamationmark.shield", trailing: "›") { app.openAdminEvents() }
        }
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.top, 10)
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
        guard !didAttemptScrollRestore, let target = app.accountScrollAnchorID else { return }
        didAttemptScrollRestore = true
        app.accountScrollAnchorID = nil
        DispatchQueue.main.async {
            app.accountScrollAnchorID = target
        }
    }
}
