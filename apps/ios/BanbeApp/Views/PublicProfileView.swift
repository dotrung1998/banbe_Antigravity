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

                    // Real, explicit, ACCEPTED event contributions only —
                    // never derived from ticket attendance/bookings/
                    // check-ins. Absent entirely if none.
                    if let credited = p.creditedEvents, !credited.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(app.T("Đã tham gia tổ chức", "Helped organize"))
                                .font(.system(size: 11.5, weight: .semibold)).opacity(0.7)
                            ForEach(credited) { ev in
                                Button { app.goEvent(ev.eventId) } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ev.eventName).font(.system(size: 12.5))
                                        Text(ev.organizerName).font(.system(size: 11)).opacity(0.6)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(app.palette.ink)
                            }
                        }
                        .padding(.top, 14)
                        .accessibilityIdentifier("publicProfile.creditedEvents")
                    }

                    Button(app.T("Hiển thị mã QR", "Show QR code")) { qrOpen = true }
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(app.palette.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(app.palette.rule))
                        .padding(.top, 16)
                        .accessibilityIdentifier("publicProfile.qrCta")

                    // iPhone fix pass — "Chỉnh sửa hồ sơ" beneath "Hiển thị
                    // mã QR", own-profile only (never rendered for a
                    // visitor viewing someone else's page — the edit RPC
                    // itself is owner-gated server-side regardless). Edits
                    // profiles fields ONLY — never organizers.name/about/
                    // avatarPath, which live on the organizer's own
                    // separate editor now (OrganizerProfileView).
                    if isOwnProfile {
                        Button(app.T("Chỉnh sửa hồ sơ", "Edit profile")) { app.openEditProfile() }
                            .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(app.palette.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(app.palette.rule))
                            .padding(.top, 10)
                            .accessibilityIdentifier("publicProfile.editPersonal")
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
            // Personal-vs-organizer hierarchy pass — always the PERSON's
            // own name first (never swapped for organizers.name any more).
            Text(p.displayName ?? "").font(BanbeTheme.display(21)).accessibilityIdentifier("publicProfile.displayName")
            // Only when this profile truly owns that organizer — a plain
            // pointer to who they are, not a second mini-dashboard (event/
            // follower stats and the follow CTA now live on the
            // organizer's own separate page, OrganizerProfileView).
            // Account extension (2026-09-27, Stage 1) — hidden for every
            // visitor (not just the owner) while THIS profile's own
            // organizer_mode is off (migration 096) — same rule as web.
            if let org = p.organizer, p.organizerMode == true {
                Text(app.T("Founder tổ chức: \(org.name)", "Founder of \(org.name)"))
                    .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.7))
                    .accessibilityIdentifier("publicProfile.founderLine")
            }
            Text("@\(p.handle ?? "")" + (p.city?.isEmpty == false ? " ▪︎ \(p.city!)" : ""))
                .font(.system(size: 12.5)).foregroundStyle(app.palette.ink.opacity(0.75))
            if let bio = p.bio, !bio.isEmpty {
                Text(bio).font(.system(size: 12.5)).multilineTextAlignment(.center).foregroundStyle(app.palette.ink)
            }
            // Organizer Team pass (2026-09-27, Stage 3) — SEPARATE
            // long-form intro; `bio` above is untouched.
            LongIntroPreview(text: p.introLong)
            SocialLinksRow(links: p.socialLinks)
            if let interests = p.interests, !interests.isEmpty {
                HStack(spacing: 6) {
                    ForEach(interests, id: \.self) { tag in
                        Text(tag).font(.system(size: 10.5, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.white.opacity(0.5), in: Capsule())
                    }
                }
            }
            // Organizer Team pass (2026-09-27, Stage 2) — ONLY this
            // profile's OWN opted-in choice (teamBadges): accepted AND
            // currently public_visible. Hiding Team association removes
            // this badge (and credited events below) in the same instant
            // server-side.
            if let badges = p.teamBadges, !badges.isEmpty {
                HStack(spacing: 6) {
                    ForEach(badges) { badge in
                        Button {
                            Task { await app.openOrganizerTeam(organizerID: badge.organizerId, back: .publicProfile) }
                        } label: {
                            Text(app.T("Thành viên của \(badge.organizerName) Team", "Member of the \(badge.organizerName) Team"))
                                .font(.system(size: 10.5, weight: .semibold))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color.white.opacity(0.7), in: Capsule())
                                .overlay(Capsule().stroke(app.palette.rule))
                                .foregroundStyle(app.palette.ink)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("publicProfile.teamBadge.\(badge.organizerId)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28).padding(.horizontal, 22)
        .background(LinearGradient(colors: [paletteColor.opacity(0.8), paletteColor.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityIdentifier("publicProfile.card")
    }
}
