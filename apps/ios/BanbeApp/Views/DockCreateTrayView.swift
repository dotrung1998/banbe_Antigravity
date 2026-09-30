import SwiftUI

/// TASK 1 real-device follow-up — the compact creation tray the dock "+"
/// opens. Presented from RootView's own main-window ZStack (not
/// BottomTabBarOverlay's separate always-on-top window DockCreateButtonView
/// itself lives in) on purpose: that window is sized to a small
/// hit-testable band just tall enough for the dock/button, nowhere near
/// enough to host a full-screen dimming scrim or a tray that visually
/// "rises above the dock" — only the MAIN window's content actually spans
/// the whole screen. A native SwiftUI `Menu` was tried instead of this
/// tray (DockCreateButtonView's own doc comment has the real-device
/// clipping bug that caused) and reverted back to this, a real,
/// previously-working mechanism. The dock/button stay visible and tappable
/// through this (no bottom padding eats their band), which is what makes
/// the "+"→"X" they show while this is open, and a second tap closing it,
/// actually work.
struct DockCreateTrayView: View {
    @EnvironmentObject private var app: AppState
    @GestureState private var dragY: CGFloat = 0
    private let dismissThreshold: CGFloat = 60
    // "Post a story" expands into a Photo library/Camera choice within
    // this same tray, matching web's identical DockCreateButton.jsx
    // (storySubOpen) — no native submenu needed, full manual control.
    @State private var storySubOpen = false

    // FIX PASS (2026-09-30, Map-sheet layering) — this tray now lives inside
    // BottomTabBarOverlay's own always-on-top UIWindow (see that file's own
    // doc comment for why — that window is the ONE thing in this app proven
    // to draw above a native `.sheet()`, which is exactly what MapExplore's
    // filter/list sheet is). That overlay temporarily grows from its normal
    // small dock-band frame to full-screen while this tray is open, then
    // shrinks back once it's gone — but only AFTER this view's own close
    // animation finishes, so the exit transition isn't clipped by a
    // premature frame shrink. `BottomTabBarOverlay.setDockCreateTrayOpen`
    // reads this exact constant for that delay, so the two can never drift
    // out of sync with each other.
    static let closeAnimationDuration: TimeInterval = 0.15

    private func close() {
        withAnimation(.easeInOut(duration: Self.closeAnimationDuration)) { app.dockCreateMenuOpen = false }
        storySubOpen = false
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Scrim — dims real screen content behind the tray; the dock
            // and "+" themselves sit in the SEPARATE, always-on-top overlay
            // window, so they're never dimmed by this and stay tappable to
            // close.
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { close() }
                .accessibilityIdentifier("dock.createBackdrop")
                .transition(.opacity)

            VStack(spacing: 0) {
                Capsule().fill(app.palette.rule).frame(width: 36, height: 4)
                    .padding(.top, 9).padding(.bottom, 4)

                Button {
                    close()
                    app.goCreate()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar.badge.plus").font(.system(size: 14, weight: .semibold))
                        Text(app.T("Tạo Sự Kiện", "Create Event")).font(.system(size: 14))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(app.palette.ink)
                    .padding(.horizontal, 18).padding(.vertical, 15)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dock.createMenu.event")

                Divider().overlay(app.palette.rule).padding(.horizontal, 18)

                // TASK 1 — "Post a story" reuses the EXACT SAME pipeline
                // AccountView's own "▪︎ Đăng story" menu uses
                // (app.storyLibraryPickerOpen/app.storyCameraOpen →
                // app.publishStory(), presented centrally from RootView) —
                // not a second upload pipeline.
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { storySubOpen.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "photo.badge.plus").font(.system(size: 14, weight: .semibold))
                        Text(app.T("Đăng Story", "Post A Story")).font(.system(size: 14))
                        Spacer(minLength: 0)
                        Image(systemName: storySubOpen ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold)).opacity(0.6)
                    }
                    .foregroundStyle(app.palette.ink)
                    .padding(.horizontal, 18).padding(.vertical, 15)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dock.createMenu.story")

                if storySubOpen {
                    VStack(spacing: 0) {
                        Button {
                            close()
                            app.storyLibraryPickerOpen = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "photo.on.rectangle").font(.system(size: 13))
                                Text(app.T("Thư Viện Ảnh", "Photo Library")).font(.system(size: 13.5))
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(app.palette.ink)
                            .padding(.leading, 40).padding(.trailing, 18).padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("dock.createMenu.story.library")

                        Button {
                            close()
                            app.storyCameraOpen = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "camera").font(.system(size: 13))
                                Text(app.T("Camera", "Camera")).font(.system(size: 13.5))
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(app.palette.ink)
                            .padding(.leading, 40).padding(.trailing, 18).padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("dock.createMenu.story.camera")
                    }
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity)
            .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(app.palette.rule, lineWidth: 1))
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
            .padding(.horizontal, BottomTabBar.dockMargin)
            // Rises to just above the dock row, not the physical screen
            // bottom — the dock/button stay visible underneath.
            .padding(.bottom, BottomTabBar.barHeight + BottomTabBar.bottomOffset + 14)
            .offset(y: dragY)
            .gesture(
                DragGesture(minimumDistance: 6)
                    .updating($dragY) { value, state, _ in state = max(0, value.translation.height) }
                    .onEnded { value in if value.translation.height > dismissThreshold { close() } }
            )
            .accessibilityIdentifier("dock.createMenu")
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(.interactiveSpring(response: 0.32, dampingFraction: 0.82), value: dragY)
    }
}
