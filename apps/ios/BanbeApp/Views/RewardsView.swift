import SwiftUI

/// Account > Rewards & badges. Private to the signed-in account; every number is server-computed
/// (migration 165). Coins are cosmetic only and never affect booking, priority or eligibility.
struct RewardsView: View {
    @EnvironmentObject var app: AppState
    @State private var confirmItem: RewardsPayload.Item?

    private var manifest: KeychainManifest? { KeychainManifest.bundled }
    private func name(_ designID: String) -> String {
        guard let d = manifest?.design(designID) else { return designID }
        return app.isEN ? d.en : d.vi
    }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.T("Tài khoản", "Account")) { app.goBack() }
                Text(app.T("Phần thưởng & huy hiệu", "Rewards & badges"))
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
                    Text(app.T("Số dư âm do điểm danh bị huỷ; kiếm thêm để về 0.", "Negative because a check-in was undone; earn coins to get back to 0."))
                        .font(.system(size: 11)).opacity(0.7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(app.T("Số dư \(r.balance) xu", "Balance \(r.balance) coins"))
            .accessibilityIdentifier("rewards.balance")

            VStack(alignment: .leading, spacing: 4) {
                Text(app.T("Chuỗi ngày", "Streak")).font(.system(size: 11.5)).opacity(0.7)
                HStack(spacing: 6) { Text("🔥").accessibilityHidden(true); Text("\(r.streak.current)") }.font(BanbeTheme.display(30))
                Text(app.T("Dài nhất: \(r.streak.longest) ngày", "Longest: \(r.streak.longest) days")).font(.system(size: 11)).opacity(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(app.T("Chuỗi \(r.streak.current) ngày, dài nhất \(r.streak.longest)", "\(r.streak.current)-day streak, longest \(r.streak.longest)"))
            .accessibilityIdentifier("rewards.streak")
        }
        .padding(.top, 16)

        section(app.T("Huy hiệu", "Badges")) {
            VStack(spacing: 8) { ForEach(r.badges) { badge($0) } }
        }

        section(app.T("Đổi thưởng (móc khoá)", "Redeem (keychain designs)")) {
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

        section(app.T("Cách kiếm xu", "How earning works")) {
            bullets(RewardsLogic.ruleLines(r.rules, T: app.T) + RewardsLogic.noCoinLines(T: app.T) + RewardsLogic.streakLines(tz: r.streak.timezone, T: app.T))
            Text(app.T("Điều kiện đổi thưởng", "Redemption terms")).font(.system(size: 13, weight: .semibold)).padding(.top, 12)
            bullets(RewardsLogic.termsLines(T: app.T))
            Text(app.T("Phiên bản quy tắc \(r.rules.version ?? 1). Các con số là đề xuất MVP và có thể thay đổi; mọi thay đổi có số phiên bản mới.",
                       "Rules version \(r.rules.version ?? 1). Numbers are an MVP proposal and may change; any change gets a new version."))
                .font(.system(size: 11)).opacity(0.6).padding(.top, 10)
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
