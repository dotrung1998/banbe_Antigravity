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
/// computed padding math. Tapping it no longer opens a menu in THIS window
/// — the tray it opens (`DockCreateTrayView`, RootView.swift) needs to rise
/// well above this window's own small hit-testable band and dim the actual
/// screen content behind it, neither of which this narrow band-sized window
/// can do — so this button only flips `app.dockCreateTrayOpen`, a plain
/// published bool the MAIN window's RootView reads to present the tray
/// itself. The "+"→"X" morph stays here, driven by that same shared bool,
/// so the two windows' visuals stay in lockstep with no duplicated state.
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
        if app.organizerMode {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { app.dockCreateTrayOpen.toggle() }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(app.palette.ink)
                    .frame(width: BottomTabBar.createButtonSize, height: BottomTabBar.createButtonSize)
                    .background(.thinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(app.palette.ink.opacity(0.06)))
                    .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 6)
                    .rotationEffect(.degrees(app.dockCreateTrayOpen ? 45 : 0))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("dock.createButton")
            .accessibilityLabel(app.dockCreateTrayOpen ? app.T("Đóng", "Close") : app.T("Tạo mới", "Create"))
        }
    }
}
