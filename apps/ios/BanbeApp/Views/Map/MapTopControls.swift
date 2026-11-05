import SwiftUI

// Map E+ (note 79, plan step 6): the shared controls over the map AND over the list: back, search, filters (with a
// count badge), then a chip row the Map passes in. Their measured bottom edge is the list's top and the reference
// rect's top. Web twin: the `map-top` block in src/screens/MapExplore.jsx.
struct MapTopControls<Chips: View>: View {
    @EnvironmentObject private var app: AppState
    @Binding var query: String
    @Binding var focused: Bool
    let filterBadge: Int
    /// Home's search field handed over a focused intent (`startFocusedOnSearch`, one-shot).
    let autofocus: Bool
    let onBack: () -> Void
    let onFilters: () -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void
    @ViewBuilder let chips: () -> Chips

    /// Body-text line height, scaled with Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var fieldHeight: CGFloat = 24

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                // Arrow only (owner 2026-11-01); the spoken label still says what it does.
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                        .nativeGlass(Circle(), interactive: true)
                }
                .accessibilityLabel(app.T("Đóng bản đồ", "Close map"))
                .accessibilityIdentifier("map.back")

                searchField

                if focused {
                    // Cancel = keyboard down.
                    Button(app.T("Huỷ", "Cancel"), action: onCancel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(app.palette.clay)
                        .frame(minHeight: 44)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("map.search.cancel")
                } else {
                    // Everything else (any date, price per ticket, almost full, type chips) in Home's sheet, as a draft.
                    Button(action: onFilters) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                            .nativeGlass(Circle(), interactive: true)
                            .overlay(alignment: .topTrailing) {
                                if filterBadge > 0 {
                                    Text("\(filterBadge)")
                                        .font(.system(size: 11, weight: .bold)).monospacedDigit()
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
                                        .background(app.palette.clay, in: Capsule())
                                        .offset(x: 2, y: -2)
                                        .accessibilityHidden(true)
                                }
                            }
                    }
                    .accessibilityLabel(filterBadge > 0 ? app.T("Bộ lọc, \(filterBadge) đang bật", "Filters, \(filterBadge) on")
                                                         : app.T("Bộ lọc", "Filters"))
                    .accessibilityIdentifier("map.filterButton")
                }
            }
            .padding(.horizontal, 16)

            chips()
        }
        .foregroundStyle(app.palette.ink)
        .padding(.top, 8)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: MapControlsBottomKey.self, value: proxy.frame(in: .global).maxY)
        })
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.top")
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Always mounted and visible (note 74): the iOS focus rule needs the field itself in the hierarchy.
    /// `FocusableTextField` (Components.swift), not SwiftUI's own `TextField` + `@FocusState`, which never delivered
    /// programmatic focus to this field on a real device.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 14)).opacity(0.55).accessibilityHidden(true)
            FocusableTextField(
                text: $query,
                isFirstResponder: $focused,
                // The matcher covers name, category, area, host and description (Search.swift); cities come from
                // cities.json (note 73).
                placeholder: app.T("Tìm tên, loại, khu vực, thành phố…", "Search name, type, area, city…"),
                font: .preferredFont(forTextStyle: .body),
                onSubmit: onSubmit
            )
            // A UITextField has no intrinsic height cap here; a min height let it fill the screen.
            .frame(height: fieldHeight)
            .accessibilityIdentifier("map.searchInput")
            .onAppear { if autofocus { focused = true } }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).opacity(0.5)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .padding(.trailing, -12)
                .accessibilityLabel(app.T("Xoá tìm kiếm", "Clear search"))
                .accessibilityIdentifier("map.searchClear")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .nativeGlass(Capsule(), interactive: false)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.searchField")
    }
}
