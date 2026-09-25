import SwiftUI

/// TASK 1 (2026-10-05 fix pass) — the compact creation tray the dock "+"
/// opens. Presented from RootView's own main-window ZStack (not
/// BottomTabBarOverlay's separate always-on-top window DockCreateButtonView
/// itself lives in) on purpose: that window is sized to a small
/// hit-testable band just tall enough for the dock/button (see
/// BottomTabBarOverlay's own `bandHeight`), nowhere near enough to host a
/// full-screen dimming scrim or a tray that visually "rises above the
/// dock" — only the MAIN window's content actually spans the whole screen.
/// The dock/button stay visible and tappable through this (no bottom
/// padding eats their band), which is what makes the "+"→"X" they show
/// while this is open, and a second tap closing it, actually work.
struct DockCreateTrayView: View {
    @EnvironmentObject private var app: AppState
    @GestureState private var dragY: CGFloat = 0
    private let dismissThreshold: CGFloat = 60

    private func close() {
        withAnimation(.easeInOut(duration: 0.15)) { app.dockCreateTrayOpen = false }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Scrim — dims real screen content behind the tray; the dock
            // and "+" themselves sit in the SEPARATE, always-on-top overlay
            // window, so they're never dimmed by this and stay tappable to
            // close, matching rule C6 ("selecting the row closes tray
            // before navigating" + "outside-tap ... downward-dismiss").
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { close() }
                .accessibilityIdentifier("dock.createBackdrop")
                .transition(.opacity)

            VStack(spacing: 0) {
                Capsule().fill(app.palette.rule).frame(width: 36, height: 4)
                    .padding(.top, 9).padding(.bottom, 4)
                // Currently ONE actionable row — no dummy/placeholder
                // options, per this ticket's own instruction; a single row
                // sized to its own content (not stretched into a big empty
                // sheet).
                Button {
                    close()
                    app.goCreate()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
                        Text(app.T("Tạo sự kiện", "Create event")).font(.system(size: 14))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(app.palette.ink)
                    .padding(.horizontal, 18).padding(.vertical, 15)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dock.createMenu.event")
            }
            .frame(maxWidth: .infinity)
            .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(app.palette.rule, lineWidth: 1))
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
            .padding(.horizontal, BottomTabBar.dockMargin)
            // Rises to just above the dock row, not the physical screen
            // bottom — the dock/button stay visible underneath, per this
            // struct's own doc comment.
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
