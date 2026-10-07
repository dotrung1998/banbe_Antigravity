import CoreLocation
import SwiftUI

// Event preferences UI (note 34): the shared chips form, Account > Event
// preferences, and the post-signup onboarding overlay (settings review, then
// five optional questions). Nothing here is mandatory: every control can be
// skipped and reserving never depends on any answer or permission.

// MARK: - Shared chips form

/// The five questions as localized multi-choice chips. Used by onboarding and
/// by Account > Event preferences so the two can never drift apart.
struct EventPreferencesForm: View {
    @EnvironmentObject var app: AppState
    @Binding var prefs: EventPreferences
    @Binding var region: BudgetRegion

    private var vi: Bool { !app.isEN }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            question(app.T("Bạn quan tâm loại sự kiện nào?", "Which events interest you?"),
                     id: "interests", options: EventPrefTaxonomy.interests, selection: $prefs.interests)
            question(app.T("Bạn muốn gì từ sự kiện?", "What do you want from events?"),
                     id: "goals", options: EventPrefTaxonomy.goals, selection: $prefs.goals)
            question(app.T("Bạn thường rảnh khi nào?", "When are you usually free?"),
                     id: "availability", options: EventPrefTaxonomy.availability, selection: $prefs.availability)
            budgetQuestion
            question(app.T("Ngôn ngữ sự kiện bạn thích", "Event languages you prefer"),
                     id: "languages", options: EventPrefTaxonomy.languages, selection: $prefs.languages)
        }
    }

    // MARK: multi-select

    private func question(_ title: String, id: String, options: [PrefOption],
                          selection: Binding<[String]?>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13.5, weight: .semibold))
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(options) { o in
                    chip(vi ? o.vi : o.en, selected: selection.wrappedValue?.contains(o.id) == true,
                         identifier: "prefs.\(id).\(o.id)") { toggle(selection, o.id) }
                }
                chip(app.T("Không ưu tiên", "No preference"),
                     selected: selection.wrappedValue == [EventPrefTaxonomy.noPreference],
                     identifier: "prefs.\(id).no_preference") { toggle(selection, EventPrefTaxonomy.noPreference) }
            }
        }
    }

    /// "No preference" is exclusive with everything else; an empty set = skipped (nil).
    private func toggle(_ selection: Binding<[String]?>, _ id: String) {
        let cur = selection.wrappedValue ?? []
        if id == EventPrefTaxonomy.noPreference {
            selection.wrappedValue = cur == [id] ? nil : [id]
            return
        }
        var arr = cur.filter { $0 != EventPrefTaxonomy.noPreference }
        if let i = arr.firstIndex(of: id) { arr.remove(at: i) } else { arr.append(id) }
        selection.wrappedValue = arr.isEmpty ? nil : arr
    }

    // MARK: budget (single select, explicit ranges)

    private var budgetQuestion: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(app.T("Ngân sách mỗi sự kiện", "Budget per event"))
                    .font(.system(size: 13.5, weight: .semibold))
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    ForEach(BudgetRegion.allCases, id: \.self) { r in
                        chip(r == .vn ? "VND" : "USD", selected: region == r,
                             identifier: "prefs.budget.region.\(r.rawValue)", compact: true) { setRegion(r) }
                    }
                }
            }
            Text(app.T("Khoảng giá tính theo \(region == .vn ? "đồng (VND)" : "đô la Mỹ (USD)").",
                       "Ranges are in \(region == .vn ? "Vietnamese dong (VND)" : "US dollars (USD)")."))
                .font(.system(size: 11.5))
                .foregroundStyle(app.palette.ink.opacity(0.7))
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(EventPrefTaxonomy.budgetTiers + [EventPrefTaxonomy.noPreference], id: \.self) { t in
                    chip(region.label(tier: t, vi: vi), selected: prefs.budget?.tier == t,
                         identifier: "prefs.budget.\(t)") { pickBudget(t) }
                }
            }
        }
    }

    private func pickBudget(_ tier: String) {
        if prefs.budget?.tier == tier { prefs.budget = nil; return }
        let noCurrency = tier == "free" || tier == EventPrefTaxonomy.noPreference
        prefs.budget = BudgetPref(tier: tier, currency: noCurrency ? nil : region.currency)
    }

    private func setRegion(_ r: BudgetRegion) {
        region = r
        if var b = prefs.budget, b.currency != nil { b.currency = r.currency; prefs.budget = b }
    }

    // MARK: chip

    private func chip(_ text: String, selected: Bool, identifier: String, compact: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: compact ? 11.5 : 13, weight: selected ? .semibold : .regular))
                .multilineTextAlignment(.leading)
                .padding(.horizontal, compact ? 10 : 14).padding(.vertical, compact ? 6 : 9)
                .foregroundStyle(selected ? app.palette.paper : app.palette.ink)
                .background(selected ? app.palette.ink : app.palette.field, in: Capsule())
                .overlay(Capsule().stroke(app.palette.rule, lineWidth: selected ? 0 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier(identifier)
    }
}

/// The privacy footer shared by both entry points.
private struct EventPrefsPrivacyNote: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        Text(app.T("Câu trả lời chỉ thuộc về tài khoản của bạn và không bao giờ hiển thị cho host. Đây là sở thích bạn tự khai, không phải thông tin đã được xác minh.",
                   "Your answers are private to your account and never shown to hosts. They are self-declared preferences, not verified credentials."))
            .font(.system(size: 11.5))
            .lineSpacing(3)
            .foregroundStyle(app.palette.ink.opacity(0.7))
    }
}

// MARK: - Account > Event preferences

struct EventPreferencesView: View {
    @EnvironmentObject var app: AppState

    @State private var draft = EventPreferences()
    @State private var region = BudgetRegion.deviceDefault()
    @State private var baseline = EventPreferences()
    @State private var saving = false
    @State private var saved = false
    @State private var failed = false
    @State private var seeded = false

    private var changed: Bool { draft.normalizedForSave() != baseline.normalizedForSave() }
    private var fromReservation: Bool { app.eventPrefsReturnScreen != nil }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.backLabel(for: app.backTargetScreen)) { app.goBack() }

                Text(app.T("Sở thích sự kiện", "Event preferences"))
                    .font(BanbeTheme.display(27))
                    .padding(.top, 16)
                Text(app.T("Dùng để gợi ý sự kiện phù hợp cho bạn. Câu nào cũng có thể bỏ qua.",
                           "Used to suggest events that suit you. Every question is optional."))
                    .font(.system(size: 13.5))
                    .lineSpacing(3)
                    .padding(.top, 10)

                EventPreferencesForm(prefs: $draft, region: $region)
                    .padding(.top, 24)
                    .onChange(of: draft) { _, _ in saved = false; failed = false }

                EventPrefsPrivacyNote().padding(.top, 22)

                if failed {
                    Text(app.T("Chưa lưu được. Vui lòng thử lại.", "Couldn't save. Please try again."))
                        .font(.system(size: 12)).foregroundStyle(BanbeTheme.alert).padding(.top, 14)
                } else if saved {
                    Text(app.T("Đã lưu sở thích.", "Preferences saved."))
                        .font(.system(size: 12)).padding(.top, 14)
                }

                InkButton(title: saving ? app.T("Đang lưu…", "Saving…")
                                        : fromReservation ? app.T("Lưu và quay lại", "Save and go back")
                                                          : app.T("Lưu", "Save"),
                          enabled: !saving && (changed || fromReservation)) {
                    Task { await save() }
                }
                .accessibilityIdentifier("prefs.save")
                .padding(.top, 16)
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 30)
            .padding(.top, 16)
            .padding(.bottom, 42)
        }
        .task { seed() }
    }

    private func seed() {
        guard !seeded else { return }
        seeded = true
        let p = app.eventPrefs ?? EventPreferences()
        draft = p; baseline = p
        if let c = p.budget?.currency { region = BudgetRegion.forCurrency(c) }
    }

    private func save() async {
        saving = true; saved = false; failed = false
        defer { saving = false }
        // Nothing changed (only reachable from the reservation prompt): just go back.
        if !changed { if fromReservation { app.goBack() }; return }
        if await app.saveEventPreferences(draft) {
            baseline = draft
            saved = true
            if fromReservation { app.goBack() }
        } else {
            failed = true
        }
    }
}

// MARK: - Onboarding overlay

/// Full-screen, mounted by RootView below the Face ID lock once the account
/// gates have cleared. Settings review first, then the five questions.
///
/// No-repeat: finishing or skipping calls `complete_*` which sets a server
/// marker. If that call fails the user stays in the step with Retry and
/// "Skip for now"; Skip closes the step for this session only (it flips the
/// in-memory flag, the server marker stays unset) so it may reappear on the
/// next launch.
struct EventOnboardingOverlay: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            app.palette.paper.ignoresSafeArea()
            if app.needsSettingsOnboarding {
                EventSettingsStep()
            } else {
                EventQuestionsStep()
            }
        }
        .transition(.opacity)
    }
}

/// Requests the real iOS location permission without touching AppState's
/// persisted `located` flag (that's only set once authorization succeeds).
private final class LocationPermissionRequester: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    override init() { super.init(); manager.delegate = self }

    /// Resolves with the status once the user answers the system prompt
    /// (immediately if it was already decided).
    func requestWhenInUse() async -> CLAuthorizationStatus {
        guard manager.authorizationStatus == .notDetermined else { return manager.authorizationStatus }
        return await withCheckedContinuation { c in
            continuation = c
            manager.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined, let c = continuation else { return }
        continuation = nil
        c.resume(returning: manager.authorizationStatus)
    }
}

/// "Step n of 2" with a filled/empty bar per step, so people know where they are.
private struct OnboardingStepIndicator: View {
    @EnvironmentObject var app: AppState
    let step: Int
    let total = 2
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(1...total, id: \.self) { i in
                    Capsule().fill(app.palette.ink.opacity(i <= step ? 1 : 0.18)).frame(height: 4)
                }
            }
            Text(app.T("Bước \(step)/\(total)", "Step \(step) of \(total)"))
                .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(app.palette.ink.opacity(0.65))
        }
        .padding(.bottom, 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.T("Bước \(step) trên \(total)", "Step \(step) of \(total)"))
        .accessibilityIdentifier("onboarding.stepIndicator")
    }
}

private struct EventSettingsStep: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var auth: AuthViewModel
    @AppStorage(Haptics.defaultsKey) private var hapticsStored = true

    @State private var haptics = true
    @State private var emailDocs = false
    @State private var seeded = false
    @State private var busy = false
    @State private var failed = false
    @State private var areaPickerOpen = false
    @State private var promo = true
    @State private var faceOn = true
    @State private var locOn = true
    @State private var faceIDMessage = ""
    @State private var requester = LocationPermissionRequester()

    private var biometryName: String {
        BiometricAuthService.biometryType() == .touchID ? "Touch ID" : "Face ID"
    }
    private var canBiometric: Bool { BiometricAuthService.canAuthenticate() }
    private var locAuthorized: Bool {
        app.locationAuthStatus == .authorizedWhenInUse || app.locationAuthStatus == .authorizedAlways
    }
    private var locBlocked: Bool {
        app.locationAuthStatus == .denied || app.locationAuthStatus == .restricted
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OnboardingStepIndicator(step: 1)
                Text(app.T("Xem nhanh cài đặt", "Quick settings review"))
                    .font(BanbeTheme.display(27))
                Text(app.T("Tất cả đều không bắt buộc, bạn có thể đổi lại bất cứ lúc nào trong Tài khoản.",
                           "Everything here is optional, you can change it any time in Account."))
                    .font(.system(size: 13.5)).lineSpacing(3).padding(.top, 10)

                VStack(spacing: 10) {
                    switchRow(app.T("Rung phản hồi", "Haptic feedback"),
                              app.T("Rung nhẹ khi bạn chạm.", "A light tap when you press things."),
                              on: haptics, id: "onboarding.settings.haptics") { haptics.toggle() }
                    switchRow(app.T("Gửi hoá đơn qua email", "Email me payment documents"),
                              app.T("Tự gửi hoá đơn/biên nhận tới email của bạn.",
                                    "Automatically email invoices and receipts to you."),
                              on: emailDocs, id: "onboarding.settings.emailDocs") { emailDocs.toggle() }
                    switchRow(app.T("Tin nhắn quảng bá từ host", "Host promotional texts"),
                              app.T("Bật mặc định cho tài khoản mới. Host bạn đã tương tác có thể soạn tin quảng bá SMS, host tự gửi; banbe không gửi hộ. Nhấn Tiếp tục là bạn đồng ý; tắt công tắc nếu không muốn. Đổi lại bất cứ lúc nào tại Tài khoản > Bảo mật.",
                                    "On by default for new accounts. Hosts you've interacted with may compose a promo text that they send themselves; banbe doesn't send for them. Tapping Continue records your agreement, switch it off if you don't want this. Change it any time in Account > Security."),
                              on: promo, id: "onboarding.settings.promo") { promo.toggle() }
                    .disabled(app.hostPromoConsent == nil)
                }
                .padding(.top, 22)

                recommendedSection.padding(.top, 26)

                if failed {
                    Text(app.T("Chưa hoàn tất được bước này. Thử lại, hoặc bỏ qua lúc này (bước này có thể hiện lại lần mở sau).",
                               "Couldn't finish this step. Retry, or skip for now (it may reappear next time you open the app)."))
                        .font(.system(size: 12)).foregroundStyle(BanbeTheme.alert).padding(.top, 16)
                }

                InkButton(title: busy ? app.T("Đang lưu…", "Saving…")
                                      : failed ? app.T("Thử lại", "Retry") : app.T("Tiếp tục", "Continue"),
                          enabled: !busy) { Task { await finish() } }
                    .accessibilityIdentifier("onboarding.settings.continue")
                    .padding(.top, 22)

                if failed {
                    Button { app.needsSettingsOnboarding = false } label: {
                        Text(app.T("Bỏ qua lúc này", "Skip for now"))
                            .font(.system(size: 13, weight: .semibold)).underline()
                            .frame(maxWidth: .infinity).padding(.top, 14)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("onboarding.settings.skip")
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 30).padding(.top, 60).padding(.bottom, 42)
        }
        .task {
            guard !seeded else { return }
            seeded = true
            await app.loadHostPromoConsent()
            // New account: ordinary non-sensitive settings default ON. An existing
            // account shows and keeps what it already has — never overwritten.
            let isNew = app.eventOnboardingIsNewAccount
            haptics = isNew ? true : hapticsStored
            emailDocs = isNew ? true : app.autoEmailDocuments
            // Existing prompted accounts keep their CURRENT consent/choices.
            promo = isNew ? true : (app.hostPromoConsent ?? false)
            faceOn = canBiometric && (isNew ? true : auth.faceIDEnabled)
            locOn = isNew ? true : (app.located == true)
        }
        .sheet(isPresented: $areaPickerOpen) { LocationPickerSheet(isPresented: $areaPickerOpen) }
    }

    // MARK: recommended features

    private var recommendedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(app.T("Tính năng gợi ý", "Recommended features"))
                .font(.system(size: 11.5, weight: .semibold))
            Text(app.T("Bật sẵn cho bạn; tắt nếu không muốn. Hệ thống sẽ hỏi quyền khi bạn nhấn Tiếp tục. Vị trí chỉ dùng để hiện khoảng cách, không lưu và không chia sẻ với host.",
                       "On for you by default; switch off any you don't want. iOS will ask for permission when you tap Continue. Location is only used for distances, not stored or shared with hosts."))
                .font(.system(size: 12)).lineSpacing(3).foregroundStyle(app.palette.ink.opacity(0.75))

            VStack(spacing: 10) {
                switchRow(app.T("Mở khoá bằng \(biometryName)", "Unlock with \(biometryName)"),
                          canBiometric
                            ? app.T("Hỏi \(biometryName) mỗi lần mở lại ứng dụng. Chỉ lưu trên máy này.",
                                    "Ask for \(biometryName) each time you return. Stored on this device only.")
                            : app.T("Không khả dụng trên thiết bị này (chưa cài đặt hoặc không hỗ trợ).",
                                    "Unavailable on this device (not set up or unsupported)."),
                          on: faceOn && canBiometric, id: "onboarding.settings.faceID") { faceOn.toggle() }
                    .disabled(!canBiometric)
                switchRow(app.T("Vị trí", "Location"), locationStatusText,
                          on: locOn, id: "onboarding.settings.location") { locOn.toggle() }
            }
            if !faceIDMessage.isEmpty {
                Text(faceIDMessage).font(.system(size: 12)).foregroundStyle(BanbeTheme.alert)
            }

            if locBlocked {
                HStack(spacing: 18) {
                    Button { LocationService.openSettings() } label: {
                        Text(app.T("Mở Cài đặt", "Open Settings")).font(.system(size: 12.5, weight: .semibold)).underline()
                    }
                    .accessibilityIdentifier("onboarding.settings.openSettings")
                    Button { areaPickerOpen = true } label: {
                        Text(app.T("Chọn khu vực thủ công", "Choose an area manually"))
                            .font(.system(size: 12.5, weight: .semibold)).underline()
                    }
                    .accessibilityIdentifier("onboarding.settings.pickArea")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var locationStatusText: String {
        switch app.locationAuthStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return app.T("Chỉ dùng để hiện khoảng cách sự kiện.", "Only used to show event distances.")
        case .denied: return app.T("Đã bị từ chối trong Cài đặt, bạn có thể chọn khu vực thủ công.", "Denied in Settings, you can pick an area manually.")
        case .restricted: return app.T("Bị hạn chế trên thiết bị này, hãy chọn khu vực thủ công.", "Restricted on this device, pick an area manually.")
        default: return app.T("Hiện khoảng cách tới sự kiện gần bạn.", "Shows how far events are from you.")
        }
    }

    private func statusLine(_ text: String, ok: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle").font(.system(size: 13))
            Text(text).font(.system(size: 12.5))
        }
    }

    private func switchRow(_ title: String, _ detail: String, on: Bool, id: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(BanbeTheme.display(16))
                    Text(detail).font(.system(size: 11.5)).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                ZStack(alignment: on ? .trailing : .leading) {
                    Capsule().fill(on ? app.palette.ink : app.palette.ink.opacity(0.18)).frame(width: 44, height: 26)
                    Circle().fill(app.palette.paper).frame(width: 20, height: 20).padding(3)
                }
                .animation(.easeInOut(duration: 0.15), value: on)
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 18).padding(.vertical, 15)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(on ? app.T("Bật", "On") : app.T("Tắt", "Off"))
        .accessibilityIdentifier(id)
    }

    // MARK: actions

    /// Face ID and location are asked separately; each is shown/persisted only
    /// when the system actually granted it. Both are device-local choices.
    private func applyRecommended() async {
        faceIDMessage = ""
        if canBiometric {
            if faceOn && !auth.faceIDEnabled {
                let ok = await auth.setFaceIDEnabled(
                    true,
                    reason: app.T("Xác nhận để bật khoá \(biometryName) cho banbe.",
                                  "Confirm to turn on \(biometryName) for banbe."))
                if !ok {
                    faceIDMessage = app.T("Chưa bật được \(biometryName). Bạn có thể bật sau trong Tài khoản > Bảo mật.",
                                          "Couldn't turn on \(biometryName). You can enable it later in Account > Security.")
                }
            } else if !faceOn && auth.faceIDEnabled {
                _ = await auth.setFaceIDEnabled(false, reason: "")
            }
        }
        if locOn {
            let status = await requester.requestWhenInUse()
            // Persist "located" only once the OS actually granted access.
            if (status == .authorizedWhenInUse || status == .authorizedAlways) && app.located != true { app.allowLocation() }
        } else if app.located == true {
            app.denyLocation()
        }
    }

    private func finish() async {
        busy = true
        defer { busy = false }
        // Write a setting only when the final toggle differs from its current value.
        if haptics != hapticsStored { hapticsStored = haptics }
        if emailDocs != app.autoEmailDocuments { app.toggleAutoEmailDocuments() }
        if promo != (app.hostPromoConsent ?? false) { _ = await app.setHostPromoConsent(promo) }
        await applyRecommended()
        failed = !(await app.completeSettingsOnboarding())
    }
}

private struct EventQuestionsStep: View {
    @EnvironmentObject var app: AppState

    @State private var draft = EventPreferences()
    @State private var region = BudgetRegion.deviceDefault()
    @State private var busy = false
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OnboardingStepIndicator(step: app.needsSettingsOnboarding ? 1 : 2)
                Text(app.T("Vài câu hỏi nhanh", "A few quick questions"))
                    .font(BanbeTheme.display(27))
                Text(app.T("Giúp chúng tôi gợi ý sự kiện hợp với bạn. Bỏ qua câu nào cũng được.",
                           "Helps us suggest events you'll like. Skip any question you like."))
                    .font(.system(size: 13.5)).lineSpacing(3).padding(.top, 10)

                EventPreferencesForm(prefs: $draft, region: $region).padding(.top, 24)
                EventPrefsPrivacyNote().padding(.top, 22)

                if failed {
                    Text(app.T("Chưa lưu được. Thử lại, hoặc bỏ qua lúc này (bước này có thể hiện lại lần mở sau).",
                               "Couldn't save. Retry, or skip for now (this step may reappear next time you open the app)."))
                        .font(.system(size: 12)).foregroundStyle(BanbeTheme.alert).padding(.top, 14)
                }

                InkButton(title: busy ? app.T("Đang lưu…", "Saving…")
                                      : failed ? app.T("Thử lại", "Retry") : app.T("Hoàn tất", "Finish"),
                          enabled: !busy) { Task { await complete(skipAll: false) } }
                    .accessibilityIdentifier("onboarding.prefs.finish")
                    .padding(.top, 20)

                Button {
                    if failed { app.needsPreferencesOnboarding = false } else { Task { await complete(skipAll: true) } }
                } label: {
                    Text(failed ? app.T("Bỏ qua lúc này", "Skip for now") : app.T("Bỏ qua tất cả", "Skip all"))
                        .font(.system(size: 13, weight: .semibold)).underline()
                        .frame(maxWidth: .infinity).padding(.top, 14)
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .accessibilityIdentifier("onboarding.prefs.skip")
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 30).padding(.top, 60).padding(.bottom, 42)
        }
    }

    private func complete(skipAll: Bool) async {
        busy = true
        defer { busy = false }
        let answered = draft.normalizedForSave()
        let ok = await app.completePreferencesOnboarding(skipAll || answered.isEmpty ? nil : draft)
        failed = !ok
    }
}
