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
        .popover(isPresented: $app.dockCreateOpen, arrowEdge: .bottom) {
            PopoverMenuList(items: centredMenuItems) { app.dockCreateOpen = false }
                .environmentObject(app)
        }
        .accessibilityIdentifier("dock.createButton")
        .tourTarget("tour.dock.create")
        .accessibilityLabel(app.T("Tạo mới", "Create"))
        .accessibilityHint(hostMenu
                           ? app.T("Tạo sự kiện, đăng story hoặc khảo sát", "Create an event, a story or a survey")
                           : app.T("Thêm vào lịch, mời bạn bè hoặc tổ chức sự kiện", "Add to your schedule, invite friends or host an event"))
    }

    /// Host (Home on Hosting): Create event first, then Post a story, Share one of my events, New survey.
    /// Goer: Add to my schedule, Invite friends, Host an event (no story: stories are host-only, owner decision 3).
    /// Guest: the goer rows, each opening the contextual sign-in prompt.
    /// The menu follows the Home view (plan items 1 + 4): a host who switched Home to Going out gets the goer rows,
    /// whose "Host an event" takes them back to Home > Hosting from any tab.
    private var hostMenu: Bool { app.isSignedIn && app.effectiveHomeView == .host }

    private var centredMenuItems: [PopoverMenuItem] {
        if hostMenu {
            return [
                PopoverMenuItem(id: "dock.createMenu.event", title: app.T("Tạo sự kiện", "Create event"),
                                systemImage: "calendar.badge.plus") { app.goCreate() },
                // Same pipeline AccountView's "Đăng story" uses (storyLibraryPickerOpen / storyCameraOpen -> publishStory()).
                PopoverMenuItem(id: "dock.createMenu.story.library", title: app.T("Đăng story từ Thư viện ảnh", "Post a story from Photos"),
                                systemImage: "photo.on.rectangle") { app.storyLibraryPickerOpen = true },
                PopoverMenuItem(id: "dock.createMenu.story.camera", title: app.T("Đăng story bằng Camera", "Post a story with Camera"),
                                systemImage: "camera") { app.storyCameraOpen = true },
                // Same picker + beginEventStory as Account's "Share one of my events" (presented by RootView).
                PopoverMenuItem(id: "dock.createMenu.story.event", title: app.T("Chia sẻ một sự kiện của tôi", "Share one of my events"),
                                systemImage: "calendar") { app.dockEventStoryPickerOpen = true },
                PopoverMenuItem(id: "dock.createMenu.survey", title: app.T("Khảo sát mới", "New survey"),
                                systemImage: "list.bullet.clipboard") {
                    app.surveysHostingTab = "active"
                    app.surveyCreateRequested = true
                    app.screen = .surveysHosting
                },
            ]
        }
        let guest = !app.isSignedIn
        return [
            PopoverMenuItem(id: "dock.createMenu.schedule", title: app.T("Thêm vào lịch của tôi", "Add to my schedule"),
                            systemImage: "calendar.badge.plus") {
                // Note 44: plans are added from Schedule's Discover list (device-local "Add to banbe Schedule").
                if guest { return app.promptSignIn(.schedule) }
                app.scheduleMode = .discover
                app.goSchedule()
            },
            PopoverMenuItem(id: "dock.createMenu.invite", title: app.T("Mời bạn bè", "Invite friends"),
                            systemImage: "person.2", disabled: !guest && app.referralLink == nil) {
                if guest { return app.promptSignIn(.invite) }
                app.shareReferral()
            },
            PopoverMenuItem(id: "dock.createMenu.host", title: app.T("Tổ chức sự kiện", "Host an event"),
                            systemImage: "sparkles") {
                // Plan item 4: the shared start-hosting path. Guest → sign-in prompt; organizer mode off → the
                // Start hosting invitation; on → lands on Home > Hosting at the top, from whichever tab this ran.
                app.startHosting(land: .home)
            },
        ]
    }
}
