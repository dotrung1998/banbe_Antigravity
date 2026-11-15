import SwiftUI
import PhotosUI

/// Personal-vs-organizer hierarchy pass (2026-09-27) — the organizer's own,
/// SEPARATE public profile, reached from the management page's "Hồ sơ công
/// khai của tổ chức" button (DashboardView) or a shared
/// /org/<organizer_id> universal link — never from the personal profile
/// any more (PublicProfileView). Real organizer data only: avatar, name,
/// intro, genuine hosting-since year, published-event/follower counts, a
/// concise real-upcoming-events preview and a handful of real photos. No
/// location/category fields — `organizers` doesn't store either, and this
/// ticket's own rule is to hide what's missing rather than invent it.
struct OrganizerProfileView: View {
    @EnvironmentObject private var app: AppState
    @State private var qrOpen = false
    @State private var pastOpen = false
    @State private var shareCardOpen = false
    @State private var editing = false
    @State private var avatarPickerItem: PhotosPickerItem?
    @State private var avatarPreviewImage: UIImage?

    private var org: OrganizerProfile? { app.organizerProfile }
    private var isOwner: Bool { org?.id != nil && (org?.id == app.myOrganizerID || app.myOrganizerIDs.contains(org?.id ?? "")) }

    private var orgPhotos: [PhotoGalleryItem] {
        app.organizerPhotos.compactMap { photo in
            guard let url = MediaURLs.eventPhoto(storagePath: photo.storagePath, r2Ref: photo.r2Ref, variant: .card)?.absoluteString
            else { return nil }
            return PhotoGalleryItem(id: photo.id.uuidString.lowercased(), url: url, eventId: photo.eventId)
        }
    }

    private var profileURL: URL? {
        guard let id = org?.id else { return nil }
        return URL(string: "banbe://org/\(id)")
    }
    private var organizerAvatarURL: URL? {
        MediaURLs.organizerAvatar(path: org?.avatarPath, r2Ref: org?.avatarR2Ref, variant: .card)
    }

    var body: some View {
        Group {
            // Note 81 (switch home_v23): the v2.3 host profile; off = the page below unchanged.
            if app.homeV23Enabled { v23Page } else { classicPage }
        }
        .task {
            guard let id = app.organizerProfileID.isEmpty ? nil : app.organizerProfileID else { return }
            await app.loadOrganizerProfileExtras(organizerID: id)
        }
        .task(id: app.organizerProfileID) {
            guard !app.organizerProfileID.isEmpty else { return }
            await app.loadOrganizerPhotos(organizerId: app.organizerProfileID)
        }
        .sheet(isPresented: $qrOpen) { qrSheet }
        .sheet(isPresented: $shareCardOpen) {
            if let org, let url = profileURL {
                ProfileShareSheet(
                    kindLabel: app.T("Tổ chức", "Host"),
                    name: org.name ?? "",
                    subtitle: app.T("\(org.eventCount ?? 0) sự kiện · \(org.followerCount ?? 0) người theo dõi", "\(org.eventCount ?? 0) events · \(org.followerCount ?? 0) followers"),
                    detail: org.about ?? "",
                    avatarURL: organizerAvatarURL,
                    roundAvatar: false, link: url, idPrefix: "organizerProfile",
                    cardKind: "host", cardID: org.id ?? "", isOwner: isOwner)
            }
        }
    }

    private var classicPage: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    BackLink(label: app.organizerProfileReturnsToPulse ? app.T("Về Pulse", "Back to Pulse") : app.T("Quay lại", "Back")) { app.backFromOrganizerProfile() }
                    Spacer()
                    if profileURL != nil, org?.name != nil {
                        Button { shareCardOpen = true } label: {
                            Text(app.T("Chia sẻ", "Share")).font(.app(size: 12, weight: .semibold)).foregroundStyle(app.palette.ink)
                        }
                        .accessibilityIdentifier("organizerProfile.share")
                    }
                }
                .padding(.top, 16)

                if app.organizerProfileLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
                } else if let org, org.success == true {
                    // iPhone fix pass (2026-09-27), Item 3 — slight,
                    // consistent breathing room between the back/share row
                    // and this rounded card: 10pt, the same small-gap value
                    // already used elsewhere in this file (teamRow/editCard
                    // below), not a new token.
                    VStack(alignment: .leading, spacing: 0) { card(org) }
                        .padding(.top, BanbeTheme.Space.s)

                    // Organizer Team pass (2026-09-27, Stage 2) — a
                    // prominent, large tappable row using the organizer's
                    // own real name (never the founder's personal name —
                    // that stays governed entirely by the founder's OWN
                    // personal-profile organizer_mode toggle, unrelated to
                    // this label). Opens the public Team page
                    // (get_organizer_team, 098/101) — accepted AND
                    // public_visible members only.
                    // iPhone fix pass (2026-09-27), Item 2 — moved to be
                    // the FIRST action directly below the card, ahead of
                    // the QR/edit rows below (was after QR) — same row,
                    // same real member logic, no duplication.
                    Button {
                        Task { await app.openOrganizerTeam(organizerID: org.id ?? "", back: .organizerProfile) }
                    } label: {
                        HStack {
                            Text(app.T("Bởi \(org.name ?? "") Team", "By the \(org.name ?? "") Team")).font(.app(.subheadline).weight(.semibold))
                            Spacer()
                            Text("›").font(.app(size: 20)).opacity(0.55)
                        }
                        .foregroundStyle(app.palette.ink)
                        .padding(.horizontal, BanbeTheme.Space.l).padding(.vertical, BanbeTheme.Space.m)
                        .frame(minHeight: 44)
                        .background(app.palette.surface2, in: RoundedRectangle(cornerRadius: BanbeTheme.Radius.card, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, BanbeTheme.Space.xl)
                    .accessibilityIdentifier("organizerProfile.teamRow")

                    Button { qrOpen = true } label: {
                        Text(app.T("Hiển thị mã QR tổ chức", "Show the organizer's QR code"))
                            .font(.app(.subheadline).weight(.semibold)).foregroundStyle(app.palette.ink)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(app.palette.surface2, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .padding(.top, BanbeTheme.Space.m)
                        .accessibilityIdentifier("organizerProfile.qrCta")

                    // Owner only — edits organizers.name/about/avatarPath
                    // (migration 090's update_organizer_profile), never
                    // profiles.* / save_profile(). `org.id == app.myOrganizerID`
                    // gates this, never a personal-profile check — there's
                    // no such concept on this screen.
                    if isOwner {
                        editCard()
                    }

                    if !app.organizerProfileUpcoming.isEmpty {
                        Text(app.T("Sự kiện sắp tới", "Upcoming events"))
                            .font(.app(size: 11.5, weight: .semibold))
                            .padding(.top, 22)
                        VStack(spacing: 0) {
                            ForEach(app.organizerProfileUpcoming) { e in
                                Button { app.goEvent(e.id) } label: {
                                    HStack(spacing: 12) {
                                        CatalogPhoto(path: e.coverURL ?? "", height: 48, width: 48, cornerRadius: 10)
                                        Text(e.name).font(BanbeTheme.display(14)).lineLimit(1)
                                        Spacer(minLength: 0)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 8)
                                if e.id != app.organizerProfileUpcoming.last?.id { Divider().overlay(app.palette.rule) }
                            }
                        }
                        .padding(.top, 8)
                    }

                    if !app.organizerProfilePast.isEmpty {
                        Button { withAnimation(.easeInOut(duration: 0.2)) { pastOpen.toggle() } } label: {
                            HStack(spacing: 8) {
                                Text(app.T("Sự kiện đã qua", "Past events"))
                                    .font(.app(size: 11.5, weight: .semibold))
                                Text("\(app.organizerProfilePast.count)")
                                    .font(.app(size: 11, weight: .semibold))
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(app.palette.field, in: Capsule())
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.down")
                                    .font(.app(size: 11, weight: .semibold))
                                    .rotationEffect(.degrees(pastOpen ? 180 : 0))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 22)
                        .accessibilityIdentifier("organizerProfile.pastToggle")
                        if pastOpen {
                            VStack(spacing: 0) {
                                ForEach(app.organizerProfilePast) { e in
                                    Button { app.goEvent(e.id) } label: {
                                        HStack(spacing: 12) {
                                            CatalogPhoto(path: e.coverURL ?? "", height: 48, width: 48, cornerRadius: 10)
                                            Text(e.name).font(BanbeTheme.display(14)).lineLimit(1)
                                            Spacer(minLength: 0)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.vertical, 8)
                                    if e.id != app.organizerProfilePast.last?.id { Divider().overlay(app.palette.rule) }
                                }
                            }
                            .padding(.top, 8)
                        }
                    }

                    // Photo section carried over unchanged from the retired
                    // organizer page: real `event_photos` of this organizer
                    // (loadOrganizerPhotos, .task below) fed into the same
                    // openPhoto/PhotoViewerView pipeline every gallery uses.
                    HStack(alignment: .firstTextBaseline) {
                        Text(app.T("Ảnh của", "Photos by") + " \(org.name ?? "")").font(.app(size: 11.5))
                        Spacer()
                        Text(app.T("do người tổ chức đăng", "posted by the organizer")).font(.app(size: 11))
                    }
                    .padding(.top, 30)

                    if app.organizerPhotosLoading {
                        Text(app.T("Đang tải…", "Loading…"))
                            .font(.app(size: 12.5)).opacity(0.6)
                            .padding(.top, 14)
                    } else if orgPhotos.isEmpty {
                        Text(app.T("Người tổ chức chưa đăng ảnh nào.", "This organizer hasn’t posted any photos yet."))
                            .font(.app(size: 12.5)).opacity(0.6)
                            .padding(.top, 14)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                            ForEach(Array(orgPhotos.enumerated()), id: \.element.id) { index, photo in
                                GeometryReader { geo in
                                    Button {
                                        app.openPhoto(gallery: orgPhotos, index: index, organizer: org.name ?? "", originRect: geo.frame(in: .global))
                                    } label: {
                                        ZStack(alignment: .topTrailing) {
                                            CatalogPhoto(path: photo.url, height: 158)
                                            if app.photoEngagement[photo.id]?.likedByMe == true {
                                                Image(systemName: "heart.fill")
                                                    .font(.app(size: 13))
                                                    .foregroundStyle(.white)
                                                    .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
                                                    .padding(8)
                                                    .allowsHitTesting(false)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                .onAppear { app.photoThumbFrames[photo.id] = geo.frame(in: .global) }
                                .onChange(of: geo.frame(in: .global)) { _, f in app.photoThumbFrames[photo.id] = f }
                                .onDisappear { app.photoThumbFrames[photo.id] = nil }
                                }
                                .frame(height: 158)
                            }
                        }
                        .padding(.top, 14)
                    }
                } else {
                    Text(app.organizerProfileError.isEmpty ? app.T("Không tìm thấy tổ chức này.", "This organizer couldn't be found.") : app.organizerProfileError)
                        .font(.app(size: 13)).foregroundStyle(app.palette.ink)
                        .frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
    }

    /// QR for the in-app `banbe://org/<id>` link — a phone camera scan opens
    /// the installed app straight on this host; long-pressing the code does
    /// the same thing from right here.
    private var qrSheet: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 14) {
                if let name = org?.name, let url = profileURL {
                    QRCodeImage(value: url.absoluteString, size: 220)
                        .contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 0.5) {
                            Haptics.light()
                            qrOpen = false
                            app.handleDeepLink(url)
                        }
                        .accessibilityHint(app.T("Nhấn giữ để mở trang tổ chức", "Press and hold to open the host page"))
                        .accessibilityIdentifier("organizerProfile.qrCode")
                    Text(name).font(.app(size: 14, weight: .semibold)).foregroundStyle(app.palette.ink)
                    Text(app.T(
                        "Quét bằng camera điện thoại để mở trang tổ chức này trong ứng dụng banbe. Nhấn giữ mã QR để mở ngay.",
                        "Scan with a phone camera to open this host's page in the banbe app. Press and hold the QR code to open it right now."))
                        .font(.app(size: 12)).foregroundStyle(app.palette.ink.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(30)

            Button { qrOpen = false } label: {
                Image(systemName: "xmark")
                    .font(.app(size: 14, weight: .semibold))
                    .foregroundStyle(app.palette.ink)
                    .frame(width: 44, height: 44)
                    .background(app.palette.field, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(14)
            .accessibilityLabel(app.T("Đóng", "Close"))
            .accessibilityIdentifier("organizerProfile.qrClose")
        }
        .presentationDetents([.medium])
    }

    /// Same identity card as the personal profile (note 68): left-aligned, full width, ring avatar, name as the
    /// largest text, a role line, the about text, then the stats strip inside the card; Follow under it.
    @ViewBuilder
    private func card(_ org: OrganizerProfile) -> some View {
        VStack(alignment: .leading, spacing: BanbeTheme.Space.m) {
            HStack(alignment: .center, spacing: BanbeTheme.Space.l) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [app.palette.clay, BanbeTheme.attn], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Circle().fill(app.palette.paper).padding(2)
                    Group {
                        if let url = organizerAvatarURL {
                            AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                        } else {
                            ZStack {
                                app.palette.ink
                                Text(String((org.name ?? "?").prefix(1)).uppercased())
                                    .font(.app(size: 26, weight: .semibold)).foregroundStyle(app.palette.paper)
                            }
                        }
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
                }
                .frame(width: 80, height: 80)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(org.name ?? "").font(BanbeTheme.display(26))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("organizerProfile.name")
                    Text("Host" + (org.verified == true ? " · ✓ " + app.T("Đã xác minh", "Verified") : ""))
                        .font(.app(.footnote)).foregroundStyle(app.palette.ink2)
                    // Derived from the earliest real published (live/ended) event — never the free-text
                    // hosting_since column (get_organizer_profile, migration 095); never a made-up year.
                    if org.hostingSinceYear == nil {
                        Text(app.T("Chưa có sự kiện công khai nào", "No published events yet"))
                            .font(.app(.footnote)).foregroundStyle(app.palette.ink2)
                    }
                }
                Spacer(minLength: 0)
            }
            if let about = org.about, !about.isEmpty {
                Text(about).font(.app(.subheadline)).fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: BanbeTheme.Space.m) {
                Rectangle().fill(app.palette.divider).frame(height: 1)
                HStack(spacing: 0) {
                    let stats: [(String, String)] = [("\(org.eventCount ?? 0)", app.T("Sự kiện", "Events")),
                                                     ("\(org.followerCount ?? 0)", app.T("Người theo dõi", "Followers"))]
                        + (org.hostingSinceYear.map { [("\($0)", app.T("Từ năm", "Since"))] } ?? [])
                    ForEach(Array(stats.enumerated()), id: \.offset) { i, st in
                        HStack(spacing: 0) {
                            if i > 0 { Rectangle().fill(app.palette.divider).frame(width: 1).padding(.trailing, BanbeTheme.Space.m) }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: st.0).font(.app(.headline).monospacedDigit())
                                Text(st.1).font(.app(.footnote)).foregroundStyle(app.palette.ink2)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("organizerProfile.stats")

            if !isOwner, app.userID != nil, let id = org.id {
                // The canonical follow list (what Account > Following edits) once loaded; the RPC flag until then.
                let following = app.followedStatus == .loaded ? app.isFollowing(id) : (org.following ?? false)
                Button {
                    Task { await app.toggleFollowOrganizer(id) }
                } label: {
                    Group {
                        if following {
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark").font(.app(size: 11, weight: .bold)).accessibilityHidden(true)
                                Text(app.T("Đang theo dõi", "Following"))
                            }
                        } else {
                            Text(app.T("Theo dõi", "Follow"))
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Capsule())
                }
                .font(.app(.subheadline).weight(.semibold))
                .background(following ? Color.clear : app.palette.ink, in: Capsule())
                .foregroundStyle(following ? app.palette.ink : app.palette.paper)
                .overlay(Capsule().stroke(following ? app.palette.rule : .clear))
                .accessibilityAddTraits(following ? .isSelected : [])
                .accessibilityIdentifier("organizerProfile.follow")
                if !app.followWriteError.isEmpty {
                    Text(app.followWriteError).font(.app(.footnote)).foregroundStyle(BanbeTheme.alert)
                        .accessibilityIdentifier("organizerProfile.followError")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background {
            let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
            ZStack {
                shape.fill(app.palette.surface2)
                shape.fill(RadialGradient(colors: [app.palette.clay.opacity(ProfileCard.glow), .clear],
                                          center: .topTrailing, startRadius: 0, endRadius: 220))
                shape.strokeBorder(app.palette.ink.opacity(0.06), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("organizerProfile.card")

        // Moved out of the card, as on the personal profile: the long intro and links under an About heading.
        if (org.introLong?.isEmpty == false) || !(org.socialLinks ?? []).isEmpty {
            VStack(alignment: .leading, spacing: BanbeTheme.Space.s) {
                Text(app.T("Giới thiệu", "About")).font(BanbeTheme.display(17))
                // Organizer Team pass (2026-09-27, Stage 3) — SEPARATE long-form intro; `about` is untouched.
                LongIntroPreview(text: org.introLong)
                SocialLinksRow(links: org.socialLinks)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, BanbeTheme.Space.xl)
        }
    }

    @ViewBuilder
    private func editCard() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if editing {
                HStack(spacing: 12) {
                    let fieldColor = app.palette.field
                    PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                        ZStack {
                            if let avatarPreviewImage {
                                Image(uiImage: avatarPreviewImage).resizable().scaledToFill()
                            } else if let url = organizerAvatarURL {
                                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { fieldColor }
                            } else {
                                fieldColor
                            }
                        }
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    Text(app.T("Đổi ảnh", "Change photo")).font(.app(size: 12)).underline()
                }
                TextField("", text: $app.orgRegName)
                    .font(.app(size: 14, weight: .semibold))
                    .padding(9)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityIdentifier("organizerProfile.nameField")
                TextEditor(text: $app.orgRegDesc)
                    .font(.app(size: 13))
                    .frame(minHeight: 80)
                    .padding(6)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityIdentifier("organizerProfile.introField")
                // Organizer Team pass (2026-09-27, Stage 3) — a SEPARATE
                // long-form intro; orgRegDesc above is untouched.
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.T("Giới thiệu chi tiết (không bắt buộc)", "Long-form intro (optional)"))
                        .font(.app(size: 11)).foregroundStyle(app.palette.ink.opacity(0.7))
                    TextEditor(text: $app.orgRegIntroLong)
                        .font(.app(size: 13)).frame(minHeight: 100)
                        .padding(6)
                        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityIdentifier("organizerProfile.introLongField")
                }
                SocialLinksEditorView(links: $app.orgRegLinks, open: $app.orgRegLinksOpen, testPrefix: "organizerProfile.link")
                HStack(spacing: 8) {
                    Button {
                        Task {
                            await app.saveOrganizerProfile(avatarImage: avatarPreviewImage)
                            editing = false
                            avatarPreviewImage = nil
                        }
                    } label: {
                        Text(app.orgProfileSaving ? app.T("Đang lưu…", "Saving…") : app.T("Lưu", "Save"))
                            .font(.app(size: 12.5, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .foregroundStyle(app.palette.paper)
                    }
                    .disabled(app.orgProfileSaving)
                    .accessibilityIdentifier("organizerProfile.save")
                    Button(app.T("Huỷ", "Cancel")) { editing = false }
                        .font(.app(size: 12.5, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(app.palette.rule))
                        .foregroundStyle(app.palette.ink)
                }
                if !app.orgProfileError.isEmpty {
                    Text(app.orgProfileError).font(.app(size: 11.5)).foregroundStyle(BanbeTheme.alert)
                }
            } else {
                Button { editing = true } label: {
                    Text(app.T("Chỉnh sửa hồ sơ tổ chức", "Edit organizer profile"))
                        .font(.app(.subheadline).weight(.semibold)).foregroundStyle(app.palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(app.palette.surface2, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                    .accessibilityIdentifier("organizerProfile.edit")
            }
        }
        .foregroundStyle(app.palette.ink)
        .padding(editing ? 16 : 0)
        .background(editing ? AnyView(app.palette.field.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))) : AnyView(Color.clear))
        .padding(.top, BanbeTheme.Space.s)
        .onChange(of: avatarPickerItem) { _, item in
            Task {
                guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                await MainActor.run { avatarPreviewImage = image }
            }
        }
    }
}

// MARK: - v2.3 host profile (note 81, switch home_v23)

/// Web twin: src/components/profile/OrganizerProfileV23.jsx. A centred face with a clay ring that springs in, the name
/// in the serif, a role line and tags, a stats block, two actions (Follow for a visitor, Edit profile for the owner;
/// Share beside it), About, Coming up as v2.3 rows, Past (collapsed) and the photos. QR, Team and Copy link sit in a
/// ⋯ menu next to Share.
extension OrganizerProfileView {
    fileprivate var v23Page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    v23Circle("chevron.left", label: app.T("Quay lại", "Back"), id: "organizerProfile.back") { app.backFromOrganizerProfile() }
                    Spacer()
                    if org?.success == true {
                        v23Circle("square.and.arrow.up", label: app.T("Chia sẻ", "Share"), id: "organizerProfile.share") { shareCardOpen = true }
                        Menu {
                            Button { qrOpen = true } label: { Label(app.T("Mã QR tổ chức", "Host QR code"), systemImage: "qrcode") }
                                .accessibilityIdentifier("organizerProfile.qrCta")
                            Button {
                                Task { await app.openOrganizerTeam(organizerID: org?.id ?? "", back: .organizerProfile) }
                            } label: { Label(app.T("Đội ngũ \(org?.name ?? "")", "The \(org?.name ?? "") team"), systemImage: "person.2") }
                                .accessibilityIdentifier("organizerProfile.teamRow")
                            Button {
                                if let id = org?.id { UIPasteboard.general.string = "\(AppConfig.publicWebOrigin)/org/\(id)"; Haptics.light() }
                            } label: { Label(app.T("Sao chép link", "Copy link"), systemImage: "link") }
                                .accessibilityIdentifier("organizerProfile.copyLink")
                        } label: {
                            Image(systemName: "ellipsis").font(.app(size: 17, weight: .medium))
                                .frame(width: 44, height: 44).background(app.palette.surface2, in: Circle())
                        }
                        .accessibilityLabel(app.T("Thêm", "More"))
                        .accessibilityIdentifier("organizerProfile.more")
                    }
                }
                .padding(.horizontal, 16).padding(.top, 12)

                if app.organizerProfileLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
                } else if let org, org.success == true {
                    v23Content(org)
                } else {
                    Text(app.organizerProfileError.isEmpty ? app.T("Không tìm thấy tổ chức này.", "This organizer couldn't be found.") : app.organizerProfileError)
                        .font(.app(size: 13)).frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.bottom, 40)
        }
        .background(app.palette.paper.ignoresSafeArea())
        .accessibilityIdentifier("organizerProfile.v23")
    }

    private func v23Circle(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.app(size: 17, weight: .medium))
                .frame(width: 44, height: 44).background(app.palette.surface2, in: Circle()).contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private func v23Heading(_ text: String) -> some View {
        Text(text.uppercased()).font(.app(size: 11, weight: .bold)).tracking(1.4).foregroundStyle(app.palette.ink3)
            .padding(.bottom, 10).accessibilityAddTraits(.isHeader)
    }

    /// One v2.3 row for a host event (the loaded catalogue/real event when the app has it, for its type and price).
    private func v23HostRow(_ e: OrganizerUpcomingEvent, past: Bool) -> V23Row {
        let known = app.resolvedEvent(for: e.id)
        let zone = known?.eventTimeZone
        let type = known.map { app.trStatus($0.catDisplay.isEmpty ? $0.cat : $0.catDisplay) } ?? ""
        let when = app.discoveryDateBadge(e.startsAt, timeZone: zone)
        let price: String = past ? "" : (known.map { $0.isFree ? app.T("Miễn phí", "Free") : app.trStatus($0.price) } ?? "")
        return V23Row(key: e.id, name: e.name, img: e.coverURL ?? known?.img ?? "",
                      kicker: [type, when].filter { !$0.isEmpty }.joined(separator: " · "),
                      place: known?.locationLabel ?? known?.location?.area ?? "",
                      priceLabel: price, isFree: !past && (known?.isFree ?? false), status: nil)
    }

    @ViewBuilder
    private func v23Content(_ org: OrganizerProfile) -> some View {
        let upcoming = app.organizerProfileUpcoming
        let areas = Array(NSOrderedSet(array: upcoming.compactMap { app.resolvedEvent(for: $0.id)?.locationLabel }.filter { !$0.isEmpty })
            .compactMap { $0 as? String }.prefix(3))
        let stats: [(String, String)] = [("\(org.eventCount ?? 0)", app.T("Sự kiện", "Events")),
                                         ("\(org.followerCount ?? 0)", app.T("Người theo dõi", "Followers"))]
            + [org.hostingSinceYear.map { ("\($0)", app.T("Từ năm", "Since")) } ?? ("\(upcoming.count)", app.T("Sắp tới", "Upcoming"))]
        VStack(spacing: 0) {
            V23HostFace(url: organizerAvatarURL, monogram: String((org.name ?? "B").prefix(1)).uppercased())
            Text(org.name ?? "").font(V23Style.serif(30)).tracking(-0.6).multilineTextAlignment(.center)
                .padding(.top, 16).padding(.bottom, 4)
                .accessibilityIdentifier("organizerProfile.name")
            Text([app.T("Chủ nhà", "Host"),
                  org.hostingSinceYear.map { app.T("từ \($0)", "since \($0)") } ?? app.T("chưa có sự kiện công khai", "no published events yet"),
                  org.verified == true ? "✓ " + app.T("Đã xác minh", "Verified") : nil].compactMap { $0 }.joined(separator: " · "))
                .font(.app(size: 13)).foregroundStyle(app.palette.ink2)
            if !areas.isEmpty || !upcoming.isEmpty {
                FlowRow(spacing: 6) {
                    ForEach(areas, id: \.self) { a in tag(a) }
                    if !upcoming.isEmpty { tag(app.T("\(upcoming.count) sắp tới", "\(upcoming.count) coming up")) }
                }
                .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 18)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("organizerProfile.card")

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(stats.enumerated()), id: \.offset) { i, st in
                    VStack(spacing: 2) {
                        Text(verbatim: st.0).font(V23Style.serif(23)).monospacedDigit()
                        Text(st.1.uppercased()).font(.app(size: 11, weight: .semibold)).tracking(0.66).foregroundStyle(app.palette.ink3)
                    }
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .leading) { if i > 0 { Rectangle().fill(app.palette.rule).frame(width: 1) } }
                    .modifier(EntranceRise(shown: true, step: i, y: 10))
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.vertical, 14).padding(.horizontal, 4)
            .background(app.palette.surface2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.bottom, 14)
            .accessibilityIdentifier("organizerProfile.stats")
            HStack(spacing: 8) {
                primaryAction(org)
                Button { shareCardOpen = true } label: {
                    Label(app.T("Chia sẻ", "Share"), systemImage: "square.and.arrow.up")
                        .font(.app(size: 14.5, weight: .bold)).frame(maxWidth: .infinity, minHeight: 46)
                        .overlay(Capsule().stroke(app.palette.rule, lineWidth: 1)).contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityIdentifier("organizerProfile.shareCard")
            }
            if !isOwner, !app.followWriteError.isEmpty {
                Text(app.followWriteError).font(.app(.footnote)).foregroundStyle(BanbeTheme.alert).padding(.top, 10)
                    .accessibilityIdentifier("organizerProfile.followError")
            }
            if !isOwner, app.userID == nil {
                Text(app.T("Đăng nhập để theo dõi chủ nhà này.", "Sign in to follow this host.")).font(.app(size: 12.5))
                    .foregroundStyle(app.palette.ink3).frame(maxWidth: .infinity).padding(.top, 8)
            }
            if isOwner && editing { editCard().padding(.top, 10) }
            if let about = org.about, !about.isEmpty || org.introLong?.isEmpty == false || !(org.socialLinks ?? []).isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    v23Heading(app.T("Giới thiệu", "About"))
                    if !about.isEmpty { Text(about).font(.app(size: 14.5)).lineSpacing(5).foregroundStyle(app.palette.ink2).fixedSize(horizontal: false, vertical: true) }
                    VStack(alignment: .leading, spacing: 8) {
                        LongIntroPreview(text: org.introLong)
                        SocialLinksRow(links: org.socialLinks)
                    }
                    .padding(.top, 10)
                }
                .padding(.top, 24)
            }
        }
        .padding(.horizontal, 16)

        if !upcoming.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                v23Heading(app.T("Sắp diễn ra", "Coming up")).padding(.horizontal, 16)
                ForEach(upcoming) { e in EventRowV23View(row: v23HostRow(e, past: false), idPrefix: "organizerProfile.upcoming") { app.goEvent(e.id) } }
            }
            .padding(.top, 24)
            .accessibilityIdentifier("organizerProfile.upcoming")
        }
        if !app.organizerProfilePast.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    v23Heading(app.T("Đã diễn ra", "Past events"))
                    Spacer()
                    Button { withAnimation(V23Style.spring) { pastOpen.toggle() } } label: {
                        HStack(spacing: 6) {
                            Text(pastOpen ? app.T("Thu gọn", "Hide") : app.T("Xem \(app.organizerProfilePast.count)", "Show \(app.organizerProfilePast.count)"))
                            Image(systemName: "chevron.down").rotationEffect(.degrees(pastOpen ? 180 : 0))
                        }
                        .font(.app(size: 13, weight: .semibold)).foregroundStyle(app.palette.ink2).frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("organizerProfile.pastToggle")
                }
                .padding(.horizontal, 16)
                if pastOpen {
                    ForEach(app.organizerProfilePast) { e in EventRowV23View(row: v23HostRow(e, past: true), idPrefix: "organizerProfile.past") { app.goEvent(e.id) } }
                }
            }
            .padding(.top, 18)
        }
        VStack(alignment: .leading, spacing: 0) {
            v23Heading(app.T("Ảnh", "Photos") + (orgPhotos.isEmpty ? "" : " · \(orgPhotos.count)"))
            if app.organizerPhotosLoading {
                Text(app.T("Đang tải…", "Loading…")).font(.app(size: 13)).foregroundStyle(app.palette.ink3)
            } else if orgPhotos.isEmpty {
                Text(app.T("Chủ nhà chưa đăng ảnh nào.", "This host hasn’t posted any photos yet.")).font(.app(size: 13)).foregroundStyle(app.palette.ink3)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(Array(orgPhotos.enumerated()), id: \.element.id) { index, photo in
                        GeometryReader { geo in
                            Button {
                                app.openPhoto(gallery: orgPhotos, index: index, organizer: org.name ?? "", originRect: geo.frame(in: .global))
                            } label: {
                                ZStack(alignment: .topTrailing) {
                                    CatalogPhoto(path: photo.url, height: 158, cornerRadius: 14)
                                    if app.photoEngagement[photo.id]?.likedByMe == true {
                                        Image(systemName: "heart.fill").font(.app(size: 13)).foregroundStyle(.white)
                                            .shadow(color: .black.opacity(0.55), radius: 2, y: 1).padding(8)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .onAppear { app.photoThumbFrames[photo.id] = geo.frame(in: .global) }
                            .onChange(of: geo.frame(in: .global)) { _, f in app.photoThumbFrames[photo.id] = f }
                            .onDisappear { app.photoThumbFrames[photo.id] = nil }
                        }
                        .frame(height: 158)
                        .accessibilityLabel(app.T("Ảnh \(index + 1)", "Photo \(index + 1)"))
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 18)
    }

    private func tag(_ text: String) -> some View {
        Text(text).font(.app(size: 12, weight: .semibold)).padding(.horizontal, 11).frame(height: 28)
            .background(app.palette.surface2, in: Capsule())
    }

    @ViewBuilder
    private func primaryAction(_ org: OrganizerProfile) -> some View {
        if isOwner {
            Button { withAnimation(V23Style.spring) { editing.toggle() } } label: {
                Label(app.T("Sửa hồ sơ", "Edit profile"), systemImage: "pencil")
                    .font(.app(size: 14.5, weight: .bold))
                    .foregroundStyle(editing ? app.palette.ink : app.palette.paper)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(editing ? Color.clear : app.palette.ink, in: Capsule())
                    .overlay(Capsule().stroke(editing ? app.palette.rule : .clear, lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityIdentifier("organizerProfile.edit")
        } else {
            let id = org.id ?? ""
            let following = app.followedStatus == .loaded ? app.isFollowing(id) : (org.following ?? false)
            Button {
                guard app.userID != nil else { return app.promptSignIn(.follow, returnTo: .organizerProfile, backTo: .organizerProfile) }
                Task { await app.toggleFollowOrganizer(id) }
            } label: {
                Label(following ? app.T("Đang theo dõi", "Following") : app.T("Theo dõi", "Follow"), systemImage: following ? "checkmark" : "plus")
                    .font(.app(size: 14.5, weight: .bold))
                    .foregroundStyle(following ? app.palette.ink : app.palette.paper)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(following ? Color.clear : app.palette.ink, in: Capsule())
                    .overlay(Capsule().stroke(following ? app.palette.rule : .clear, lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityAddTraits(following ? .isSelected : [])
            .accessibilityIdentifier("organizerProfile.follow")
        }
    }
}

/// The host's face with a clay ring that springs in (Reduce Motion: just there).
private struct V23HostFace: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let url: URL?
    let monogram: String
    @State private var shown = false
    var body: some View {
        ZStack {
            Circle().fill(app.palette.clay)
            if let url { RemoteImage(path: url.absoluteString, maxPixel: 264) } else {
                Text(monogram).font(.app(size: 32, weight: .semibold)).foregroundStyle(.white)
            }
        }
        .frame(width: 88, height: 88)
        .clipShape(Circle())
        .padding(4)
        .overlay(Circle().stroke(app.palette.clay.opacity(0.45), lineWidth: 1.5))
        .scaleEffect(shown || reduceMotion ? 1 : 0.7)
        .opacity(shown || reduceMotion ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.56, dampingFraction: 0.62)) { shown = true } }
        .accessibilityHidden(true)
    }
}
