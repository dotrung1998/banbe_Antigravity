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
/// those cases (see that file's own applyVisibility()). The window's band
/// is already full-device-width on every current iPhone size (bandWidth's
/// own 444pt exceeds every iPhone's screen width, so `min(bandWidth,
/// screenBounds.width)` always clamps to the screen — confirmed by
/// reading BottomTabBarOverlay.attach(), not assumed), so this button has
/// real room to sit beside the dock without widening that band at all.
struct DockCreateButtonView: View {
    @EnvironmentObject private var app: AppState
    @State private var open = false
    private let size: CGFloat = 46

    var body: some View {
        // Visible only in organizer mode (current UI preference — see
        // AppState+Data.swift's applyOrganizerMode fix — never
        // eligibility), matching the old pill's own gate exactly.
        if app.organizerMode {
            VStack(alignment: .trailing, spacing: 10) {
                if open {
                    VStack(spacing: 0) {
                        Button {
                            open = false
                            app.goCreate()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
                                Text(app.T("Tạo sự kiện", "Create event")).font(.system(size: 13.5))
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(app.palette.ink)
                            .padding(.horizontal, 14).padding(.vertical, 13)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("dock.createMenu.event")
                    }
                    .frame(minWidth: 176)
                    .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(app.palette.rule, lineWidth: 1))
                    .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)
                    .accessibilityIdentifier("dock.createMenu")
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .bottomTrailing)))
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { open.toggle() }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(app.palette.paper)
                        .frame(width: size, height: size)
                        .background(app.palette.ink, in: Circle())
                        .shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 4)
                        .rotationEffect(.degrees(open ? 45 : 0))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dock.createButton")
                .accessibilityLabel(app.T("Tạo mới", "Create"))
            }
            .padding(.trailing, 16)
            .padding(.bottom, BottomTabBar.bottomOffset + (BottomTabBar.barHeight - size) / 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            // Outside-tap-to-close (rule C6) — a transparent full-window
            // tap target BEHIND the button/menu (same ZStack layer order
            // trick RootView already uses elsewhere), only while open.
            .background(
                Group {
                    if open {
                        Color.black.opacity(0.0001)
                            .contentShape(Rectangle())
                            .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { open = false } }
                    }
                }
            )
        }
    }
}
