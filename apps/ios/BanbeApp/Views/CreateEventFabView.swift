import SwiftUI

/// TASK C (2026-10-01 UX foundation pass) — persistent compact pill FAB for
/// organizer mode, matching Reserve/InkButton's own visual language (dark
/// ink fill, soft drop shadow, press-state scale) rather than a new style.
/// Placement is an ALLOWLIST (mirrors CreateEventFab.jsx exactly: Home,
/// Dashboard, Account only), not a "hide everywhere except" denylist.
struct CreateEventFabView: View {
    @EnvironmentObject private var app: AppState
    @GestureState private var pressed = false

    static let allowedScreens: Set<Screen> = [.home, .dashboard, .profile]

    var body: some View {
        if app.organizerMode, Self.allowedScreens.contains(app.screen) {
            Button(action: { app.goCreate() }) {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                    Text(app.T("Tạo sự kiện", "Create event"))
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(app.palette.paper)
                .padding(.vertical, 13).padding(.horizontal, 18)
                .background(app.palette.ink, in: Capsule())
                .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 10)
                .scaleEffect(pressed ? 0.95 : 1)
            }
            .buttonStyle(.plain)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($pressed) { _, state, _ in state = true }
            )
            .accessibilityIdentifier("create-event-fab")
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }
}
