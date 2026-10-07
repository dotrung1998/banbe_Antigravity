import SwiftUI
import Supabase

// Host "Reservation criteria" picker + guest unmet-criteria card (migration 162).
// Criteria are self-declared interests/goals ONLY; hosts never see guest answers.

private struct CriteriaRow: Decodable {
    let reservationCriteria: ReservationCriteria?
    enum CodingKeys: String, CodingKey { case reservationCriteria = "reservation_criteria" }
}

extension AppState {
    /// Small per-event read (kept out of shared select lists so pre-migration
    /// clients/servers are unaffected). nil = unavailable (column missing etc.).
    func fetchEventCriteria(eventKey: String) async -> ReservationCriteria? {
        do {
            let rows: [CriteriaRow] = try await SupabaseService.client
                .from("events").select("reservation_criteria")
                .eq("id", value: eventKey).limit(1).execute().value
            return rows.first?.reservationCriteria
        } catch { return nil }
    }

    func loadEventCriteria(eventKey: String) async {
        guard let c = await fetchEventCriteria(eventKey: eventKey) else { return }
        eventCriteriaByKey[eventKey] = c
    }

    /// Re-checks the caller against the event's criteria. Everyone events and
    /// older servers (checker returns nil) stay unblocked.
    func recheckReservationEligibility(eventKey: String) async {
        reserveEligibilityChecking = true
        let r = await checkReservationEligibility(eventKey: eventKey)
        guard self.eventKey == eventKey else { reserveEligibilityChecking = false; return }
        reserveEligibilityBlock = (r?.eligible == false) ? r : nil
        reserveEligibilityChecking = false
    }
}

/// Host picker used inside CreateEventView.
struct ReservationCriteriaPicker: View {
    @EnvironmentObject var app: AppState

    private var declared: Bool { app.createCriteria.mode == "declared" }
    private var hasValues: Bool {
        !(app.createCriteria.interests?.values.isEmpty ?? true) || !(app.createCriteria.goals?.values.isEmpty ?? true)
    }

    private func setMode(_ declared: Bool) {
        app.createCriteria.mode = declared ? "declared" : "everyone"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(app.T("Điều kiện đặt chỗ", "Reservation criteria")).font(.system(size: 11.5))
            HStack(spacing: 8) {
                modeButton(app.T("Mọi người", "Everyone"), active: !declared, id: "everyone") { setMode(false) }
                modeButton(app.T("Người đã khai báo…", "Only people who declare…"), active: declared, id: "declared") { setMode(true) }
            }
            .accessibilityIdentifier("create.criteria.mode")
            if declared {
                group(title: app.T("Sở thích", "Interests"), options: EventPrefTaxonomy.interests, kind: "interests")
                group(title: app.T("Mục tiêu", "Goals"), options: EventPrefTaxonomy.goals, kind: "goals")
                if !hasValues {
                    Text(app.T("Chọn ít nhất một mục ở một nhóm, nếu không sự kiện sẽ mở cho mọi người.",
                               "Pick at least one item in a group, otherwise the event stays open to everyone."))
                        .font(.system(size: 11)).foregroundStyle(BanbeTheme.alert)
                        .accessibilityIdentifier("create.criteria.emptyHint")
                }
                Text(app.T("Đây là sở thích do khách tự khai, không được xác minh và khách có thể chỉnh sửa. Không dùng cho ngân sách, lịch, ngôn ngữ, độ tuổi hay thông tin cá nhân.",
                           "These are self-declared preferences, not verified, and guests can edit them. Not used for budget, schedule, language, age or personal traits."))
                    .font(.system(size: 11)).opacity(0.6)
            }
            Text(app.T("Ai được đặt chỗ: ", "Who can reserve: ") + app.createCriteria.normalizedForSave().summary(vi: !app.isEN))
                .font(.system(size: 11.5, weight: .semibold))
                .accessibilityIdentifier("create.criteria.summary")
        }
        .foregroundStyle(app.palette.ink)
    }

    private func modeButton(_ label: String, active: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 13)).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(active ? app.palette.ink : .clear, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(active ? app.palette.paper : app.palette.ink)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(active ? .clear : app.palette.rule))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("create.criteria.mode.\(id)")
    }

    private func group(title: String, options: [PrefOption], kind: String) -> some View {
        let isInterests = kind == "interests"
        let current = isInterests ? app.createCriteria.interests : app.createCriteria.goals
        let rule = current?.rule ?? "any"
        let values = current?.values ?? []
        func write(_ g: CriteriaGroup) {
            if isInterests { app.createCriteria.interests = g } else { app.createCriteria.goals = g }
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .semibold))
            HStack(spacing: 8) {
                ForEach([("any", "Một trong các mục này", "Any of these"), ("all", "Tất cả các mục này", "All of these")], id: \.0) { key, vi, en in
                    let active = rule == key
                    Button { write(CriteriaGroup(rule: key, values: values)) } label: {
                        Text(app.T(vi, en)).font(.system(size: 12))
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background(active ? app.palette.ink.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(app.palette.rule))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("create.criteria.\(kind).rule.\(key)")
                }
            }
            Text(rule == "all"
                 ? app.T("Khách phải đã khai báo mọi mục bạn chọn.", "Guests must have declared every item you pick.")
                 : app.T("Khách chỉ cần đã khai báo ít nhất một mục bạn chọn.", "Guests need to have declared at least one item you pick."))
                .font(.system(size: 11)).opacity(0.6)
            FlowRow(spacing: 8) {
                ForEach(options) { opt in
                    let on = values.contains(opt.id)
                    Button {
                        var v = values
                        if on { v.removeAll { $0 == opt.id } } else { v.append(opt.id) }
                        write(CriteriaGroup(rule: rule, values: v))
                    } label: {
                        Text(app.T(opt.vi, opt.en)).font(.system(size: 13))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(on ? app.palette.ink : .clear, in: Capsule())
                            .foregroundStyle(on ? app.palette.paper : app.palette.ink)
                            .overlay(Capsule().stroke(on ? .clear : app.palette.rule))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("create.criteria.\(kind).\(opt.id)")
                }
            }
        }
    }
}

/// Guest-facing card: exact missing items + a way to edit preferences.
struct CriteriaUnmetCard: View {
    @EnvironmentObject var app: AppState
    let eligibility: ReservationEligibility
    let returnTo: Screen
    let idPrefix: String

    var body: some View {
        let vi = !app.isEN
        VStack(alignment: .leading, spacing: 8) {
            Text(app.T("Sự kiện này dành cho người đã khai báo sở thích phù hợp.",
                       "This event is for people who declared matching preferences."))
                .font(.system(size: 13.5, weight: .semibold))
            if let c = app.eventCriteriaByKey[app.eventKey], !c.isEveryone {
                Text(app.T("Ai được đặt chỗ: ", "Who can reserve: ") + c.summary(vi: vi)).font(.system(size: 12))
            }
            ForEach(eligibility.guidance(vi: vi), id: \.self) { line in
                Text("• " + line).font(.system(size: 12.5))
            }
            Text(app.T("Bạn tự chỉnh và lưu sở thích, banbe không tự thay đổi gì.",
                       "You edit and save your preferences yourself, nothing is changed for you."))
                .font(.system(size: 11)).opacity(0.65)
            InkButton(title: app.T("Cập nhật sở thích", "Update my preferences"), cornerRadius: 999) {
                app.openEventPreferences(returnTo: returnTo)
            }
            .accessibilityIdentifier("\(idPrefix).criteria.updatePrefs")
        }
        .foregroundStyle(app.palette.ink)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("\(idPrefix).criteria.card")
    }
}
