import SwiftUI

/// What the screen under the persistent search bar wants from it (the bar itself is hosted once, in RootView).
/// `owner` stops a screen that is going away from clearing the handlers of the one coming in.
struct SearchBarHandlers {
    var owner: String
    var placeholder: String
    var back: () -> Void
    var submit: () -> Void = {}
    var cancel: () -> Void = {}
    /// Map only: the filters button (with its count) shown while the field is not focused.
    var filters: (() -> Void)? = nil
    var badge = 0
}

/// ONE search bar for Search and Map (hosted above both, so it never rebuilds when one gives way to the other: the
/// text field, its focus and the keyboard carry over). Context-aware: on Search it edits the global query, on Map the
/// map's own query. Home keeps its tappable bar in the feed; this one starts over it and glides up to the top, and
/// glides back down on close (`app.searchBarAtHome` is driven by the screen that is open).
struct PersistentSearchBar: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// After the screen under the bar closes onto Home, the bar stays a moment over Home's own bar and fades out
    /// while Home fades in (no empty beat in between).
    @State private var lingering = false
    @State private var lastHandlers: SearchBarHandlers?
    private var isMap: Bool { app.screen == .mapExplore }
    private var active: Bool {
        isMap || app.screen == .search || (app.searchOverlayOpen && app.screen == .home)
    }
    private var topInset: CGFloat {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.keyWindow?.safeAreaInsets.top ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            if active || lingering, let h = app.searchBarHandlers ?? lastHandlers {
                let home = app.homeSearchBarFrame
                let atHome = app.searchBarAtHome && home.width > 0 && !reduceMotion
                bar(h, atHome: atHome)
                    .frame(width: atHome ? home.width : geo.size.width - 32, height: atHome ? 46 : 44)
                    .offset(x: atHome ? home.minX : 16, y: atHome ? home.minY : topInset + 8)
                    .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.88), value: atHome)
                    .opacity(active ? 1 : 0)
                    .allowsHitTesting(active)
                    .animation(.easeOut(duration: 0.3), value: active)
            }
        }
        .ignoresSafeArea()
        .onChange(of: app.searchBarHandlers?.owner) { _, _ in if let h = app.searchBarHandlers { lastHandlers = h } }
        .onChange(of: active) { was, now in
            guard was, !now, app.searchBarAtHome else { return }
            lingering = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { lingering = false; lastHandlers = nil }
        }
    }

    private func bar(_ h: SearchBarHandlers, atHome: Bool) -> some View {
        HStack(spacing: atHome ? 0 : 8) {
            Button(action: h.back) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .mapSurface(Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .frame(width: atHome ? 0 : 44)
            .opacity(atHome ? 0 : 1)
            .clipped()
            .accessibilityLabel(isMap ? app.T("Đóng bản đồ", "Close map") : app.T("Quay lại", "Back"))
            .accessibilityIdentifier(isMap ? "map.back" : "search.back")

            field(h)

            if isMap {
                if app.searchBarFocused {
                    Button(app.T("Huỷ", "Cancel"), action: h.cancel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(app.palette.clay)
                        .frame(minHeight: 44)
                        .buttonStyle(.plain)
                        .opacity(atHome ? 0 : 1)
                        .accessibilityIdentifier("map.search.cancel")
                } else if let filters = h.filters {
                    Button(action: filters) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                            .mapSurface(Circle(), interactive: true)
                            .overlay(alignment: .topTrailing) {
                                if h.badge > 0 {
                                    Text("\(h.badge)")
                                        .font(.system(size: 11, weight: .bold)).monospacedDigit()
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
                                        .background(app.palette.clay, in: Capsule())
                                        .offset(x: 4, y: -4)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .frame(width: atHome ? 0 : 44)
                    .opacity(atHome ? 0 : 1)
                    .clipped()
                    .accessibilityLabel(h.badge > 0 ? app.T("Bộ lọc, \(h.badge) đang bật", "Filters, \(h.badge) on")
                                                    : app.T("Bộ lọc", "Filters"))
                    .accessibilityIdentifier("map.filterButton")
                }
            }
        }
        .foregroundStyle(app.palette.ink)
    }

    private func field(_ h: SearchBarHandlers) -> some View {
        let text = isMap ? $app.mapSearchText : $app.searchQuery
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .semibold)).opacity(0.6).accessibilityHidden(true)
            FocusableTextField(text: text, isFirstResponder: $app.searchBarFocused, placeholder: h.placeholder,
                               font: .preferredFont(forTextStyle: .body), onSubmit: h.submit)
                .frame(height: 24)
                .accessibilityLabel(app.T("Tìm kiếm", "Search"))
                .accessibilityIdentifier(isMap ? "map.searchInput" : "search.input")
            if !text.wrappedValue.isEmpty {
                Button { text.wrappedValue = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).opacity(0.5)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .padding(.trailing, -12)
                .accessibilityLabel(app.T("Xoá", "Clear"))
                .accessibilityIdentifier(isMap ? "map.searchClear" : "search.clear")
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 44)
        .mapSurface(Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(isMap ? "map.searchField" : "search.field")
    }
}
