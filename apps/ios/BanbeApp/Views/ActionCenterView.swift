import SwiftUI

/// TASK A (2026-10-01 UX foundation pass) — reusable presentational piece,
/// mirrors src/screens/ActionCenter.jsx exactly: at most 3 cards + a "Xem
/// tất cả" row when more exist; renders nothing at all when `items` is
/// empty (the section itself must not exist, not just be visually empty).
struct ActionCenterView: View {
    @EnvironmentObject private var app: AppState
    let items: [ActionCenterItem]
    let onSeeAll: () -> Void
    /// Most callers (Home, Account) sit inside a container with no horizontal
    /// padding of its own, so this view applies its own 20pt. Dashboard's
    /// container already applies 22pt to everything inside it — pass 0 there
    /// to avoid double-padding instead of negative-padding as a workaround.
    var horizontalInset: CGFloat = 20

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(app.T("Việc cần xử lý", "Things to do"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(app.palette.ink.opacity(0.7))
                ForEach(items.prefix(3)) { item in
                    Button(action: item.onTap) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.label)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(item.severity == .overdue ? BanbeTheme.alert : app.palette.ink)
                                Text(item.detail).font(.system(size: 12.5)).lineLimit(1).foregroundStyle(app.palette.ink)
                            }
                            Spacer(minLength: 8)
                            Text(item.ctaLabel + " ›")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(app.palette.ink.opacity(0.7))
                        }
                        .padding(14)
                        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(item.testId)
                }
                if items.count > 3 {
                    Button(action: onSeeAll) {
                        Text(app.T("Xem tất cả", "See all"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(app.palette.ink.opacity(0.75))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, horizontalInset)
            .padding(.top, 10)
            .accessibilityIdentifier("action-center")
        }
    }
}
