import SwiftUI
import PhotosUI

/// TASK D (2026-10-01 UX foundation pass) — the owner's own editable public
/// identity: avatar, handle, display name, bio, city, interests, palette.
/// Reachable by tapping Account's own profile card (AccountView.swift).
struct EditProfileView: View {
    @EnvironmentObject private var app: AppState
    @State private var avatarPickerItem: PhotosPickerItem?

    private var canSave: Bool {
        app.editProfileHandle.trimmingCharacters(in: .whitespaces).count >= 3
            && !app.editProfileName.trimmingCharacters(in: .whitespaces).isEmpty
            && !app.editProfileBusy
    }
    private var monogram: String {
        String((app.editProfileName.isEmpty ? app.T("B", "B") : app.editProfileName).prefix(1)).uppercased()
    }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    BackLink(label: app.T("Tài khoản", "Account")) { app.backFromEditProfile() }
                    Spacer()
                    Text(app.T("Chỉnh sửa hồ sơ", "Edit profile")).font(BanbeTheme.display(16))
                    Spacer()
                    Color.clear.frame(width: 50)
                }

                VStack(spacing: 10) {
                    ZStack {
                        if let url = app.user?.avatarURL, let imageURL = URL(string: url) {
                            AsyncImage(url: imageURL) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                                .frame(width: 84, height: 84).clipShape(Circle())
                        } else {
                            Circle().fill(app.palette.ink).frame(width: 84, height: 84)
                                .overlay(Text(monogram).font(.system(size: 30, weight: .bold)).foregroundStyle(app.palette.paper))
                        }
                    }
                    HStack(spacing: 14) {
                        PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                            Text(app.T("Đổi ảnh", "Change photo")).font(.system(size: 12, weight: .semibold)).foregroundStyle(app.palette.ink)
                        }
                        .accessibilityIdentifier("editProfile.avatarPick")
                        if app.user?.avatarURL != nil {
                            Button(app.T("Xoá ảnh", "Remove photo")) { Task { await app.removeAvatar() } }
                                .font(.system(size: 12)).foregroundStyle(BanbeTheme.alert)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 22)
                .onChange(of: avatarPickerItem) { _, newItem in
                    Task {
                        guard let newItem, let data = try? await newItem.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                        if let url = await app.uploadAvatar(image) { await app.saveProfileFields(avatarURLOverride: url) }
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    field(app.T("Tên người dùng (handle)", "Handle"), prefix: "@", text: Binding(
                        get: { app.editProfileHandle },
                        set: { app.editProfileHandle = $0.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" } }
                    ), id: "editProfile.handle")
                    field(app.T("Tên hiển thị", "Display name"), text: $app.editProfileName, id: "editProfile.name")
                    field(app.T("Giới thiệu ngắn", "Short bio"), text: $app.editProfileBio, id: "editProfile.bio")
                    field(app.T("Khu vực (không bắt buộc)", "City (optional)"), text: $app.editProfileCity, id: "editProfile.city")
                    field(app.T("Sở thích, cách nhau bởi dấu phẩy", "Interests, comma-separated"), text: $app.editProfileInterests, id: "editProfile.interests")

                    VStack(alignment: .leading, spacing: 8) {
                        Text(app.T("Bảng màu hồ sơ", "Profile palette")).font(.system(size: 11.5)).foregroundStyle(app.palette.ink)
                        HStack(spacing: 10) {
                            ForEach(ProfilePalette.all, id: \.key) { p in
                                Circle().fill(p.color).frame(width: 34, height: 34)
                                    .overlay(Circle().stroke(app.palette.ink, lineWidth: app.editProfileTheme == p.key ? 2.5 : 0))
                                    .onTapGesture { app.editProfileTheme = p.key }
                                    .accessibilityIdentifier("editProfile.theme.\(p.key)")
                            }
                        }
                    }

                    if !app.editProfileError.isEmpty {
                        Text(app.editProfileError).font(.system(size: 12)).foregroundStyle(BanbeTheme.alert)
                    }

                    InkButton(title: app.editProfileBusy ? app.T("Đang lưu…", "Saving…") : app.T("Lưu", "Save"), enabled: canSave) {
                        Task { await app.saveProfileFields() }
                    }
                    .accessibilityIdentifier("editProfile.save")

                    if let handle = app.user?.handle, !handle.isEmpty {
                        Button(app.T("Xem hồ sơ công khai của bạn", "View your public profile")) {
                            app.openPublicProfile(handle: handle, back: .editProfile)
                        }
                        .font(.system(size: 12.5)).foregroundStyle(app.palette.ink.opacity(0.75))
                        .frame(maxWidth: .infinity).padding(.top, 10).padding(.bottom, 30)
                        .accessibilityIdentifier("editProfile.preview")
                    }
                }
                .padding(.top, 22)
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 20).padding(.top, 16)
        }
    }

    @ViewBuilder
    private func field(_ label: String, prefix: String? = nil, text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 11.5)).foregroundStyle(app.palette.ink)
            HStack {
                if let prefix { Text(prefix).font(.system(size: 13)).foregroundStyle(app.palette.ink.opacity(0.6)) }
                TextField("", text: text).font(.system(size: 13)).accessibilityIdentifier(id)
            }
            .padding(11)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

struct ProfilePalette {
    let key: String
    let color: Color
    static let all: [ProfilePalette] = [
        ProfilePalette(key: "default", color: Color(red: 0.93, green: 0.91, blue: 0.85)),
        ProfilePalette(key: "rose", color: Color(red: 0.91, green: 0.79, blue: 0.76)),
        ProfilePalette(key: "moss", color: Color(red: 0.78, green: 0.80, blue: 0.70)),
        ProfilePalette(key: "ink", color: Color(red: 0.23, green: 0.21, blue: 0.19)),
        ProfilePalette(key: "sand", color: Color(red: 0.89, green: 0.83, blue: 0.71)),
    ]
}
