import SwiftUI

/// Publishes a real control's on-screen frame for the v3 tour (note 64) under a stable id ("tour.home.search").
/// Global coordinates: the main window and the dock window are both full-screen at the origin, so a frame from either
/// lines up with the overlay drawn in the dock window. Nothing about the control itself changes.
/// Each modifier instance is its own owner: when two views publish the same id in turn (Account's Personal and Host
/// tiles swapping), the outgoing one's onDisappear must not wipe the incoming one's frame.
private struct TourTargetModifier: ViewModifier {
    let id: String
    @State private var owner = UUID()
    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rect in
                OnboardingTourController.shared.report(id, rect, owner: owner)
            }
            .onDisappear { OnboardingTourController.shared.report(id, nil, owner: owner) }
    }
}

extension View {
    func tourTarget(_ id: String) -> some View { modifier(TourTargetModifier(id: id)) }
}
