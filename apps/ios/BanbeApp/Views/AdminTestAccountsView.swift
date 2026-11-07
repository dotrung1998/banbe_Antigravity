import SwiftUI
import Supabase

/// Admin > Test accounts (migration 159) — the iOS counterpart of
/// src/screens/AdminTestAccounts.jsx. Pick an existing account by email, store
/// its contact phone in profiles.phone, grant/revoke the server-side "no SMS
/// OTP" TEST exemption and, if it has none, seed a date of birth. Authority is
/// enforced by the two admin_* RPCs (profiles.role = 'admin' checked
/// server-side); this view only calls them. The phone is never marked verified,
/// no SMS is sent, an existing DOB is never changed, and the DOB is write-only
/// here (the server never returns it).
struct AdminTestAccountsView: View {
    @EnvironmentObject private var app: AppState

    private struct Found: Decodable {
        let success: Bool?
        let error: String?
        let userId: UUID?
        let email: String?
        let displayName: String?
        let role: String?
        let profilePhone: String?
        let phoneVerified: Bool?
        let grandfathered: Bool?
        let testExempt: Bool?
        let hasDob: Bool?
        enum CodingKeys: String, CodingKey {
            case success, error, email, role, grandfathered
            case userId = "user_id", displayName = "display_name", profilePhone = "profile_phone"
            case phoneVerified = "phone_verified", testExempt = "test_exempt", hasDob = "has_dob"
        }
    }

    private struct Match: Decodable, Identifiable {
        let userId: UUID, email: String, displayName: String?, role: String?
        var id: UUID { userId }
        enum CodingKeys: String, CodingKey { case email, role, userId = "user_id", displayName = "display_name" }
    }
    private struct SearchResult: Decodable { let success: Bool?; let results: [Match]? }

    private struct SaveResult: Decodable { let success: Bool?; let error: String? }

    private struct SaveParams: Encodable {
        let userId: UUID, phone: String?, dob: String?, grant: Bool
        enum CodingKeys: String, CodingKey { case userId = "p_user_id", phone = "p_phone", dob = "p_dob", grant = "p_grant" }
        // Explicit nulls: the RPC has no argument defaults, so keys must be present.
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(userId, forKey: .userId)
            try c.encode(phone, forKey: .phone)
            try c.encode(dob, forKey: .dob)
            try c.encode(grant, forKey: .grant)
        }
    }

    private struct BypassState: Decodable { let success: Bool?; let error: String?; let enabled: Bool? }

    // Global "waive SMS for everyone" switch (migration 181). nil = not loaded.
    @State private var bypassAll: Bool?
    @State private var bypassBusy = false
    @State private var confirmTo: Bool?

    @State private var email = ""
    @State private var found: Found?
    @State private var nameQuery = ""
    @State private var matches: [Match] = []
    @State private var phone = ""
    @State private var setDOB = false
    @State private var dob = Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1)) ?? Date()
    @State private var grant = true
    @State private var busy = false
    @State private var message = ""
    @State private var messageIsError = false
    // TESTING PHASE: delete the found account (server: /api/auth admin_delete_account).
    @State private var confirmDelete = false
    @State private var deleting = false

    private func errorText(_ code: String?) -> String {
        switch code {
        case "INVALID_VALUE": return app.T("Giá trị không hợp lệ.", "Invalid value.")
        case "NOT_AUTHORIZED": return app.T("Bạn không có quyền.", "You are not allowed to do this.")
        case "USER_NOT_FOUND": return app.T("Không tìm thấy tài khoản với email này.", "No account with that email.")
        case "INVALID_TARGET": return app.T("Không thể áp dụng cho chính bạn.", "You can't change your own account here.")
        case "INVALID_PHONE": return app.T("Số điện thoại phải theo định dạng quốc tế, ví dụ +4917656035288.", "Phone must be international format, e.g. +4917656035288.")
        case "PHONE_IN_USE": return app.T("Số này đã gắn với tài khoản khác.", "That number already belongs to another account.")
        case "INVALID_DOB": return app.T("Ngày sinh không hợp lệ.", "Invalid date of birth.")
        case "TARGET_IS_ADMIN": return app.T("Không thể xoá tài khoản quản trị viên ở đây.", "Admin accounts can't be deleted here.")
        case "ACCOUNT_DELETION_BLOCKED_OPEN_EVENT": return app.T("Tài khoản này còn sự kiện đang mở. Huỷ hoặc gỡ sự kiện trước.", "This account still owns an open event. Cancel or remove it first.")
        case "DOB_ALREADY_SET": return app.T("Tài khoản đã có ngày sinh khác. Ngày sinh không bao giờ bị ghi đè.", "This account already has a different date of birth. It is never overwritten.")
        default: return app.T("Không thực hiện được. Thử lại.", "Couldn't do that. Try again.")
        }
    }

    private var isoDOB: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: dob)
    }

    private func field(_ placeholder: String, text: Binding<String>, id: String, keyboard: UIKeyboardType = .default) -> some View {
        TextField(placeholder, text: text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(keyboard)
            .font(.system(size: 14))
            .padding(14)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityIdentifier(id)
    }

    private func loadBypass() async {
        let r: BypassState? = try? await SupabaseService.client.rpc("admin_get_phone_bypass_all").execute().value
        if r?.success == true { bypassAll = r?.enabled ?? false }
    }

    private func applyBypass() async {
        guard let next = confirmTo else { return }
        bypassBusy = true; message = ""
        defer { bypassBusy = false; confirmTo = nil }
        do {
            let r: BypassState = try await SupabaseService.client
                .rpc("admin_set_phone_bypass_all", params: ["p_enabled": next]).execute().value
            guard r.success == true else { show(errorText(r.error), error: true); return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { bypassAll = r.enabled ?? next }
            show(next ? app.T("Đã BẬT: mọi người dùng được bỏ qua bước SMS.", "Turned ON: every user can skip the SMS step.")
                      : app.T("Đã TẮT: bước SMS được áp dụng lại.", "Turned OFF: the SMS step applies again."), error: false)
        } catch { show(errorText(nil), error: true) }
    }

    /// A tap only opens the confirmation; it never flips directly (shared look: Views/GlassSwitch.swift).
    private var bypassSwitch: some View {
        GlassSwitch(isOn: bypassAll == true, loading: bypassAll == nil || bypassBusy, identifier: "adminTest.bypassSwitch") {
            confirmTo = !(bypassAll == true)
        }
    }

    private func lookup(_ target: String? = nil) async {
        busy = true; message = ""; found = nil
        defer { busy = false }
        do {
            let r: Found = try await SupabaseService.client
                .rpc("admin_phone_exempt_lookup", params: ["p_email": target ?? email]).execute().value
            guard r.success == true, r.userId != nil else { show(errorText(r.error), error: true); return }
            found = r
            phone = r.profilePhone ?? ""
            setDOB = false
            grant = r.grandfathered != true
        } catch { show(errorText(nil), error: true) }
    }

    private func save() async {
        guard let id = found?.userId else { return }
        busy = true; message = ""
        defer { busy = false }
        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        do {
            let r: SaveResult = try await SupabaseService.client
                .rpc("admin_set_phone_exemption", params: SaveParams(
                    userId: id, phone: trimmed.isEmpty ? nil : trimmed,
                    dob: (setDOB && found?.hasDob != true) ? isoDOB : nil, grant: grant)).execute().value
            guard r.success == true else { show(errorText(r.error), error: true); return }
            show(app.T("Đã lưu. Số điện thoại vẫn CHƯA được xác minh.", "Saved. The phone number is still NOT verified."), error: false)
            await lookup(found?.email)
            // lookup() clears the message; show the confirmation again.
            show(app.T("Đã lưu. Số điện thoại vẫn CHƯA được xác minh.", "Saved. The phone number is still NOT verified."), error: false)
        } catch { show(errorText(nil), error: true) }
    }

    /// TESTING PHASE (owner, 2026-10-22): frees a test email without going through that account's own deletion flow.
    /// The server checks the caller is an admin, refuses admins and accounts that still own an open event, writes
    /// the admin action log, then runs the same deletion workflow as Delete Account.
    private func deleteFound() async {
        guard let f = found, let id = f.userId else { return }
        deleting = true; message = ""
        defer { deleting = false }
        guard let url = URL(string: AppConfig.apiBaseURL + "/api/auth"),
              let token = try? await SupabaseService.client.auth.session.accessToken else { show(errorText(nil), error: true); return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["type": "admin_delete_account", "userId": id.uuidString.lowercased()])
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), json["deleted"] as? Bool == true else {
                let code = json["error"] as? String
                let names = ((json["openEvents"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }.joined(separator: ", ")
                show(errorText(code) + (names.isEmpty ? "" : " (\(names))"), error: true)
                return
            }
            let gone = f.email ?? ""
            found = nil; email = ""; phone = ""
            show(app.T("Đã xoá \(gone). Email này có thể dùng để đăng ký lại.", "Deleted \(gone). This email can be used to sign up again."), error: false)
        } catch { show(errorText(nil), error: true) }
    }

    private func search() async {
        let q = nameQuery.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { matches = []; return }
        try? await Task.sleep(nanoseconds: 300_000_000)   // debounce; a newer keystroke cancels this task
        guard !Task.isCancelled else { return }
        let r: SearchResult? = try? await SupabaseService.client
            .rpc("admin_phone_exempt_search", params: ["p_query": q]).execute().value
        if !Task.isCancelled { matches = (r?.success == true) ? (r?.results ?? []) : [] }
    }

    private func show(_ text: String, error: Bool) { message = text; messageIsError = error }

    private func yesNo(_ v: Bool?) -> String { v == true ? app.T("Có", "Yes") : app.T("Không", "No") }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.T("Duyệt & Kiểm Duyệt", "Review & Moderation")) { app.screen = .accountGroup }
                    .padding(.top, 8)
                    .accessibilityIdentifier("adminTest.back")

                Text(app.T("Tài Khoản Thử Nghiệm", "Test Accounts"))
                    .font(BanbeTheme.display(24)).padding(.top, 14)
                    .accessibilityIdentifier("adminTest.title")
                Text(app.T("Miễn bước SMS cho tài khoản thử nghiệm. Số điện thoại KHÔNG được đánh dấu đã xác minh, không gửi SMS, và vẫn phải nhập/xác nhận ngày sinh.",
                           "Waive the SMS step for a test account. The phone is NOT marked verified, no SMS is sent, and the date-of-birth steps still apply."))
                    .font(.system(size: 12.5)).foregroundStyle(app.palette.ink.opacity(0.75)).padding(.top, 8)

                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.T("Bỏ qua SMS cho tất cả", "Bypass SMS for everyone"))
                            .font(.system(size: 14, weight: .semibold))
                        Text(bypassAll == nil ? app.T("Đang tải…", "Loading…")
                             : bypassAll == true ? app.T("ĐANG BẬT. Không ai phải xác minh SMS.", "ON. Nobody has to verify by SMS.")
                             : app.T("Đang tắt. Người dùng phải xác minh SMS.", "Off. Users must verify by SMS."))
                            .font(.system(size: 11.5)).opacity(0.7)
                    }
                    Spacer(minLength: 0)
                    bypassSwitch
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.top, 14)
                .accessibilityIdentifier("adminTest.bypassCard")

                field("email@example.com", text: $email, id: "adminTest.email", keyboard: .emailAddress)
                    .submitLabel(.search)
                    .onSubmit { if !email.trimmingCharacters(in: .whitespaces).isEmpty { Task { await lookup() } } }
                    .padding(.top, 10)

                field(app.T("Hoặc tìm theo tên hiển thị", "Or search by display name"), text: $nameQuery, id: "adminTest.name")
                    .padding(.top, 10)
                    .task(id: nameQuery) { await search() }
                if !matches.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(matches) { m in
                            Button {
                                email = m.email; nameQuery = ""; matches = []
                                Task { await lookup(m.email) }
                            } label: {
                                Text("\(m.displayName ?? "—") · \(m.email) · \(m.role ?? "")")
                                    .font(.system(size: 13)).multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("adminTest.match")
                        }
                    }
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.top, 8)
                }

                if let f = found {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(f.displayName?.isEmpty == false ? (f.displayName ?? "") : (f.email ?? ""))
                            .font(.system(size: 14, weight: .semibold))
                        Text("\(f.email ?? "") · \(f.role ?? "")").font(.system(size: 12)).opacity(0.75)
                        Text("\(app.T("Xác minh SMS", "SMS verified")): \(yesNo(f.phoneVerified))\n\(app.T("Miễn SMS thử nghiệm", "SMS test exemption")): \(yesNo(f.testExempt))\n\(app.T("Nhóm người dùng cũ (đã miễn)", "Legacy grandfathered")): \(yesNo(f.grandfathered))\n\(app.T("Đã có ngày sinh", "Has date of birth")): \(yesNo(f.hasDob))")
                            .font(.system(size: 12)).lineSpacing(3)
                        field("+4917656035288", text: $phone, id: "adminTest.phone", keyboard: .phonePad)
                        if f.hasDob != true {
                            Toggle(app.T("Đặt ngày sinh (chỉ ghi, không bao giờ ghi đè)", "Set date of birth (write-only, never overwritten)"), isOn: $setDOB)
                                .font(.system(size: 13)).accessibilityIdentifier("adminTest.setDob")
                            if setDOB {
                                DatePicker("", selection: $dob, in: ...Date(), displayedComponents: .date)
                                    .datePickerStyle(.compact).labelsHidden()
                                    .accessibilityIdentifier("adminTest.dob")
                            }
                        }
                        if f.grandfathered != true {
                            Toggle(app.T("Miễn SMS OTP (tài khoản thử nghiệm)", "Waive SMS OTP (test account)"), isOn: $grant)
                                .font(.system(size: 13)).accessibilityIdentifier("adminTest.grant")
                        }
                        InkButton(title: busy ? app.T("Đang lưu…", "Saving…") : app.T("Lưu", "Save")) { Task { await save() } }
                            .disabled(busy).accessibilityIdentifier("adminTest.save")
                        Text(app.T("Số chỉ lưu trong hồ sơ, không có trong Auth nên không dùng được cho tin nhắn quảng bá.",
                                   "The number is stored on the profile only (not in Auth), so it does not enable promo texting."))
                            .font(.system(size: 11.5)).opacity(0.65)
                        if f.role != "admin" {
                            Button { confirmDelete = true } label: {
                                Text(deleting ? app.T("Đang xoá…", "Deleting…") : app.T("Xoá tài khoản", "Delete account"))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(BanbeTheme.alert)
                                    .frame(maxWidth: .infinity, minHeight: 46)
                                    .overlay(Capsule().stroke(BanbeTheme.alert, lineWidth: 1.2))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(PressableButtonStyle())
                            .disabled(deleting || busy)
                            .padding(.top, 6)
                            .accessibilityIdentifier("adminTest.delete")
                        }
                    }
                    .alert(app.T("Xoá tài khoản này?", "Delete this account?"), isPresented: $confirmDelete) {
                        Button(app.T("Huỷ", "Cancel"), role: .cancel) {}
                        Button(app.T("Xoá vĩnh viễn", "Delete permanently"), role: .destructive) { Task { await deleteFound() } }
                    } message: {
                        Text(app.T("\(f.email ?? "") và mọi dữ liệu gắn với tài khoản sẽ bị xoá vĩnh viễn. Không thể hoàn tác. Email này có thể đăng ký lại sau đó.",
                                   "\(f.email ?? "") and everything tied to the account are deleted permanently. This can't be undone. The email can sign up again afterwards."))
                    }
                    .padding(16)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.top, 18)
                }

                if !message.isEmpty {
                    Text(message).font(.system(size: 12.5))
                        .foregroundStyle(messageIsError ? BanbeTheme.alert : app.palette.ink)
                        .padding(.top, 14).accessibilityIdentifier("adminTest.message")
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 30).padding(.bottom, 42)
        }
        // The main action always sits at the very bottom (owner, 2026-10-22).
        .safeAreaInset(edge: .bottom) {
            InkButton(title: busy && found == nil ? app.T("Đang tìm…", "Finding…") : app.T("Tìm tài khoản", "Find account")) { Task { await lookup() } }
                .disabled(busy || email.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal, 30).padding(.top, 10).padding(.bottom, 8)
                .background(app.palette.paper.ignoresSafeArea(edges: .bottom))
                .accessibilityIdentifier("adminTest.find")
        }
        .task { await loadBypass() }
        .alert(confirmTo == true ? app.T("Bật bỏ qua SMS cho tất cả?", "Bypass SMS for everyone?")
                                 : app.T("Tắt bỏ qua SMS?", "Turn the SMS bypass off?"),
               isPresented: Binding(get: { confirmTo != nil }, set: { if !$0 { confirmTo = nil } })) {
            Button(app.T("Huỷ", "Cancel"), role: .cancel) { confirmTo = nil }
            Button(confirmTo == true ? app.T("Bật", "Turn on") : app.T("Tắt", "Turn off"),
                   role: confirmTo == true ? .destructive : nil) { Task { await applyBypass() } }
        } message: {
            Text(confirmTo == true
                 ? app.T("Mọi người dùng trên web và iOS sẽ không phải xác minh số điện thoại bằng SMS. Ngày sinh vẫn bắt buộc.",
                         "Every user on web and iOS will be able to continue without SMS phone verification. Date of birth is still required.")
                 : app.T("Người dùng chưa xác minh sẽ phải xác minh số điện thoại bằng SMS trở lại.",
                         "Users who are not verified will have to verify their phone by SMS again."))
        }
    }
}
