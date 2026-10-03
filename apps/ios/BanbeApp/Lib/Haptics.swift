import UIKit

/// The one place app-owned haptics go through. Uses only the system
/// feedback generators and respects Settings -> Haptic Feedback
/// (`banbe.hapticsEnabled`, default on).
///
/// Call it from a user ACTION or a server-confirmed RESULT — never from a
/// render, poll, hydration, background error or per-pixel drag update.
enum Haptics {
    static let defaultsKey = "banbe.hapticsEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }

    /// A committed choice (tab, filter, save, reorder).
    @MainActor static func selection() {
        guard isEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// A light physical tap for a plain action (open, copy, toggle).
    @MainActor static func light() { impact(.light) }

    @MainActor static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    /// A server-confirmed success.
    @MainActor static func success() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// A user-confirmed destructive action.
    @MainActor static func warning() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// An actionable failure the user triggered (use sparingly).
    @MainActor static func error() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
