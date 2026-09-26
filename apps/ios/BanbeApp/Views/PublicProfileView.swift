import SwiftUI
import PhotosUI

/// TASK D (2026-10-01 UX foundation pass) — what anyone (signed in or not)
/// sees at https://banbe.app/u/<handle>. Organizer mode transforms the
/// SAME card into the organizer presentation (event/follower stats, follow
/// CTA) rather than a second, conflicting persona.
struct PublicProfileView: View {
    @EnvironmentObject private var app: AppState
    @State private var qrOpen = false
    // iPhone fix pass (2026-09-26) — inline editing for the ORGANIZER half
    // of this same page, mirroring AccountView's own host-tab card exactly
    // (same orgRegName/orgRegDesc/saveOrganizerProfile — this account has
    // at most one organizer, app.myOrganizerID). A SEPARATE action from
    // "Chỉnh sửa hồ sơ" (personal, -> EditProfileView) — never the same,
    // since they edit different rows in different tables.
    @State private var orgEditing = false
    @State private var orgAvatarPickerItem: PhotosPickerItem?
    @State private var orgAvatarPreviewImage: UIImage?

    private var isOwnProfile: Bool { app.userID != nil && app.publicProfile?.id == app.userID }

    private var profileURL: URL? {
        guard let handle = app.publicProfile?.handle else { return nil }
        return URL(string: "https://banbe.app/u/\(handle)")
    }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    BackLink(label: app.T("Quay lại", "Back")) { app.backFromPublicProfile() }
                    Spacer()
                    if let url = profileURL {
                        ShareLink(item: url, subject: Text(shareTitle)) {
                            Text(app.T("Chia sẻ", "Share")).font(.system(size: 12, weight: .semibold)).foregroundStyle(app.palette.ink)
                        }
                        .accessibilityIdentifier("publicProfile.share")
                    }
                }
                .padding(.top, 16)

                if app.publicProfileLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
                } else if let p = app.publicProfile, p.success == true {
                    card(p)
                    Button(app.T("Hiển thị mã QR", "Show QR code")) { qrOpen = true }
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(app.palette.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(app.palette.rule))
                        .padding(.top, 16)
                        .accessibilityIdentifier("publicProfile.qrCta")

                    // iPhone fix pass — "Chỉnh sửa hồ sơ" beneath "Hiển thị
                    // mã QR", own-profile only (never rendered for a
                    // visitor viewing someone else's page — the edit RPCs
                    // themselves are owner/admin-gated server-side
                    // regardless, same as AccountView's own card).
                    if isOwnProfile {
                        Button(app.T("Chỉnh sửa hồ sơ", "Edit profile")) { app.openEditProfile() }
                            .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(app.palette.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(app.palette.rule))
                            .padding(.top, 10)
                            .accessibilityIdentifier("publicProfile.editPersonal")
                    }

                    // Organizer's own edit — a SEPARATE action from the
                    // personal one above; edits organizers.name/about/
                    // avatar_path only (migration 090's
                    // update_organizer_profile), never profiles.*.
                    // `org.id == app.myOrganizerID` — never editing on the
                    // strength of `isOwnProfile` alone; the one place a
                    // mismatch would silently edit the WRONG organizer.
                    if isOwnProfile, let org = p.organizer, org.id == app.myOrganizerID {
                        orgEditCard()
                    }
                } else {
                    Text(app.publicProfileError.isEmpty ? app.T("Không tìm thấy hồ sơ này.", "This profile couldn't be found.") : app.publicProfileError)
                        .font(.system(size: 13)).foregroundStyle(app.palette.ink)
                        .frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 20)
        }
        .sheet(isPresented: $qrOpen) {
            VStack(spacing: 14) {
                if let handle = app.publicProfile?.handle, let url = profileURL {
                    QRCodeImage(value: url.absoluteString, size: 220)
                    Text("@\(handle)").font(.system(size: 12)).foregroundStyle(app.palette.ink)
                }
            }
            .padding(30)
            .presentationDetents([.medium])
        }
    }

    private var shareTitle: String {
        app.T("Hồ sơ banbe của \(app.publicProfile?.displayName ?? "")", "\(app.publicProfile?.displayName ?? "")\u{2019}s banbe profile")
    }

    @ViewBuilder
    private func card(_ p: PublicProfile) -> some View {
        let paletteColor = ProfilePalette.all.first { $0.key == (p.profileTheme ?? "default") }?.color ?? ProfilePalette.all[0].color
        VStack(spacing: 10) {
            if let urlStr = p.avatarURL, let url = URL(string: urlStr) {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                    .frame(width: 88, height: 88).clipShape(Circle())
                    .overlay(Circle().stroke(app.palette.paper, lineWidth: 3))
            } else {
                Circle().fill(app.palette.ink).frame(width: 88, height: 88)
                    .overlay(Text(String((p.displayName ?? p.handle ?? "?").prefix(1)).uppercased()).font(.system(size: 32, weight: .bold)).foregroundStyle(app.palette.paper))
                    .overlay(Circle().stroke(app.palette.paper, lineWidth: 3))
            }
            Text(p.displayName ?? "").font(BanbeTheme.display(21))
            Text("@\(p.handle ?? "")" + (p.city?.isEmpty == false ? " ▪︎ \(p.city!)" : ""))
                .font(.system(size: 12.5)).foregroundStyle(app.palette.ink.opacity(0.75))
            if let bio = p.bio, !bio.isEmpty {
                Text(bio).font(.system(size: 12.5)).multilineTextAlignment(.center).foregroundStyle(app.palette.ink)
            }
            if let interests = p.interests, !interests.isEmpty {
                HStack(spacing: 6) {
                    ForEach(interests, id: \.self) { tag in
                        Text(tag).font(.system(size: 10.5, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.white.opacity(0.5), in: Capsule())
                    }
                }
            }
            if let org = p.organizer {
                HStack(spacing: 20) {
                    statView("\(org.eventCount)", app.T("Sự kiện", "Events"))
                    statView("\(org.followerCount)", app.T("Người theo dõi", "Followers"))
                    if org.verified { statView("✓", app.T("Đã xác minh", "Verified")) }
                }
                .padding(.top, 6)

                // iPhone fix pass — derived from the earliest REAL published
                // event (migration 091), never a fabricated year.
                Text(org.hostingSinceYear.map { app.T("Tổ chức từ \($0)", "Hosting since \($0)") }
                     ?? app.T("Chưa có sự kiện công khai nào", "No published events yet"))
                    .font(.system(size: 11)).foregroundStyle(app.palette.ink.opacity(0.7))

                if app.userID != p.id {
                    Button(org.following ? app.T("Đang theo dõi", "Following") : app.T("Theo dõi", "Follow")) {
                        Task { await app.toggleFollowOrganizer(org.id) }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .background(org.following ? Color.clear : app.palette.ink, in: Capsule())
                    .foregroundStyle(org.following ? app.palette.ink : app.palette.paper)
                    .overlay(Capsule().stroke(org.following ? app.palette.rule : .clear))
                    .padding(.top, 6)
                    .accessibilityIdentifier("publicProfile.follow")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28).padding(.horizontal, 22)
        .background(LinearGradient(colors: [paletteColor.opacity(0.8), paletteColor.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityIdentifier("publicProfile.card")
    }

    @ViewBuilder
    private func statView(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(BanbeTheme.display(17))
            Text(label).font(.system(size: 10)).foregroundStyle(app.palette.ink.opacity(0.7))
        }
    }

    private var organizerAvatarURL: URL? {
        guard !app.myOrganizerAvatarPath.isEmpty else { return nil }
        return try? SupabaseService.client.storage.from("organizer-photos").getPublicURL(path: app.myOrganizerAvatarPath)
    }

    @ViewBuilder
    private func orgEditCard() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if orgEditing {
                HStack(spacing: 12) {
                    PhotosPicker(selection: $orgAvatarPickerItem, matching: .images) {
                        ZStack {
                            if let orgAvatarPreviewImage {
                                Image(uiImage: orgAvatarPreviewImage).resizable().scaledToFill()
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
                    .accessibilityIdentifier("publicProfile.orgNameField")
                TextEditor(text: $app.orgRegDesc)
                    .font(.system(size: 13))
                    .frame(minHeight: 80)
                    .padding(6)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityIdentifier("publicProfile.orgIntroField")
                HStack(spacing: 8) {
                    Button {
                        Task {
                            await app.saveOrganizerProfile(avatarImage: orgAvatarPreviewImage)
                            orgEditing = false
                            orgAvatarPreviewImage = nil
                        }
                    } label: {
                        Text(app.orgProfileSaving ? app.T("Đang lưu…", "Saving…") : app.T("Lưu", "Save"))
                            .font(.system(size: 12.5, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .foregroundStyle(app.palette.paper)
                    }
                    .disabled(app.orgProfileSaving)
                    .accessibilityIdentifier("publicProfile.orgSave")
                    Button(app.T("Huỷ", "Cancel")) { orgEditing = false }
                        .font(.system(size: 12.5, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(app.palette.rule))
                        .foregroundStyle(app.palette.ink)
                }
                if !app.orgProfileError.isEmpty {
                    Text(app.orgProfileError).font(.system(size: 11.5)).foregroundStyle(BanbeTheme.alert)
                }
            } else {
                Button(app.T("Chỉnh sửa hồ sơ tổ chức", "Edit host profile")) { orgEditing = true }
                    .font(.system(size: 12.5, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("publicProfile.editOrg")
            }
        }
        .foregroundStyle(app.palette.ink)
        .padding(16)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.top, 10)
        .onChange(of: orgAvatarPickerItem) { _, item in
            Task {
                guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                await MainActor.run { orgAvatarPreviewImage = image }
            }
        }
    }
}
