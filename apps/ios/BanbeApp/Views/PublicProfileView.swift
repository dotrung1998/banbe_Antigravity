import SwiftUI

/// TASK D (2026-10-01 UX foundation pass) — what anyone (signed in or not)
/// sees at https://banbe.app/u/<handle>. Organizer mode transforms the
/// SAME card into the organizer presentation (event/follower stats, follow
/// CTA) rather than a second, conflicting persona.
struct PublicProfileView: View {
    @EnvironmentObject private var app: AppState
    @State private var qrOpen = false

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
}
