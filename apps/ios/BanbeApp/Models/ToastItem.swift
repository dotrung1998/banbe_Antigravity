import Foundation

/// One ephemeral in-app toast — see AppState.pushToast() / ToastOverlay.swift.
/// Mirrors the shape of a web toast (src/screens/ToastStack.jsx), sourced
/// from the same `notifications` row (AppNotification.title/.body).
struct ToastItem: Identifiable, Equatable {
    let id: UUID
    let title: String
    let body: String
}
