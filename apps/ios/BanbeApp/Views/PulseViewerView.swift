import SwiftUI
import UIKit

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
    // TASK A7 (2026-10-03 fix pass) — interactive swipe-to-dismiss for the
    // fullScreenCover presentation (a plain `.fullScreenCover` has no
    // built-in interactive dismiss the way `.sheet` does). Attached ONLY
    // to the header row below (title/tabs/close button), never to the
    // ScrollView — so a downward drag on the card list still scrolls it
    // normally instead of competing for the same gesture, and tab
    // switching/the organizer sheet's own presentation are untouched.
    @GestureState private var dragOffset: CGFloat = 0
    private let dismissThreshold: CGFloat = 120

    // TASK 3 (2026-10-05 fix pass) — real iOS-style edge swipe-back: drag
    // from the LEFT SCREEN EDGE toward the right, live-following the
    // finger, same affordance RootView's own `edgeSwipe` gives every other
    // screen (a `.fullScreenCover` doesn't inherit that — it's a wholly
    // separate presentation, not part of RootView's ZStack). Confined to a
    // thin leading strip (`edgeZoneWidth`) via `.highPriorityGesture`,
    // exactly like RootView's own — see that gesture's doc comment for why
    // a screen-wide gesture would instead end up arbitrating against every
    // ordinary vertical scroll/tap for every touch, which is what would
    // "steal" them. Attached to the WHOLE body below (content included),
    // not just the header — a real edge-originated drag is unambiguous
    // (nothing else recognizes touches starting in that strip), so there's
    // no separate reason to restrict it to the header the way the
    // downward drag above deliberately is.
    @GestureState private var edgeDragOffset: CGFloat = 0
    private let edgeZoneWidth: CGFloat = 20

    private var edgeSwipe: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .updating($edgeDragOffset) { value, state, _ in
                state = max(0, value.translation.width)
            }
            .onEnded { value in
                let width = UIScreen.main.bounds.width
                let crossedDistance = value.translation.width > width * 0.3
                let flicked = value.predictedEndTranslation.width > width * 0.6
                if crossedDistance || flicked {
                    app.closePulseViewer()
                }
                // A cancelled/partial swipe just needs nothing further —
                // `edgeDragOffset` (a `@GestureState`) snaps back to 0 on
                // its own the instant the gesture ends, animated by the
                // `.animation(_:value:)` below.
            }
    }

    private var items: [PulseItem] { app.pulseTab == .weekly ? app.pulseWeekly : app.pulseDaily }
    private var loading: Bool {
        switch app.pulseTab {
        case .weekly: return app.pulseWeeklyLoading
        case .daily: return app.pulseDailyLoading
        case .photos: return app.pulsePhotosLoading
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text(app.T("Banbe Pulse", "Banbe Pulse")).font(BanbeTheme.display(20))
                    Spacer()
                    Button { app.closePulseViewer() } label: {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(app.palette.ink)
                    }
                    .accessibilityIdentifier("pulse.close")
                }
                .padding(.horizontal, 20).padding(.top, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        tabButton(.daily, app.T("Hôm nay", "Today"))
                        tabButton(.weekly, app.T("Tuần này", "This week"))
                        // TASK 4 (2026-09-25 fix pass) — third tab: ranked
                        // individual event photos, a separate list from
                        // the two event-level tabs above.
                        tabButton(.photos, app.T("Ảnh nổi bật", "Featured photos"))
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.top, 16)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 8)
                    .updating($dragOffset) { value, state, _ in
                        // Downward only — an upward drag from the header
                        // has nothing to do (there's no content above it
                        // to reveal), so it's ignored rather than fighting
                        // the release-snap-back animation for no reason.
                        state = max(0, value.translation.height)
                    }
                    .onEnded { value in
                        if value.translation.height > dismissThreshold {
                            app.closePulseViewer()
                        }
                    }
            )

            ScrollView {
                VStack(spacing: 10) {
                    if loading {
                        Text(app.T("Đang tải…", "Loading…"))
                            .font(.system(size: 13)).foregroundStyle(app.palette.ink.opacity(0.6))
                            .padding(.top, 60)
                            .accessibilityIdentifier("pulse.loading")
                    } else if app.pulseTab == .photos {
                        if app.pulsePhotos.isEmpty {
                            Text(app.T("Chưa có dữ liệu xếp hạng.", "Nothing ranked yet."))
                                .font(.system(size: 13)).foregroundStyle(app.palette.ink.opacity(0.7))
                                .padding(.top, 60)
                                .accessibilityIdentifier("pulse.empty")
                        } else {
                            ForEach(Array(app.pulsePhotos.enumerated()), id: \.element.id) { i, item in
                                pulsePhotoCard(item, rank: i + 1)
                            }
                        }
                    } else if items.isEmpty {
                        Text(app.T("Chưa có dữ liệu xếp hạng.", "Nothing ranked yet."))
                            .font(.system(size: 13)).foregroundStyle(app.palette.ink.opacity(0.7))
                            .padding(.top, 60)
                            .accessibilityIdentifier("pulse.empty")
                    } else {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                            pulseCard(item, rank: i + 1)
                        }
                    }
                }
                .padding(20)
            }
        }
        .background(app.palette.paper.ignoresSafeArea())
        .offset(x: edgeDragOffset, y: dragOffset)
        .animation(.interactiveSpring(), value: dragOffset)
        .animation(isDraggingEdge ? nil : .interactiveSpring(), value: edgeDragOffset)
        // A sliver of dimming that fades out as the edge-swipe progresses —
        // the same depth cue RootView's own edge-swipe gives every other
        // screen (see that gesture's `peekOffset`/dimming comment).
        .overlay(Color.black.opacity(max(0, 0.12 - Double(edgeDragOffset) / 1400)).ignoresSafeArea().allowsHitTesting(false))

        // The edge-swipe hit zone — a thin leading strip, exactly like
        // RootView's own `edgeSwipe`. `.highPriorityGesture` so a touch
        // starting in this strip always wins over the ScrollView beneath
        // it instead of the two arbitrating; a touch outside it is never
        // even offered to this recognizer (see `edgeZoneWidth`'s own
        // comment), so ordinary vertical scroll, tab switching, a photo
        // tap, and the organizer sheet's own gestures are all untouched.
        Color.clear
            .contentShape(Rectangle())
            .frame(width: edgeZoneWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .highPriorityGesture(edgeSwipe)
        }
        .sheet(item: $app.pulseOrganizerSheet) { item in
            organizerSheet(item)
                .presentationDetents([.height(260)])
        }
        // TASK 5 (2026-09-25 fix pass) — the ranked-photo popup: photo,
        // organizer identity/verified badge, a real like toggle, share,
        // and a "view event" action, same shape as `organizerSheet` above.
        .sheet(item: $app.pulsePhotoSheet) { item in
            photoSheet(item)
                .presentationDetents([.height(360)])
        }
    }

    // `edgeDragOffset` is a `@GestureState`, so it's only ever nonzero
    // WHILE a drag is live — good enough to key "don't spring-animate every
    // per-frame update of a live drag" off directly, matching RootView's
    // own `dragTranslation > 0` check for the identical reason (a spring
    // chasing a continuously-moving target reads as laggy, not smooth).
    private var isDraggingEdge: Bool { edgeDragOffset > 0 }

    @ViewBuilder
    private func tabButton(_ tab: PulseTab, _ label: String) -> some View {
        Button(label) { app.pulseTab = tab }
            .font(.system(size: 12.5, weight: .semibold))
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(app.pulseTab == tab ? app.palette.ink : Color.clear, in: Capsule())
            .foregroundStyle(app.pulseTab == tab ? app.palette.paper : app.palette.ink)
            .overlay(Capsule().stroke(app.pulseTab == tab ? .clear : app.palette.rule))
            .buttonStyle(.plain)
            .fixedSize()
    }

    // 2026-09-25 fix pass — shares a ranked photo via the real native share
    // sheet, logging `photo_shares` ONLY on the sheet's own
    // `completionWithItemsHandler` reporting `completed == true` — never
    // merely from presenting it (matches this ticket's own explicit "not
    // merely opening a share sheet" instruction; the existing
    // `PhotoViewerView` share helper does NOT do this — it flips its own
    // "shared" flag at presentation time — so this is a deliberately new,
    // correct helper, not a reuse of that one). Link carries `pid` (the
    // real `event_photos` id) through `/api/photo-share`, the SAME OG-tag
    // endpoint `sharePhotoOrganizer`'s web equivalent already uses,
    // extended (not duplicated) to also resolve a real photo row server-side.
    private func sharePulsePhoto(_ item: PulsePhotoItem) {
        guard let url = URL(string: "https://banbe-two.vercel.app/api/photo-share?pid=\(item.photoId)") else { return }
        let title = app.T("Ảnh từ \(item.organizerName) trên banbe", "A photo from \(item.organizerName) on banbe")
        let activity = UIActivityViewController(activityItems: [title, url], applicationActivities: nil)
        activity.completionWithItemsHandler = { _, completed, _, _ in
            guard completed else { return }
            Task { await app.logPulsePhotoShare(item.photoId) }
        }
        UIApplication.shared.topViewController?.present(activity, animated: true)
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

    // TASK 4 (2026-09-25 fix pass) — a ranked-photo row: rank + like/share
    // counts, tapping opens the compact popup below (never navigates
    // immediately — same rule the organizer-identity sheet already
    // follows).
    @ViewBuilder
    private func pulsePhotoCard(_ item: PulsePhotoItem, rank: Int) -> some View {
        Button { app.openPulsePhotoSheet(item) } label: {
            HStack(spacing: 0) {
                ZStack {
                    app.palette.field
                    if let urlStr = eventPhotoURL(item.photoPath), let url = URL(string: urlStr) {
                        AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                    }
                }
                .frame(width: 88, height: 88)
                .clipped()

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("#\(rank)").font(.system(size: 11, weight: .bold)).foregroundStyle(app.palette.ink.opacity(0.5))
                        Text(item.eventName).font(BanbeTheme.display(14)).lineLimit(1)
                    }
                    Text(item.organizerName + (item.organizerVerified ? " ✓" : ""))
                        .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.75))
                    Text(app.T("\(item.likeCount) lượt thích ▪︎ \(item.shareCount) lượt chia sẻ",
                               "\(item.likeCount) likes ▪︎ \(item.shareCount) shares"))
                        .font(.system(size: 11)).foregroundStyle(app.palette.ink.opacity(0.6))
                }
                .padding(.horizontal, 14)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("pulse.photoCard")
    }

    // TASK 5 (2026-09-25 fix pass) — photo + organizer identity/verified
    // badge + a real like toggle + share + "view event", same shape as
    // `organizerSheet` above.
    @ViewBuilder
    private func photoSheet(_ item: PulsePhotoItem) -> some View {
        VStack(spacing: 10) {
            Capsule().fill(app.palette.rule).frame(width: 36, height: 4).padding(.top, 8)
            ZStack {
                app.palette.field
                if let urlStr = eventPhotoURL(item.photoPath), let url = URL(string: urlStr) {
                    AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                }
            }
            .frame(width: 160, height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.top, 8)

            Text(item.organizerName + (item.organizerVerified ? " ✓" : "")).font(BanbeTheme.display(17))
            if item.organizerVerified {
                Text(app.T("Đã xác minh", "Verified")).font(.system(size: 11)).foregroundStyle(app.palette.ink.opacity(0.7))
            }

            HStack(spacing: 10) {
                Button {
                    Task { await app.togglePulsePhotoLike(item.photoId) }
                } label: {
                    let liked = app.pulsePhotoLiked[item.photoId] == true
                    Text((liked ? app.T("♥ Đã thích", "♥ Liked") : app.T("♡ Thích", "♡ Like")) + " · \(item.likeCount)")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(liked ? app.palette.ink : Color.clear, in: Capsule())
                        .foregroundStyle(liked ? app.palette.paper : app.palette.ink)
                        .overlay(Capsule().stroke(liked ? .clear : app.palette.rule))
                        .opacity(app.pulsePhotoBusy[item.photoId] == true ? 0.6 : 1)
                }
                .buttonStyle(.plain)
                .disabled(app.pulsePhotoBusy[item.photoId] == true)
                .accessibilityIdentifier("pulse.photoLike")

                Button {
                    sharePulsePhoto(item)
                } label: {
                    Text(app.T("Chia sẻ", "Share") + " · \(item.shareCount)")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .overlay(Capsule().stroke(app.palette.rule))
                        .foregroundStyle(app.palette.ink)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pulse.photoShare")
            }
            .padding(.top, 6)

            Button(app.T("Xem sự kiện / trang tổ chức", "View event / host page")) {
                app.closePulsePhotoSheet()
                app.closePulseViewer()
                app.goEvent(item.eventId)
            }
            .font(.system(size: 12)).foregroundStyle(app.palette.ink).underline()
            .padding(.top, 4)
            .accessibilityIdentifier("pulse.photoViewEvent")
            Spacer()
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 22)
        .background(app.palette.paper.ignoresSafeArea())
    }
}
