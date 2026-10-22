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
        selection.wrappedValue = PrefSelection.toggle(selection.wrappedValue, id)
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
        prefs.budget = PrefSelection.pickBudget(prefs.budget, tier: tier, region: region)
    }

    private func setRegion(_ r: BudgetRegion) {
        region = r
        prefs.budget = PrefSelection.switchRegion(prefs.budget, to: r)
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
struct EventPrefsPrivacyNote: View {
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


// MARK: - Onboarding settings step

/// The short account-settings review that follows the personalization story
/// (only when the server still owes it). It writes a setting only when the
/// final value differs from the current one, then marks
/// `complete_settings_onboarding` — the same contract as before.
///
/// Face ID and location are no longer asked here: Face ID is offered in the
/// Home activation checklist and Account > Security (still device-local),
/// location when Map or the area picker first needs it. The promotional-texts
/// row starts OFF and is written only when the person switches it on (note 48,
/// resolving note 43's open consent decision): silence is not consent, and the
/// server's own default (migration 123) is already OFF.
struct OnboardingSettingsStep: View {
    @EnvironmentObject var app: AppState
    @AppStorage(Haptics.defaultsKey) private var hapticsStored = true
    let onDone: () -> Void

    @State private var haptics = true
    @State private var emailDocs = false
    @State private var promo = false
    @State private var seeded = false
    @State private var busy = false
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(app.T("Một chút cài đặt cuối", "A few last settings"))
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("onboarding.settings")
                Text(app.T("Không bắt buộc, đổi lại bất cứ lúc nào trong Tài khoản.",
                           "Optional, change them any time in Account."))
                    .font(.subheadline).lineSpacing(3).padding(.top, 8)
                    .foregroundStyle(app.palette.ink.opacity(0.75))

                VStack(spacing: 10) {
                    switchRow(app.T("Rung phản hồi", "Haptic feedback"),
                              app.T("Rung nhẹ khi bạn chạm.", "A light tap when you press things."),
                              on: haptics, id: "onboarding.settings.haptics") { haptics.toggle() }
                    switchRow(app.T("Gửi hoá đơn qua email", "Email me payment documents"),
                              app.T("Tự gửi hoá đơn/biên nhận tới email của bạn.",
                                    "Automatically email invoices and receipts to you."),
                              on: emailDocs, id: "onboarding.settings.emailDocs") { emailDocs.toggle() }
                }
                .padding(.top, 22)

                // A separate decision, visually and semantically apart from the
                // convenience toggles above.
                Text(app.T("Liên lạc quảng bá", "Promotional messages"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(app.palette.ink.opacity(0.7))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 26)
                switchRow(app.T("Tin nhắn quảng bá từ host", "Host promotional texts"),
                          app.T("Tắt trừ khi bạn bật. Nếu bật, host bạn đã tương tác có thể soạn tin quảng bá SMS và tự gửi. banbe không gửi hộ. Đổi lại bất cứ lúc nào tại Tài khoản > Bảo mật.",
                                "Off unless you switch it on. If on, hosts you've interacted with may compose a promo text that they send themselves. banbe doesn't send for them. Change it any time in Account > Security."),
                          on: promo, id: "onboarding.settings.promo") { promo.toggle() }
                    .disabled(app.hostPromoConsent == nil)
                    .padding(.top, 10)

                if failed {
                    Label(app.T("Chưa hoàn tất được bước này. Thử lại, hoặc bỏ qua lúc này (bước này có thể hiện lại lần mở sau).",
                                "Couldn't finish this step. Retry, or skip for now (it may reappear next time you open the app)."),
                          systemImage: "exclamationmark.circle")
                        .font(.footnote).foregroundStyle(BanbeTheme.alert).padding(.top, 16)
                }

                InkButton(title: busy ? app.T("Đang lưu…", "Saving…")
                                      : failed ? app.T("Thử lại", "Retry") : app.T("Tiếp tục", "Continue"),
                          enabled: !busy) { Task { await finish() } }
                    .accessibilityIdentifier("onboarding.settings.continue")
                    .padding(.top, 22)

                if failed {
                    Button {
                        // Session-only: the server marker stays unset.
                        app.needsSettingsOnboarding = false
                        onDone()
                    } label: {
                        Text(app.T("Bỏ qua lúc này", "Skip for now"))
                            .font(.subheadline.weight(.semibold)).underline()
                            .frame(maxWidth: .infinity, minHeight: 44).padding(.top, 6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("onboarding.settings.skip")
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 24).padding(.top, 40).padding(.bottom, 42)
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
            // Consent is never pre-ticked: new accounts start OFF, existing
            // accounts show their CURRENT stored choice.
            promo = isNew ? false : (app.hostPromoConsent ?? false)
        }
    }

    private func switchRow(_ title: String, _ detail: String, on: Bool, id: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(.headline, design: .rounded))
                    Text(detail).font(.footnote).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                ZStack(alignment: on ? .trailing : .leading) {
                    Capsule().fill(on ? app.palette.ink : app.palette.ink.opacity(0.18)).frame(width: 44, height: 26)
                    Circle().fill(app.palette.paper).frame(width: 20, height: 20).padding(3)
                }
                .animation(.easeInOut(duration: 0.15), value: on)
                .accessibilityHidden(true)
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 18).padding(.vertical, 15)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(on ? app.T("Bật", "On") : app.T("Tắt", "Off"))
        .accessibilityIdentifier(id)
    }

    private func finish() async {
        busy = true
        defer { busy = false }
        // Write a setting only when the final toggle differs from its current value.
        if haptics != hapticsStored { hapticsStored = haptics }
        if emailDocs != app.autoEmailDocuments { app.toggleAutoEmailDocuments() }
        // Only write consent when the current value actually loaded (the row is
        // disabled otherwise) and the person changed it.
        if let current = app.hostPromoConsent, promo != current { _ = await app.setHostPromoConsent(promo) }
        if await app.completeSettingsOnboarding() {
            failed = false
            onDone()
        } else {
            failed = true
        }
    }
}
