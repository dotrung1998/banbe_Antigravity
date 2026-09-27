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
    @State private var editing = false
    @State private var avatarPickerItem: PhotosPickerItem?
    @State private var avatarPreviewImage: UIImage?

    private var org: OrganizerProfile? { app.organizerProfile }
    private var isOwner: Bool { org?.id != nil && org?.id == app.myOrganizerID }

    private var profileURL: URL? {
        guard let id = org?.id else { return nil }
        return URL(string: "https://banbe.app/org/\(id)")
    }
    private var organizerAvatarURL: URL? {
        guard let path = org?.avatarPath, !path.isEmpty else { return nil }
        return try? SupabaseService.client.storage.from("organizer-photos").getPublicURL(path: path)
    }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    BackLink(label: app.T("Quay lại", "Back")) { app.backFromOrganizerProfile() }
                    Spacer()
                    if let url = profileURL, let name = org?.name {
                        ShareLink(item: url, subject: Text(app.T("Trang tổ chức banbe của \(name)", "\(name)\u{2019}s banbe organizer page"))) {
                            Text(app.T("Chia sẻ", "Share")).font(.system(size: 12, weight: .semibold)).foregroundStyle(app.palette.ink)
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
                    card(org)
                        .padding(.top, 10)

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
                            Text(app.T("Bởi \(org.name ?? "") Team", "By the \(org.name ?? "") Team")).font(.system(size: 14, weight: .semibold))
                            Spacer()
                            Text("›").font(.system(size: 20)).opacity(0.55)
                        }
                        .foregroundStyle(app.palette.ink)
                        .padding(16)
                        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                    .accessibilityIdentifier("organizerProfile.teamRow")

                    Button(app.T("Hiển thị mã QR tổ chức", "Show the organizer's QR code")) { qrOpen = true }
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(app.palette.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(app.palette.rule))
                        .padding(.top, 10)
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
                            .font(.system(size: 11.5, weight: .semibold))
                            .padding(.top, 22)
                        VStack(spacing: 0) {
                            ForEach(app.organizerProfileUpcoming) { e in
                                Button { app.goEvent(e.id) } label: {
                                    HStack(spacing: 12) {
                                        CatalogPhoto(path: EventCatalog.find(e.id)?.img ?? "", height: 48, width: 48, cornerRadius: 10)
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

                    if !app.organizerProfilePhotos.isEmpty {
                        Text(app.T("Ảnh", "Photos"))
                            .font(.system(size: 11.5, weight: .semibold))
                            .padding(.top, 22)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                            ForEach(app.organizerProfilePhotos) { photo in
                                photoTile(photo)
                            }
                        }
                        .padding(.top, 8)
                    }
                } else {
                    Text(app.organizerProfileError.isEmpty ? app.T("Không tìm thấy tổ chức này.", "This organizer couldn't be found.") : app.organizerProfileError)
                        .font(.system(size: 13)).foregroundStyle(app.palette.ink)
                        .frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .task {
            guard let id = app.organizerProfileID.isEmpty ? nil : app.organizerProfileID else { return }
            await app.loadOrganizerProfileExtras(organizerID: id)
        }
        .sheet(isPresented: $qrOpen) {
            VStack(spacing: 14) {
                if let name = org?.name, let url = profileURL {
                    QRCodeImage(value: url.absoluteString, size: 220)
                    Text(name).font(.system(size: 12)).foregroundStyle(app.palette.ink)
                }
            }
            .padding(30)
            .presentationDetents([.medium])
        }
    }

    @ViewBuilder
    private func photoTile(_ photo: OrganizerPhoto) -> some View {
        let relative = photo.storagePath.hasPrefix("event-photos/")
            ? String(photo.storagePath.dropFirst("event-photos/".count))
            : photo.storagePath
        if let url = try? SupabaseService.client.storage.from("event-photos").getPublicURL(path: relative) {
            AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { app.palette.field }
                .frame(height: 100).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    @ViewBuilder
    private func card(_ org: OrganizerProfile) -> some View {
        VStack(spacing: 10) {
            if let url = organizerAvatarURL {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                    .frame(width: 88, height: 88).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(app.palette.paper, lineWidth: 3))
            } else {
                RoundedRectangle(cornerRadius: 20).fill(app.palette.ink).frame(width: 88, height: 88)
                    .overlay(Text(String((org.name ?? "?").prefix(1)).uppercased()).font(.system(size: 32, weight: .bold)).foregroundStyle(app.palette.paper))
            }
            HStack(spacing: 8) {
                Text(org.name ?? "").font(BanbeTheme.display(21)).accessibilityIdentifier("organizerProfile.name")
                if org.verified == true {
                    Text("✓ " + app.T("Đã xác minh", "Verified")).font(.system(size: 11, weight: .semibold)).foregroundStyle(app.palette.ink.opacity(0.7))
                }
            }
            if let about = org.about, !about.isEmpty {
                Text(about).font(.system(size: 12.5)).multilineTextAlignment(.center).foregroundStyle(app.palette.ink)
            }
            // Organizer Team pass (2026-09-27, Stage 3) — SEPARATE
            // long-form intro; `about` above is untouched.
            LongIntroPreview(text: org.introLong)
            SocialLinksRow(links: org.socialLinks)
            HStack(spacing: 20) {
                statView("\(org.eventCount ?? 0)", app.T("Sự kiện", "Events"))
                statView("\(org.followerCount ?? 0)", app.T("Người theo dõi", "Followers"))
            }
            .padding(.top, 6)
            // Derived from the earliest real published (live/ended) event —
            // never the organizer's own free-text hosting_since column,
            // which nothing ever actually sets (get_organizer_profile,
            // migration 095).
            Text(org.hostingSinceYear.map { app.T("Tổ chức từ \($0)", "Hosting since \($0)") }
                 ?? app.T("Chưa có sự kiện công khai nào", "No published events yet"))
                .font(.system(size: 11)).foregroundStyle(app.palette.ink.opacity(0.7))

            if !isOwner, app.userID != nil, let id = org.id {
                Button((org.following ?? false) ? app.T("Đang theo dõi", "Following") : app.T("Theo dõi", "Follow")) {
                    Task { await app.toggleFollowOrganizer(id) }
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 24).padding(.vertical, 10)
                .background((org.following ?? false) ? Color.clear : app.palette.ink, in: Capsule())
                .foregroundStyle((org.following ?? false) ? app.palette.ink : app.palette.paper)
                .overlay(Capsule().stroke((org.following ?? false) ? app.palette.rule : .clear))
                .padding(.top, 6)
                .accessibilityIdentifier("organizerProfile.follow")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28).padding(.horizontal, 22)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityIdentifier("organizerProfile.card")
    }

    @ViewBuilder
    private func statView(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(BanbeTheme.display(17))
            Text(label).font(.system(size: 10)).foregroundStyle(app.palette.ink.opacity(0.7))
        }
    }

    @ViewBuilder
    private func editCard() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if editing {
                HStack(spacing: 12) {
                    PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                        ZStack {
                            if let avatarPreviewImage {
                                Image(uiImage: avatarPreviewImage).resizable().scaledToFill()
                            } else if let url = organizerAvatarURL {
                                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { app.palette.field }
                            } else {
                                app.palette.field
                            }
                        }
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    Text(app.T("Đổi ảnh", "Change photo")).font(.system(size: 12)).underline()
                }
                TextField("", text: $app.orgRegName)
                    .font(.system(size: 14, weight: .semibold))
                    .padding(9)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityIdentifier("organizerProfile.nameField")
                TextEditor(text: $app.orgRegDesc)
                    .font(.system(size: 13))
                    .frame(minHeight: 80)
                    .padding(6)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityIdentifier("organizerProfile.introField")
                // Organizer Team pass (2026-09-27, Stage 3) — a SEPARATE
                // long-form intro; orgRegDesc above is untouched.
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.T("Giới thiệu chi tiết (không bắt buộc)", "Long-form intro (optional)"))
                        .font(.system(size: 11)).foregroundStyle(app.palette.ink.opacity(0.7))
                    TextEditor(text: $app.orgRegIntroLong)
                        .font(.system(size: 13)).frame(minHeight: 100)
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
                            .font(.system(size: 12.5, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .foregroundStyle(app.palette.paper)
                    }
                    .disabled(app.orgProfileSaving)
                    .accessibilityIdentifier("organizerProfile.save")
                    Button(app.T("Huỷ", "Cancel")) { editing = false }
                        .font(.system(size: 12.5, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(app.palette.rule))
                        .foregroundStyle(app.palette.ink)
                }
                if !app.orgProfileError.isEmpty {
                    Text(app.orgProfileError).font(.system(size: 11.5)).foregroundStyle(BanbeTheme.alert)
                }
            } else {
                Button(app.T("Chỉnh sửa hồ sơ tổ chức", "Edit organizer profile")) { editing = true }
                    .font(.system(size: 12.5, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(app.palette.rule))
                    .foregroundStyle(app.palette.ink)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("organizerProfile.edit")
            }
        }
        .foregroundStyle(app.palette.ink)
        .padding(editing ? 16 : 0)
        .background(editing ? AnyView(app.palette.field.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))) : AnyView(Color.clear))
        .padding(.top, 10)
        .onChange(of: avatarPickerItem) { _, item in
            Task {
                guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                await MainActor.run { avatarPreviewImage = image }
            }
        }
    }
}
