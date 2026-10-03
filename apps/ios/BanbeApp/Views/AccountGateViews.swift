import SwiftUI

/// Where a "can't recover my date of birth" user can reach a human. There is
/// no self-service reset by design. Left nil until a support address exists —
/// the screen then just explains the situation without inventing one.
enum AccountGateSupport {
    static let email: String? = nil
}

/// Covers the app while the signed-in session hasn't cleared the server-owned
/// gate (see migration 123): required enrollment for a new registration
/// (verified phone, then date of birth), or "Confirm date of birth" for a
/// session of an account that has one. The server enforces the same rule
/// through RLS — this view is only the UI for it.
struct AccountGateOverlay: View {
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var app: AppState

    var body: some View {
        ZStack {
            app.palette.paper.ignoresSafeArea()
            switch auth.gate {
            case .blocked(let status):
                if status.phoneRequired {
                    PhoneEnrollmentView()
                } else if status.dobEnrollmentRequired {
                    DOBEnrollmentView()
                } else {
                    ConfirmDOBView()
                }
            case .unavailable:
                GateScaffold(
                    title: app.T("Chưa thể kiểm tra tài khoản", "Couldn't check your account"),
                    subtitle: app.T("Kiểm tra kết nối rồi thử lại. Bạn chưa vào được ứng dụng cho tới khi bước này hoàn tất.",
                                    "Check your connection and try again. You can't use the app until this finishes.")
                ) {
                    InkButton(title: app.T("Thử lại", "Try again")) { Task { await auth.refreshGate() } }
                }
            default:
                BanbeLoadingVisual(size: 44)
            }
        }
        .foregroundStyle(app.palette.ink)
        .transition(.opacity)
    }
}

// MARK: - Shared chrome

private struct GateScaffold<Content: View>: View {
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var app: AppState
    let title: String
    let subtitle: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BanbeLogo(kind: .wordmark, width: BanbeLogo.headerWordmarkWidth)
                    .padding(.top, 36)
                Text(title).font(BanbeTheme.display(26)).padding(.top, 28)
                Text(subtitle)
                    .font(.system(size: 14)).lineSpacing(3)
                    .foregroundStyle(app.palette.ink.opacity(0.8))
                    .padding(.top, 10)
                VStack(alignment: .leading, spacing: 14) { content() }
                    .padding(.top, 22)
                Button(app.T("Đăng xuất", "Sign out")) { Task { await auth.signOut() } }
                    .font(.system(size: 13))
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 28)
                    .accessibilityIdentifier("gate.signOut")
            }
            .padding(.horizontal, 24).padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

/// Day / Month / Year as three separate fields (VI: Ngày / Tháng / Năm).
/// Digits only; focus moves on as each field fills.
struct DOBFieldsView: View {
    @EnvironmentObject private var app: AppState
    @Binding var input: DateOfBirthInput
    var identifierPrefix = "dob"

    private enum Field { case day, month, year }
    @FocusState private var focus: Field?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            field(app.T("Ngày", "Day"), "DD", $input.day, .day, max: 2, width: nil)
            field(app.T("Tháng", "Month"), "MM", $input.month, .month, max: 2, width: nil)
            field(app.T("Năm", "Year"), "YYYY", $input.year, .year, max: 4, width: nil)
                .frame(maxWidth: .infinity)
        }
        .onChange(of: input.day) { _, v in
            let d = DateOfBirthInput.digits(v, max: 2)
            if d != v { input.day = d }
            if d.count == 2 { focus = .month }
        }
        .onChange(of: input.month) { _, v in
            let d = DateOfBirthInput.digits(v, max: 2)
            if d != v { input.month = d }
            if d.count == 2 { focus = .year }
        }
        .onChange(of: input.year) { _, v in
            let d = DateOfBirthInput.digits(v, max: 4)
            if d != v { input.year = d }
        }
    }

    private func field(_ label: String, _ placeholder: String, _ text: Binding<String>, _ f: Field, max: Int, width: CGFloat?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 11.5, weight: .semibold))
            TextField(placeholder, text: text)
                .keyboardType(.numberPad)
                .textContentType(.none)
                .multilineTextAlignment(.center)
                .font(.system(size: 17, weight: .medium))
                .padding(.vertical, 12)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .focused($focus, equals: f)
                .accessibilityIdentifier("\(identifierPrefix).\(label.lowercased())")
        }
    }
}

private func dobProblemText(_ p: DateOfBirthInput.Problem, T: (String, String) -> String) -> String {
    switch p {
    case .incomplete: return T("Nhập đủ ngày, tháng và năm (4 chữ số).", "Enter the day, month and a 4-digit year.")
    case .invalidDate: return T("Ngày này không có trong lịch.", "That date doesn't exist.")
    case .future: return T("Ngày sinh không thể ở tương lai.", "Date of birth can't be in the future.")
    case .tooOld: return T("Hãy nhập năm sinh từ 1900 trở đi.", "Enter a year from 1900 onward.")
    }
}

// MARK: - Phone verification (new registrations)

struct PhoneEnrollmentView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var app: AppState

    @State private var country = PhoneCountry.defaultCountry(regionCode: Locale.current.region?.identifier)
    @State private var number = ""
    @State private var e164 = ""
    @State private var codeSent = false
    @State private var code = ""
    @State private var busy = false
    @State private var message: String?
    @State private var cooldown = 0
    @State private var cooldownTask: Task<Void, Never>?

    var body: some View {
        GateScaffold(
            title: codeSent ? app.T("Nhập mã xác minh", "Enter the verification code")
                            : app.T("Xác minh số điện thoại", "Verify your phone number"),
            subtitle: codeSent
                ? app.T("Chúng tôi đã gửi mã 6 số qua SMS tới \(e164). Mã chỉ xác minh bạn dùng được số này.",
                        "We sent a 6-digit code by SMS to \(e164). It only confirms you can receive texts on this number.")
                : app.T("Thêm số điện thoại có mã quốc gia để hoàn tất đăng ký. Chúng tôi sẽ gửi một mã SMS.",
                        "Add a phone number with its country code to finish registering. We'll text you a code.")
        ) {
            if codeSent { codeStep } else { numberStep }
            if let message {
                Text(message).font(.system(size: 12.5)).foregroundStyle(BanbeTheme.alert)
                    .accessibilityIdentifier("gate.phone.error")
            }
        }
        .onDisappear { cooldownTask?.cancel() }
    }

    private var numberStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Menu {
                    ForEach(PhoneCountry.all) { c in
                        Button("\(c.flag) \(app.T(c.nameVi, c.nameEn)) (+\(c.dial))") { country = c }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(country.flag)
                        Text("+\(country.dial)").font(.system(size: 16, weight: .medium))
                        Image(systemName: "chevron.down").font(.system(size: 10))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 13)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .accessibilityIdentifier("gate.phone.country")
                TextField(app.T("Số điện thoại", "Phone number"), text: $number)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .font(.system(size: 17))
                    .padding(.horizontal, 14).padding(.vertical, 13)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityIdentifier("gate.phone.number")
            }
            InkButton(title: busy ? app.T("Đang gửi…", "Sending…") : app.T("Gửi mã", "Send code"),
                      enabled: !busy) { send() }
                .accessibilityIdentifier("gate.phone.send")
        }
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("123456", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .multilineTextAlignment(.center)
                .font(.system(size: 24, weight: .semibold))
                .padding(.vertical, 14)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onChange(of: code) { _, v in
                    let d = DateOfBirthInput.digits(v, max: 6)
                    if d != v { code = d }
                }
                .accessibilityIdentifier("gate.phone.code")
            InkButton(title: busy ? app.T("Đang kiểm tra…", "Checking…") : app.T("Xác minh", "Verify"),
                      enabled: !busy && code.count == 6) { verify() }
                .accessibilityIdentifier("gate.phone.verify")
            HStack {
                Button(cooldown > 0
                       ? app.T("Gửi lại sau \(cooldown)s", "Resend in \(cooldown)s")
                       : app.T("Gửi lại mã", "Resend code")) { resend() }
                    .disabled(cooldown > 0 || busy)
                    .font(.system(size: 13))
                Spacer()
                Button(app.T("Đổi số", "Change number")) {
                    codeSent = false; code = ""; message = nil
                }
                .font(.system(size: 13))
            }
            .buttonStyle(.plain)
        }
    }

    private func startCooldown() {
        cooldownTask?.cancel()
        cooldown = 60
        cooldownTask = Task {
            while cooldown > 0, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if !Task.isCancelled { cooldown -= 1 }
            }
        }
    }

    private func send() {
        message = nil
        guard let parsed = country.e164(from: number) else {
            message = app.T("Số điện thoại chưa hợp lệ. Kiểm tra mã quốc gia và số.", "That phone number isn't valid. Check the country code and number.")
            return
        }
        busy = true
        Task {
            defer { busy = false }
            if let failure = await auth.sendPhoneCode(e164: parsed) {
                message = text(for: failure)
                return
            }
            e164 = parsed
            codeSent = true
            startCooldown()
        }
    }

    private func resend() {
        message = nil
        busy = true
        Task {
            defer { busy = false }
            if let failure = await auth.resendPhoneCode(e164: e164) { message = text(for: failure); return }
            startCooldown()
        }
    }

    private func verify() {
        message = nil
        busy = true
        Task {
            defer { busy = false }
            if let failure = await auth.verifyPhoneCode(e164: e164, code: code) {
                code = ""
                message = text(for: failure)
            }
        }
    }

    private func text(for failure: PhoneCodeFailure) -> String {
        switch failure {
        case .phoneInUse:
            return app.T("Số này đã được liên kết với tài khoản khác. Hãy dùng số khác.", "This number is already linked to another account. Use a different number.")
        case .rateLimited:
            return app.T("Bạn đã yêu cầu quá nhiều mã. Vui lòng thử lại sau.", "Too many code requests. Please try again later.")
        case .providerUnavailable:
            return app.T("Chưa gửi được SMS: dịch vụ SMS chưa được cấu hình hoặc đang lỗi. Số của bạn chưa được xác minh.", "Couldn't send the SMS: the SMS service isn't configured or is failing. Your number has NOT been verified.")
        case .invalidNumber:
            return app.T("Số điện thoại chưa hợp lệ.", "That phone number isn't valid.")
        case .expired:
            return app.T("Mã đã hết hạn. Hãy gửi lại mã mới.", "That code expired. Request a new one.")
        case .wrongCode:
            return app.T("Mã chưa đúng. Thử lại.", "That code isn't right. Try again.")
        case .network:
            return app.T("Không có kết nối. Thử lại.", "No connection. Try again.")
        case .other:
            return app.T("Chưa thực hiện được. Thử lại sau.", "That didn't work. Please try again later.")
        }
    }
}

// MARK: - Date of birth (new registrations)

struct DOBEnrollmentView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var app: AppState

    @State private var input = DateOfBirthInput()
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        GateScaffold(
            title: app.T("Ngày sinh", "Date of birth"),
            subtitle: app.T("Nhập ngày sinh của bạn để hoàn tất đăng ký.", "Enter your date of birth to complete registration.")
        ) {
            DOBFieldsView(input: $input, identifierPrefix: "gate.enroll")
            Text(app.T("Bạn không thể tự đổi ngày sinh sau khi lưu.", "You can't change your date of birth yourself after saving."))
                .font(.system(size: 12)).foregroundStyle(app.palette.ink.opacity(0.7))
            if let message {
                Text(message).font(.system(size: 12.5)).foregroundStyle(BanbeTheme.alert)
                    .accessibilityIdentifier("gate.enroll.error")
            }
            InkButton(title: busy ? app.T("Đang lưu…", "Saving…") : app.T("Hoàn tất đăng ký", "Complete registration"),
                      enabled: !busy) { submit() }
                .accessibilityIdentifier("gate.enroll.submit")
        }
    }

    private func submit() {
        message = nil
        switch input.validate() {
        case .failure(let p):
            message = dobProblemText(p, T: app.T)
        case .success(let iso):
            busy = true
            Task {
                defer { busy = false }
                if await !auth.submitEnrollmentDOB(iso: iso) {
                    message = app.T("Chưa lưu được. Thử lại sau.", "Couldn't save. Please try again.")
                }
            }
        }
    }
}

// MARK: - Confirm date of birth (every new session of an account that has one)

struct ConfirmDOBView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var app: AppState

    @State private var input = DateOfBirthInput()
    @State private var busy = false
    @State private var message: String?
    @State private var lockedFor = 0
    @State private var lockTask: Task<Void, Never>?

    var body: some View {
        GateScaffold(
            title: app.T("Xác nhận ngày sinh", "Confirm date of birth"),
            subtitle: app.T("Nhập ngày sinh đã đăng ký để tiếp tục đăng nhập.", "Enter your registered date of birth to continue signing in.")
        ) {
            DOBFieldsView(input: $input, identifierPrefix: "gate.confirm")
            if let message {
                Text(message).font(.system(size: 12.5)).foregroundStyle(BanbeTheme.alert)
                    .accessibilityIdentifier("gate.confirm.error")
            }
            InkButton(title: busy ? app.T("Đang kiểm tra…", "Checking…") : app.T("Tiếp tục", "Continue"),
                      enabled: !busy && lockedFor == 0) { submit() }
                .accessibilityIdentifier("gate.confirm.submit")
            VStack(alignment: .leading, spacing: 6) {
                Text(app.T("Quên ngày sinh đã đăng ký?", "Forgot your registered date of birth?"))
                    .font(.system(size: 12, weight: .semibold))
                Text(app.T("Ngày sinh không thể tự đặt lại trong ứng dụng. Hãy đăng xuất và liên hệ hỗ trợ banbe để được trợ giúp.",
                           "It can't be reset in the app. Sign out and contact banbe support for help."))
                    .font(.system(size: 12)).foregroundStyle(app.palette.ink.opacity(0.75))
                if let email = AccountGateSupport.email, let url = URL(string: "mailto:\(email)") {
                    Link(email, destination: url).font(.system(size: 12))
                }
            }
            .padding(.top, 6)
        }
        .onDisappear { lockTask?.cancel() }
    }

    private func submit() {
        message = nil
        switch input.validate() {
        case .failure(let p):
            message = dobProblemText(p, T: app.T)
        case .success(let iso):
            busy = true
            Task {
                defer { busy = false; input = DateOfBirthInput() } // always blank for the next try
                switch await auth.confirmDOB(iso: iso) {
                case .success:
                    break
                case .incorrect(let left):
                    message = left.map { app.T("Ngày sinh chưa đúng. Còn \($0) lần thử.", "That isn't right. \($0) tries left.") }
                        ?? app.T("Ngày sinh chưa đúng.", "That isn't right.")
                case .locked(let secs):
                    startLock(secs ?? 900)
                case .failed:
                    message = app.T("Chưa kiểm tra được. Thử lại sau.", "Couldn't check. Please try again.")
                }
            }
        }
    }

    private func startLock(_ seconds: Int) {
        lockTask?.cancel()
        lockedFor = max(seconds, 1)
        updateLockMessage()
        lockTask = Task {
            while lockedFor > 0, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                lockedFor -= 1
                if lockedFor % 30 == 0 || lockedFor == 0 { updateLockMessage() }
            }
            message = nil
        }
    }

    private func updateLockMessage() {
        guard lockedFor > 0 else { return }
        let mins = Int(ceil(Double(lockedFor) / 60))
        message = app.T("Quá nhiều lần thử. Thử lại sau khoảng \(mins) phút.", "Too many attempts. Try again in about \(mins) min.")
    }
}
