import SwiftUI

/// Port of src/screens/Organizer.jsx — the public organizer page: name and
/// track record, Instagram, follow toggle, bio, their current events, and
/// their photo grid, with "Message <host>" pinned at the bottom.
struct OrganizerView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.openURL) private var openURL

    private var event: CatalogEvent { app.currentEvent }
    private var following: Bool { app.following.contains(event.key) }
    private var orgEvents: [CatalogEvent] {
        EventCatalog.all.filter { $0.orgName == event.orgName && $0.isOpen }
    }

    var body: some View {
        ZStack {
            app.palette.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        BackLink(label: event.name) { app.backToEvent() }
                            .padding(.bottom, 16)

                        Text(app.T("Người tổ chức", "Organizer")).font(.system(size: 11.5))

                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(event.orgName).font(BanbeTheme.display(29))
                            if event.orgTrusted {
                                Text(app.T("Tổ chức lâu năm", "Established host"))
                                    .font(.system(size: 13, weight: .medium))
                            }
                        }
                        .padding(.top, 8)

                        if event.orgTrusted {
                            Text(app.T(
                                "Tổ chức từ \(event.orgSince) ▪︎ \(event.orgCount) sự kiện",
                                "Hosting since \(event.orgSince) ▪︎ \(event.orgCount) events"
                            ))
                            .font(.system(size: 12))
                            .padding(.top, 4)
                        }

                        HStack(spacing: 14) {
                            Button(event.orgIg) {
                                let handle = event.orgIg.replacingOccurrences(of: "@", with: "")
                                if let url = URL(string: "https://instagram.com/\(handle)") { openURL(url) }
                            }
                            .font(.system(size: 13))

                            Button { app.toggleFollow(event.key) } label: {
                                Text(following
                                     ? app.T("Đang theo dõi ▪︎ sẽ báo sự kiện mới", "Following ▪︎ new events by email")
                                     : app.T("Theo dõi", "Follow"))
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 14).padding(.vertical, 7)
                                    .overlay(Capsule().stroke(following ? .clear : app.palette.rule, lineWidth: 1))
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 10)

                        Text(event.orgDesc)
                            .font(.system(size: 14))
                            .lineSpacing(4)
                            .padding(.top, 16)

                        Text(app.T("Sự kiện đang mở", "Current events"))
                            .font(.system(size: 11.5, weight: .semibold))
                            .padding(.top, 26)

                        VStack(spacing: 0) {
                            ForEach(orgEvents) { item in
                                Button { app.goEvent(item.key) } label: {
                                    HStack(spacing: 12) {
                                        CatalogPhoto(path: item.img, height: 52, width: 52)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.name).font(BanbeTheme.display(15)).lineLimit(1)
                                            Text(app.trStatus(app.stripKm(item.meta, event: item)))
                                                .font(.system(size: 11.5)).lineLimit(1)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.vertical, 12)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if item.key != orgEvents.last?.key {
                                    Divider().overlay(app.palette.rule)
                                }
                            }
                        }
                        .padding(.top, 6)

                        HStack(alignment: .firstTextBaseline) {
                            Text(app.T("Ảnh của", "Photos by") + " \(event.orgName)").font(.system(size: 11.5))
                            Spacer()
                            Text(app.T("do người tổ chức đăng", "posted by the organizer")).font(.system(size: 11))
                        }
                        .padding(.top, 30)

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                            ForEach(Array(event.orgGallery.enumerated()), id: \.offset) { _, path in
                                Button { app.openPhoto(path: path, organizer: event.orgName) } label: {
                                    CatalogPhoto(path: path, height: 158)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 14)
                    }
                    .foregroundStyle(app.palette.ink)
                    .padding(.horizontal, 22)
                    .padding(.top, 16)
                    .padding(.bottom, 30)
                }

                InkButton(title: app.T("Nhắn cho", "Message") + " \(event.hostShort)") { app.goChat() }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
        }
    }
}
