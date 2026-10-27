import SwiftUI

/// Publishes a real control's on-screen frame for the v3 tour (note 64) under a stable id ("tour.home.search").
/// Global coordinates: the main window and the dock window are both full-screen at the origin, so a frame from either
/// lines up with the overlay drawn in the dock window. Nothing about the control itself changes.
private struct TourTargetModifier: ViewModifier {
    let id: String
    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rect in
                OnboardingTourController.shared.report(id, rect)
            }
            .onDisappear { OnboardingTourController.shared.report(id, nil) }
    }
}

extension View {
    func tourTarget(_ id: String) -> some View { modifier(TourTargetModifier(id: id)) }
}
