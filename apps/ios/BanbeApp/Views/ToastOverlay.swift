import SwiftUI

/// Small, ephemeral in-app toasts — mirrors src/screens/ToastStack.jsx on
/// web. Separate from NotificationsView (the permanent, pull-based inbox):
/// this is what proactively surfaces an event while the app is open. See
/// .claude/notes/07-notifications.md.
struct ToastOverlay: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(spacing: 8) {
            ForEach(app.toasts) { toast in
                VStack(alignment: .leading, spacing: 2) {
                    Text(toast.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(app.palette.ink)
                    if !toast.body.isEmpty {
                        Text(toast.body)
                            .font(.system(size: 12))
                            .foregroundStyle(app.palette.ink.opacity(0.75))
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity.combined(with: .move(edge: .top))
                ))
                .accessibilityIdentifier("toast")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.28), value: app.toasts)
        .allowsHitTesting(false)
    }
}
