import SwiftUI

/// "✓ Following" marker next to a host name. Plain inline text — never drawn over an avatar,
/// so it cannot collide with story rings.
struct FollowingBadge: View {
    @EnvironmentObject private var app: AppState
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).accessibilityHidden(true)
            Text(app.T("Đang theo dõi", "Following")).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(app.palette.ink.opacity(0.8))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.T("Đang theo dõi", "Following"))
        .accessibilityIdentifier("following.badge")
    }
}

/// Account > Following. Reads ONLY this account's own `follows` rows; the list is never shown to anyone else.
struct FollowingView: View {
    @EnvironmentObject var app: AppState
    @State private var query = ""
    @State private var confirmID: String?
    @State private var busyID: String?

    private var shown: [FollowedHost] { FollowLogic.filter(app.followedHosts, query: query) }
    private var loading: Bool { app.followedStatus == .loading || app.followedStatus == .idle }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.T("Tài khoản", "Account")) { app.goBack() }
                Text(app.T("Đang theo dõi", "Following"))
                    .font(BanbeTheme.display(27)).padding(.top, 16)
                    .accessibilityAddTraits(.isHeader)
                Text(app.T("Danh sách này chỉ mình bạn thấy.", "Only you can see this list."))
                    .font(.system(size: 13)).opacity(0.75).padding(.top, 8)

                if app.followedStatus == .error && !app.followedError.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(app.followedError).font(.system(size: 13)).foregroundStyle(BanbeTheme.alert)
                        Button { Task { await app.loadFollowedHosts() } } label: {
                            Text(app.T("Thử lại", "Retry")).font(.system(size: 13, weight: .semibold)).underline()
                        }.buttonStyle(.plain).accessibilityIdentifier("following.retry")
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.top, 16)
                }
                if !app.followWriteError.isEmpty {
                    Text(app.followWriteError).font(.system(size: 12.5)).foregroundStyle(BanbeTheme.alert).padding(.top, 12)
                        .accessibilityIdentifier("following.writeError")
                }

                if loading && app.followedHosts.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }.padding(.top, 28)
                        .accessibilityIdentifier("following.loading")
                } else if !loading && app.followedStatus != .error && app.followedHosts.isEmpty {
                    emptyState.padding(.top, 20)
                }

                if !app.followedHosts.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.system(size: 14)).opacity(0.55)
                        TextField(app.T("Tìm tổ chức bạn theo dõi…", "Search hosts you follow…"), text: $query)
                            .font(.system(size: 13.5)).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("following.search")
                        if !query.isEmpty {
                            Button { query = "" } label: { Image(systemName: "xmark.circle.fill").opacity(0.45) }
                                .buttonStyle(.plain).accessibilityLabel(app.T("Xoá", "Clear"))
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.top, 18)

                    Text(app.followedHosts.count == 1 ? app.T("1 tổ chức", "1 host") : app.T("\(app.followedHosts.count) tổ chức", "\(app.followedHosts.count) hosts"))
                        .font(.system(size: 11.5)).opacity(0.65).padding(.top, 12).padding(.bottom, 8)
                        .accessibilityIdentifier("following.count")

                    if shown.isEmpty {
                        Text(app.T("Không có tổ chức nào khớp \"\(query.trimmingCharacters(in: .whitespaces))\".",
                                   "No followed hosts match \"\(query.trimmingCharacters(in: .whitespaces))\"."))
                            .font(.system(size: 13)).frame(maxWidth: .infinity).padding(18)
                            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .accessibilityIdentifier("following.noMatch")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(shown.enumerated()), id: \.element.id) { i, host in
                                row(host)
                                if i < shown.count - 1 { Divider().overlay(app.palette.rule) }
                            }
                        }
                        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 42)
        }
        .task { await app.loadFollowedHosts() }
        .alert(app.T("Bỏ theo dõi?", "Unfollow?"), isPresented: Binding(get: { confirmID != nil }, set: { if !$0 { confirmID = nil } })) {
            Button(app.T("Huỷ", "Cancel"), role: .cancel) { confirmID = nil }
            Button(app.T("Bỏ theo dõi", "Unfollow"), role: .destructive) {
                guard let id = confirmID else { return }
                confirmID = nil
                busyID = id
                Task { await app.setFollowing(id, false); busyID = nil }
            }
        } message: {
            let host = app.followedHosts.first { $0.organizerID == confirmID }
            Text(host?.available == true
                 ? app.T("\(host?.name ?? "") sẽ rời danh sách theo dõi của bạn và story của họ sẽ không còn hiện trên Trang chủ.",
                         "\(host?.name ?? "") will leave your Following list and their stories will stop appearing on Home.")
                 : app.T("Tổ chức này sẽ được xoá khỏi danh sách theo dõi của bạn.", "This host will be removed from your Following list."))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text(app.T("Bạn chưa theo dõi tổ chức nào", "You're not following any hosts yet")).font(.system(size: 14, weight: .semibold))
            Text(app.T("Mở trang của một tổ chức và nhấn Theo dõi để thấy họ ở đây.", "Open a host's page and tap Follow to see them here."))
                .font(.system(size: 12.5)).opacity(0.75).multilineTextAlignment(.center)
            Button { app.screen = .home } label: {
                Text(app.T("Khám phá sự kiện", "Browse events")).font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .background(app.palette.ink, in: Capsule()).foregroundStyle(app.palette.paper)
            }.buttonStyle(.plain).accessibilityIdentifier("following.browse")
        }
        .frame(maxWidth: .infinity).padding(22)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("following.empty")
    }

    @ViewBuilder
    private func row(_ host: FollowedHost) -> some View {
        HStack(spacing: 12) {
            Button {
                if host.available { app.openOrganizerProfile(organizerID: host.organizerID, back: .following) }
            } label: {
                HStack(spacing: 12) {
                    avatar(host)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(host.available ? host.name + (host.verified ? " ✓" : "")
                                            : app.T("Tổ chức này không còn khả dụng", "This host is no longer available"))
                            .font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        FollowingBadge()
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!host.available)
            .accessibilityLabel(host.available ? app.T("Mở trang của \(host.name)", "Open \(host.name)'s page") : app.T("Tổ chức không còn khả dụng", "Host no longer available"))
            .accessibilityIdentifier("following.open.\(host.organizerID)")

            Button { confirmID = host.organizerID } label: {
                Text(app.T("Bỏ theo dõi", "Unfollow")).font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .overlay(Capsule().stroke(app.palette.rule))
                    .opacity(busyID == host.organizerID ? 0.5 : 1)
            }
            .buttonStyle(.plain)
            .disabled(busyID != nil)
            .accessibilityLabel(app.T("Bỏ theo dõi \(host.name)", "Unfollow \(host.name.isEmpty ? "this host" : host.name)"))
            .accessibilityIdentifier("following.unfollow.\(host.organizerID)")
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func avatar(_ host: FollowedHost) -> some View {
        let url = host.available ? MediaURLs.organizerAvatar(path: host.avatarPath, r2Ref: host.avatarR2Ref.isEmpty ? nil : host.avatarR2Ref, variant: .card) : nil
        if let url {
            AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { app.palette.field }
                .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 11, style: .continuous).fill(app.palette.ink).frame(width: 44, height: 44)
                .overlay(Text(host.available ? String(host.name.prefix(1)).uppercased() : "–").font(.system(size: 17, weight: .bold)).foregroundStyle(app.palette.paper))
        }
    }
}
