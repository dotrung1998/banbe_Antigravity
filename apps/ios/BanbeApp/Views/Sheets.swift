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
struct AreaSheetView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        BottomSheet(onDismiss: { app.areaAsking = false }) {
            HStack {
                Text("Khu vực").font(.system(size: 11.5, weight: .semibold))
                Spacer()
                Button { app.areaAsking = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(app.palette.ink.opacity(0.6))
                        .padding(4)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("area.close")
            }
            LocationPickerList { app.pickArea($0) }

            Button(app.located == true
                   ? "Tắt vị trí ▪︎ đang hiển thị khoảng cách"
                   : "Dùng vị trí của tôi để xem khoảng cách") {
                if app.located == true { app.denyLocation() } else { app.allowLocation() }
            }
            .font(.system(size: 13))
            .frame(maxWidth: .infinity)
            .padding(8)
            .padding(.top, 14)
            .buttonStyle(.plain)
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

/// Map Explore's own copy of the picker, presented as a nested `.sheet`
/// from inside the map's list sheet (RootView's `AreaSheetView` overlay
/// would sit BEHIND that system sheet). Same shared `app.area` selection
/// as Home; no location-permission control here at all.
struct MapLocationPickerSheet: View {
    @EnvironmentObject var app: AppState
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
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(app.palette.paper)
        .foregroundStyle(app.palette.ink)
        .presentationDetents([.large])
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
