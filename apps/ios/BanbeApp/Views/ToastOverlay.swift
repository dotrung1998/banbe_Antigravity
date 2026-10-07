import SwiftUI

/// Small, ephemeral in-app toasts — mirrors src/screens/ToastStack.jsx on
/// web. Separate from NotificationsView (the permanent, pull-based inbox):
/// this is what proactively surfaces an event while the app is open. See
/// .claude/notes/07-notifications.md.
///
/// Only the visible stack is capped (visibleCount) — "Xem thêm" reveals the
/// rest of the SAME local queue in place, no fetch. "Tắt tất cả" and every
/// dismiss path here (individual/see-more/all) only ever touch the local
/// `app.toasts` queue via dismissToast()/dismissAllToasts() — neither calls
/// markNotificationRead(), so the bell inbox's unread state/badge count are
/// untouched. See .claude/notes/07-notifications.md.
struct ToastOverlay: View {
    @EnvironmentObject private var app: AppState
    @State private var expanded = false
    private let visibleCount = 3

    private var hiddenCount: Int { app.toasts.count - visibleCount }
    private var shown: [ToastItem] {
        expanded || hiddenCount <= 0 ? app.toasts : Array(app.toasts.prefix(visibleCount))
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(shown) { toast in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(toast.notification.kind == "event_announcement" ? "📣 " + app.T("Thông báo từ host", "Host announcement") : toast.notification.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(toast.notification.kind == "event_announcement" ? BanbeTheme.alert : app.palette.ink)
                        if !toast.notification.body.isEmpty {
                            Text(toast.notification.body)
                                .font(.system(size: 12))
                                .foregroundStyle(app.palette.ink.opacity(0.75))
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                    Button {
                        app.dismissToast(toast.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(app.palette.ink.opacity(0.55))
                            .frame(width: 20, height: 20)
                    }
                    .accessibilityIdentifier("toast.dismiss")
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(toast.notification.kind == "event_announcement" ? BanbeTheme.alert : app.palette.rule,
                                lineWidth: toast.notification.kind == "event_announcement" ? 1.5 : 1)
                )
                .contentShape(Rectangle())
                // Notification banner fix pass (2026-09-30 third) — one
                // gesture does double duty: `pressing` toggles the SAME
                // real pause/resume timer a `.onTapGesture` alone couldn't
                // observe (pause while the user is actively pressing the
                // banner), `perform` fires on a completed tap. Race fix:
                // the auto-dismiss timer is cancelled (via dismissToast)
                // BEFORE openNotification's own async work runs.
                .onLongPressGesture(minimumDuration: 0, pressing: { pressing in
                    if pressing { app.pauseToastTimer(toast.id) } else { app.resumeToastTimer(toast.id) }
                }, perform: {
                    app.dismissToast(toast.id) // don't wait for the auto-dismiss timer — it's been acted on
                    app.openNotification(toast.notification)
                })
                .onAppear {
                    // Duration starts here — when this card is actually
                    // painted — not at whatever earlier moment pushToast()
                    // enqueued it (it may have sat behind "Xem thêm" until
                    // now). Idempotent on AppState's side.
                    app.markToastVisible(toast.id)
                }
                .allowsHitTesting(true)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity.combined(with: .move(edge: .top))
                ))
                .accessibilityIdentifier("toast")
            }
            if hiddenCount > 0 || app.toasts.count > 1 {
                HStack(spacing: 8) {
                    if !expanded && hiddenCount > 0 {
                        Button("Xem thêm (\(hiddenCount))") { expanded = true }
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(app.palette.ink)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(app.palette.field, in: Capsule())
                            .overlay(Capsule().stroke(app.palette.rule, lineWidth: 1))
                            .accessibilityIdentifier("toast.seeMore")
                    }
                    if app.toasts.count > 1 {
                        Button("Tắt tất cả") {
                            app.dismissAllToasts()
                            expanded = false
                        }
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(app.palette.ink.opacity(0.75))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(app.palette.field, in: Capsule())
                        .overlay(Capsule().stroke(app.palette.rule, lineWidth: 1))
                        .accessibilityIdentifier("toast.dismissAll")
                    }
                }
                .allowsHitTesting(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.28), value: app.toasts)
        .allowsHitTesting(false)
        // Notification banner fix pass (2026-09-30 third) — reports this
        // content's own real on-screen frame (zero when there's nothing to
        // show) so `BottomTabBarOverlay` can widen its always-on-top
        // window's geometric pass-through hit-test region to cover it —
        // see `ToastFramePreferenceKey`'s own doc comment below.
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ToastFramePreferenceKey.self, value: app.toasts.isEmpty ? .zero : proxy.frame(in: .global))
            }
        )
    }
}

/// Notification banner fix pass (2026-09-30 third) — carries `ToastOverlay`'s
/// own real on-screen frame up to `BottomTabBarOverlayRoot`
/// (BottomTabBarOverlay.swift), which forwards it to
/// `BottomTabBarOverlay.setToastRect(_:)`. This is what lets
/// `DockOverlayWindow.hitTest` (a window that otherwise geometrically
/// rejects every touch outside its small dock band or an open tray) also
/// let a tap on the toast banner itself through, now that `ToastOverlay`
/// renders inside that same always-on-top window instead of the main one.
struct ToastFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
