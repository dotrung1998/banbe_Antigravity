import SwiftUI

/// Port of src/screens/Organizer.jsx — the public organizer page: name and
/// track record, Instagram, follow toggle, bio, their current events, and
/// their photo grid, with "Message <host>" pinned at the bottom.
struct OrganizerView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.openURL) private var openURL

    private var event: CatalogEvent { app.currentEvent }
    private var following: Bool { app.following.contains(event.key) }
    // 2026-09-25 fix pass (Task 0 audit) — real, user-visible bug: this
    // organizer's OTHER "current events" (shown to every visitor of this
    // public page) used the raw static catalogue — both `isOpen`
    // (cancelled/endedHoursAgo) and every displayed date (`meta`) came
    // from the frozen catalogue, never live status. Same `applyingLiveStatus`
    // merge `feed`/`myOrgEvents` already use.
    private var orgEvents: [CatalogEvent] {
        EventCatalog.all
            .map { $0.applyingLiveStatus(app.homeLiveEvents[$0.key]) }
            .filter { $0.orgName == event.orgName && $0.isOpen }
    }
    // STAGE B (2026-09-25) — real photo URLs from `app.organizerPhotos`
    // (loadOrganizerPhotos), resolved the same way PulseViewerView's own
    // `eventPhotoURL` already does.
    // Photo-interactions redesign (2026-09-26) — THE EVENTID BUG FIX: this
    // grid spans ALL of an organizer's events, so every photo must carry
    // its OWN `photo.eventId` (already fetched by loadOrganizerPhotos,
    // previously discarded) — not the screen's currently-viewed
    // `event.key`. Previously every photo here was tagged with whichever
    // event happened to be on screen, so PhotoViewerView's "save event"
    // bookmark could silently act on the wrong event.
    private var orgPhotos: [PhotoGalleryItem] {
        app.organizerPhotos.compactMap { photo in
            let relative = photo.storagePath.hasPrefix("event-photos/")
                ? String(photo.storagePath.dropFirst("event-photos/".count))
                : photo.storagePath
            guard let url = try? SupabaseService.client.storage.from("event-photos").getPublicURL(path: relative).absoluteString
            else { return nil }
            return PhotoGalleryItem(id: photo.id.uuidString.lowercased(), url: url, eventId: photo.eventId)
        }
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

                        // STAGE B (2026-09-25) — real `event_photos` rows
                        // (loadOrganizerPhotos, .task below), not the
                        // static demo `orgGallery`. Resolved to full
                        // Supabase Storage public URLs and fed straight
                        // into the SAME `openPhoto`/`PhotoViewerView`
                        // pipeline every other gallery uses — PhotoLoader
                        // was taught to fetch an already-absolute URL
                        // directly (see its own doc comment), so no second
                        // lightbox was needed. A genuinely empty result
                        // shows plain text, never a fake/demo photo
                        // standing in for a real one.
                        if app.organizerPhotosLoading {
                            Text(app.T("Đang tải…", "Loading…"))
                                .font(.system(size: 12.5)).opacity(0.6)
                                .padding(.top, 14)
                        } else if orgPhotos.isEmpty {
                            Text(app.T("Người tổ chức chưa đăng ảnh nào.", "This organizer hasn’t posted any photos yet."))
                                .font(.system(size: 12.5)).opacity(0.6)
                                .padding(.top, 14)
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                                ForEach(Array(orgPhotos.enumerated()), id: \.element.id) { index, photo in
                                    GeometryReader { geo in
                                        Button {
                                            app.openPhoto(gallery: orgPhotos, index: index, organizer: event.orgName, originRect: geo.frame(in: .global))
                                        } label: {
                                            ZStack(alignment: .topTrailing) {
                                                CatalogPhoto(path: photo.url, height: 158)
                                                if app.photoEngagement[photo.id]?.likedByMe == true {
                                                    Image(systemName: "heart.fill")
                                                        .font(.system(size: 13))
                                                        .foregroundStyle(.white)
                                                        .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
                                                        .padding(8)
                                                        .allowsHitTesting(false)
                                                }
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .frame(height: 158)
                                }
                            }
                            .padding(.top, 14)
                        }
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
        // 2026-09-25 fix pass (Task 0 audit) — see `orgEvents`' own
        // comment; this screen can be reached without Home ever having
        // populated `homeLiveEvents`.
        .task { await app.loadHomeLiveEvents() }
        // STAGE B (2026-09-25) — re-fetched whenever the viewed event
        // changes (a shared link/back-navigation can land here for a
        // different organizer entirely).
        .task(id: event.key) { await app.loadOrganizerPhotos(eventKey: event.key) }
    }
}
