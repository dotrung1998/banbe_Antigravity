import Foundation

/// One ephemeral in-app toast — see AppState.pushToast() / ToastOverlay.swift.
/// Mirrors the shape of a web toast (src/screens/ToastStack.jsx): carries
/// the whole source `AppNotification`, not just title/body, so tapping it
/// can route to the right place the same way NotificationsView's own rows
/// do (AppState.openNotification()).
struct ToastItem: Identifiable, Equatable {
    let id: UUID
    let notification: AppNotification
}
