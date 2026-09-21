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

    private var myStoryGroup: StoryGroup? {
        app.homeStories.first { g in app.myOrganizerIdsCache.contains(g.organizerId) }
    }

    private var subtitle: String {
        if app.accountType == "admin" { return app.T("Quản trị viên", "Admin") }
        return app.canHost ? app.T("Người tham gia ▪︎ Người tổ chức", "Goer ▪︎ Host")
                           : app.T("Người tham gia", "Goer")
    }

    var body: some View {
        ScreenScaffold(tracksBottomBarScroll: true) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(app.T("Tài khoản", "Account")).font(BanbeTheme.display(27))
                    Spacer()
                    Button(app.T("Xong", "Done")) { app.goHome() }
                        .font(.system(size: 12)).buttonStyle(.plain)
                }

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
                            Text(String(app.displayName.prefix(1)).uppercased())
                                .font(BanbeTheme.display(22))
                                .frame(width: 56, height: 56)
                                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(myStoryGroup == nil)
                    .accessibilityIdentifier("account.storyRing")
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(app.displayName).font(BanbeTheme.display(22)).lineLimit(1)
                            if app.isSignedIn {
                                Button(app.T("Đổi tên", "Rename")) { app.goEditName() }
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(app.palette.ink.opacity(0.65))
                                    .buttonStyle(.plain)
                            }
                        }
                        Text(subtitle).font(.system(size: 11)).kerning(0.6)
                        // Task 3.2 — story creation entry point, hosts only.
                        if app.canHost {
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
                }
                .padding(.top, 22)

                HStack(spacing: 10) {
                    counter(value: app.goingEventsCount, label: app.T("Đang tham gia", "Going")) { app.goGoingList() }
                    counter(value: app.favorites.count, label: app.T("Đã lưu", "Saved")) { app.goSavedList() }
                }
                .padding(.top, 22)

                VStack(spacing: 0) {
                    row(app.T("Tin nhắn", "Messages"), trailing: "›") { app.goInbox() }
                    Divider().overlay(app.palette.rule)
                    row(app.T("Sự kiện đã hoàn thành", "Completed events"), trailing: "\(app.completedEventsCount) ›") { app.goCompletedList() }
                    Divider().overlay(app.palette.rule)
                    row(app.T("Ngôn ngữ & hiển thị", "Language & appearance"),
                        identifier: "account.preferences",
                        trailing: (app.lang == "en" ? "English" : "Tiếng Việt") + " ▪︎ "
                            + (app.theme == "dark" ? app.T("Tối", "Dark") : app.T("Sáng", "Light"))) {
                        app.openPreferences()
                    }
                    Divider().overlay(app.palette.rule)
                    row(app.T("Hoá đơn", "Invoices"),
                        identifier: "account.invoices", trailing: "›") {
                        app.openDocuments(kind: "invoice", role: "guest")
                    }
                    Divider().overlay(app.palette.rule)
                    row(app.T("Biên nhận", "Receipts"),
                        identifier: "account.receipts", trailing: "›") {
                        app.openDocuments(kind: "receipt", role: "guest")
                    }
                    Divider().overlay(app.palette.rule)
                    row(app.T("Bảo mật", "Security"),
                        identifier: "account.security",
                        trailing: "›") {
                        app.openSecurity()
                    }
                }
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 20)

                Text(app.T("Tổ chức", "Hosting"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.top, 22)

                Button { app.toggleOrganizerMode() } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.T("Chế độ tổ chức", "Organizer mode")).font(.system(size: 14))
                            Text(app.T("Bật để tạo và quản lý sự kiện. Tắt lúc nào cũng được.",
                                       "Turn on to create and manage events. Turn it off any time."))
                                .font(.system(size: 11.5))
                                .foregroundStyle(app.palette.ink.opacity(0.7))
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        ZStack(alignment: app.canHost ? .trailing : .leading) {
                            Capsule()
                                .fill(app.canHost ? app.palette.ink : app.palette.ink.opacity(0.18))
                                .frame(width: 44, height: 26)
                            Circle().fill(app.palette.paper).frame(width: 20, height: 20).padding(3)
                        }
                        .animation(.easeInOut(duration: 0.15), value: app.canHost)
                    }
                    .foregroundStyle(app.palette.ink)
                    .padding(16)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 10)

                if !app.organizerModeError.isEmpty {
                    Text(app.organizerModeError)
                        .font(.system(size: 12))
                        .foregroundStyle(BanbeTheme.alert)
                        .padding(.top, 10)
                }

                if app.canHost {
                    VStack(spacing: 0) {
                        row(app.T("Chờ xác nhận thanh toán", "Awaiting verification"),
                            identifier: "host.verifications", trailing: "›") { app.openVerifications() }
                        Divider().overlay(app.palette.rule)
                        row(app.T("Nhận thanh toán", "Getting paid"),
                            identifier: "host.payout", trailing: "›") { app.openPayout() }
                        Divider().overlay(app.palette.rule)
                        row(app.T("Hoá đơn đã phát hành", "Invoices issued"),
                            identifier: "host.invoices", trailing: "›") {
                            app.openDocuments(kind: "invoice", role: "host")
                        }
                        Divider().overlay(app.palette.rule)
                        row(app.T("Biên nhận đã phát hành", "Receipts issued"),
                            identifier: "host.receipts", trailing: "›") {
                            app.openDocuments(kind: "receipt", role: "host")
                        }
                    }
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.top, 10)
                }

                // Admin Panel — visible only to accountType == "admin"
                // (banbetestadmin@gmail.com, migration 040), never to a
                // plain organizer. RLS (v_disputes, resolve_dispute,
                // payment_audit_log, the 'pay-proof' bucket) is the real
                // backstop; openAdminDashboard() guards again regardless.
                if app.isAdmin {
                    Text(app.T("Quản trị", "Admin"))
                        .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(app.palette.ink)
                        .padding(.top, 22)
                    VStack(spacing: 0) {
                        row(app.T("Bảng quản trị", "Admin Panel"),
                            identifier: "admin.panel", trailing: "›") { app.openAdminDashboard() }
                    }
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.top, 10)
                }

                if app.canHost {
                    Button { app.switchToHost(back: .profile) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(app.orgRegName.isEmpty ? "Bếp Nhỏ" : app.orgRegName)
                                    .font(BanbeTheme.display(17))
                                Text(app.mode == "host"
                                     ? app.T("Xem trang tổ chức của bạn", "View your host page")
                                     : app.T("Chuyển sang chế độ tổ chức", "Switch to hosting"))
                                    .font(.system(size: 12))
                            }
                            Spacer()
                            Text("›").font(.system(size: 17))
                        }
                        .foregroundStyle(app.palette.ink)
                        .padding(16)
                        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                } else {
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

                Button(app.isSignedIn
                       ? app.T("Đăng xuất", "Sign out")
                       : app.T("Đăng nhập để lưu sự kiện và nhắn tin", "Sign in to save events and message hosts")) {
                    if app.isSignedIn { Task { await app.signOut() } } else { app.goLogin() }
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
        .task { if app.userID != nil { await app.loadHomeStories() } }
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

    private func counter(value: Int, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(value)").font(BanbeTheme.display(24))
                Text(label).font(.system(size: 11))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .foregroundStyle(app.palette.ink)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func row(_ title: String, identifier: String? = nil, trailing: String,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
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
}
