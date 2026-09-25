import SwiftUI

/// TASK E (2026-10-01 UX foundation pass) — two tabs ("Hôm nay"/"Tuần
/// này") of ranked public event/organizer cards. Tapping an unfollowed
/// organizer's identity opens a compact sheet with a Follow CTA (never
/// navigates away immediately); tapping the event card navigates straight
/// to the event page.
/// Same "event-photos/" prefix-stripping convention AppState+Data.swift's
/// own eventPhotoByEventId map uses.
private func eventPhotoURL(_ path: String?) -> String? {
    guard let path else { return nil }
    let relative = path.hasPrefix("event-photos/") ? String(path.dropFirst("event-photos/".count)) : path
    return try? SupabaseService.client.storage.from("event-photos").getPublicURL(path: relative).absoluteString
}

struct PulseViewerView: View {
    @EnvironmentObject private var app: AppState

    private var items: [PulseItem] { app.pulseTab == .weekly ? app.pulseWeekly : app.pulseDaily }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(app.T("Banbe Pulse", "Banbe Pulse")).font(BanbeTheme.display(20))
                Spacer()
                Button { app.closePulseViewer() } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(app.palette.ink)
                }
            }
            .padding(.horizontal, 20).padding(.top, 20)

            HStack(spacing: 8) {
                tabButton(.daily, app.T("Hôm nay", "Today"))
                tabButton(.weekly, app.T("Tuần này", "This week"))
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 16)

            ScrollView {
                VStack(spacing: 10) {
                    if items.isEmpty {
                        Text(app.T("Chưa có dữ liệu xếp hạng.", "Nothing ranked yet."))
                            .font(.system(size: 13)).foregroundStyle(app.palette.ink.opacity(0.7))
                            .padding(.top, 60)
                    }
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                        pulseCard(item, rank: i + 1)
                    }
                }
                .padding(20)
            }
        }
        .background(app.palette.paper.ignoresSafeArea())
        .sheet(item: $app.pulseOrganizerSheet) { item in
            organizerSheet(item)
                .presentationDetents([.height(260)])
        }
    }

    @ViewBuilder
    private func tabButton(_ tab: PulseTab, _ label: String) -> some View {
        Button(label) { app.pulseTab = tab }
            .font(.system(size: 12.5, weight: .semibold))
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(app.pulseTab == tab ? app.palette.ink : Color.clear, in: Capsule())
            .foregroundStyle(app.pulseTab == tab ? app.palette.paper : app.palette.ink)
            .overlay(Capsule().stroke(app.pulseTab == tab ? .clear : app.palette.rule))
            .buttonStyle(.plain)
    }

    @ViewBuilder
    private func pulseCard(_ item: PulseItem, rank: Int) -> some View {
        HStack(spacing: 0) {
            Button {
                app.closePulseViewer()
                app.goEvent(item.eventId)
            } label: {
                // TASK E — these are real Supabase Storage `event_photos`
                // rows (approved organizer media), not the bundled static
                // demo catalogue CatalogPhoto/PhotoLoader is built for —
                // resolved straight to a public URL and loaded with
                // AsyncImage instead, same convention AppState+Data.swift's
                // own eventPhotoByEventId map already uses.
                ZStack {
                    app.palette.field
                    if let urlStr = eventPhotoURL(item.photoPath), let url = URL(string: urlStr) {
                        AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                    }
                }
                .frame(width: 88, height: 88)
                .clipped()
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("#\(rank)").font(.system(size: 11, weight: .bold)).foregroundStyle(app.palette.ink.opacity(0.5))
                    Button {
                        app.closePulseViewer()
                        app.goEvent(item.eventId)
                    } label: {
                        Text(item.eventName).font(BanbeTheme.display(14)).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    app.openPulseOrganizerSheet(item)
                } label: {
                    Text(item.organizerName + (item.organizerVerified ? " ✓" : ""))
                        .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.75))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pulse.organizerIdentity")
            }
            .padding(.horizontal, 14)
            Spacer(minLength: 0)
        }
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("pulse.card")
    }

    @ViewBuilder
    private func organizerSheet(_ item: PulseItem) -> some View {
        VStack(spacing: 10) {
            Capsule().fill(app.palette.rule).frame(width: 36, height: 4).padding(.top, 8)
            Text(item.organizerName).font(BanbeTheme.display(19)).padding(.top, 8)
            if item.organizerVerified {
                Text(app.T("Đã xác minh", "Verified")).font(.system(size: 11)).foregroundStyle(app.palette.ink.opacity(0.7))
            }
            Button {
                Task { await app.followPulseOrganizer(item.organizerId) }
            } label: {
                Text(item.following ? app.T("Đang theo dõi", "Following") : app.T("Theo dõi", "Follow"))
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 28).padding(.vertical, 10)
                    .background(item.following ? Color.clear : app.palette.ink, in: Capsule())
                    .foregroundStyle(item.following ? app.palette.ink : app.palette.paper)
                    .overlay(Capsule().stroke(item.following ? app.palette.rule : .clear))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pulse.follow")
            Button(app.T("Xem sự kiện", "View event")) {
                app.closePulseOrganizerSheet()
                app.closePulseViewer()
                app.goEvent(item.eventId)
            }
            .font(.system(size: 12)).foregroundStyle(app.palette.ink).underline()
            .padding(.top, 4)
            Spacer()
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 22)
        .background(app.palette.paper.ignoresSafeArea())
    }
}
