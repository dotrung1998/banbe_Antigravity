import SwiftUI

/// Personal-vs-organizer hierarchy pass (2026-09-27) — PERSONAL ONLY: what
/// anyone (signed in or not) sees at https://banbe.app/u/<handle>. Always
/// leads with profiles.displayName — never organizers.name — and carries
/// no organizer edit/guest-preview affordance any more; the organizer's own
/// separate public page (real avatar/stats/upcoming events/photos, its own
/// shareable /org/<id> link, its own owner-only edit) is
/// OrganizerProfileView, reached from the management page (DashboardView's
/// "Hồ sơ công khai của tổ chức" button), never from here.
struct PublicProfileView: View {
    @EnvironmentObject private var app: AppState
    @State private var qrOpen = false
    @State private var shareCardOpen = false

    private var isOwnProfile: Bool { app.userID != nil && app.publicProfile?.id == app.userID }

    private var profileURL: URL? {
        guard let handle = app.publicProfile?.handle else { return nil }
        return URL(string: "banbe://u/\(handle)")
    }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    BackLink(label: app.T("Quay lại", "Back")) { app.backFromPublicProfile() }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("publicProfile.back")
                    Spacer()
                    if profileURL != nil {
                        Button { shareCardOpen = true } label: {
                            Text(app.T("Chia sẻ", "Share")).font(.subheadline.weight(.semibold)).foregroundStyle(app.palette.ink)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("publicProfile.share")
                    }
                }
                .padding(.top, BanbeTheme.Space.s)

                if app.publicProfileLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
                } else if let p = app.publicProfile, p.success == true {
                    // Identity card (note 68): left-aligned, full width, stats inside; owner actions OUTSIDE it.
                    card(p)
                        .padding(.top, BanbeTheme.Space.s)

                    // Own profile: QR / Edit profile / Edit charm as one row of equal 44pt pills. Visitors only get QR.
                    HStack(spacing: BanbeTheme.Space.s) {
                        profileActionButton(icon: "qrcode", label: app.T("Mã QR", "QR code"), id: "publicProfile.qrCta") { qrOpen = true }
                        if isOwnProfile {
                            // Edits profiles fields ONLY — never organizers.name/about/
                            // avatarPath (OrganizerProfileView owns those).
                            profileActionButton(icon: "pencil", label: app.T("Sửa hồ sơ", "Edit profile"), id: "publicProfile.editPersonal") { app.openEditProfile() }
                            profileActionButton(icon: "key.fill", label: app.T("Sửa móc khoá", "Edit charm"), id: "publicProfile.editCharm") {
                                KeychainStore.shared.focusKeychainOnEdit = true
                                app.openEditProfile()
                            }
                        }
                    }
                    .padding(.top, BanbeTheme.Space.m)

                    belowCard(p)
                        .padding(.top, BanbeTheme.Space.xl)
                } else {
                    Text(app.publicProfileError.isEmpty ? app.T("Không tìm thấy hồ sơ này.", "This profile couldn't be found.") : app.publicProfileError)
                        .font(.subheadline).foregroundStyle(app.palette.ink)
                        .frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 16)
            .padding(.bottom, BanbeTheme.Space.xl)
        }
        .task(id: isOwnProfile) {
            // Own profile with Rewards on: the earned-badge count for the stats strip (loaded once, like Account).
            if isOwnProfile, app.rewardsEnabled, app.rewardsStatus == .idle { await app.loadRewards() }
        }
        .sheet(isPresented: $qrOpen) { qrSheet }
        .sheet(isPresented: $shareCardOpen) {
            if let p = app.publicProfile, let url = profileURL {
                ProfileShareSheet(
                    kindLabel: app.T("Thành viên", "Member"),
                    name: p.displayName ?? "",
                    subtitle: p.handle.map { "@\($0)" } ?? "",
                    detail: p.bio ?? "",
                    avatarURL: p.avatarURL.flatMap(URL.init(string:)),
                    roundAvatar: true, link: url, idPrefix: "publicProfile",
                    cardKind: "member", cardID: p.handle ?? "",
                    isOwner: p.handle != nil && p.handle?.lowercased() == app.user?.handle?.lowercased())
            }
        }
    }

    private func profileActionButton(icon: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 15, weight: .regular))
                Text(label).font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.85)
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(app.palette.surface2, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    /// QR for the in-app `banbe://u/<handle>` link — a phone camera scan
    /// opens the installed app on this profile; long-pressing the code does
    /// the same from right here.
    private var qrSheet: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 14) {
                if let handle = app.publicProfile?.handle, let url = profileURL {
                    QRCodeImage(value: url.absoluteString, size: 220)
                        .contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 0.5) {
                            Haptics.light()
                            qrOpen = false
                            app.handleDeepLink(url)
                        }
                        .accessibilityHint(app.T("Nhấn giữ để mở hồ sơ", "Press and hold to open the profile"))
                        .accessibilityIdentifier("publicProfile.qrCode")
                    Text("@\(handle)").font(.system(size: 14, weight: .semibold)).foregroundStyle(app.palette.ink)
                    Text(app.T(
                        "Quét bằng camera điện thoại để mở hồ sơ này trong ứng dụng banbe. Nhấn giữ mã QR để mở ngay.",
                        "Scan with a phone camera to open this profile in the banbe app. Press and hold the QR code to open it right now."))
                        .font(.system(size: 12)).foregroundStyle(app.palette.ink.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(30)

            Button { qrOpen = false } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(app.palette.ink)
                    .frame(width: 44, height: 44)
                    .background(app.palette.field, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(14)
            .accessibilityLabel(app.T("Đóng", "Close"))
            .accessibilityIdentifier("publicProfile.qrClose")
        }
        .presentationDetents([.medium])
    }

    private var shareTitle: String {
        app.T("Hồ sơ banbe của \(app.publicProfile?.displayName ?? "")", "\(app.publicProfile?.displayName ?? "")\u{2019}s banbe profile")
    }

    private func isHost(_ p: PublicProfile) -> Bool { p.organizer != nil && p.organizerMode == true }
    private func role(_ p: PublicProfile) -> String {
        ProfileCard.roleLabel(organizerName: p.organizer?.name, organizerMode: p.organizerMode == true, vi: !app.isEN)
    }

    private func stats(_ p: PublicProfile) -> [ProfileCard.Stat] {
        let goingCount = isOwnProfile ? app.goingEventsCount : nil
        let badgeCount = isOwnProfile && app.rewardsEnabled ? app.rewards.map { $0.badges.filter(\.earned).count } : nil
        return ProfileCard.stats(eventCount: p.organizer?.eventCount, followerCount: p.organizer?.followerCount,
                                 hostingSinceYear: p.organizer?.hostingSinceYear, isHost: isHost(p), isOwner: isOwnProfile,
                                 rewardsOn: app.rewardsEnabled, badgeCount: badgeCount, upcomingCount: goingCount)
    }
    private func statLabel(_ id: String) -> String {
        switch id {
        case "hosted": return app.T("Sự kiện", "Hosted")
        case "followers": return app.T("Người theo dõi", "Followers")
        case "since": return app.T("Từ năm", "Since")
        case "badges": return app.T("Huy hiệu", "Badges")
        default: return app.T("Sắp tới", "Upcoming")
        }
    }

    /// Upcoming (note 68), from what the app already has: this person's own hosted events still ahead (public), and
    /// for the owner only, the events they are going to. Never anyone else's bookings.
    private func upcoming(_ p: PublicProfile) -> [(ProfileCard.Upcoming, CatalogEvent)] {
        var byKey: [String: CatalogEvent] = [:]
        for e in EventCatalog.all { byKey[e.key] = app.resolvedEvent(for: e.key) ?? e }
        for case let (key, e?) in app.realEventsByID { byKey[key] = e }
        let inputs = byKey.values.map { e in
            ProfileCard.UpcomingInput(key: e.key, name: e.name, organizerId: e.organizerId ?? app.eventOrganizerID[e.key],
                                      start: e.startDate?.timeIntervalSince1970, ended: e.endedHoursAgo != nil, cancelled: e.cancelled)
        }.sorted { $0.key < $1.key }
        return ProfileCard.upcoming(inputs, organizerId: p.organizer?.id, organizerMode: p.organizerMode == true,
                                    isOwner: isOwnProfile, goingKeys: app.attending)
            .compactMap { u in byKey[u.event.key].map { (u, $0) } }
    }

    /// Identity card (note 68): left-aligned, full width. Avatar with a clay→gold ring, the name as the largest text
    /// (wraps, never truncates), one role line, @handle · city, the bio, then the stats strip. The charm hangs in the
    /// corner the owner chose, with a gutter so text never runs under it. Surface: surface2 + the person's palette as a
    /// light tint + a soft clay glow at the charm corner + a hairline highlight (ProfileCard, contrast-tested).
    @ViewBuilder
    private func card(_ p: PublicProfile) -> some View {
        let paletteColor = ProfilePalette.all.first { $0.key == (p.profileTheme ?? "default") }?.color ?? ProfilePalette.all[0].color
        let stats = stats(p)
        VStack(alignment: .leading, spacing: BanbeTheme.Space.m) {
            HStack(alignment: .center, spacing: BanbeTheme.Space.l) {
                avatar(p)
                VStack(alignment: .leading, spacing: 2) {
                    // Always the PERSON's own name first (never swapped for organizers.name).
                    Text(p.displayName ?? "").font(BanbeTheme.display(26))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("publicProfile.displayName")
                    // One role line. Organizer mode OFF hides the host role for every visitor (migration 096).
                    Text(role(p)).font(.footnote).foregroundStyle(app.palette.ink2)
                        .accessibilityIdentifier(isHost(p) ? "publicProfile.founderLine" : "publicProfile.role")
                    Text("@\(p.handle ?? "")" + (p.city?.isEmpty == false ? " · \(p.city!)" : ""))
                        .font(.footnote).foregroundStyle(app.palette.ink2)
                }
                Spacer(minLength: 0)
            }
            if let bio = p.bio, !bio.isEmpty {
                Text(bio).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("publicProfile.bio")
            }
            if !stats.isEmpty {
                VStack(spacing: BanbeTheme.Space.m) {
                    Rectangle().fill(app.palette.divider).frame(height: 1)
                    HStack(spacing: 0) {
                        ForEach(Array(stats.enumerated()), id: \.element.id) { i, st in
                            HStack(spacing: 0) {
                                if i > 0 { Rectangle().fill(app.palette.divider).frame(width: 1).padding(.trailing, BanbeTheme.Space.m) }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: "\(st.value)").font(.headline.monospacedDigit())
                                    Text(statLabel(st.id)).font(.footnote).foregroundStyle(app.palette.ink2)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("publicProfile.stat.\(st.id)")
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("publicProfile.stats")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .keychainProfileCharm(handle: p.handle, layout: .leading, outset: 20)
        .padding(20)
        .background {
            let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
            ZStack {
                shape.fill(app.palette.surface2)
                shape.fill(paletteColor.opacity(ProfileCard.tint))
                shape.fill(RadialGradient(colors: [app.palette.clay.opacity(ProfileCard.glow), .clear],
                                          center: .topTrailing, startRadius: 0, endRadius: 220))
                shape.strokeBorder(app.palette.ink.opacity(0.06), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("publicProfile.card")
    }

    /// 80pt: a 2pt clay→gold ring, a 2pt paper gap, the 72pt photo (or monogram). Decorative to VoiceOver.
    private func avatar(_ p: PublicProfile) -> some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [app.palette.clay, BanbeTheme.attn], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().fill(app.palette.paper).padding(2)
            Group {
                if let urlStr = p.avatarURL, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                } else {
                    ZStack {
                        app.palette.ink
                        Text(String((p.displayName ?? p.handle ?? "?").prefix(1)).uppercased())
                            .font(.system(size: 26, weight: .semibold)).foregroundStyle(app.palette.paper)
                    }
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(Circle())
        }
        .frame(width: 80, height: 80)
        .accessibilityHidden(true)
    }

    /// Below the card (note 68): what used to be crammed inside it, then Upcoming and credits. 24 between sections.
    private func belowCard(_ p: PublicProfile) -> some View {
        let interests = ProfileCard.dedupeChips(p.interests ?? [], alreadyShown: [role(p), p.bio, p.displayName])
        let badges = p.teamBadges ?? []
        let upcoming = upcoming(p)
        return VStack(alignment: .leading, spacing: BanbeTheme.Space.xl) {
            if (p.introLong?.isEmpty == false) || !(p.socialLinks ?? []).isEmpty {
                VStack(alignment: .leading, spacing: BanbeTheme.Space.s) {
                    Text(app.T("Giới thiệu", "About")).font(BanbeTheme.display(17))
                    // Organizer Team pass (2026-09-27, Stage 3) — SEPARATE long-form intro; `bio` is untouched.
                    LongIntroPreview(text: p.introLong)
                    SocialLinksRow(links: p.socialLinks)
                }
                .accessibilityIdentifier("publicProfile.about")
            }
            if !interests.isEmpty || !badges.isEmpty {
                VStack(alignment: .leading, spacing: BanbeTheme.Space.s) {
                    Text(app.T("Sở thích & nhóm", "Interests & teams")).font(BanbeTheme.display(17))
                    FlowRow(spacing: BanbeTheme.Space.s) {
                        ForEach(interests, id: \.self) { tag in
                            Text(tag).font(.footnote.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(app.palette.surface2, in: Capsule())
                        }
                        // Organizer Team pass (2026-09-27, Stage 2) — ONLY this profile's OWN opted-in choice
                        // (teamBadges): accepted AND currently public_visible.
                        ForEach(badges) { badge in
                            Button {
                                // iPhone fix pass (2026-09-27), Issue 3 — one shared `organizerTeamBackScreen` (no real
                                // navigation stack): reaching this profile FROM that same organizer's Team, the badge
                                // pops back to that Team screen instead of pushing a second one that would clobber its
                                // own back target (the reported OrganizerProfile -> Team -> member -> Back loop).
                                if app.organizerTeamOrganizerId == badge.organizerId, app.publicProfileBackScreen == .organizerTeam {
                                    app.backFromPublicProfile()
                                } else {
                                    Task { await app.openOrganizerTeam(organizerID: badge.organizerId, back: .publicProfile) }
                                }
                            } label: {
                                Text(app.T("Thành viên của \(badge.organizerName) Team", "Member of the \(badge.organizerName) Team"))
                                    .font(.footnote.weight(.semibold))
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(app.palette.clayBg, in: Capsule())
                                    .foregroundStyle(app.palette.clay)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("publicProfile.teamBadge.\(badge.organizerId)")
                        }
                    }
                }
            }
            if !upcoming.isEmpty || isOwnProfile {
                VStack(alignment: .leading, spacing: BanbeTheme.Space.s) {
                    Text(app.T("Sắp tới", "Upcoming")).font(BanbeTheme.display(17))
                    if upcoming.isEmpty {
                        // Owner empty state: say what this is and where to go next.
                        HStack {
                            Text(app.T("Chưa có sự kiện sắp tới", "Nothing coming up yet")).font(.subheadline).foregroundStyle(app.palette.ink2)
                            Spacer(minLength: BanbeTheme.Space.m)
                            Button(app.T("Xem sự kiện ›", "Browse events ›")) { app.goHome() }
                                .font(.subheadline.weight(.semibold)).foregroundStyle(app.palette.clay)
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("publicProfile.browse")
                        }
                        .padding(.horizontal, BanbeTheme.Space.l)
                        .background(app.palette.surface2, in: RoundedRectangle(cornerRadius: BanbeTheme.Radius.card, style: .continuous))
                        .accessibilityIdentifier("publicProfile.upcomingEmpty")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(upcoming.enumerated()), id: \.element.0.event.key) { i, item in
                                let (u, e) = item
                                Button { app.goEvent(e.key) } label: {
                                    HStack(spacing: BanbeTheme.Space.m) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(e.name).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                                            Text(app.trStatus(e.when)).font(.footnote).foregroundStyle(app.palette.ink2)
                                        }
                                        Spacer(minLength: 0)
                                        Text(u.role == "hosting" ? app.T("Tổ chức", "Hosting") : app.T("Sẽ đi", "Going"))
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(u.role == "hosting" ? app.palette.clay : app.palette.ink2)
                                            .padding(.horizontal, 10).padding(.vertical, 4)
                                            .background(u.role == "hosting" ? app.palette.clayBg : .clear, in: Capsule())
                                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(app.palette.ink2)
                                    }
                                    .padding(.horizontal, BanbeTheme.Space.l).padding(.vertical, BanbeTheme.Space.m)
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(app.palette.divider).frame(height: 1) } }
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("publicProfile.upcoming.\(i)")
                            }
                        }
                        .background(app.palette.surface2, in: RoundedRectangle(cornerRadius: BanbeTheme.Radius.card, style: .continuous))
                    }
                }
                .accessibilityIdentifier("publicProfile.upcoming")
            }
            // Real, explicit, ACCEPTED event contributions only — never derived from ticket attendance/bookings/
            // check-ins. Absent entirely if none.
            if let credited = p.creditedEvents, !credited.isEmpty {
                VStack(alignment: .leading, spacing: BanbeTheme.Space.s) {
                    Text(app.T("Đã tham gia tổ chức", "Helped organize")).font(BanbeTheme.display(17))
                    ForEach(credited) { ev in
                        Button { app.goEvent(ev.eventId) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ev.eventName).font(.subheadline)
                                Text(ev.organizerName).font(.footnote).foregroundStyle(app.palette.ink2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, BanbeTheme.Space.l).padding(.vertical, BanbeTheme.Space.m)
                            .background(app.palette.surface2, in: RoundedRectangle(cornerRadius: BanbeTheme.Radius.card, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(app.palette.ink)
                    }
                }
                .accessibilityIdentifier("publicProfile.creditedEvents")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
