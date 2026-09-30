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
/// TASK 1 (dock "+" native-menu pass) — the custom bottom tray
/// (`DockCreateTrayView`, now removed) this used to open is replaced by a
/// native SwiftUI `Menu`, the SAME anchored-popover pattern already used by
/// `NotificationsView`'s row "…" menu and `InboxRow`'s own (MessagingViews.
/// swift) — a `Menu`'s popover is owned by UIKit and composites above
/// everything, including a `.sheet()` on Map, with zero extra wiring, and
/// unlike the old tray it needs no full-screen scrim, so it can stay
/// entirely inside this view — still a child of BottomTabBarOverlay's own
/// separate always-on-top UIWindow, same as the dock itself. Dismissing
/// without picking a row is handled entirely by the system (no scrim/state
/// to leak), so Map's own camera/list-detent/search/filter/scroll state is
/// untouched by construction.
///
/// "Post a story" reuses the EXACT SAME pipeline AccountView's own
/// "▪︎ Đăng story" menu uses (`app.storyLibraryPickerOpen`/
/// `app.storyCameraOpen` → `app.publishStory()`, presented centrally from
/// RootView) — not a second upload pipeline. Per AccountView's own
/// "PhotosPicker inside Menu swallowing taps" note, these rows only flip a
/// flag; they never present a picker directly.
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
struct DockCreateButtonView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        // Visible only in organizer mode (current UI preference — see
        // AppState+Data.swift's applyOrganizerMode fix — never
        // eligibility), matching the old pill's own gate exactly. DockRow
        // itself already only inserts this view under the same condition,
        // but keeping the check here too means this view never renders
        // anything if ever reused/embedded elsewhere without that gate.
        // Same gate Post-story's own row in AccountView uses, so a
        // non-organizer never sees a dead "Post a story" action here either
        // — the whole button (and both its actions) is simply absent,
        // matching this codebase's existing "hide while organizerMode is
        // off" convention rather than showing a disabled/explained row.
        if app.organizerMode {
            Menu {
                Button {
                    app.goCreate()
                } label: {
                    Label(app.T("Tạo sự kiện", "Create event"), systemImage: "calendar.badge.plus")
                }
                .accessibilityIdentifier("dock.createMenu.event")
                Menu {
                    Button {
                        app.storyLibraryPickerOpen = true
                    } label: {
                        Label(app.T("Thư viện ảnh", "Photo library"), systemImage: "photo.on.rectangle")
                    }
                    Button {
                        app.storyCameraOpen = true
                    } label: {
                        Label(app.T("Camera", "Camera"), systemImage: "camera")
                    }
                } label: {
                    Label(app.T("Đăng story", "Post a story"), systemImage: "photo.badge.plus")
                }
                .accessibilityIdentifier("dock.createMenu.story")
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(app.palette.ink)
                    .frame(width: BottomTabBar.createButtonSize, height: BottomTabBar.createButtonSize)
                    .background(.thinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(app.palette.ink.opacity(0.06)))
                    .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 6)
            }
            .accessibilityIdentifier("dock.createButton")
            .accessibilityLabel(app.T("Tạo mới", "Create"))
        }
    }
}
