import SwiftUI

/// TASK C (2026-10-03 fix pass) — replaces the old floating "Tạo sự kiện"
/// pill (CreateEventFabView.swift, removed) with a compact "+" that sits
/// right next to the dock. Deliberately a child of BottomTabBarOverlayRoot
/// (same separate always-on-top UIWindow the dock itself lives in) rather
/// than a new ZStack sibling in RootView's own main window — this ticket's
/// own instruction is "work with the existing overlay, don't add another
/// competing floating UIWindow." Being inside that window means it
/// automatically inherits ALL of BottomTabBarOverlay's existing
/// show/hide logic (forcedHidden/storyViewerOpen/pulseViewerOpen/
/// modalActionSheetPresented, and BottomTabBar.visibleScreens itself) for
/// free — it can never render above a full-screen sheet/story/Pulse
/// because the WHOLE WINDOW it lives in already hides itself for exactly
/// those cases (see that file's own applyVisibility()).
///
/// TASK 1 (2026-10-05 fix pass) — this view used to own BOTH the round
/// button AND its own anchored popover menu, positioned/sized independently
/// of the dock (see DockRow's own doc comment for the overlap bug that
/// caused). Now it's JUST the button — a fixed-size (`BottomTabBar.
/// createButtonSize`, matching `barHeight` exactly) trailing child of
/// DockRow's HStack, so it shares the dock's vertical center structurally
/// (same height, same HStack `alignment: .center`) instead of independently
/// computed padding math.
///
/// TASK 1 real-device follow-up — a native SwiftUI `Menu` HERE was tried
/// (dock "+" native-menu pass) and reverted: this view lives inside
/// BottomTabBarOverlay's own separate UIWindow, which is deliberately
/// sized to a small band just tall enough for the dock (see that file's
/// own doc comment) — a `Menu`'s popover, when it needs to open UPWARD
/// past that window's own top edge, gets clipped by the window's own
/// frame (confirmed on a real device: tapping "+" showed only a sliver of
/// the menu, not the actual rows — and an invisible-but-still-tappable
/// remnant of it could absorb a later unrelated tap). Back to a tray
/// (`DockCreateTrayView`, RootView.swift) — a real, previously-working
/// mechanism — instead: this button only flips `app.dockCreateOpen`,
/// the MAIN window's RootView reads it and presents the tray itself,
/// exactly like the original 2026-10-05 pass did before this went to a
/// Menu. The "+"→"X" morph is restored too, now that there's a real bool
/// to drive it again.
///
/// "Post a story" (a row inside that tray) reuses the EXACT SAME pipeline
/// AccountView's own "▪︎ Đăng story" menu uses
/// (`app.storyLibraryPickerOpen`/`app.storyCameraOpen` → `app.
/// publishStory()`, presented centrally from RootView) — not a second
/// upload pipeline.
///
/// BUG (2026-10-06 fix pass) — this used to paint itself as a SOLID
/// `app.palette.ink`-filled circle with its own independently-chosen
/// shadow (`opacity(0.22), radius: 10, y: 4`) — a visually-similar but
/// genuinely different style from the dock's own translucent
/// `.thinMaterial` capsule (`overlay` stroke opacity 0.06, `shadow`
/// `opacity(0.16), radius: 14, y: 6`), which is exactly why it read as "a
/// solid black circle next to a translucent dock" on a real device. Now
/// reuses the dock's own material/stroke/shadow constants verbatim (not a
/// second, matching-by-eye style) — background `.thinMaterial` in a
/// `Circle`, the SAME stroke opacity, the SAME shadow — with the glyph
/// itself switched from white-on-ink to `app.palette.ink`, since a
/// translucent material needs an ink-colored glyph for contrast the same
/// way every dock tab icon already is.
///
/// Simple Shell (note 66, switch `simple_shell`): `centred: true` is the "+" INSIDE the bar's centre slot — shown to
/// everyone (guests too), an ink disc with a paper "+", and a menu that follows the mode (Lib/DockLayout.swift and
/// BottomTabBar's overlay place it). `centred: false` is today's host-only "+" beside the bar, unchanged.
struct DockCreateButtonView: View {
    @EnvironmentObject private var app: AppState
    @State private var menuOpen = false
    var centred = false
    /// Simple Shell: a dock scrub is currently over the "+" slot (BottomTabBar passes it): a subtle pressed look.
    var scrubHover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if centred {
            centredButton
        } else if app.organizerMode {
            // Visible only in organizer mode (current UI preference — see
            // AppState+Data.swift's applyOrganizerMode fix — never
            // eligibility), matching the old pill's own gate exactly. DockRow
            // itself already only inserts this view under the same condition,
            // but keeping the check here too means this view never renders
            // anything if ever reused/embedded elsewhere without that gate.
            // Note 53 (owner report): a popover, not a `Menu`. On iOS 26 the Menu lifted this disc's bounding box
            // into the menu and put a white square back for a moment after it closed. Same three actions; the story
            // submenu is flattened into two rows.
            Button { menuOpen = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(app.palette.ink)
                    .frame(width: BottomTabBar.createButtonSize, height: BottomTabBar.createButtonSize)
                    // Native glass like the dock beside it (note 45).
                    .nativeGlass(Circle(), interactive: true)
                    // The whole disc opens the menu, not just the plus glyph in its middle.
                    .contentShape(Circle())
            }
            .buttonStyle(PressableButtonStyle(haptic: false))
            .popover(isPresented: $menuOpen, arrowEdge: .bottom) {
                PopoverMenuList(items: [
                    PopoverMenuItem(id: "dock.createMenu.event", title: app.T("Tạo Sự Kiện", "Create Event"),
                                    systemImage: "calendar.badge.plus") { app.goCreate() },
                    // Same pipeline AccountView's "Đăng story" uses (storyLibraryPickerOpen / storyCameraOpen -> publishStory()).
                    PopoverMenuItem(id: "dock.createMenu.story.library", title: app.T("Đăng story từ Thư viện ảnh", "Post a story from Photos"),
                                    systemImage: "photo.on.rectangle") { app.storyLibraryPickerOpen = true },
                    PopoverMenuItem(id: "dock.createMenu.story.camera", title: app.T("Đăng story bằng Camera", "Post a story with Camera"),
                                    systemImage: "camera") { app.storyCameraOpen = true },
                ]) { menuOpen = false }
                .environmentObject(app)
            }
            .accessibilityIdentifier("dock.createButton")
            .tourTarget("tour.dock.create")
            .accessibilityLabel(app.T("Tạo mới", "Create"))
        }
    }

    // MARK: Simple Shell centre "+"

    /// Ink disc, paper "+", 48pt (the touch target is the whole disc; the bar slot around it is wider).
    private static let discSize: CGFloat = 48

    /// Simple Shell follow-up (plan item 3): the popover is bound to `app.dockCreateOpen`, so a dock drag released
    /// over this slot opens the same menu, from the same anchor, as a tap.
    private var centredButton: some View {
        Button {
            Haptics.light()
            app.dockCreateOpen = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(app.palette.paper)
                .frame(width: Self.discSize, height: Self.discSize)
                .background(app.palette.ink, in: Circle())
                .scaleEffect(scrubHover ? 0.9 : 1)
                .opacity(scrubHover ? 0.82 : 1)
                .animation(Motion.animation(.spring(response: 0.22, dampingFraction: 0.7), reduce: reduceMotion), value: scrubHover)
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle(haptic: false))
        // The menu is a bottom sheet presented by RootView (DockCreateSheet), like the web one.
        .accessibilityIdentifier("dock.createButton")
        .tourTarget("tour.dock.create")
        .accessibilityLabel(app.T("Tạo mới", "Create"))
        .accessibilityHint(hostMenu
                           ? app.T("Tạo sự kiện, đăng story hoặc khảo sát", "Create an event, a story or a survey")
                           : app.T("Xem tuần này, mời bạn bè hoặc tổ chức sự kiện", "See this weekend, invite friends or host an event"))
    }

    private var hostMenu: Bool { app.isSignedIn && app.effectiveHomeView == .host }
}

/// The centre "+" menu as a bottom sheet, the same content as web's DockCreateCenter.jsx: title, icon tile + title +
/// one-line description per row.
///   Host (Home on Hosting): Create event (primary) · Post a story (library / camera) · Share one of my events · New survey.
///   Goer: This weekend · Invite friends · Host an event (stories are host-only). Guest: the same rows, each opening the
///   contextual sign-in prompt. "Host an event" is the shared startHosting path.
struct DockCreateSheet: View {
    @EnvironmentObject private var app: AppState
    @State private var storyOpen = false

    private var hostMenu: Bool { app.isSignedIn && app.effectiveHomeView == .host }

    /// Close the sheet first, then act once it is gone (the action may present another sheet or change screen).
    private func run(_ action: @escaping () -> Void) {
        app.dockCreateOpen = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { action() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(hostMenu ? app.T("Tạo mới", "Create") : app.T("Bạn muốn làm gì?", "What would you like to do?"))
                    .font(BanbeTheme.display(22))
                    .foregroundStyle(app.palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button { app.dockCreateOpen = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(app.palette.ink)
                        .frame(width: 36, height: 36)
                        .background(app.palette.ink.opacity(0.08), in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(app.T("Đóng", "Close"))
                .accessibilityIdentifier("dock.createMenu.close")
            }
            .padding(.horizontal, 6).padding(.bottom, 2)
            if hostMenu { hostRows } else { goerRows }
        }
        .padding(.horizontal, 12).padding(.top, 20).padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(app.palette.paper.ignoresSafeArea())
        .presentationDetents([.height(hostMenu ? (storyOpen ? 450 : 390) : 330)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(22)
        .presentationBackground(app.palette.paper)
    }

    @ViewBuilder private var goerRows: some View {
        let guest = !app.isSignedIn
        row("dock.createMenu.weekend", "calendar", app.T("Tuần này", "This weekend"),
            app.T("Sự kiện cuối tuần quanh bạn.", "Events happening this weekend.")) {
            if guest { app.promptSignIn(.schedule) } else { app.goHomeThisWeekend() }
        }
        row("dock.createMenu.invite", "envelope", app.T("Mời bạn bè", "Invite friends"),
            app.T("Gửi link mời của riêng bạn.", "Send your own invite link.")) {
            if guest { app.promptSignIn(.invite) } else if app.referralLink != nil { app.shareReferral() } else { app.screen = .profile }
        }
        row("dock.createMenu.host", "star", app.T("Tổ chức sự kiện", "Host an event"),
            app.T("Miễn phí. Tắt lúc nào cũng được.", "Free. Turn it off any time.")) {
            app.startHosting(land: .home)
        }
    }

    @ViewBuilder private var hostRows: some View {
        row("dock.createMenu.event", "plus", app.T("Tạo sự kiện", "Create event"),
            app.T("5 bước, có thể lưu nháp.", "5 steps, save a draft any time."), primary: true) { app.goCreate() }
        row("dock.createMenu.story", "camera", app.T("Đăng story", "Post a story"),
            app.T("Ảnh từ thư viện hoặc camera.", "A photo from your library or camera."), expanded: storyOpen, closes: false) {
            withAnimation(.easeOut(duration: 0.2)) { storyOpen.toggle() }
        }
        if storyOpen {
            subRow("dock.createMenu.story.library", "photo.on.rectangle", app.T("Thư viện ảnh", "Photo library")) { app.storyLibraryPickerOpen = true }
            subRow("dock.createMenu.story.camera", "camera", app.T("Camera", "Camera")) { app.storyCameraOpen = true }
        }
        row("dock.createMenu.story.event", "square.and.arrow.up", app.T("Chia sẻ một sự kiện của tôi", "Share one of my events"),
            app.T("Gửi link sự kiện đang mở.", "Send the link to a live event.")) { app.dockEventStoryPickerOpen = true }
        row("dock.createMenu.survey", "list.bullet.clipboard", app.T("Khảo sát mới", "New survey"),
            app.T("Hỏi khách muốn gì cho buổi tới.", "Ask guests what they want next.")) {
            app.surveysHostingTab = "active"
            app.surveyCreateRequested = true
            app.screen = .surveysHosting
        }
    }

    private func row(_ id: String, _ icon: String, _ title: String, _ desc: String, primary: Bool = false,
                     expanded: Bool? = nil, closes: Bool = true, action: @escaping () -> Void) -> some View {
        Button {
            if closes { run(action) } else { action() }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 40, height: 40)
                    .background(primary ? app.palette.paper.opacity(0.16) : app.palette.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16, weight: .semibold))
                    Text(desc).font(.system(size: 13)).opacity(primary ? 0.8 : 1)
                        .foregroundStyle(primary ? app.palette.paper : app.palette.ink.opacity(0.62))
                }
                Spacer(minLength: 0)
                if let expanded {
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0)).accessibilityHidden(true)
                }
            }
            .foregroundStyle(primary ? app.palette.paper : app.palette.ink)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: primary ? 64 : 56, alignment: .leading)
            .background(primary ? app.palette.ink : Color.clear, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func subRow(_ id: String, _ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button { run(action) } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 15)).frame(width: 22).accessibilityHidden(true)
                Text(title).font(.system(size: 14.5))
                Spacer(minLength: 0)
            }
            .foregroundStyle(app.palette.ink)
            .padding(.leading, 76).padding(.trailing, 12)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}
