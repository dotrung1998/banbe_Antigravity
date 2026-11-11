import SwiftUI

/// One of the four big Account tiles (note 66, Simple Shell phase 2). Mirrors web `AccountTiles`.
struct AccountTile: Identifiable {
    let key: String
    let symbol: String
    let title: String
    let value: String
    var badge: Int = 0
    let action: () -> Void
    var id: String { key }
}

/// The compact one-row shortcut strip under the Account tabs (web `AccountTileGrid`): icon over label, four columns,
/// hairlines above and below, no card fills. The whole cell is the tap target; a badge sits on its corner.
struct AccountTilesGrid: View {
    @EnvironmentObject var app: AppState
    let tiles: [AccountTile]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(tiles) { tileButton($0) }
        }
        .overlay(alignment: .top) { Rectangle().fill(app.palette.divider).frame(height: 1 / UIScreen.main.scale) }
        .overlay(alignment: .bottom) { Rectangle().fill(app.palette.divider).frame(height: 1 / UIScreen.main.scale) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("account.tiles")
        .tourTarget("tour.account.shortcuts")
    }

    private func tileButton(_ tile: AccountTile) -> some View {
        SwipeSafeButton {
            Haptics.light()
            tile.action()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: tile.symbol)
                    .font(.system(size: 22, weight: .light))
                    .frame(height: 26)
                    .foregroundStyle(app.palette.ink)
                Text(tile.title)
                    .font(.system(size: 12))
                    .foregroundStyle(app.palette.ink2)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 16).padding(.bottom, 14)
            .overlay(alignment: .topTrailing) {
                if tile.badge > 0 {
                    Text(AccountBadges.format(tile.badge))
                        .font(.caption2.weight(.bold)).monospacedDigit()
                        .padding(.horizontal, 6)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(BanbeTheme.alert, in: Capsule())
                        .foregroundStyle(BanbeTheme.onAlert)
                        .padding(.top, 8).padding(.trailing, 8)
                        .accessibilityIdentifier("account.tile.\(tile.key).badge")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(tile))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("account.tile.\(tile.key)")
    }

    private func accessibilityLabel(_ tile: AccountTile) -> String {
        let base = tile.value.isEmpty ? tile.title : "\(tile.title), \(tile.value)"
        guard tile.badge > 0 else { return base }
        return base + app.T(", \(tile.badge) mục mới", ", \(tile.badge) new item(s)")
    }
}

/// Hosting mode card shared by Account and the Home quick sheet (web: the `organizer-mode-toggle` card). Moss-washed
/// with a moss switch while on; the block fill with a grey switch while off. The whole card toggles.
struct HostingModeCard: View {
    @EnvironmentObject private var app: AppState
    let isOn: Bool
    var busy = false
    let identifier: String
    let action: () -> Void

    var body: some View {
        SwipeSafeButton(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "storefront")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 36, height: 36)
                    .background(app.palette.paper, in: Circle())
                    .foregroundStyle(app.palette.ink)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.T("Chế độ tổ chức", "Hosting mode")).font(.system(size: 15, weight: .semibold))
                    Text(app.T("Bật để tạo và quản lý sự kiện", "Turn on to create and manage events"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(app.palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule().fill(isOn ? app.palette.update : app.palette.ink.opacity(0.18))
                    Circle().fill(Color.white).frame(width: 22, height: 22)
                        .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                        .padding(3)
                }
                .frame(width: 46, height: 28)
                .animation(.easeOut(duration: 0.2), value: isOn)
                .accessibilityHidden(true)
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(app.palette.block)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(app.palette.update.opacity(isOn ? 0.18 : 0)))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .opacity(busy ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.T("Chế độ tổ chức", "Hosting mode"))
        .accessibilityValue(isOn ? app.T("Bật", "On") : app.T("Tắt", "Off"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
    }
}
