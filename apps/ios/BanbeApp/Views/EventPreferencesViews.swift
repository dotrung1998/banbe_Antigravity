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
            Text(title).font(.app(size: 13.5, weight: .semibold))
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
                    .font(.app(size: 13.5, weight: .semibold))
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
                .font(.app(size: 11.5))
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
                .font(.app(size: compact ? 11.5 : 13, weight: selected ? .semibold : .regular))
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
            .font(.app(size: 11.5))
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
                    .font(.app(size: 13.5))
                    .lineSpacing(3)
                    .padding(.top, 10)

                EventPreferencesForm(prefs: $draft, region: $region)
                    .padding(.top, 24)
                    .onChange(of: draft) { _, _ in saved = false; failed = false }

                EventPrefsPrivacyNote().padding(.top, 22)

                if failed {
                    Text(app.T("Chưa lưu được. Vui lòng thử lại.", "Couldn't save. Please try again."))
                        .font(.app(size: 12)).foregroundStyle(BanbeTheme.alert).padding(.top, 14)
                } else if saved {
                    Text(app.T("Đã lưu sở thích.", "Preferences saved."))
                        .font(.app(size: 12)).padding(.top, 14)
                }

                // Note 64: stay-and-update from Settings; navigate (back to the reservation) after the ✓ from there.
                AsyncSuccessButton(title: fromReservation ? app.T("Lưu và quay lại", "Save and go back") : app.T("Lưu", "Save"),
                                   enabled: changed || fromReservation,
                                   pendingLabel: app.T("Đang lưu…", "Saving…"), successLabel: app.T("Đã lưu", "Saved"),
                                   resetAfterSuccess: !fromReservation, identifier: "prefs.save",
                                   run: { await save() ? .success : .failure() },
                                   onSuccessAnimationComplete: fromReservation ? { app.goBack() } : nil)
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

    /// True when saved (or nothing to save). Going back is the button's job, after its ✓.
    private func save() async -> Bool {
        saved = false; failed = false
        if !changed { return true }
        if await app.saveEventPreferences(draft) {
            baseline = draft
            saved = true
            return true
        }
        failed = true
        return false
    }
}

