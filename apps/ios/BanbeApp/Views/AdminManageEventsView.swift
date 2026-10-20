import SwiftUI

/// Admin > Manage events (migrations 188 + 189, note 54). Every event, any status: search, a status filter, select one
/// or many, then
/// - Remove (reason required): hides it everywhere; bookings, payments, refunds and history are kept; host notified.
///   Refused while money is still in play (active bookings, unsettled refunds, open disputes) — the row says why.
/// - Restore: back to the status it had.
/// - Delete permanently (reason required): only removed events that never had a booking.
/// - TESTING-PHASE: Wipe (no reason) erases any event and everything tied to it, only while the admin switch
///   "Test event wipe" is on. Remove before public release.
/// The server enforces every rule; this screen explains them before anyone taps. Web twin: AdminManageEvents.jsx.
struct AdminManageEventsView: View {
    @EnvironmentObject private var app: AppState

    @State private var rows: [AdminEventRow] = []
    @State private var checks: [String: AdminEventCheck] = [:]
    @State private var filter: String? = nil
    @State private var search = ""
    @State private var selected: Set<String> = []
    @State private var loading = false
    @State private var busy = false
    @State private var loadError = ""
    @State private var banner: String?
    @State private var reasonAction: AdminEventAction?
    @State private var reason = ""
    @State private var confirmRestore = false
    @State private var confirmWipe = false     // TESTING-PHASE
    @FocusState private var searchFocused: Bool

    private static let filters: [(key: String?, vi: String, en: String)] = [
        (nil, "Tất cả", "All"), ("live", "Đang mở", "Live"), ("review", "Chờ duyệt", "In review"),
        ("draft", "Nháp", "Draft"), ("ended", "Đã kết thúc", "Ended"), ("cancelled", "Đã huỷ", "Cancelled"),
        ("removed", "Đã gỡ", "Removed"),
    ]

    /// TESTING-PHASE: shown only while the admin switch is explicitly on.
    private var wipeEnabled: Bool { FeatureFlags.isOn(app.featureFlags, "admin_event_wipe") }

    private var selectedRows: [AdminEventRow] { rows.filter { selected.contains($0.id) } }
    private var removeIDs: [String] {
        selectedRows.filter { $0.status != "removed" && checks[$0.id]?.isBlocked != true }.map(\.id)
    }
    private var blockedSelected: Int { selectedRows.filter { $0.status != "removed" && checks[$0.id]?.isBlocked == true }.count }
    private var restoreIDs: [String] { selectedRows.filter { $0.status == "removed" }.map(\.id) }
    private var purgeIDs: [String] { selectedRows.filter { $0.status == "removed" && checks[$0.id]?.purgeable == true }.map(\.id) }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.T("Duyệt & Kiểm Duyệt", "Review & Moderation")) { app.screen = .accountGroup }
                    .padding(.top, 8)
                    .accessibilityIdentifier("adminManage.back")
                Text(app.T("Quản lý sự kiện", "Manage events"))
                    .font(BanbeTheme.display(24)).padding(.top, 14)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("adminManage.title")
                Text(app.T("Gỡ một hay nhiều sự kiện khỏi ứng dụng. Đặt chỗ, thanh toán, hoàn tiền và lịch sử luôn được giữ lại.",
                           "Take one or more events off the app. Bookings, payments, refunds and history are always kept."))
                    .font(.system(size: 13.5)).foregroundStyle(app.palette.ink.opacity(0.75)).padding(.top, 8)

                searchField.padding(.top, 18)
                filterChips.padding(.top, 12)

                if let banner {
                    Text(banner)
                        .font(.system(size: 13, weight: .semibold))
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.top, 12)
                        .accessibilityIdentifier("adminManage.banner")
                }

                listBody.padding(.top, 14)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, selected.isEmpty ? 40 : 190)
        }
        .overlay(alignment: .bottom) { if !selected.isEmpty { actionBar } }
        .task(id: "\(filter ?? "all")|\(search)") {
            // A short pause so typing in the search box doesn't reload on every keystroke.
            try? await Task.sleep(nanoseconds: search.isEmpty ? 0 : 300_000_000)
            guard !Task.isCancelled else { return }
            await reload()
        }
        .sheet(item: Binding(get: { reasonAction.map(ReasonRequest.init) }, set: { if $0 == nil { reasonAction = nil } })) { req in
            reasonSheet(req.action)
        }
        .confirmationDialog(app.T("Khôi phục \(restoreIDs.count) sự kiện?", "Restore \(Self.en(restoreIDs.count, "event"))?"),
                            isPresented: $confirmRestore, titleVisibility: .visible) {
            Button(app.T("Khôi phục", "Restore")) { Task { await run(.restore, ids: restoreIDs) } }
            Button(app.T("Huỷ", "Cancel"), role: .cancel) {}
        } message: {
            Text(app.T("Sự kiện quay về trạng thái trước khi bị gỡ và người tổ chức được báo.",
                       "They go back to the status they had before, and the host is told."))
        }
        // TESTING-PHASE (remove before public release).
        .confirmationDialog(app.T("Xoá vĩnh viễn \(selected.count) sự kiện? (thử nghiệm)", "Permanently wipe \(Self.en(selected.count, "event"))? (testing)"),
                            isPresented: $confirmWipe, titleVisibility: .visible) {
            Button(app.T("Xoá vĩnh viễn", "Wipe permanently"), role: .destructive) {
                Task { await run(.wipeTesting, ids: Array(selected)) }
            }
            Button(app.T("Huỷ", "Cancel"), role: .cancel) {}
        } message: {
            Text(app.T("Xoá sự kiện cùng mọi đặt chỗ, thanh toán, hoàn tiền, tin nhắn và tranh chấp của nó. Chỉ dùng cho dữ liệu thử nghiệm. Không thể hoàn tác.",
                       "Deletes the events with all their bookings, payments, refunds, chats and disputes. For test data only. This can't be undone."))
        }
    }

    // MARK: pieces

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 14)).opacity(0.55).accessibilityHidden(true)
            TextField(app.T("Tìm theo tên sự kiện", "Search by event name"), text: $search)
                .font(.system(size: 15))
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .accessibilityIdentifier("adminManage.search")
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill").opacity(0.45) }
                    .buttonStyle(.plain).accessibilityLabel(app.T("Xoá", "Clear"))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .fieldChrome(focused: searchFocused, cornerRadius: 14, bordered: false)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.filters, id: \.en) { f in
                    ChoiceChip(title: app.T(f.vi, f.en), selected: filter == f.key, compact: true,
                               identifier: "adminManage.filter.\(f.key ?? "all")") {
                        filter = f.key
                        selected = []
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var listBody: some View {
        if loading && rows.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
        } else if !loadError.isEmpty {
            Text(loadError).font(.system(size: 13)).foregroundStyle(BanbeTheme.alert)
                .accessibilityIdentifier("adminManage.error")
        } else if rows.isEmpty {
            Text(app.T("Không có sự kiện nào.", "No events here."))
                .font(.system(size: 14)).opacity(0.7).padding(.top, 20)
        } else {
            HStack {
                Text(app.T("\(rows.count) sự kiện", Self.en(rows.count, "event"))).font(.system(size: 12.5, weight: .semibold)).opacity(0.7)
                Spacer()
                Button(selected.count == rows.count ? app.T("Bỏ chọn tất cả", "Deselect all") : app.T("Chọn tất cả", "Select all")) {
                    selected = selected.count == rows.count ? [] : Set(rows.map(\.id))
                }
                .font(.system(size: 13, weight: .semibold))
                .buttonStyle(.plain)
                .accessibilityIdentifier("adminManage.selectAll")
            }
            .padding(.bottom, 8)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    if i > 0 { Divider().overlay(app.palette.rule) }
                    eventRow(row)
                }
            }
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func eventRow(_ row: AdminEventRow) -> some View {
        let isOn = selected.contains(row.id)
        let check = checks[row.id]
        return Button {
            if isOn { selected.remove(row.id) } else { selected.insert(row.id) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isOn ? app.palette.ink : app.palette.ink.opacity(0.3))
                    .padding(.top, 1)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.name).font(.system(size: 15, weight: .semibold)).multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        Text(statusLabel(row.status))
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(row.status == "removed" ? BanbeTheme.alert.opacity(0.14) : app.palette.ink.opacity(0.08), in: Capsule())
                            .foregroundStyle(row.status == "removed" ? BanbeTheme.alert : app.palette.ink)
                        Text([row.startsAt.map(Self.dateLabel), row.organizerName].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 12)).opacity(0.7).lineLimit(1)
                    }
                    if row.status == "removed" {
                        Text(app.T("Lý do: ", "Reason: ") + (row.removalReason ?? ""))
                            .font(.system(size: 12)).opacity(0.75).lineLimit(2)
                        if check?.purgeable == true {
                            Text(app.T("Chưa từng có đặt chỗ — có thể xoá vĩnh viễn.", "Never booked — can be deleted permanently."))
                                .font(.system(size: 11.5, weight: .semibold)).opacity(0.7)
                        }
                    } else if let check, check.isBlocked {
                        Text(blockerLine(check))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(app.palette.honey)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("adminManage.blocked.\(row.id)")
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .accessibilityIdentifier("adminManage.row.\(row.id)")
    }

    private var actionBar: some View {
        VStack(spacing: 8) {
            Text(app.T("Đã chọn \(selected.count)", "\(selected.count) selected") + (blockedSelected > 0
                 ? app.T(" · \(blockedSelected) chưa gỡ được", " · \(blockedSelected) can't be removed yet") : ""))
                .font(.system(size: 12.5, weight: .semibold)).opacity(0.75)
            HStack(spacing: 8) {
                if !removeIDs.isEmpty {
                    actionButton(app.T("Gỡ (\(removeIDs.count))", "Remove (\(removeIDs.count))"), id: "remove", destructive: true) {
                        reason = ""; reasonAction = .remove
                    }
                }
                if !restoreIDs.isEmpty {
                    actionButton(app.T("Khôi phục (\(restoreIDs.count))", "Restore (\(restoreIDs.count))"), id: "restore") { confirmRestore = true }
                }
                if !purgeIDs.isEmpty {
                    actionButton(app.T("Xoá hẳn (\(purgeIDs.count))", "Delete (\(purgeIDs.count))"), id: "purge", destructive: true) {
                        reason = ""; reasonAction = .purge
                    }
                }
            }
            // TESTING-PHASE (remove before public release): iOS only, only while the admin switch is on.
            if wipeEnabled {
                Button { confirmWipe = true } label: {
                    Label(app.T("Xoá vĩnh viễn — thử nghiệm (\(selected.count))", "Wipe permanently — testing (\(selected.count))"),
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13.5, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(BanbeTheme.alert)
                        .overlay(Capsule().stroke(BanbeTheme.alert, lineWidth: 1.2))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(busy)
                .accessibilityIdentifier("adminManage.action.wipe")
            }
            Button(app.T("Bỏ chọn", "Clear selection")) { selected = [] }
                .font(.system(size: 13, weight: .semibold)).buttonStyle(.plain).frame(minHeight: 32)
        }
        .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .nativeGlassPanel(cornerRadius: 24)
        .padding(.horizontal, 12).padding(.bottom, 8)
    }

    private func actionButton(_ title: String, id: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14.5, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(destructive ? BanbeTheme.onAlert : app.palette.paper)
                .background(destructive ? BanbeTheme.alert : app.palette.ink, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(busy)
        .accessibilityIdentifier("adminManage.action.\(id)")
    }

    private struct ReasonRequest: Identifiable { let action: AdminEventAction; var id: String { action.rawValue } }

    private func reasonSheet(_ action: AdminEventAction) -> some View {
        let isPurge = action == .purge
        let count = isPurge ? purgeIDs.count : removeIDs.count
        let quick = [app.T("Spam", "Spam"), app.T("Trùng lặp", "Duplicate"),
                     app.T("Vi phạm quy định cộng đồng", "Breaks community guidelines"), app.T("Sự kiện thử nghiệm", "Test event")]
        return VStack(alignment: .leading, spacing: 14) {
            Text(isPurge ? app.T("Xoá vĩnh viễn \(count) sự kiện", "Permanently delete \(Self.en(count, "event"))")
                         : app.T("Gỡ \(count) sự kiện", "Remove \(Self.en(count, "event"))"))
                .font(BanbeTheme.display(22))
            Text(isPurge
                 ? app.T("Chỉ áp dụng cho sự kiện đã gỡ và chưa từng có đặt chỗ. Không thể hoàn tác. Hành động được ghi lại.",
                         "Only for removed events that never had a booking. This can't be undone. It's logged.")
                 : app.T("Sự kiện biến mất khỏi Trang chủ, Bản đồ, Tìm kiếm và trang host. Mọi đặt chỗ, thanh toán và lịch sử được giữ. Người tổ chức nhận lý do bên dưới.",
                         "They disappear from Home, Map, Search and host pages. All bookings, payments and history are kept. The host is sent the reason below."))
                .font(.system(size: 13.5)).opacity(0.8)
            FlowRow(spacing: 8) {
                ForEach(quick, id: \.self) { q in
                    ChoiceChip(title: q, selected: reason == q, compact: true) { reason = q }
                }
            }
            TextField(app.T("Lý do (bắt buộc)", "Reason (required)"), text: $reason, axis: .vertical)
                .lineLimit(2...5)
                .roundedFormField(app: app, focused: false)
                .accessibilityIdentifier("adminManage.reason")
            HStack(spacing: 10) {
                SecondaryButton(title: app.T("Huỷ", "Cancel")) { reasonAction = nil }
                InkButton(title: isPurge ? app.T("Xoá vĩnh viễn", "Delete permanently") : app.T("Gỡ sự kiện", "Remove"),
                          enabled: reason.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 && !busy,
                          cornerRadius: 18) {
                    let ids = isPurge ? purgeIDs : removeIDs
                    let why = reason
                    reasonAction = nil
                    Task { await run(action, ids: ids, reason: why) }
                }
                .accessibilityIdentifier("adminManage.reason.confirm")
            }
        }
        .padding(22)
        .presentationDetents([.medium, .large])
        .environmentObject(app)
    }

    // MARK: behaviour

    private func reload() async {
        loading = true
        defer { loading = false }
        do {
            let list = try await app.loadAdminManagedEvents(status: filter, search: search)
            rows = list
            loadError = ""
            selected = selected.intersection(Set(list.map(\.id)))
            checks = await app.adminEventChecks(list.map(\.id))
        } catch {
            rows = []
            loadError = RewardsLogic.isFunctionMissing(error) || "\(error)".contains("removal_reason")
                ? app.T("Máy chủ chưa có tính năng này (chạy migration 188–189).", "The server doesn't have this yet (apply migrations 188–189).")
                : app.T("Không tải được danh sách. Thử lại nhé.", "Couldn't load events. Try again.")
        }
    }

    private func run(_ action: AdminEventAction, ids: [String], reason: String = "") async {
        busy = true
        defer { busy = false }
        let outcome = await app.runAdminEventAction(action, ids: ids, reason: reason)
        if let error = outcome.error {
            banner = errorMessage(error)
        } else {
            Haptics.success()
            banner = summary(action, outcome)
            selected = []
        }
        await reload()
    }

    private func summary(_ action: AdminEventAction, _ o: AdminEventActionOutcome) -> String {
        let done: String
        switch action {
        case .remove: done = app.T("Đã gỡ \(o.done) sự kiện.", "Removed \(Self.en(o.done, "event")).")
        case .restore: done = app.T("Đã khôi phục \(o.done) sự kiện.", "Restored \(Self.en(o.done, "event")).")
        case .purge: done = app.T("Đã xoá vĩnh viễn \(o.done) sự kiện.", "Permanently deleted \(Self.en(o.done, "event")).")
        case .wipeTesting: done = app.T("Đã xoá sạch \(o.done) sự kiện (thử nghiệm).", "Wiped \(Self.en(o.done, "event")) (testing).")
        }
        guard !o.skipped.isEmpty else { return done }
        let why = Dictionary(grouping: o.skipped, by: { $0.error ?? "" }).map { "\($0.value.count) \(skipReason($0.key))" }
            .sorted().joined(separator: ", ")
        return done + " " + app.T("Bỏ qua: ", "Skipped: ") + why + "."
    }

    private func skipReason(_ code: String) -> String {
        switch code {
        case "HAS_OPEN_OBLIGATIONS": return app.T("còn đặt chỗ/hoàn tiền/tranh chấp", "still have bookings, refunds or disputes")
        case "ALREADY_REMOVED": return app.T("đã gỡ trước đó", "already removed")
        case "NOT_REMOVED": return app.T("chưa bị gỡ", "not removed")
        case "HAS_BOOKING_HISTORY": return app.T("đã từng có đặt chỗ", "had bookings")
        case "NOT_FOUND": return app.T("không còn tồn tại", "no longer exist")
        default: return code
        }
    }

    private func errorMessage(_ code: String) -> String {
        switch code {
        case "NOT_AUTHORIZED": return app.T("Bạn không có quyền.", "You are not allowed to do this.")
        case "REASON_REQUIRED": return app.T("Hãy nhập lý do (ít nhất 3 ký tự).", "Please give a reason (at least 3 characters).")
        case "NOT_ENABLED": return app.T("Bật \"Xoá sự kiện thử nghiệm\" trong Công tắc tính năng trước.", "Turn on \"Test event wipe\" in Feature switches first.")
        case "NOT_DEPLOYED": return app.T("Máy chủ chưa có tính năng này (chạy migration 188–189).", "The server doesn't have this yet (apply migrations 188–189).")
        case "INVALID_VALUE": return app.T("Chọn tối đa 100 sự kiện mỗi lần.", "Pick at most 100 events at a time.")
        default: return app.T("Không kết nối được. Thử lại nhé.", "Couldn't reach the server. Try again.")
        }
    }

    private func blockerLine(_ c: AdminEventCheck) -> String {
        var parts: [String] = []
        if c.activeBookings > 0 { parts.append(app.T("\(c.activeBookings) đặt chỗ đang hiệu lực", Self.en(c.activeBookings, "active booking"))) }
        if c.unsettledRefunds > 0 { parts.append(app.T("\(c.unsettledRefunds) khoản hoàn tiền chưa xong", Self.en(c.unsettledRefunds, "refund") + " not settled")) }
        if c.openDisputes > 0 { parts.append(app.T("\(c.openDisputes) tranh chấp đang mở", Self.en(c.openDisputes, "open dispute"))) }
        return parts.joined(separator: " · ") + app.T(" — người tổ chức cần huỷ và hoàn tiền trước.", " — the host must cancel and refund first.")
    }

    private func statusLabel(_ s: String) -> String {
        switch s {
        case "live": return app.T("Đang mở", "Live")
        case "review": return app.T("Chờ duyệt", "In review")
        case "draft": return app.T("Nháp", "Draft")
        case "ended": return app.T("Đã kết thúc", "Ended")
        case "cancelled": return app.T("Đã huỷ", "Cancelled")
        case "removed": return app.T("Đã gỡ", "Removed")
        default: return s
        }
    }

    /// English count + noun ("1 event", "3 events"). Vietnamese has no plural form.
    static func en(_ n: Int, _ noun: String) -> String { n == 1 ? "\(n) \(noun)" : "\(n) \(noun)s" }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"
        f.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")
        return f
    }()
    private static func dateLabel(_ d: Date) -> String { dateFormatter.string(from: d) }
}
