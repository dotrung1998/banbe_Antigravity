import SwiftUI

/// Account > Rewards & badges. Private to the signed-in account; every number is server-computed
/// (migration 165). Coins are cosmetic only and never affect booking, priority or eligibility.
struct RewardsView: View {
    @EnvironmentObject var app: AppState
    @State private var confirmItem: RewardsPayload.Item?
    /// One celebration at a time (badge earned, week milestone, redeem). `n` re-triggers the confetti.
    @State private var celebration: (title: String, sub: String, n: Int)?
    @State private var celebrationTask: Task<Void, Never>?
    @State private var goalBusy = false
    @State private var goalError = ""

    private var manifest: KeychainManifest? { KeychainManifest.bundled }
    private func name(_ designID: String) -> String {
        guard let d = manifest?.design(designID) else { return designID }
        return app.isEN ? d.en : d.vi
    }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.rewardsBackScreen == .home ? app.T("Trang chủ", "Home") : app.T("Tài khoản", "Account")) { app.goBack() }
                Text(app.T("Phần thưởng & huy hiệu", "Rewards & Badges"))
                    .font(BanbeTheme.display(27)).padding(.top, 16)
                    .accessibilityAddTraits(.isHeader)
                Text(app.T("Chỉ mình bạn thấy trang này. Huy hiệu và lịch sử không hiển thị công khai.",
                           "Only you can see this page. Badges and history are never shown publicly."))
                    .font(.system(size: 13)).opacity(0.75).padding(.top, 8)

                switch app.rewardsStatus {
                case .unavailable:
                    note(app.T("Phần thưởng chưa khả dụng. Vui lòng quay lại sau.", "Rewards aren't available yet. Please check back later."))
                        .padding(.top, 16).accessibilityIdentifier("rewards.unavailable")
                case .error:
                    VStack(alignment: .leading, spacing: 8) {
                        Text(app.T("Không tải được phần thưởng.", "Couldn't load your rewards.")).font(.system(size: 13)).foregroundStyle(BanbeTheme.alert)
                        Button { Task { await app.loadRewards() } } label: {
                            Text(app.T("Thử lại", "Retry")).font(.system(size: 13, weight: .semibold)).underline()
                        }.buttonStyle(.plain).accessibilityIdentifier("rewards.retry")
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous)).padding(.top, 16)
                default: EmptyView()
                }

                if let r = app.rewards {
                    content(r)
                } else if app.rewardsStatus == .loading || app.rewardsStatus == .idle {
                    HStack { Spacer(); ProgressView(); Spacer() }.padding(.top, 28).accessibilityIdentifier("rewards.loading")
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 42)
        }
        .task { await app.loadRewards() }
        .overlay(alignment: .top) { celebrationCard }
        .onChange(of: app.rewards) { _, r in if let r { celebrateIfNew(r) } }
        .onChange(of: app.rewardsRedeemResult) { _, res in
            if let res, res.ok, !res.already {
                celebrate(app.T("Đã mở khoá!", "Unlocked!"), app.T("Mẫu móc khoá mới đã sẵn sàng.", "Your new keychain design is ready."))
            }
        }
        .alert(app.T("Đổi phần thưởng?", "Redeem this reward?"), isPresented: Binding(get: { confirmItem != nil }, set: { if !$0 { confirmItem = nil } })) {
            Button(app.T("Huỷ", "Cancel"), role: .cancel) { confirmItem = nil }
            Button(app.T("Đổi", "Redeem")) {
                guard let item = confirmItem else { return }
                confirmItem = nil
                Task { await app.redeemReward(item.code) }
            }
        } message: {
            if let item = confirmItem {
                Text(app.T("Dùng \(item.price) xu để mở khoá \"\(name(item.designId))\". Việc này không thể hoàn tác và không đổi lại thành tiền.",
                           "Spend \(item.price) coins to unlock \"\(name(item.designId))\". This can't be undone and isn't refundable as cash."))
            }
        }
    }

    // MARK: Celebrations (Phase 0, peak moment): once per account per device; the first visit on a device only
    // remembers what is already earned. Reduced motion: ConfettiBurst renders nothing, the card still says it.
    @ViewBuilder private var celebrationCard: some View {
        if let c = celebration {
            VStack(spacing: 2) {
                Text(c.title).font(BanbeTheme.display(18))
                if !c.sub.isEmpty { Text(c.sub).font(.system(size: 12.5)).opacity(0.8) }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18).padding(.vertical, 14).frame(maxWidth: 340)
            .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(app.palette.rule))
            .shadow(color: .black.opacity(0.18), radius: 15, y: 10)
            .overlay(alignment: .top) { ConfettiBurst().id(c.n).padding(.top, 10) }
            .foregroundStyle(app.palette.ink)
            .padding(.top, 84).padding(.horizontal, 16)
            .transition(.opacity.combined(with: .move(edge: .top)))
            .onTapGesture { celebration = nil }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
            .accessibilityIdentifier("rewards.celebration")
        }
    }

    private func celebrate(_ title: String, _ sub: String) {
        Haptics.success()
        withAnimation(.easeOut(duration: 0.3)) { celebration = (title, sub, (celebration?.n ?? 0) + 1) }
        UIAccessibility.post(notification: .announcement, argument: "\(title) \(sub)")
        celebrationTask?.cancel()
        celebrationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_600_000_000)
            if !Task.isCancelled { withAnimation(.easeIn(duration: 0.25)) { celebration = nil } }
        }
    }

    private func celebrateIfNew(_ r: RewardsPayload) {
        guard let uid = app.userID?.uuidString, app.rewardsStatus == .loaded else { return }
        let week = app.rewardsV2Enabled ? r.weekStreak : nil
        let diff = RewardsLogic.celebrationDiff(badges: r.badges, week: week, celebrated: RewardsLogic.readCelebrated(uid))
        RewardsLogic.writeCelebrated(uid, diff.keys)
        guard let first = diff.show.first else { return }
        switch first {
        case .badge(let code):
            let b = r.badges.first { $0.code == code }
            celebrate(app.T("Huy hiệu mới!", "New badge!"), b.map { app.isEN ? $0.titleEn : $0.titleVi } ?? "")
            Analytics.track(.rewardsBadgeCelebrated(code: code))
        case .weeks(let n):
            celebrate(app.T("Chuỗi \(n) tuần!", "\(n)-week streak!"), app.T("Bạn đã ra ngoài đều đặn. Tuyệt!", "You've kept showing up. Nice!"))
            Analytics.track(.rewardsWeekMilestone(weeks: n))
        }
    }

    private func note(_ s: String) -> some View {
        Text(s).font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func content(_ r: RewardsPayload) -> some View {
        // Balance + streak
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(app.T("Số dư xu", "Coin balance")).font(.system(size: 11.5)).opacity(0.7)
                Text("\(r.balance)").font(BanbeTheme.display(30))
                if r.balance < 0 {
                    Text(app.T("Số dư âm do điểm danh bị huỷ. Kiếm thêm để về 0.", "Negative because a check-in was undone. Earn coins to get back to 0."))
                        .font(.system(size: 11)).opacity(0.7)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(16)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(app.T("Số dư \(r.balance) xu", "Balance \(r.balance) coins"))
            .accessibilityIdentifier("rewards.balance")

            if app.rewardsV2Enabled, let ws = r.weekStreak {
                weekStreakCard(ws)
            } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(app.T("Chuỗi ngày", "Streak")).font(.system(size: 11.5)).opacity(0.7)
                HStack(spacing: 6) { Text("🔥").accessibilityHidden(true); Text("\(r.streak.current)") }.font(BanbeTheme.display(30))
                Text(app.T("Dài nhất: \(r.streak.longest) ngày", "Longest: \(r.streak.longest) days")).font(.system(size: 11)).opacity(0.7)
                let today = r.streak.activeToday == true
                Text(today ? app.T("✓ Hôm nay đã được tính", "✓ Today's counted") : app.T("Hôm nay chưa được tính", "Today isn't counted yet"))
                    .font(.system(size: 11.5, weight: .semibold)).padding(.top, 6)
                    .accessibilityIdentifier("rewards.streak.status")
                Text(today ? app.T("Quay lại ngày mai để giữ chuỗi.", "Come back tomorrow to keep it going.")
                           : app.T("Lưu 1 sự kiện hoặc đi 1 sự kiện để được +1 ngày. Chỉ mở app thì chưa tính.", "Save an event or attend one to earn +1 day. Just opening the app does not count."))
                    .font(.system(size: 11)).lineSpacing(2).opacity(0.75)
                    .accessibilityIdentifier("rewards.streak.how")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(16)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(app.T("Chuỗi \(r.streak.current) ngày, dài nhất \(r.streak.longest)", "\(r.streak.current)-day streak, longest \(r.streak.longest)"))
            .accessibilityIdentifier("rewards.streak")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 16)

        if app.rewardsV2Enabled, let nb = r.nextBadge { nextBadgeCard(nb).padding(.top, 12) }
        if app.rewardsV2Enabled, let g = r.goal { goalCard(g).padding(.top, 12) }

        section(app.T("Huy hiệu", "Badges")) {
            if app.rewardsV2Enabled {
                VStack(spacing: 8) { ForEach(RewardsLogic.groupBadgesByFamily(r.badges)) { familyCard($0) } }
            } else {
                VStack(spacing: 8) { ForEach(r.badges) { badge($0) } }
            }
        }

        section(app.T("Trang trí (móc khoá)", "Decorations (keychain designs)")) {
            Text(app.T("Tuỳ chọn, chỉ để trang trí. 24 mẫu miễn phí vẫn luôn dùng được.", "Optional and cosmetic only. The 24 free charms always stay available."))
                .font(.system(size: 12)).opacity(0.75).padding(.bottom, 4)
            if let res = app.rewardsRedeemResult {
                if !res.ok {
                    Text(RewardsLogic.redeemErrorMessage(res.error, T: app.T)).font(.system(size: 12.5)).foregroundStyle(BanbeTheme.alert)
                        .accessibilityIdentifier("rewards.redeemError")
                } else if !res.already {
                    Text(app.T("Đã mở khoá!", "Unlocked!")).font(.system(size: 12.5)).accessibilityIdentifier("rewards.redeemOk")
                }
            }
            VStack(spacing: 8) { ForEach(r.catalog) { catalogRow($0, balance: r.balance) } }
        }

        if RewardsLogic.showsOffersSection(r) {
            section(app.T("Ưu đãi", "Offers")) {
                Text(app.T("Ưu đãi do đối tác cung cấp. Hiện chưa thể đổi.", "Offers come from partners. They cannot be redeemed yet."))
                    .font(.system(size: 12)).opacity(0.75).padding(.bottom, 4)
                VStack(spacing: 8) { ForEach(r.offers) { offerRow($0) } }
            }
            .accessibilityIdentifier("rewards.offers")
        }

        section(app.T("Lịch sử gần đây", "Recent history")) {
            if r.history.isEmpty {
                note(app.T("Chưa có hoạt động nào. Tham dự một sự kiện để bắt đầu.", "No activity yet. Attend an event to get started."))
                    .accessibilityIdentifier("rewards.historyEmpty")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(r.history.enumerated()), id: \.element.id) { i, h in
                        historyRow(h)
                        if i < r.history.count - 1 { Divider().overlay(app.palette.rule) }
                    }
                }
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }

        if let tz = r.timezoneSettings { timezoneSection(tz) }

        section(app.T("Cách kiếm xu", "How earning works")) {
            let weekly = app.rewardsV2Enabled && r.weekStreak != nil
            bullets(RewardsLogic.ruleLines(r.rules, T: app.T) + RewardsLogic.noCoinLines(T: app.T)
                    + (weekly ? RewardsLogic.weekStreakLines(r.weekStreak, T: app.T) : RewardsLogic.streakLines(tz: r.streak.timezone, T: app.T)))
            Text(app.T("Điều kiện đổi thưởng", "Redemption terms")).font(.system(size: 13, weight: .semibold)).padding(.top, 12)
            bullets(RewardsLogic.termsLines(weekly: weekly, T: app.T))
            Text(app.T("Phiên bản quy tắc \(r.rules.version ?? 1). Các con số là đề xuất MVP và có thể thay đổi. Mọi thay đổi có số phiên bản mới.",
                       "Rules version \(r.rules.version ?? 1). Numbers are an MVP proposal and may change. Any change gets a new version."))
                .font(.system(size: 11)).opacity(0.6).padding(.top, 10)
        }
    }

    @State private var tzBusy = false
    @State private var tzError = ""

    @ViewBuilder private func timezoneSection(_ tz: RewardsPayload.TimezoneSettings) -> some View {
        let current = tz.pendingTz ?? tz.effectiveTz
        let hint = RewardsLogic.deviceTimezoneHint()
        let options = RewardsLogic.suggestedTimezones.map { ($0.id, app.T($0.vi, $0.en)) }
            + (RewardsLogic.suggestedTimezones.contains { $0.id == tz.effectiveTz } ? [] : [(tz.effectiveTz, tz.effectiveTz)])
        section(app.T("Múi giờ cho chuỗi ngày", "Time zone for streak days")) {
            VStack(alignment: .leading, spacing: 8) {
                Picker(app.T("Múi giờ", "Time zone"), selection: Binding(get: { current }, set: { new in
                    guard new != current else { return }
                    tzBusy = true; tzError = ""
                    Task {
                        let err = await app.setRewardTimezone(new)
                        tzBusy = false
                        if let err { tzError = RewardsLogic.timezoneErrorMessage(err, T: app.T) }
                    }
                })) {
                    ForEach(options, id: \.0) { o in Text(o.1 + (o.0 == hint ? app.T(" (gợi ý theo thiết bị)", " (suggested from your device)") : "")).tag(o.0) }
                }
                .pickerStyle(.menu)
                .disabled(tzBusy || ((tz.changesLeft ?? 0) == 0 && tz.pendingTz == nil))
                .accessibilityIdentifier("rewards.timezone")
                note(tz.pendingTz != nil
                     ? app.T("Đổi sang \(tz.pendingTz ?? "") có hiệu lực từ ngày kế tiếp.", "The change to \(tz.pendingTz ?? "") takes effect from the next day.")
                     : (tz.chosen == true
                        ? app.T("Đổi múi giờ có hiệu lực từ ngày kế tiếp, tối đa 2 lần mỗi 30 ngày.", "A change takes effect from the next day, at most twice per 30 days.")
                        : app.T("Mặc định là giờ Việt Nam. Chọn múi giờ của bạn nếu khác.", "Defaults to Vietnam time. Pick yours if different.")))
                if !tzError.isEmpty { Text(tzError).font(.system(size: 12)).foregroundStyle(BanbeTheme.alert) }
            }
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ body: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold)).accessibilityAddTraits(.isHeader)
            body()
        }
        .padding(.top, 22)
    }

    private func bullets(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•").font(.system(size: 12.5)).frame(width: 10, alignment: .leading).accessibilityHidden(true)
                    Text(l).font(.system(size: 12.5)).lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Rewards v2 (migration 192)

    private func weekStreakCard(_ ws: RewardsPayload.WeekStreak) -> some View {
        let h = RewardsLogic.weekStreakHint(ws, en: app.isEN, T: app.T)
        return VStack(alignment: .leading, spacing: 4) {
            Text(app.T("Chuỗi tuần", "Week streak")).font(.system(size: 11.5)).opacity(0.7)
            HStack(spacing: 6) { Text("🔥").accessibilityHidden(true); Text("\(ws.current)") }.font(BanbeTheme.display(30))
            Text(app.T("Dài nhất: \(ws.longest) tuần", "Longest: \(ws.longest) \(ws.longest == 1 ? "week" : "weeks")")).font(.system(size: 11)).opacity(0.7)
            Text(h.status).font(.system(size: 11.5, weight: .semibold)).padding(.top, 6).accessibilityIdentifier("rewards.streak.status")
            Text(h.how).font(.system(size: 11)).lineSpacing(2).opacity(0.75).accessibilityIdentifier("rewards.streak.how")
            if ws.graceMax > 0 {
                HStack(spacing: 4) {
                    Text(String(repeating: "🛡", count: ws.graceHeld) + String(repeating: "·", count: max(0, ws.graceMax - ws.graceHeld))).accessibilityHidden(true)
                    Text(RewardsLogic.graceLine(ws, T: app.T))
                }
                .font(.system(size: 11)).opacity(0.75).padding(.top, 4)
                .accessibilityIdentifier("rewards.grace")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(16)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("rewards.weekStreak")
    }

    private func nextBadgeCard(_ nb: RewardsPayload.NextBadge) -> some View {
        let shown = min(nb.progress, nb.target)
        return VStack(alignment: .leading, spacing: 6) {
            Text(app.T("Huy hiệu tiếp theo", "Next badge")).font(.system(size: 11.5)).opacity(0.7)
            Text(RewardsLogic.nextBadgeLine(nb, en: app.isEN, T: app.T)).font(.system(size: 14, weight: .semibold))
            ProgressView(value: Double(shown), total: Double(max(nb.target, 1))).tint(app.palette.ink)
            Text("\(shown) / \(nb.target)").font(.system(size: 11)).opacity(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 14)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("rewards.nextBadge")
    }

    private func goalCard(_ g: RewardsPayload.Goal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if let t = g.target {
                    ZStack {
                        Circle().stroke(app.palette.rule, lineWidth: 4)
                        Circle().trim(from: 0, to: CGFloat(min(g.progress, t)) / CGFloat(t))
                            .stroke(app.palette.ink, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                    }
                    .frame(width: 34, height: 34).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.T("Mục tiêu tháng này", "My goal this month")).font(.system(size: 13.5, weight: .semibold))
                    Text(RewardsLogic.goalLine(g, T: app.T)).font(.system(size: 12)).opacity(0.8).accessibilityIdentifier("rewards.goal.line")
                }
            }
            HStack(spacing: 8) {
                ForEach([0] + RewardsLogic.goalChoices, id: \.self) { choice in
                    let on = (g.target ?? 0) == choice
                    Button {
                        guard !on, !goalBusy else { return }
                        Haptics.selection()
                        goalBusy = true; goalError = ""
                        Task {
                            let err = await app.setOutingGoal(choice)
                            goalBusy = false
                            if let err { goalError = RewardsLogic.goalErrorMessage(err, T: app.T) }
                        }
                    } label: {
                        Text(choice == 0 ? app.T("Không đặt", "None") : app.T("\(choice) / tháng", "\(choice) / month"))
                            .font(.system(size: 12.5, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(on ? app.palette.ink : .clear, in: Capsule())
                            .foregroundStyle(on ? app.palette.paper : app.palette.ink)
                            .overlay(Capsule().stroke(on ? app.palette.ink : app.palette.rule))
                            .opacity(goalBusy ? 0.6 : 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("rewards.goal.\(choice)")
                }
            }
            if !goalError.isEmpty { Text(goalError).font(.system(size: 12)).foregroundStyle(BanbeTheme.alert) }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 14)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("rewards.goal")
    }

    private func familyCard(_ g: RewardsLogic.BadgeGroup) -> some View {
        let head = g.next ?? g.top ?? g.badges[0]
        let title = RewardsLogic.familyTitle(g.family, T: app.T) ?? (app.isEN ? head.titleEn : head.titleVi)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Spacer()
                HStack(spacing: 4) {
                    ForEach(g.badges) { b in
                        Circle().strokeBorder(app.palette.ink, lineWidth: 1.5)
                            .background(Circle().fill(b.earned ? app.palette.ink : .clear))
                            .frame(width: 10, height: 10)
                            .accessibilityIdentifier("rewards.badge.\(b.code)")
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(app.T("Đã đạt \(g.earnedCount)/\(g.badges.count) cấp", "\(g.earnedCount) of \(g.badges.count) tiers earned"))
            }
            if let top = g.top {
                Text("✓ " + (app.isEN ? top.titleEn : top.titleVi) + (top.earnedAt.map { " ▪︎ " + RewardsView.dateText($0, en: app.isEN) } ?? ""))
                    .font(.system(size: 12))
            }
            if let next = g.next {
                let shown = min(next.progress, next.target)
                Text(app.T("Tiếp theo", "Next") + ": " + (app.isEN ? next.titleEn : next.titleVi) + " ▪︎ " + (app.isEN ? next.descEn : next.descVi))
                    .font(.system(size: 12)).opacity(0.75)
                ProgressView(value: Double(shown), total: Double(max(next.target, 1))).tint(app.palette.ink)
                Text("\(shown) / \(next.target)").font(.system(size: 11)).opacity(0.7)
            } else {
                Text(app.T("Đã đạt mọi cấp ✓", "Every tier earned ✓")).font(.system(size: 12)).opacity(0.75)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("rewards.family.\(g.family)")
    }

    private func badge(_ b: RewardsPayload.Badge) -> some View {
        let shown = min(b.progress, b.target)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text((b.earned ? "✓ " : "") + (app.isEN ? b.titleEn : b.titleVi)).font(.system(size: 13.5, weight: .semibold))
                Spacer()
                Text(b.earned ? app.T("Đã đạt", "Earned") : app.T("Chưa đạt", "Locked")).font(.system(size: 11, weight: .semibold)).opacity(0.8)
            }
            Text(app.isEN ? b.descEn : b.descVi).font(.system(size: 12)).opacity(0.75)
            ProgressView(value: Double(shown), total: Double(max(b.target, 1))).tint(app.palette.ink)
            Text("\(shown) / \(b.target)").font(.system(size: 11)).opacity(0.7)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(app.isEN ? b.titleEn : b.titleVi). \(b.earned ? app.T("Đã đạt", "Earned") : app.T("Chưa đạt", "Locked")). \(shown) / \(b.target). \(app.isEN ? b.descEn : b.descVi)")
        .accessibilityIdentifier("rewards.badge.\(b.code)")
    }

    private func offerRow(_ o: RewardsPayload.Offer) -> some View {
        let title = (app.lang == "en" ? o.titleEn : o.titleVi) ?? o.titleVi ?? o.titleEn ?? o.code
        let desc = (app.lang == "en" ? o.descEn : o.descVi) ?? o.descVi ?? o.descEn ?? ""
        return VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 13.5, weight: .semibold))
            if !desc.isEmpty { Text(desc).font(.system(size: 12)).opacity(0.75) }
            Text(app.T("Chưa khả dụng", "Not available yet")).font(.system(size: 11.5)).opacity(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("rewards.offer.\(o.code)")
    }

    private func catalogRow(_ c: RewardsPayload.Item, balance: Int) -> some View {
        let need = RewardsLogic.shortfall(balance: balance, price: c.price)
        let busy = app.rewardsRedeemBusy == c.code
        let design = manifest?.design(c.designId)
        return HStack(spacing: 12) {
            Group {
                if let d = design, let ui = KeychainArtwork.bundledImage(d) { Image(uiImage: ui).resizable().scaledToFit() } else { Color.clear }
            }.frame(width: 40, height: 60)
            VStack(alignment: .leading, spacing: 2) {
                Text(name(c.designId)).font(.system(size: 13.5, weight: .semibold))
                Text(c.unlocked ? app.T("Đã mở khoá", "Unlocked")
                     : need > 0 ? app.T("\(c.price) xu ▪︎ cần thêm \(need)", "\(c.price) coins ▪︎ \(need) more needed")
                     : app.T("\(c.price) xu", "\(c.price) coins"))
                    .font(.system(size: 11.5)).opacity(0.75)
            }
            Spacer(minLength: 0)
            if c.unlocked {
                Button { KeychainStore.shared.focusKeychainOnEdit = true; app.openEditProfile() } label: {
                    Text(app.T("Dùng", "Use")).font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 10).overlay(Capsule().stroke(app.palette.rule))
                }
                .buttonStyle(.plain).accessibilityIdentifier("rewards.use.\(c.code)")
            } else {
                Button { confirmItem = c } label: {
                    Text(busy ? app.T("Đang xử lý…", "Working…") : app.T("Đổi", "Redeem")).font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(need > 0 ? Color.clear : app.palette.ink, in: Capsule())
                        .foregroundStyle(need > 0 ? app.palette.ink : app.palette.paper)
                        .overlay(Capsule().stroke(need > 0 ? app.palette.rule : .clear))
                        .opacity(need > 0 || busy ? 0.55 : 1)
                }
                .buttonStyle(.plain).disabled(need > 0 || !app.rewardsRedeemBusy.isEmpty)
                .accessibilityLabel(need > 0 ? app.T("Đổi \(name(c.designId)), cần thêm \(need) xu", "Redeem \(name(c.designId)), \(need) more coins needed")
                                             : app.T("Đổi \(name(c.designId)) với \(c.price) xu", "Redeem \(name(c.designId)) for \(c.price) coins"))
                .accessibilityIdentifier("rewards.redeem.\(c.code)")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func historyRow(_ h: RewardsPayload.Entry) -> some View {
        let label = h.type == "redemption" && h.itemCode != nil
            ? RewardsLogic.historyLabel(reason: h.reason, eventName: nil, T: app.T) + " ▪︎ " + name(h.itemCode ?? "")
            : RewardsLogic.historyLabel(reason: h.reason, eventName: h.eventName, T: app.T)
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 12.5))
                Text(RewardsView.dateText(h.createdAt, en: app.isEN)).font(.system(size: 11)).opacity(0.6)
            }
            Spacer(minLength: 0)
            Text(h.amount > 0 ? "+\(h.amount)" : "\(h.amount)").font(.system(size: 13, weight: .bold))
                .accessibilityLabel(app.T("\(h.amount) xu", "\(h.amount) coins"))
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("rewards.history.row")
    }

    static func dateText(_ iso: String, en: Bool) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let d else { return "" }
        let out = DateFormatter()
        out.locale = Locale(identifier: en ? "en_US" : "vi_VN")
        out.dateStyle = .medium
        out.timeStyle = .none
        return out.string(from: d)
    }
}
