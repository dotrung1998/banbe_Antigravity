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
                .presentationDetents([.height(300)])
        }
        // TASK 5 (2026-09-25 fix pass) / B5 (2026-09-26 redesign) — the
        // ranked-photo popup is now a real fixed-height sheet at two-thirds
        // of the screen (`.fraction(0.66)`, matching web's `height: '66vh'`)
        // rather than a small fixed-point height.
        .sheet(item: $app.pulsePhotoSheet) { item in
            photoSheet(item)
                .presentationDetents([.fraction(0.66)])
                .presentationDragIndicator(.hidden)
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
    // `PhotoViewerView` share helper does the same, independently, since it
    // also attaches a cached image via `PhotoShareSource` — a legitimate
    // per-surface difference, not a missed reuse). Link carries `pid` (the
    // real `event_photos` id) through `/api/photo-share`, the SAME OG-tag
    // endpoint web's unified `sharePhoto` already uses.
    // 2026-09-26 photo-interactions redesign — logs through the CANONICAL
    // `AppState.logPhotoShare` (replaces the old Pulse-only
    // `logPulsePhotoShare`), so the bumped share count lands in the one
    // shared `photoEngagement` map every surface reads.
    private func sharePulsePhoto(_ item: PulsePhotoItem) {
        guard let url = URL(string: "https://banbe-two.vercel.app/api/photo-share?pid=\(item.photoId)") else { return }
        let title = app.T("Ảnh từ \(item.organizerName) trên banbe", "A photo from \(item.organizerName) on banbe")
        let activity = UIActivityViewController(activityItems: [title, url], applicationActivities: nil)
        activity.completionWithItemsHandler = { _, completed, _, _ in
            guard completed else { return }
            Task { await app.logPhotoShare(item.photoId) }
        }
        UIApplication.shared.topViewController?.present(activity, animated: true)
    }

    /// Canonical engagement for a ranked photo — reads `app.photoEngagement`
    /// first (kept correct by likes/shares done on ANY surface), falling
    /// back to the ranking RPC's own `likeCount`/`shareCount` only until
    /// that map has an entry for this id yet (mirrors web's own
    /// `s.photoEngagement[item.photo_id] || { likeCount: item.like_count,
    /// ... }` fallback).
    private func engagement(_ item: PulsePhotoItem) -> PhotoEngagement {
        app.photoEngagement[item.photoId] ?? PhotoEngagement(likeCount: item.likeCount, shareCount: item.shareCount, likedByMe: false)
    }

    // B — tapping ANYWHERE on a ranked event card now always opens the
    // follow/view-event sheet below (was: only the organizer-name text did
    // this, while tapping the photo/event-name navigated away immediately —
    // one consistent tap target per card now, matching web's own B3 fix).
    // The right-hand breakdown column is a transparent read of the REAL
    // score components migration 086 returns — nothing here is invented.
    @ViewBuilder
    private func pulseCard(_ item: PulseItem, rank: Int) -> some View {
        Button {
            app.openPulseOrganizerSheet(item)
        } label: {
            HStack(spacing: 0) {
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

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("#\(rank)").font(.system(size: 11, weight: .bold)).foregroundStyle(app.palette.ink.opacity(0.5))
                        Text(item.eventName).font(BanbeTheme.display(14)).lineLimit(1)
                    }
                    Text(item.organizerName + (item.organizerVerified ? " ✓" : ""))
                        .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.75))
                        .accessibilityIdentifier("pulse.organizerIdentity")
                    if let included = item.included, !included.isEmpty {
                        Text(app.T("Bao gồm: ", "Includes: ") + included)
                            .font(.system(size: 10)).foregroundStyle(app.palette.ink.opacity(0.55))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 14)
                Spacer(minLength: 0)

                // Right-side breakdown — cat_label pill + booking/check-in/
                // follow counts, every number a field goc_pulse_ranked()
                // actually returns (migration 086). `followCount` is the
                // organizer's TOTAL follower count (a documented proxy,
                // not period-scoped) — copy below deliberately doesn't
                // claim otherwise.
                VStack(alignment: .trailing, spacing: 3) {
                    if let cat = item.catLabel, !cat.isEmpty {
                        Text(cat)
                            .font(.system(size: 9.5, weight: .semibold))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(app.palette.paper, in: Capsule())
                            .foregroundStyle(app.palette.ink)
                            .lineLimit(1)
                    }
                    Text(app.T("\(item.bookingCount) vé", "\(item.bookingCount) bkgs"))
                        .font(.system(size: 9.5)).foregroundStyle(app.palette.ink.opacity(0.65)).lineLimit(1)
                    Text(app.T("\(item.checkinCount) check-in", "\(item.checkinCount) chk-in"))
                        .font(.system(size: 9.5)).foregroundStyle(app.palette.ink.opacity(0.65)).lineLimit(1)
                    Text(app.T("\(item.followCount) theo dõi", "\(item.followCount) follows"))
                        .font(.system(size: 9.5)).foregroundStyle(app.palette.ink.opacity(0.5)).lineLimit(1)
                }
                .frame(width: 82, alignment: .trailing)
                .padding(.trailing, 12)
                .accessibilityIdentifier("pulse.rankBreakdown")
            }
        }
        .buttonStyle(.plain)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("pulse.card")
    }

    // B3 — two large, equal-width, side-by-side rounded buttons instead of
    // a solid Follow pill + a separately-sized underlined "Xem sự kiện"
    // link. "Xem sự kiện" is now always a solid filled primary button
    // (matches web); "Theo dõi"/"Đang theo dõi" keeps its existing
    // filled/outline toggle look.
    @ViewBuilder
    private func organizerSheet(_ item: PulseItem) -> some View {
        VStack(spacing: 10) {
            Capsule().fill(app.palette.rule).frame(width: 36, height: 4).padding(.top, 8)
            Text(item.organizerName).font(BanbeTheme.display(19)).padding(.top, 8)
            if item.organizerVerified {
                Text(app.T("Đã xác minh", "Verified")).font(.system(size: 11)).foregroundStyle(app.palette.ink.opacity(0.7))
            }
            HStack(spacing: 10) {
                Button {
                    Task { await app.followPulseOrganizer(item.organizerId) }
                } label: {
                    Text(item.following ? app.T("Đang theo dõi", "Following") : app.T("Theo dõi", "Follow"))
                        .font(.system(size: 13.5, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14).padding(.horizontal, 10)
                        .background(item.following ? Color.clear : app.palette.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .foregroundStyle(item.following ? app.palette.ink : app.palette.paper)
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(item.following ? app.palette.rule : .clear))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pulse.follow")

                Button {
                    app.closePulseOrganizerSheet()
                    app.closePulseViewer()
                    app.goEvent(item.eventId)
                } label: {
                    Text(app.T("Xem sự kiện", "View event"))
                        .font(.system(size: 13.5, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14).padding(.horizontal, 10)
                        .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .foregroundStyle(app.palette.paper)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pulse.viewEvent")
            }
            .padding(.top, 10)
            Spacer()
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 22)
        .background(app.palette.paper.ignoresSafeArea())
    }

    // TASK 4 (2026-09-25 fix pass) / B4 (2026-09-26 redesign) — a
    // ranked-photo row: rank + a right-side quick-actions column (like,
    // share), each its own tap target — tapping a quick action does NOT
    // also open the popup sheet below (SwiftUI hit-tests the innermost
    // `Button` first, so nesting them as SIBLINGS of the card's own
    // `.onTapGesture`, rather than wrapping the whole card in one `Button`,
    // is what gives each control its own target without a manual
    // stop-propagation call). Tapping anywhere else on the card still opens
    // the sheet. Counts/liked-state read the canonical `photoEngagement`
    // map (`engagement(_:)` above), never a Pulse-local copy.
    @ViewBuilder
    private func pulsePhotoCard(_ item: PulsePhotoItem, rank: Int) -> some View {
        let eng = engagement(item)
        HStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                app.palette.field
                if let urlStr = eventPhotoURL(item.photoPath), let url = URL(string: urlStr) {
                    AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                }
                // Heart rule (Task 3) — rendered ONLY when this user has
                // liked the photo, same `heart.fill` asset
                // PhotoViewerView's own action button already uses; no
                // outline heart badge in the unliked state.
                if eng.likedByMe {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
                        .padding(6)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("pulse.photoCard.liked")
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
            }
            .padding(.horizontal, 14)
            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 8) {
                Button {
                    Task { await app.togglePhotoLike(item.photoId) }
                } label: {
                    HStack(spacing: 4) {
                        Text("\(eng.likeCount)").font(.system(size: 11)).foregroundStyle(app.palette.ink)
                        if eng.likedByMe {
                            Image(systemName: "heart.fill").font(.system(size: 12)).foregroundStyle(app.palette.ink)
                        } else {
                            Text(app.T("Thích", "Like")).font(.system(size: 11)).foregroundStyle(app.palette.ink.opacity(0.55))
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(app.photoEngagementBusy.contains(item.photoId))
                .accessibilityIdentifier("pulse.photoCard.quickLike")

                Button {
                    sharePulsePhoto(item)
                } label: {
                    HStack(spacing: 4) {
                        Text("\(eng.shareCount)").font(.system(size: 11)).foregroundStyle(app.palette.ink.opacity(0.7))
                        Image(systemName: "square.and.arrow.up").font(.system(size: 12)).foregroundStyle(app.palette.ink.opacity(0.7))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pulse.photoCard.quickShare")
            }
            .frame(width: 60)
            .padding(.trailing, 12)
        }
        .contentShape(Rectangle())
        .onTapGesture { app.openPulsePhotoSheet(item) }
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("pulse.photoCard")
    }

    // TASK 5 (2026-09-25 fix pass) / B5 (2026-09-26 redesign) — a real
    // fixed-height sheet, top 2/3 a large `<img>`-equivalent (`.scaledToFit`,
    // never a cropping `.scaledToFill` — portrait AND landscape photos both
    // display honestly, un-cropped) on a near-black background with a drag
    // handle + explicit "×" close button overlaid; bottom 1/3 (scrollable)
    // keeps the organizer identity/verified badge, like/share buttons with
    // counts, and "Xem sự kiện" link. The `GeometryReader` drives the exact
    // 2:1 split against the sheet's own live height (this view fills
    // whatever the `.presentationDetents([.fraction(0.66)])` container
    // below gives it, matching web's `height: '66vh'`).
    @ViewBuilder
    private func photoSheet(_ item: PulsePhotoItem) -> some View {
        let eng = engagement(item)
        GeometryReader { geo in
            VStack(spacing: 0) {
                ZStack {
                    Color(red: 0.047, green: 0.043, blue: 0.035)
                    if let urlStr = eventPhotoURL(item.photoPath), let url = URL(string: urlStr) {
                        AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { Color.clear }
                    }
                    VStack {
                        Capsule().fill(Color.white.opacity(0.55)).frame(width: 36, height: 4)
                            .padding(.top, 10)
                        Spacer()
                    }
                    VStack {
                        HStack {
                            Spacer()
                            Button { app.closePulsePhotoSheet() } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 30, height: 30)
                                    .background(Color.black.opacity(0.5), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .padding(12)
                            .accessibilityIdentifier("pulse-photo-sheet-close")
                        }
                        Spacer()
                    }
                }
                .frame(height: geo.size.height * 2 / 3)
                .clipped()

                ScrollView {
                    VStack(spacing: 8) {
                        Text(item.organizerName + (item.organizerVerified ? " ✓" : "")).font(BanbeTheme.display(16))
                        if item.organizerVerified {
                            Text(app.T("Đã xác minh", "Verified")).font(.system(size: 11)).foregroundStyle(app.palette.ink.opacity(0.7))
                        }

                        HStack(spacing: 10) {
                            // Heart rule (Task 3) — the glyph only ever
                            // renders filled (liked) or not at all; no
                            // outline/empty heart state. Reads/writes the
                            // canonical `photoEngagement` map, so this
                            // matches whatever the quick-action column and
                            // EventDetail/Organizer/PhotoViewer already show
                            // for the same photo id.
                            Button {
                                Task { await app.togglePhotoLike(item.photoId) }
                            } label: {
                                HStack(spacing: 6) {
                                    if eng.likedByMe {
                                        Image(systemName: "heart.fill").font(.system(size: 13))
                                    }
                                    Text(app.T("Thích", "Like") + " · \(eng.likeCount)")
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 18).padding(.vertical, 10)
                                .background(eng.likedByMe ? app.palette.ink : Color.clear, in: Capsule())
                                .foregroundStyle(eng.likedByMe ? app.palette.paper : app.palette.ink)
                                .overlay(Capsule().stroke(eng.likedByMe ? .clear : app.palette.rule))
                                .opacity(app.photoEngagementBusy.contains(item.photoId) ? 0.6 : 1)
                            }
                            .buttonStyle(.plain)
                            .disabled(app.photoEngagementBusy.contains(item.photoId))
                            .accessibilityIdentifier("pulse.photoLike")

                            Button {
                                sharePulsePhoto(item)
                            } label: {
                                Text(app.T("Chia sẻ", "Share") + " · \(eng.shareCount)")
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
                    }
                    .foregroundStyle(app.palette.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 26)
                }
                .frame(height: geo.size.height / 3)
                .background(app.palette.paper)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }
}
