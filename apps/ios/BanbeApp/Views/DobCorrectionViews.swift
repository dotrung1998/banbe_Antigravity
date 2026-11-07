import SwiftUI
import Supabase

/// Birthday corrections (migration 175) — the iOS counterpart of
/// src/screens/DobCorrectionRequest.jsx and src/screens/AdminDobCorrections.jsx.
/// The profile birthday is never edited in the app: the owner files a request,
/// a platform admin reviews it and applies it (server-side, admin-only RPCs).

private let dobISO: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.calendar = Calendar(identifier: .gregorian)
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

private func shortDate(_ iso: String?) -> String {
    guard let iso, let d = dobISO.date(from: iso) else { return "—" }
    return d.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year())
}

private struct RPCResult: Decodable { let success: Bool?; let error: String? }

/// Shown under the profile birthday on Reserve (ticket 1).
struct DobCorrectionRequestView: View {
    @EnvironmentObject private var app: AppState

    private struct Mine: Decodable {
        let status: String?
        let requestedDob: String?
        let decisionNote: String?
        enum CodingKeys: String, CodingKey { case status, requestedDob = "requested_dob", decisionNote = "decision_note" }
    }
    private struct Params: Encodable {
        let dob: String, reason: String
        enum CodingKeys: String, CodingKey { case dob = "p_dob", reason = "p_reason" }
    }

    @State private var mine: Mine?
    @State private var open = false
    @State private var dob = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    @State private var reason = ""
    @State private var busy = false
    @State private var errorMsg = ""

    private func errorText(_ code: String?) -> String {
        switch code {
        case "INVALID_DOB": return app.T("Ngày sinh không hợp lệ.", "That date of birth isn’t valid.")
        case "INVALID_REASON": return app.T("Hãy nêu lý do (ít nhất 5 ký tự).", "Please give a reason (at least 5 characters).")
        case "SAME_DOB": return app.T("Ngày này giống ngày hiện tại.", "That is the same as the current date.")
        case "ALREADY_PENDING": return app.T("Bạn đã có một yêu cầu đang chờ.", "You already have a request waiting.")
        case "NO_DOB_ON_FILE": return app.T("Hồ sơ chưa có ngày sinh.", "There is no birthday on your profile.")
        default: return app.T("Không gửi được. Thử lại.", "Couldn’t send that. Try again.")
        }
    }

    private func load() async {
        mine = try? await SupabaseService.client.rpc("get_my_dob_correction").execute().value
    }

    private func submit() async {
        busy = true; errorMsg = ""
        defer { busy = false }
        do {
            let r: RPCResult = try await SupabaseService.client
                .rpc("request_dob_correction", params: Params(dob: dobISO.string(from: dob), reason: reason)).execute().value
            guard r.success == true else { errorMsg = errorText(r.error); return }
            open = false; reason = ""
            await load()
        } catch { errorMsg = errorText(nil) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if mine?.status == "pending" {
                Text(app.T("Yêu cầu sửa thành \(shortDate(mine?.requestedDob)) đang chờ quản trị viên xem xét.",
                           "Your request to change it to \(shortDate(mine?.requestedDob)) is waiting for an admin."))
                    .font(.system(size: 11.5)).opacity(0.75)
                    .accessibilityIdentifier("dobCorrection.pending")
            } else {
                if mine?.status == "rejected" {
                    Text(app.T("Yêu cầu sửa trước đó đã bị từ chối", "Your last correction request was declined")
                         + ((mine?.decisionNote ?? "").isEmpty ? "." : ": \(mine?.decisionNote ?? "")"))
                        .font(.system(size: 11.5)).opacity(0.75)
                }
                if !open {
                    Button(app.T("Sai ngày sinh? Yêu cầu sửa", "Wrong? Request a correction")) { open = true }
                        .font(.system(size: 11.5, weight: .semibold)).underline().buttonStyle(.plain)
                        .accessibilityIdentifier("dobCorrection.open")
                } else {
                    HStack {
                        Text(app.T("Ngày sinh đúng", "Correct date of birth")).font(.system(size: 12.5))
                        Spacer()
                        DatePicker("", selection: $dob, in: ...Date(), displayedComponents: .date).labelsHidden()
                            .accessibilityIdentifier("dobCorrection.dob")
                    }
                    TextField(app.T("Lý do (ví dụ: nhập nhầm khi đăng ký)", "Reason (for example: mistyped at sign-up)"), text: $reason, axis: .vertical)
                        .lineLimit(2...4)
                        .font(.system(size: 13))
                        .padding(10)
                        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityIdentifier("dobCorrection.reason")
                    Text(app.T("Quản trị viên sẽ xem xét. Ngày sinh chỉ đổi khi yêu cầu được duyệt.",
                               "An admin reviews it. Your birthday only changes if the request is approved."))
                        .font(.system(size: 11)).opacity(0.65)
                    if !errorMsg.isEmpty { Text(errorMsg).font(.system(size: 12)).foregroundStyle(BanbeTheme.alert) }
                    HStack(spacing: 14) {
                        Button(busy ? app.T("Đang gửi…", "Sending…") : app.T("Gửi yêu cầu", "Send request")) { Task { await submit() } }
                            .disabled(busy || reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 5)
                            .accessibilityIdentifier("dobCorrection.submit")
                        Button(app.T("Hủy", "Cancel")) { open = false; errorMsg = "" }
                    }
                    .font(.system(size: 12.5, weight: .semibold)).buttonStyle(.plain)
                }
            }
        }
        .task { await load() }
    }
}

/// Admin > Review & Moderation > Birthday corrections.
struct AdminDobCorrectionsView: View {
    @EnvironmentObject private var app: AppState

    private struct Row: Decodable, Identifiable {
        let id: UUID
        let status: String
        let reason: String
        let requestedDob: String
        let currentDob: String?
        let displayName: String?
        let email: String
        let decisionNote: String?
        enum CodingKeys: String, CodingKey {
            case id, status, reason, email
            case requestedDob = "requested_dob", currentDob = "current_dob"
            case displayName = "display_name", decisionNote = "decision_note"
        }
    }
    private struct Listing: Decodable { let success: Bool?; let requests: [Row]? }
    private struct DecideParams: Encodable {
        let id: UUID, approve: Bool, note: String?
        enum CodingKeys: String, CodingKey { case id = "p_id", approve = "p_approve", note = "p_note" }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id); try c.encode(approve, forKey: .approve); try c.encode(note, forKey: .note)
        }
    }

    @State private var rows: [Row] = []
    @State private var notes: [UUID: String] = [:]
    @State private var loading = true
    @State private var busy = false
    @State private var message = ""
    @State private var messageIsError = false

    private func errorText(_ code: String?) -> String {
        switch code {
        case "NOT_AUTHORIZED": return app.T("Bạn không có quyền.", "You are not allowed to do this.")
        case "NOT_PENDING": return app.T("Yêu cầu này đã được xử lý.", "That request was already handled.")
        case "INVALID_TARGET": return app.T("Bạn không thể xử lý yêu cầu của chính mình.", "You can’t decide your own request.")
        default: return app.T("Không thực hiện được. Thử lại.", "Couldn’t do that. Try again.")
        }
    }

    private func load() async {
        defer { loading = false }
        let r: Listing? = try? await SupabaseService.client.rpc("admin_list_dob_corrections").execute().value
        if r?.success == true { rows = r?.requests ?? [] }
        else { message = app.T("Không tải được danh sách.", "Couldn’t load the list."); messageIsError = true }
    }

    private func decide(_ row: Row, approve: Bool) async {
        busy = true; message = ""
        defer { busy = false }
        let note = (notes[row.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let r: RPCResult = try await SupabaseService.client
                .rpc("admin_decide_dob_correction", params: DecideParams(id: row.id, approve: approve, note: note.isEmpty ? nil : note)).execute().value
            guard r.success == true else { message = errorText(r.error); messageIsError = true; return }
            message = approve ? app.T("Đã duyệt và cập nhật ngày sinh.", "Approved. The birthday was updated.") : app.T("Đã từ chối.", "Declined.")
            messageIsError = false
            await load()
        } catch { message = errorText(nil); messageIsError = true }
    }

    private func card(_ r: Row, actions: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(r.displayName?.isEmpty == false ? (r.displayName ?? "") : r.email).font(.system(size: 14, weight: .semibold))
            Text(r.email).font(.system(size: 12)).opacity(0.75)
            Text("\(app.T("Hiện tại", "Current")): \(shortDate(r.currentDob))\n\(app.T("Yêu cầu đổi thành", "Requested")): \(shortDate(r.requestedDob))\n\(app.T("Lý do", "Reason")): \(r.reason)")
                .font(.system(size: 12.5)).lineSpacing(3)
            if actions {
                TextField(app.T("Ghi chú cho người dùng (không bắt buộc)", "Note to the user (optional)"),
                          text: Binding(get: { notes[r.id] ?? "" }, set: { notes[r.id] = $0 }))
                    .font(.system(size: 13)).padding(12)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                HStack(spacing: 8) {
                    InkButton(title: app.T("Duyệt", "Approve")) { Task { await decide(r, approve: true) } }
                        .disabled(busy).accessibilityIdentifier("dobAdmin.approve.\(r.id)")
                    Button(app.T("Từ chối", "Decline")) { Task { await decide(r, approve: false) } }
                        .font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .buttonStyle(.plain).disabled(busy).accessibilityIdentifier("dobAdmin.decline.\(r.id)")
                }
            } else {
                Text((r.status == "approved" ? app.T("Đã duyệt", "Approved") : app.T("Đã từ chối", "Declined"))
                     + ((r.decisionNote ?? "").isEmpty ? "" : ": \(r.decisionNote ?? "")"))
                    .font(.system(size: 12)).opacity(0.75)
            }
        }
        .padding(16)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.top, 10)
    }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.T("Duyệt & Kiểm Duyệt", "Review & Moderation")) { app.screen = .accountGroup }
                    .padding(.top, 8)
                Text(app.T("Sửa ngày sinh", "Birthday corrections")).font(BanbeTheme.display(24)).padding(.top, 14)
                Text(app.T("Người dùng gửi yêu cầu khi ngày sinh trong hồ sơ bị sai. Duyệt sẽ ghi đè ngày sinh đã lưu.",
                           "People file a request when the birthday on their profile is wrong. Approving overwrites the stored birthday."))
                    .font(.system(size: 12.5)).opacity(0.75).padding(.top, 8)
                if !message.isEmpty {
                    Text(message).font(.system(size: 12.5))
                        .foregroundStyle(messageIsError ? BanbeTheme.alert : app.palette.ink).padding(.top, 12)
                }
                let pending = rows.filter { $0.status == "pending" }
                let done = rows.filter { $0.status != "pending" }
                if loading { Text(app.T("Đang tải…", "Loading…")).font(.system(size: 13)).opacity(0.65).padding(.top, 18) }
                else if pending.isEmpty { Text(app.T("Không có yêu cầu nào đang chờ.", "No requests waiting.")).font(.system(size: 13)).opacity(0.65).padding(.top, 18) }
                ForEach(pending) { card($0, actions: true) }
                if !done.isEmpty {
                    Text(app.T("Đã xử lý", "Handled")).font(.system(size: 11.5, weight: .semibold)).padding(.top, 24)
                    ForEach(done) { card($0, actions: false) }
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 30).padding(.bottom, 42)
        }
        .task { await load() }
    }
}
