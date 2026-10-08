import SwiftUI

/// A bottom sheet with the web app's paper styling — the shape all three
/// of the sheets below share (src/screens/sheets/*.jsx).
struct BottomSheet<Content: View>: View {
    @EnvironmentObject private var app: AppState
    let onDismiss: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
            VStack(alignment: .leading, spacing: 0) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 26)
                .padding(.bottom, 36)
                .background(app.palette.paper)
                .foregroundStyle(app.palette.ink)
        }
        .transition(.opacity)
    }
}

/// Port of AreaSheet.jsx — pick a location from the data-driven
/// hierarchy (`LocationHierarchy`, migration 112), with a real open-event
/// count per node (invite-only excluded, same universe as the feed) and a
/// genuine on/off toggle for location sharing. Choosing ANY location here
/// (including an empty US root) only ever sets `app.area` — it never
/// requests location permission; only the explicit toggle below does.
///
/// This used to be `AreaSheetView`, a hand-rolled glass panel anchored to the
/// header control with its own scale/opacity reveal, its own outside-tap
/// scrim and its own placement math (`AreaMenuPlacement`). It is now an
/// ordinary native `Menu`, mounted inline on Home's header control — the same
/// mechanism the chat composer's "+" attachment button uses — so its
/// open/close animation, Liquid Glass appearance, anchoring and outside-tap
/// dismissal are the system's, identical on every OS version and correct
/// around screen edges, the safe areas, light/dark and Reduce Motion without
/// a single line of geometry code. See `AreaMenuOptions` below for the
/// content, and `LocationPickerSheet` for the searchable list.
struct AreaMenuOptions: View {
    @EnvironmentObject private var app: AppState
    /// Opens the searchable, scrollable location list. A native Menu has no
    /// room for a text field, so the one thing submenus genuinely can't do —
    /// jump straight to a leaf by typing — is offered as its own row instead
    /// of being dropped.
    var onSearch: () -> Void

    var body: some View {
        let rows: [AnyView] = [AnyView(allLocationsRow)]
            + menuRows(app.locationTree)
            + [AnyView(Divider()), AnyView(locationToggleRow), AnyView(searchRow)]
        ForEach(Array(rows.enumerated()), id: \.offset) { $0.element }
    }

    // MARK: Hierarchy -> nested submenus

    /// A country is always expandable (so an empty root can show its honest
    /// empty state); anything else only when it has children. Identical rule
    /// to `LocationPickerList`'s own `isExpandable`, so the menu and the
    /// searchable sheet can never disagree about which rows nest.
    private func isExpandable(_ n: LocationNode) -> Bool { n.kind == .country || !n.children.isEmpty }

    private func containsSelection(_ n: LocationNode) -> Bool {
        app.area != LocationHierarchy.allID && LocationHierarchy.matches(leafID: app.area, selection: n.id)
    }

    private func countLabel(_ n: Int) -> String { app.T("\(n) sự kiện", n == 1 ? "1 event" : "\(n) events") }

    /// Same identifier scheme the searchable list has always used, so an
    /// automation lookup written against it keeps resolving whether the row is
    /// reached through a submenu or through the search sheet.
    private func accessibilityID(_ nodeID: String) -> String {
        "area." + (LocationHierarchy.legacyKey(forNodeID: nodeID) ?? nodeID)
    }

    private func label(_ title: String, systemImage: String) -> Label<Text, Image> {
        Label(title, systemImage: systemImage)
    }

    private func optionLabel(_ title: String, count: Int, selected: Bool) -> Label<Text, Text> {
        // A native Menu item has no checkmark slot, so the selection is marked
        // in the row's own text. The selected node's own ancestors mark
        // themselves too (`containsSelection`), which is what makes the
        // selection visible at every level of the submenu path rather than
        // only once the user has drilled all the way down to it.
        Label {
            Text(selected ? "✓ " + title : title)
        } icon: {
            Text(countLabel(count))
        }
    }

    private func optionRow(id: String, title: String, count: Int) -> some View {
        let selected = app.area == id
        return Button { Haptics.selection(); app.pickArea(id) } label: {
            optionLabel(title, count: count, selected: selected)
        }
        .accessibilityIdentifier(accessibilityID(id))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var allLocationsRow: some View {
        Button { Haptics.selection(); app.pickArea(LocationHierarchy.allID) } label: {
            optionLabel(app.T("Tất cả khu vực", "All locations"),
                        count: app.locationTree.reduce(0) { $0 + $1.openCount },
                        selected: app.area == LocationHierarchy.allID)
        }
        .accessibilityIdentifier(accessibilityID(LocationHierarchy.allID))
        .accessibilityAddTraits(app.area == LocationHierarchy.allID ? .isSelected : [])
    }

    /// Built as data rather than as nested `@ViewBuilder` calls: a SwiftUI
    /// view builder cannot call itself (the opaque result type would recurse),
    /// so each level's rows are assembled into a plain `[AnyView]` and
    /// rendered by one flat `ForEach`. Every level is therefore the same
    /// concrete type, and an arbitrarily deep hierarchy compiles.
    private func menuRows(_ nodes: [LocationNode]) -> [AnyView] {
        var out: [AnyView] = []
        for n in nodes {
            let selectedHere = containsSelection(n)
            if isExpandable(n) {
                // A parent node is selected through its own "All in [X]" row,
                // exactly as in the searchable list — expanding never changes
                // what is selected.
                var children: [AnyView] = [AnyView(
                    optionRow(id: n.id,
                              title: app.T("Tất cả tại \(LocationHierarchy.label(n, T: app.T))",
                                           "All in \(LocationHierarchy.label(n, T: app.T))"),
                              count: n.openCount)
                )]
                if n.children.isEmpty {
                    children.append(AnyView(
                        Button { } label: {
                            Text(app.T("Chưa có sự kiện nào ở đây.", "No events here yet."))
                        }
                        .disabled(true)
                    ))
                } else {
                    children.append(contentsOf: menuRows(n.children))
                }
                out.append(AnyView(
                    Menu {
                        ForEach(Array(children.enumerated()), id: \.offset) { $0.element }
                    } label: {
                        // Submenus get the system's own disclosure indicator, so
                        // this label is title + count only.
                        Text(selectedHere ? "✓ " + LocationHierarchy.label(n, T: app.T) : LocationHierarchy.label(n, T: app.T))
                    }
                    .accessibilityIdentifier(accessibilityID(n.id))
                ))
            } else {
                out.append(AnyView(optionRow(id: n.id,
                                             title: LocationHierarchy.label(n, T: app.T),
                                             count: n.openCount)))
            }
        }
        return out
    }

    // MARK: The two actions that are not a location

    private var locationToggleRow: some View {
        Button {
            Haptics.selection()
            if app.located == true { app.denyLocation() } else { app.allowLocation() }
        } label: {
            label(app.located == true
                  ? app.T("Tắt vị trí ▪︎ đang hiển thị khoảng cách", "Turn off location ▪︎ showing distance")
                  : app.T("Dùng vị trí của tôi để xem khoảng cách", "Use my location to show distance"),
                  systemImage: app.located == true ? "location.slash" : "location")
        }
        .accessibilityIdentifier("area.locationToggle")
    }

    private var searchRow: some View {
        Button { Haptics.selection(); onSearch() } label: {
            label(app.T("Tìm khu vực…", "Search locations…"), systemImage: "magnifyingglass")
        }
        .accessibilityIdentifier("area.search")
    }
}

extension View {
    /// The floating Liquid Glass card used by Home's area picker (26pt
    /// corners, glass fill following `glassOpacity`, hairline stroke), shared
    /// so Map's picker looks identical.
    func glassPanel() -> some View { modifier(GlassPanelModifier()) }
}

private struct GlassPanelModifier: ViewModifier {
    @EnvironmentObject private var app: AppState

    func body(content: Content) -> some View {
        content
            .background {
                if #available(iOS 26.0, *) {
                    GlassEffectContainer {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(.clear)
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                            .opacity(app.glassOpacity)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(app.palette.paper.opacity(0.28 * app.glassOpacity))
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .opacity(app.glassOpacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(app.palette.rule.opacity(0.65), lineWidth: 1)
            }
    }
}

/// The hierarchical, searchable location list shared by Home's area sheet
/// and Map Explore's own location picker. Rows are flattened from the tree
/// so expand/collapse (keyed by stable node ID in `app.areaExpanded`) and
/// search visibility are plain data, never view identity tricks.
struct LocationPickerList: View {
    @EnvironmentObject var app: AppState
    let onPick: (String) -> Void
    @State private var query = ""

    private enum Row: Identifiable {
        case node(LocationNode, Int)
        case allIn(LocationNode, Int)
        case empty(String, Int)

        var id: String {
            switch self {
            case .node(let n, _): return "node:" + n.id
            case .allIn(let n, _): return "all:" + n.id
            case .empty(let parent, _): return "empty:" + parent
            }
        }
    }

    /// A country is always expandable (so an empty root can show its
    /// honest empty state); anything else only when it has children.
    private func isExpandable(_ n: LocationNode) -> Bool { n.kind == .country || !n.children.isEmpty }

    private func rows(_ nodes: [LocationNode], depth: Int, search: (visible: Set<String>, autoExpanded: Set<String>)?) -> [Row] {
        var out: [Row] = []
        for n in nodes {
            if let search, !search.visible.contains(n.id) { continue }
            out.append(.node(n, depth))
            guard isExpandable(n) else { continue }
            let expanded = app.areaExpanded.contains(n.id) || (search?.autoExpanded.contains(n.id) ?? false)
            guard expanded else { continue }
            out.append(.allIn(n, depth + 1))
            if n.children.isEmpty {
                out.append(.empty(n.id, depth + 1))
            } else {
                out.append(contentsOf: rows(n.children, depth: depth + 1, search: search))
            }
        }
        return out
    }

    private func countLabel(_ n: Int) -> String { app.T("\(n) sự kiện", n == 1 ? "1 event" : "\(n) events") }

    private func accessibilityID(_ nodeID: String) -> String {
        "area." + (LocationHierarchy.legacyKey(forNodeID: nodeID) ?? nodeID)
    }

    var body: some View {
        let roots = app.locationTree
        let search = LocationHierarchy.search(roots, query: query, T: app.T)
        let list = rows(roots, depth: 0, search: search)
        let totalOpen = roots.reduce(0) { $0 + $1.openCount }
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 13)).opacity(0.55)
                TextField(app.T("Tìm tỉnh, thành phố, khu vực…", "Search state, city, area…"), text: $query)
                    .font(.system(size: 14))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("area.search")
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 13)).opacity(0.45)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("area.searchClear")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.top, 12)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if search == nil {
                        selectRow(id: LocationHierarchy.allID, title: app.T("Tất cả khu vực", "All locations"), count: totalOpen, depth: 0)
                    }
                    ForEach(list) { row in
                        switch row {
                        case .node(let n, let depth):
                            if isExpandable(n) {
                                expandRow(n, depth: depth)
                            } else {
                                selectRow(id: n.id, title: LocationHierarchy.label(n, T: app.T), count: n.openCount, depth: depth, legacy: n.kind == .legacyArea)
                            }
                        case .allIn(let n, let depth):
                            selectRow(id: n.id, title: app.T("Tất cả tại \(LocationHierarchy.label(n, T: app.T))", "All in \(LocationHierarchy.label(n, T: app.T))"), count: n.openCount, depth: depth)
                        case .empty(_, let depth):
                            Text(app.T("Chưa có sự kiện nào ở đây.", "No events here yet."))
                                .font(.system(size: 12.5))
                                .opacity(0.6)
                                .padding(.leading, CGFloat(depth) * 16)
                                .padding(.vertical, 11)
                        }
                    }
                    if search != nil && list.isEmpty {
                        Text(app.T("Không tìm thấy khu vực phù hợp.", "No matching location."))
                            .font(.system(size: 12.5))
                            .opacity(0.6)
                            .padding(.vertical, 13)
                    }
                }
            }
            .frame(maxHeight: 380)
            .padding(.top, 6)
        }
        .onAppear {
            // Reveal (never change) the current selection.
            app.areaExpanded.formUnion(LocationHierarchy.ancestorIDs(of: app.area))
        }
    }

    /// A parent node: tapping only expands/collapses — selection lives on
    /// its own "All in [X]" row (and on its children), so expanding never
    /// changes what's selected. A dot marks a selection hidden inside.
    private func expandRow(_ n: LocationNode, depth: Int) -> some View {
        let expanded = app.areaExpanded.contains(n.id)
        let containsSelection = app.area != LocationHierarchy.allID && LocationHierarchy.matches(leafID: app.area, selection: n.id)
        return Button {
            if expanded { app.areaExpanded.remove(n.id) } else { app.areaExpanded.insert(n.id) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .opacity(0.6)
                    .frame(width: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocationHierarchy.label(n, T: app.T))
                        .font(.system(size: 14.5, weight: containsSelection ? .semibold : .regular))
                    if n.kind == .legacyArea { legacyCaption }
                }
                if containsSelection { Circle().frame(width: 5, height: 5) }
                Spacer()
                Text(countLabel(n.openCount)).font(.system(size: 11))
            }
            .padding(.leading, CGFloat(depth) * 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("area.toggle.\(n.id)")
        .overlay(alignment: .bottom) { Divider().overlay(app.palette.rule) }
    }

    private func selectRow(id: String, title: String, count: Int, depth: Int, legacy: Bool = false) -> some View {
        let selected = app.area == id
        return Button { onPick(id) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Color.clear.frame(width: 12, height: 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14.5, weight: selected ? .semibold : .regular))
                    if legacy { legacyCaption }
                }
                Spacer()
                Text(countLabel(count)).font(.system(size: 11))
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .opacity(selected ? 1 : 0)
                    .accessibilityHidden(!selected)
            }
            .padding(.leading, CGFloat(depth) * 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID(id))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .overlay(alignment: .bottom) { Divider().overlay(app.palette.rule) }
    }

    /// `events.area` values are free-text "familiar" names (many are
    /// pre-2025 district names) — labelled as such, never presented as a
    /// current official administrative unit.
    private var legacyCaption: some View {
        Text(app.T("Tên khu vực quen gọi", "Familiar area name"))
            .font(.system(size: 10.5))
            .opacity(0.55)
    }
}

/// The searchable, scrollable location list, as a sheet. Used by Map
/// Explore's own picker (drawn inside the map's list sheet, which the root
/// area overlay would sit behind) and by Home's area menu's "Search
/// locations…" row — a native `Menu` can't host a text field, so this is where
/// typing a place name still works. Both entry points share the same
/// `app.area` selection, and neither requests location permission on its own
/// (only the explicit toggle below does).
struct LocationPickerSheet: View {
    @EnvironmentObject private var app: AppState
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(app.T("Khu vực", "Location")).font(.system(size: 11.5, weight: .semibold))
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(app.palette.ink.opacity(0.6))
                        .padding(4)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("map.area.close")
            }
            LocationPickerList { id in
                app.area = LocationHierarchy.migrateSelection(id)
                isPresented = false
            }

            // Same location on/off toggle as Home's area picker.
            Button(app.located == true
                   ? app.T("Tắt vị trí ▪︎ đang hiển thị khoảng cách", "Turn off location ▪︎ showing distance")
                   : app.T("Dùng vị trí của tôi để xem khoảng cách", "Use my location to show distance")) {
                if app.located == true { app.denyLocation() } else { app.allowLocation() }
            }
            .font(.system(size: 13))
            .frame(maxWidth: .infinity)
            .padding(8)
            .padding(.top, 8)
            .buttonStyle(.plain)
            .accessibilityIdentifier("map.area.locationToggle")
        }
        // Same floating glass card as the map's picker, inset from the sheet
        // edges over a clear sheet background.
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 16)
        .frame(maxWidth: 560, maxHeight: .infinity, alignment: .topLeading)
        .glassPanel()
        .padding(.horizontal, 16)
        // Keep the whole card (incl. the location toggle) above the floating
        // dock, which overlays the bottom of this sheet.
        .padding(.top, 4)
        .padding(.bottom, BottomTabBar.barHeight + 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background {
            // Dim only the list sheet underneath; tap outside to close.
            Color.black.opacity(0.32)
                .contentShape(Rectangle())
                .onTapGesture { isPresented = false }
        }
        .foregroundStyle(app.palette.ink)
    }
}

/// Port of LocationSheet.jsx — the permission explainer, only shown when
/// someone actually reaches for a distance.
struct LocationSheetView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        BottomSheet(onDismiss: { app.denyLocation() }) {
            Text("Vị trí").font(.system(size: 11.5))
            Text("Cho banbe biết bạn đang ở đâu?")
                .font(BanbeTheme.display(23))
                .padding(.top, 8)
            Text("Chỉ để hiện khoảng cách tới mỗi sự kiện. Không lưu, không chia sẻ với người tổ chức.")
                .font(.system(size: 13.5))
                .lineSpacing(3)
                .padding(.top, 12)
            InkButton(title: "Dùng vị trí của tôi") { app.allowLocation() }
                .padding(.top, 22)
            Button("Để sau") { app.denyLocation() }
                .font(.system(size: 13.5))
                .frame(maxWidth: .infinity)
                .padding(8)
                .padding(.top, 10)
                .buttonStyle(.plain)
        }
    }
}

/// Port of ReasonSheet.jsx — an organizer reversing a check-in, cancelling a
/// paid booking, or rejecting a still-pending one must pick one of a fixed
/// list of reasons (no free text), so the guest's notification always says
/// something concrete. `.confirmCheckin` (14-organizer-checkin.md, Bug 3)
/// has no reason list at all — a plain yes/no before marking a guest
/// arrived.
struct ReasonSheetView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        if let prompt = app.reasonPrompt {
            if prompt.kind == .confirmCheckin {
                BottomSheet(onDismiss: { if !app.reasonPromptBusy { app.closeReasonPrompt() } }) {
                    Text(app.T("Xác nhận điểm danh", "Confirm check-in"))
                        .font(.system(size: 11.5, weight: .semibold))
                    Text(prompt.guestName.isEmpty
                         ? app.T("Bạn có chắc muốn xác nhận khách này đã tới?", "Are you sure this guest has arrived?")
                         : app.T("Bạn có chắc muốn xác nhận \(prompt.guestName) đã tới?", "Are you sure \(prompt.guestName) has arrived?"))
                        .font(.system(size: 13))
                        .lineSpacing(3)
                        .padding(.top, 8)
                    HStack(spacing: 8) {
                        Button(app.T("Xác nhận", "Confirm")) { Task { await app.confirmCheckIn() } }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(app.palette.paper)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .buttonStyle(.plain)
                        Button(app.T("Để sau", "Not now")) { app.closeReasonPrompt() }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(app.palette.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(app.palette.rule))
                            .buttonStyle(.plain)
                    }
                    .padding(.top, 16)
                }
            } else {
                let reasons: [ReasonOption] = prompt.kind == .undoCheckin ? ReasonOption.undoCheckin
                    : prompt.kind == .rejectGuest ? ReasonOption.rejectGuest
                    : ReasonOption.cancelBooking
                let title = prompt.kind == .undoCheckin ? app.T("Huỷ điểm danh", "Undo check-in")
                    : prompt.kind == .rejectGuest ? app.T("Từ chối yêu cầu đặt chỗ", "Reject this request")
                    : app.T("Huỷ vé", "Cancel booking")

                BottomSheet(onDismiss: { if !app.reasonPromptBusy { app.closeReasonPrompt() } }) {
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                    if !prompt.guestName.isEmpty {
                        Text(prompt.kind == .undoCheckin
                             ? app.T("Vì sao bạn muốn chuyển \(prompt.guestName) về \"Chưa đến\"?",
                                     "Why move \(prompt.guestName) back to \"Not yet\"?")
                             : prompt.kind == .rejectGuest
                             ? app.T("Vì sao bạn không nhận yêu cầu của \(prompt.guestName)?",
                                     "Why reject \(prompt.guestName)'s request?")
                             : app.T("Vì sao bạn muốn huỷ vé của \(prompt.guestName)?",
                                     "Why cancel \(prompt.guestName)'s booking?"))
                            .font(.system(size: 13))
                            .lineSpacing(3)
                            .padding(.top, 8)
                    }
                    Text(prompt.kind == .rejectGuest
                         ? app.T("Chỗ sẽ được mở lại ngay và khách sẽ được báo trong ứng dụng.",
                                 "The seat is returned to the pool immediately and the guest is notified in the app.")
                         : app.T("Khách sẽ được báo qua email và trong ứng dụng.",
                                 "The guest will be notified by email and in the app."))
                        .font(.system(size: 12))
                        .foregroundStyle(app.palette.ink.opacity(0.7))
                        .padding(.top, 6)

                    VStack(spacing: 0) {
                        ForEach(reasons) { reason in
                            Button {
                                guard !app.reasonPromptBusy else { return }
                                Task { await app.submitReason(app.T(reason.vi, reason.en)) }
                            } label: {
                                Text(app.T(reason.vi, reason.en))
                                    .font(.system(size: 14.5))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 13)
                                    .opacity(app.reasonPromptBusy ? 0.5 : 1)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider().overlay(app.palette.rule)
                        }
                    }
                    .padding(.top, 14)

                    if !app.reasonPromptError.isEmpty {
                        Text(app.reasonPromptError)
                            .font(.system(size: 12))
                            .foregroundStyle(BanbeTheme.alert)
                            .padding(.top, 12)
                    }

                    Button(app.reasonPromptBusy ? app.T("Đang xử lý…", "Working…") : app.T("Để sau", "Not now")) {
                        if !app.reasonPromptBusy { app.closeReasonPrompt() }
                    }
                    .font(.system(size: 13.5))
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .padding(.top, 14)
                    .buttonStyle(.plain)
                }
            }
        }
    }
}


/// System sheet styled like the profile "Share card" sheet (inline centred title, paper
/// background, grabber) but with an "X" on the trailing side instead of a Close/Cancel button.
struct CardSheet<Content: View>: View {
    @EnvironmentObject var app: AppState
    let title: String
    var closeID: String = "cardSheet.close"
    let onClose: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationStack {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(20)
                .foregroundStyle(app.palette.ink)
            .background(app.palette.paper.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if #available(iOS 26.0, *) {
                        // The system close button: the glass "X" iOS 26+ draws on its own sheets
                        // (same as the screenshot-markup close).
                        Button(role: .close, action: onClose)
                            .accessibilityIdentifier(closeID)
                    } else {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(app.palette.ink)
                                .frame(width: 30, height: 30)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .accessibilityLabel(app.T("Đóng", "Close"))
                        .accessibilityIdentifier(closeID)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
