import SwiftUI

/// Port of src/screens/EventDetail.jsx — hero photo with back/share pills,
/// the address as a Maps link, details, organizer row, photo strip, and the
/// bottom action bar (which shows your ticket if you already hold one).
struct EventDetailView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.openURL) private var openURL
    @State private var shareStoryMessage: String?
    @State private var shareConfirmOpen = false

    private var event: CatalogEvent { app.currentEvent }
    // STAGE D (2026-09-25) — real event_photos URLs, replacing the static
    // demo `event.gallery` below.
    // Photo-interactions redesign (2026-09-26) — each entry now carries the
    // photo's real id + its OWN owning event id (every photo here genuinely
    // belongs to `event.key`, since this is a single-event query), not just
    // a bare URL — see `PhotoGalleryItem`'s own doc comment.
    private var realPhotos: [PhotoGalleryItem] {
        app.eventPhotos.compactMap { photo in
            let relative = photo.storagePath.hasPrefix("event-photos/")
                ? String(photo.storagePath.dropFirst("event-photos/".count))
                : photo.storagePath
            guard let url = try? SupabaseService.client.storage.from("event-photos").getPublicURL(path: relative).absoluteString
            else { return nil }
            return PhotoGalleryItem(id: photo.id.uuidString.lowercased(), url: url, eventId: event.key)
        }
    }

    /// Reached from several places, so "back" returns to whichever one you
    /// actually came from, labelled accordingly.
    private var backLabel: String {
        // BUG 3 fix (2026-09-22 follow-up) — an event opened from a story
        // has exactly one consistent origin: StoryViewer, not whichever
        // screen happened to be showing underneath it — the pill used to
        // fall through to the plain `default: "banbe"` case below while
        // `backFromEvent()` actually reopened the story, the same
        // label-vs-behavior contradiction Follow-up bug 2 (just above)
        // already fixed once for Map Explore.
        if app.eventBackIsStory {
            if let host = app.storyReturnHostName { return app.T("Tin của \(host)", "\(host)’s story") }
            return app.T("Story", "Story")
        }
        switch app.eventBackScreen {
        case .dashboard: return app.T("Trang của bạn", "Your dashboard")
        case .organizer: return app.T("Trang tổ chức", "Organizer page")
        case .create: return app.T("Tạo sự kiện", "Create event")
        // Named after whichever list it is ("Going"/"Saved"/"Completed
        // events"), so the pill says where it actually goes.
        case .eventList: return app.eventListTitle
        // Follow-up bug 2: this used to fall through to the "banbe"/Home
        // default below, even though `backFromEvent()` already correctly
        // routed back to Map Explore (eventBackScreen was `.mapExplore`,
        // not `.home`) — the pill *said* "banbe" while *behaving* like it
        // went to the map, which read as wrong regardless of the real
        // destination being correct.
        case .mapExplore: return app.T("Bản đồ", "Map")
        default: return "banbe"
        }
    }

    /// A live booking for this exact event opens the ticket instead of
    /// running the guest through Reserve again.
    private var myBooking: Booking? {
        guard let booking = app.booking,
              booking.eventId == event.key,
              ["pending", "confirmed", "attended"].contains(booking.status)
        else { return nil }
        return booking
    }

    var body: some View {
        ZStack(alignment: .top) {
            app.palette.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        hero
                        details
                    }
                }
                actionBar
            }
            // Task 3 follow-up: back/share used to live INSIDE `hero`,
            // which scrolls away with the rest of the content the instant
            // the user scrolls the photo out of view. Rendered here
            // instead — a ZStack sibling of the ScrollView, not a
            // descendant of it — so they float persistently regardless of
            // scroll position, the same floating-pill treatment the map
            // screen's own back/compass buttons already get.
            backShareRow
        }
        .sheet(isPresented: $shareConfirmOpen) { shareConfirmSheet }
        // STAGE D (2026-09-25) — re-fetched whenever the viewed event
        // changes (this view can be reached repeatedly for different
        // events without ever being torn down, e.g. via `goEvent`).
        .task(id: event.key) { await app.loadEventPhotos(eventID: event.key) }
    }

    // BUG 4 fix (2026-09-22 follow-up) — event cover preview, title/date,
    // and an explicit Cancel/Post choice before anything is written.
    private var shareConfirmSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                CatalogPhoto(path: event.img, height: 64, width: 64, cornerRadius: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.name).font(BanbeTheme.display(15))
                    Text(event.when).font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.7))
                }
            }
            Text(app.T("Sẽ hiển thị dưới dạng story trong 24 giờ.", "This will be visible as a story for 24 hours."))
                .font(.system(size: 12)).foregroundStyle(app.palette.ink.opacity(0.7))
            HStack(spacing: 8) {
                Button(app.T("Hủy", "Cancel")) { shareConfirmOpen = false }
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(app.palette.rule))
                    .accessibilityIdentifier("event.shareToStory.cancel")
                Button {
                    Task {
                        shareConfirmOpen = false
                        let ok = await app.createEventShareStory(eventKey: event.key)
                        shareStoryMessage = ok ? app.T("Đã đăng lên story", "Posted to Story") : app.T("Không đăng được", "Couldn't post")
                        try? await Task.sleep(nanoseconds: 2_400_000_000)
                        shareStoryMessage = nil
                    }
                } label: {
                    Text(app.T("Đăng Story", "Post Story"))
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .foregroundStyle(app.palette.paper)
                        .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityIdentifier("event.shareToStory.confirm")
            }
        }
        .foregroundStyle(app.palette.ink)
        .padding(20)
        .presentationDetents([.height(220)])
    }

    private var backShareRow: some View {
        HStack {
            pill("‹ \(backLabel)") { app.backFromEvent() }
                .accessibilityIdentifier("event.back")
                // Follow-up bug 2: an explicit, map-specific
                // accessibility label — distinct from the visible pill
                // text — so VoiceOver users get the same "this returns
                // to the map, not Home" clarity the sighted fix gives.
                .accessibilityLabel(
                    app.eventBackScreen == .mapExplore
                        ? app.T("Quay lại bản đồ", "Back to map")
                        : "‹ \(backLabel)"
                )
            Spacer()
            pill(app.sharedFlash ? app.T("Đã sao chép link", "Link copied") : app.T("Chia sẻ", "Share")) {
                share()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        // Blocker fix (retention roadmap follow-up) — EventDetail had no
        // save affordance at all before this pass. Uses the exact same
        // isSaved/toggleFavorite Home's own EventCard already does —
        // already catalogue-agnostic (both key off the real `favorites`
        // table by event id), so this works identically for a static demo
        // event and a real host-created one with no special-casing.
        .overlay(alignment: .bottom) {
            HStack {
                Spacer()
                pill(app.isSaved(event.key) ? app.T("Đã lưu", "Saved") : app.T("Lưu", "Save")) {
                    app.toggleFavorite(event.key)
                }
                .accessibilityIdentifier("event.save")
            }
            .padding(.horizontal, 16)
            .offset(y: 44)
        }
    }

    private var hero: some View {
        CatalogPhoto(path: event.img, height: 400, cornerRadius: 0)
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [app.palette.paper.opacity(0), app.palette.paper],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 78)
            }
    }

    private func pill(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(app.palette.ink)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(app.palette.paper.opacity(0.85), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            if app.eventBackScreen != .home {
                Button(app.T("▪︎ Về trang chính", "▪︎ Back to home")) { app.goHome() }
                    .font(.system(size: 11.5))
                    .foregroundStyle(app.palette.ink.opacity(0.65))
                    .buttonStyle(.plain)
                    .padding(.bottom, 10)
            }
            // Task 1a: only when this screen was reached from Home, not
            // from tapping the event inside Map's own sheet list — reuses
            // the exact same `eventBackScreen` convention the "Về trang
            // chính" link above already established, just the opposite
            // condition (that one hides FROM home; this shows only FROM
            // home). `openEventOnMap` reuses MapExploreView's own restored-
            // snapshot mechanism, so the same info card that view already
            // renders for a selected pin/list row appears automatically.
            //
            // BUG 3 fix (2026-09-22 fifteenth follow-up) — the extra
            // `&& !app.eventBackIsStory` used to hide this action entirely
            // whenever Event Detail was reached from a story, even though
            // `goEventFromStory()` sets `eventBackScreen` to whichever
            // screen the story was opened over (Home, in the common case)
            // — the exact same value a Home-origin open would have. This
            // was an origin-visibility bug, not an intentional "no map from
            // story" product decision (nothing about a story origin makes
            // the event's own coordinates less valid) — removed so a
            // story-originated Event Detail shows the same Map action a
            // Home-originated one does, whenever `eventBackScreen == .home`.
            if app.eventBackScreen == .home {
                Button(app.T("▪︎ Xem trên bản đồ", "▪︎ Open in map")) { app.openEventOnMap(event) }
                    .font(.system(size: 11.5))
                    .foregroundStyle(app.palette.ink.opacity(0.65))
                    .buttonStyle(.plain)
                    .padding(.bottom, 10)
                    .accessibilityIdentifier("event.openInMap")
            }
            // Task 4B (2026-09-22 follow-up) — only when the signed-in
            // account actually owns/manages this exact event's organizer
            // (app.myOrgEventKeys, loaded at sign-in from the real
            // event -> organizer -> owner_id/user_id relationship) — never
            // for a goer. UI nicety only; createEventShareStory() re-checks
            // ownership server-side regardless.
            if app.myOrgEventKeys.contains(event.key) {
                // BUG 4 fix (2026-09-22 follow-up) — opens a real confirm
                // step instead of publishing immediately; Cancel writes
                // nothing at all.
                Button {
                    shareConfirmOpen = true
                } label: {
                    Text(app.storyCreateBusy ? app.T("Đang đăng…", "Posting…") : app.T("▪︎ Chia sẻ lên Story", "▪︎ Share to Story"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(app.palette.ink.opacity(app.storyCreateBusy ? 0.4 : 0.65))
                }
                .buttonStyle(.plain)
                .disabled(app.storyCreateBusy)
                .padding(.bottom, 10)
                .accessibilityIdentifier("event.shareToStory")
            }
            if let shareStoryMessage {
                Text(shareStoryMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(app.palette.ink.opacity(0.7))
                    .padding(.bottom, 10)
            }

            HStack(spacing: 8) {
                Text(app.trStatus(event.cat)).font(.system(size: 11.5))
                if event.inviteOnly {
                    Text(app.T("Riêng tư ▪︎ theo lời mời", "Private ▪︎ invite only"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(app.palette.paper)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(app.palette.ink)
                }
            }

            Text(event.name)
                .font(BanbeTheme.display(29))
                .padding(.top, 8)
                .padding(.bottom, 10)

            if let mapsURL = event.mapsURL {
                Button {
                    // Opening directions is the natural moment to also offer
                    // the distance, if that's never been decided.
                    if app.located == nil { app.askLocation() }
                    openURL(mapsURL)
                } label: {
                    Text(app.trStatus(app.stripKm(event.where, event: event)) + " ↗")
                        .font(.system(size: 13))
                        .underline()
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            }

            Text(app.trStatus(event.soldOut ? "Hết chỗ" : event.seatsLong))
                .font(.system(size: 13))
                .padding(.top, 5)

            if event.inviteOnly {
                Text(app.T("Bạn có thể mời thêm 1 người.", "You can bring one +1."))
                    .font(.system(size: 12.5)).padding(.top, 6)
            }

            Text(event.desc)
                .font(.system(size: 14))
                .lineSpacing(4)
                .padding(.top, 20)

            VStack(spacing: 0) {
                Divider().overlay(app.palette.rule)
                detailRow(app.T("Bao gồm", "Included"), value: event.included)
                Button { app.goOrganizer() } label: {
                    detailRow(app.T("Người tổ chức", "Organizer"),
                              value: app.T("Ghé", "Visit") + " \(event.orgName) ›")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("event.organizer")
                if event.orgTrusted {
                    detailRow(app.T("Uy tín", "Track record"), value: app.T(
                        "Tổ chức từ \(event.orgSince) ▪︎ \(event.orgCount) sự kiện",
                        "Hosting since \(event.orgSince) ▪︎ \(event.orgCount) events"
                    ))
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(app.T("Giá", "Price")).font(.system(size: 13))
                    Spacer()
                    Text(app.trStatus(event.price)).font(BanbeTheme.display(23))
                }
                .padding(.top, 16)
            }
            .padding(.top, 22)

            if event.isOpen && !event.isFree {
                Text(app.T(
                    "Nếu sự kiện bị hủy, bạn được hoàn tiền tự động 100%.",
                    "If the event is cancelled, you are automatically refunded in full."
                ))
                .font(.system(size: 11.5))
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
            }

            Text(app.T("Hình ảnh", "Photos"))
                .font(.system(size: 11.5))
                .padding(.top, 28)
            // STAGE D (2026-09-25) — real event_photos rows, not the
            // static demo `event.gallery`. A genuinely photo-less real
            // event shows plain text, never a fake/demo photo standing in
            // for a real one.
            if app.eventPhotosLoading {
                Text(app.T("Đang tải…", "Loading…"))
                    .font(.system(size: 12.5)).opacity(0.6)
                    .padding(.top, 12)
            } else if realPhotos.isEmpty {
                Text(app.T("Chưa có ảnh nào cho sự kiện này.", "No photos for this event yet."))
                    .font(.system(size: 12.5)).opacity(0.6)
                    .padding(.top, 12)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(Array(realPhotos.enumerated()), id: \.element.id) { index, photo in
                            // GeometryReader wraps each thumbnail so its own
                            // tap can read `geo.frame(in: .global)` at the
                            // moment it's tapped — the origin rect the photo
                            // viewer's dismiss animation shrinks back to.
                            GeometryReader { geo in
                                Button {
                                    app.openPhoto(gallery: realPhotos, index: index, organizer: event.orgName, originRect: geo.frame(in: .global))
                                } label: {
                                    ZStack(alignment: .topTrailing) {
                                        CatalogPhoto(path: photo.url, height: 186, width: 148)
                                        // A liked photo gets a filled heart
                                        // badge; an unliked one shows no
                                        // heart glyph at all here — only the
                                        // full-screen viewer's own like
                                        // button (opened by tapping the
                                        // photo) is the discoverable way to
                                        // like it, matching web's rule.
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
                            .frame(width: 148, height: 186)
                            .accessibilityIdentifier("event.photo.\(index)")
                        }
                    }
                }
                .padding(.top, 12)
            }
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 22)
        .padding(.bottom, 30)
    }

    private func detailRow(_ label: String, value: String) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                Text(label).font(.system(size: 13))
                Spacer(minLength: 0)
                Text(value).font(.system(size: 13)).multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 12)
            .foregroundStyle(app.palette.ink)
            Divider().overlay(app.palette.rule)
        }
        // Without this the gap between the label and the value isn't part
        // of the button at all — tapping the middle of the row did nothing.
        .contentShape(Rectangle())
    }

    // A completed event has nothing left to reserve — showing "Reserve"
    // (or even the sold-out waitlist prompt) on something that already
    // happened reads as broken, not just unnecessary.
    private var ended: Bool { event.endedHoursAgo != nil }

    private var actionBar: some View {
        Group {
            if let booking = myBooking, booking.isTicket {
                InkButton(title: app.T("Xem vé của bạn ▪︎ mã \(booking.code ?? "")",
                                       "View your ticket ▪︎ code \(booking.code ?? "")")) {
                    app.openHeld()
                }
            } else if myBooking != nil {
                // TASK B (2026-10-01 UX foundation pass) — myBooking.status
                // (checked below) can be "pending" while payment is still
                // just holding/awaiting verification — this used to
                // unconditionally announce "your ticket" + expose the
                // entry code before there was one. Booking.isTicket is the
                // one shared rule (Booking.swift).
                InkButton(title: app.T("Xem trạng thái thanh toán", "View payment status")) {
                    app.openHeld()
                }
            } else if event.cancelled {
                // Bug 2b (01-hold-payment.md follow-up): `event.cancelled`
                // already existed and was already used elsewhere on this
                // view (the refund note) but this bar never checked it —
                // a cancelled event fell through to the live "Giữ chỗ"
                // default, which then only ever failed later, server-side,
                // via hold_seats()'s own EVENT_NOT_LIVE check. Checked
                // before `ended`/`soldOut` since a cancelled event's stale
                // `seatsRemaining` can still read as available or sold out.
                Text(app.T("Sự kiện đã bị huỷ", "Event has been cancelled"))
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(app.palette.ink)
            } else if ended {
                Text(app.T("Sự kiện đã kết thúc", "Event has ended"))
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(app.palette.ink)
            } else if event.soldOut {
                Button { app.goChat() } label: {
                    Text(app.T("Hết chỗ ▪︎ nhắn để vào danh sách chờ", "Sold out ▪︎ message for waitlist"))
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .foregroundStyle(app.palette.ink)
                }
                .buttonStyle(.plain)
            } else {
                InkButton(title: app.T("Giữ chỗ ▪︎ ", "Reserve ▪︎ ") + app.trStatus(event.price)) {
                    app.goReserve()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .accessibilityIdentifier("event.actionBar")
    }

    /// The web app copies a share link; iOS has a real share sheet.
    private func share() {
        guard let url = URL(string: "https://banbe.app/\(event.key)") else { return }
        let activity = UIActivityViewController(activityItems: [event.name, url], applicationActivities: nil)
        UIApplication.shared.topViewController?.present(activity, animated: true)
    }
}

extension UIApplication {
    /// Topmost view controller — needed to present UIKit's share sheet from
    /// SwiftUI without threading a presenter through every screen.
    var topViewController: UIViewController? {
        let scene = connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
