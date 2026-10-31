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

/// The 2×2 grid of big tiles at the top of Account. Each tile is ≥ 88pt tall, sits on palette.block with no
/// border, and grows with Dynamic Type; at accessibility sizes the grid becomes one column.
struct AccountTilesGrid: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let tiles: [AccountTile]

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) {
                    ForEach(tiles) { tileButton($0) }
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(stride(from: 0, to: tiles.count, by: 2)), id: \.self) { i in
                        HStack(alignment: .top, spacing: 12) {
                            tileButton(tiles[i])
                            if i + 1 < tiles.count { tileButton(tiles[i + 1]) } else { Color.clear.frame(maxWidth: .infinity) }
                        }
                        // Both tiles in a row share the taller one's height.
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("account.tiles")
    }

    private func tileButton(_ tile: AccountTile) -> some View {
        SwipeSafeButton {
            Haptics.light()
            tile.action()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Image(systemName: tile.symbol)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(app.palette.ink)
                    Spacer(minLength: 4)
                    if tile.badge > 0 {
                        Text(AccountBadges.format(tile.badge))
                            .font(.caption2.weight(.bold)).monospacedDigit()
                            .padding(.horizontal, 6)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(BanbeTheme.alert, in: Capsule())
                            .foregroundStyle(BanbeTheme.onAlert)
                            .accessibilityIdentifier("account.tile.\(tile.key).badge")
                    }
                }
                Spacer(minLength: 0)
                Text(tile.title)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(app.palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(tile.value)
                    .font(.footnote)
                    .foregroundStyle(app.palette.ink2)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.leading)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 88, maxHeight: .infinity, alignment: .topLeading)
            .background(app.palette.block, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(tile))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("account.tile.\(tile.key)")
    }

    private func accessibilityLabel(_ tile: AccountTile) -> String {
        let base = "\(tile.title), \(tile.value)"
        guard tile.badge > 0 else { return base }
        return base + app.T(", \(tile.badge) mục mới", ", \(tile.badge) new item(s)")
    }
}
