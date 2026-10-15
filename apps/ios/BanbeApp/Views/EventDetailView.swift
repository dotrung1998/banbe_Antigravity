import SwiftUI

private extension View {
    /// Live vertical scroll offset (0 at the very top), straight from the scroll view where the system provides it
    /// (iOS 18+); older systems rely on the preference-key reading set up by the caller.
    @ViewBuilder func trackingScrollOffset(_ offset: Binding<CGFloat>) -> some View {
        if #available(iOS 18.0, *) {
            self.onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, new in offset.wrappedValue = new }
        } else {
            self
        }
    }
}

private struct EventScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Port of src/screens/EventDetail.jsx — hero photo with back/share pills,
/// the address as a Maps link, details, organizer row, photo strip, and the
/// bottom action bar (which shows your ticket if you already hold one).
struct EventDetailView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.openURL) private var openURL
    @State private var shareStoryMessage: String?
    @State private var shareConfirmOpen = false
    // Intro/included-parity fix pass (2026-09-28) — "Bao gồm"/Included was
    // plain, non-tappable text; now opens a sheet showing the event's own
    // "Giới thiệu sự kiện"/introduction FIRST, then the structured
    // Included items below it — same content web already has, just
    // surfaced differently there (an always-visible intro section plus
    // its own separate included-only sheet) vs. here (one sheet, both).
    @State private var introIncludedSheetOpen = false

    // Airbnb-style layout: the photo is a fixed backdrop that fades out while the rounded info sheet scrolls up over it.
    private let heroHeight: CGFloat = 400
    private let sheetOverlap: CGFloat = 40
    // Matches the iPhone's own screen-corner curvature (~47-55pt on current models).
    private let sheetRadius: CGFloat = 46
    /// With the info fully pulled up, this much of the photo (from the top of the screen) stays visible above it.
    private let pinnedStrip: CGFloat = 120
    @State private var scrollOffset: CGFloat = 0
    // Drag-down-to-close (only from the very top of the scroll view).
    @State private var dismissDrag: CGFloat = 0
    @State private var isDismissDragging = false
    @State private var isDismissing = false
    /// Whether the current touch started with the scroll view already at the very top. Closing is only allowed
    /// then: scrolling up to the top and carrying on in the SAME drag must not close the screen.
    @State private var dragBeganAtTop: Bool?
    /// 0 = shrunk into the card it opened from, 1 = full screen. Flipped (animated) on appear and on close.
    @State private var presented = false
    /// The page itself (background, info sheet, buttons): fades in after the photo starts growing, out before it shrinks.
    @State private var contentShown = false
    private var screenSize: CGSize { UIScreen.main.bounds.size }
    private var bottomInset: CGFloat {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.keyWindow?.safeAreaInsets.bottom ?? 0
    }
    /// Where this screen zooms out of / back into: the tapped card's photo (nil when opened from somewhere with none).
    /// Only meaningful while zooming (opening: the rect captured at the tap; closing: the card's live frame, or that
    /// same rect if the card has scrolled away). At rest, and for opens that did not start from a card, it is nil.
    private var zoomOrigin: CGRect? {
        // Opened from Map: no card to zoom from; the screen opens from, and closes toward, the centre of the screen.
        guard app.eventBackScreen != .mapExplore else { return nil }
        if app.eventOpening { return app.eventOriginRect }
        if isDismissing { return app.zoomOrigin(for: event.key) ?? app.eventOriginRect }
        return nil
    }
    /// True when there is no card to zoom from/into: the whole screen then scales up from the centre and fades.
    private var centerPose: Bool { zoomOrigin == nil }
    private var zoomT: CGFloat { presented ? 1 : 0 }
    /// The cover photo's frame (screen coordinates): the tapped card's photo at 0, the full-bleed cover at 1. With no
    /// card to come from it grows from a slightly inset copy of the cover.
    private var heroFrame: CGRect {
        let full = CGRect(x: 0, y: 0, width: screenSize.width, height: topInset + heroHeight)
        let from = zoomOrigin ?? full
        func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * zoomT }
        return CGRect(x: lerp(from.minX, full.minX), y: lerp(from.minY, full.minY),
                      width: lerp(from.width, full.width), height: lerp(from.height, full.height))
    }
    private func closeAnimated() {
        guard !isDismissing else { return }
        isDismissing = true
        Haptics.light()
        // RootView draws a stand-in underneath only when there is no live screen there (publishing this would make
        // every screen re-render, Home included, mid-animation).
        let live = app.eventHasLiveUnderlay
        if !live { app.eventDismissProgress = max(app.eventDismissProgress, 0.001) }
        withAnimation(.easeIn(duration: centerPose ? 0.34 : 0.22)) { contentShown = false }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.92)) { presented = false; dismissDrag = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.62) {
            app.backFromEvent()
            DispatchQueue.main.async {
                if app.eventDismissProgress != 0 { app.eventDismissProgress = 0 }
                isDismissing = false
            }
        }
    }
    private var topInset: CGFloat {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.keyWindow?.safeAreaInsets.top ?? 0
    }
    private var dismissProgress: CGFloat { min(1, max(0, dismissDrag / 320)) }

    private var event: CatalogEvent { app.currentEvent }
    // STAGE D (2026-09-25) — real event_photos URLs, replacing the static
    // demo `event.gallery` below.
    // Photo-interactions redesign (2026-09-26) — each entry now carries the
    // photo's real id + its OWN owning event id (every photo here genuinely
    // belongs to `event.key`, since this is a single-event query), not just
    // a bare URL — see `PhotoGalleryItem`'s own doc comment.
    private var realPhotos: [PhotoGalleryItem] {
        // Strict invite-only events (migration 113) — app.eventPhotoURLs
        // is already resolved by loadEventPhotos (public getPublicURL or a
        // private-bucket signed URL); a photo with no resolved URL yet
        // (still loading, or resolution failed) is simply omitted rather
        // than shown broken.
        app.eventPhotos.compactMap { photo in
            guard let url = app.eventPhotoURLs[photo.id] else { return nil }
            return PhotoGalleryItem(id: photo.id.uuidString.lowercased(), url: url.absoluteString, eventId: event.key)
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
        case .organizerProfile: return app.T("Trang tổ chức", "Organizer page")
        case .create: return app.T("Tạo Sự Kiện", "Create Event")
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
            // The page background and everything on it fade in AFTER the photo has started growing out of the card
            // (and fade out first when closing), so it reads as the card's photo expanding, not a screen on top.
            app.palette.paper.ignoresSafeArea().opacity(contentShown ? 1 : 0)
            // The photo is a layer of the screen itself (not inside the stack below), so it can reach the very top
            // edge, under the status bar, and both side edges. It is also the shared element: its frame runs from
            // the tapped card's photo to the full-bleed cover (see `heroFrame`).
            heroBackdrop
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .ignoresSafeArea(edges: .top)
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Room for the backdrop photo; the sheet below starts `sheetOverlap` up inside it. This
                        // content starts at the safe-area top, and the photo is `topInset` taller than `heroHeight`.
                        Color.clear.frame(height: topInset + heroHeight - sheetOverlap - pinnedStrip)
                        details
                            .background(
                                app.palette.paper,
                                in: UnevenRoundedRectangle(topLeadingRadius: sheetRadius, topTrailingRadius: sheetRadius, style: .continuous)
                            )
                            .shadow(color: .black.opacity(0.10), radius: 14, y: -4)
                    }
                    .background(GeometryReader { g in
                        Color.clear.preference(key: EventScrollOffsetKey.self, value: -g.frame(in: .named("eventScroll")).minY)
                    })
                }
                .coordinateSpace(name: "eventScroll")
                .onPreferenceChange(EventScrollOffsetKey.self) { if #unavailable(iOS 18.0) { scrollOffset = $0 } }
                .trackingScrollOffset($scrollOffset)
                .scrollDisabled(isDismissDragging)
                .simultaneousGesture(dismissGesture)
                // The scrolling area starts `pinnedStrip` down the screen, with the sheet's own rounded top corners,
                // so a band of the photo stays visible above the info however far it is pulled up.
                .mask { UnevenRoundedRectangle(topLeadingRadius: sheetRadius, topTrailingRadius: sheetRadius, style: .continuous) }
                .padding(.top, max(0, pinnedStrip - topInset))
                actionBar
            }
            .opacity(contentShown ? 1 : 0)
            // Task 3 follow-up: back/share used to live INSIDE `hero`,
            // which scrolls away with the rest of the content the instant
            // the user scrolls the photo out of view. Rendered here
            // instead — a ZStack sibling of the ScrollView, not a
            // descendant of it — so they float persistently regardless of
            // scroll position, the same floating-pill treatment the map
            // screen's own back/compass buttons already get.
            backShareRow.opacity(contentShown ? 1 : 0)
        }
        // No card to come from (Map): the whole screen grows from / shrinks toward the middle of the screen.
        .scaleEffect(centerPose ? 0.84 + 0.16 * zoomT : 1)
        // Drag-down-to-close: the whole screen shrinks toward the middle, rounds off and dims while the screen
        // underneath (RootView peeks it) shows through.
        // A mask that ignores the safe area (a plain clipShape would cut the full-bleed photo off at the status bar).
        .mask { RoundedRectangle(cornerRadius: min(sheetRadius, dismissProgress * 120), style: .continuous).ignoresSafeArea() }
        .scaleEffect(1 - 0.16 * dismissProgress)
        .offset(y: dismissDrag * 0.35)
        .onAppear {
            Haptics.light()
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.9)) { presented = true }
                withAnimation(.easeOut(duration: 0.36).delay(zoomOrigin == nil ? 0 : 0.2)) { contentShown = true }
            }
        }
        .onDisappear { if app.eventDismissProgress != 0 { app.eventDismissProgress = 0 } }
        .sheet(isPresented: $shareConfirmOpen) { shareConfirmSheet }
        .sheet(isPresented: $introIncludedSheetOpen) {
            CardSheet(title: app.T("Giới thiệu & Bao gồm", "About & Included"),
                      closeID: "event.includedSheet.close",
                      onClose: { introIncludedSheetOpen = false }) { introIncludedSheetContent }
        }
        // STAGE D (2026-09-25) — re-fetched whenever the viewed event
        // changes (this view can be reached repeatedly for different
        // events without ever being torn down, e.g. via `goEvent`).
        .task(id: event.key) { await app.loadEventPhotos(eventID: event.key) }
        .task(id: event.key) { await app.loadEventOrgStats(forEventKey: event.key) }
        // Reservation criteria (migration 162): small per-event read; only a
        // restricted event triggers the eligibility pre-check (Everyone = no
        // extra calls/UI). Re-runs when the guest saves new preferences.
        .task(id: "\(event.key)|\(app.eventPrefsVersion)|\(app.isSignedIn)") {
            app.reserveEligibilityBlock = nil
            await app.loadEventCriteria(eventKey: event.key)
            if app.isSignedIn, let c = app.eventCriteriaByKey[event.key], !c.isEveryone {
                await app.recheckReservationEligibility(eventKey: event.key)
            }
        }
    }

    /// Pull down from the very top to close: the screen follows the finger (shrinking), and a long enough pull or a
    /// flick finishes the close with the same shrink-and-fade. Anything else springs back. Never starts mid-scroll.
    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                guard !isDismissing else { return }
                let dx = value.translation.width, dy = value.translation.height
                if dragBeganAtTop == nil { dragBeganAtTop = scrollOffset <= 12 }
                guard dragBeganAtTop == true else { return }
                if !isDismissDragging {
                    guard scrollOffset <= 1, dy > 0, dy > abs(dx) * 1.2 else { return }
                    isDismissDragging = true
                }
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) {
                    dismissDrag = max(0, dy)
                    if !app.eventHasLiveUnderlay { app.eventDismissProgress = max(0.001, dismissProgress) }
                }
            }
            .onEnded { value in
                defer { dragBeganAtTop = nil }
                guard isDismissDragging else { return }
                isDismissDragging = false
                if dismissDrag > 140 || value.predictedEndTranslation.height > 420 {
                    closeAnimated()
                } else {
                    withAnimation(.spring(response: 0.46, dampingFraction: 0.86)) { dismissDrag = 0 }
                    if app.eventDismissProgress != 0 { app.eventDismissProgress = 0 }
                }
            }
    }

    @ViewBuilder
    private var criteriaSection: some View {
        if let c = app.eventCriteriaByKey[event.key], !c.isEveryone {
            VStack(alignment: .leading, spacing: 10) {
                Text(app.T("Ai được đặt chỗ: ", "Who can reserve: ") + c.summary(vi: !app.isEN))
                    .font(.system(size: 12.5, weight: .semibold))
                    .accessibilityIdentifier("event.criteria.summary")
                if let block = app.reserveEligibilityBlock {
                    CriteriaUnmetCard(eligibility: block, returnTo: .event, idPrefix: "event")
                }
            }
            .padding(.bottom, 14)
        }
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
        HStack(alignment: .top) {
            pill("‹ \(backLabel)") { closeAnimated() }
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
            // Share and Save as plain icons side by side. Save uses the same isSaved/toggleFavorite Home's own
            // EventCard does (catalogue-agnostic: keys off the real `favorites` table by event id).
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 10) {
                    iconButton("square.and.arrow.up", label: app.T("Chia sẻ", "Share")) { share() }
                        .accessibilityIdentifier("event.share")
                    iconButton(app.isSaved(event.key) ? "heart.fill" : "heart",
                               label: app.isSaved(event.key) ? app.T("Đã lưu", "Saved") : app.T("Lưu", "Save"),
                               tint: app.isSaved(event.key) ? Color(hex: 0xC8372D) : nil) {
                        app.toggleFavorite(event.key)
                    }
                    .accessibilityIdentifier("event.save")
                }
                if app.sharedFlash {
                    Text(app.T("Đã sao chép link", "Link copied"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(app.palette.ink)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(app.palette.paper.opacity(0.9), in: Capsule())
                        .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    /// Round glass icon button for the photo's top-right corner (same disc treatment as the back pill).
    private func iconButton(_ symbol: String, label: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint ?? app.palette.ink)
                .frame(width: 40, height: 40)
                .background(app.palette.paper.opacity(0.85), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// The cover photo, full-bleed to the top and side edges, pinned behind the scrolling sheet. It fades to the
    /// page colour as the sheet rises over it, and drifts up a little more slowly than the content.
    private var heroBackdrop: some View {
        // Fades only part-way (never to nothing): the strip left above the pulled-up info stays clearly visible.
        let fade = min(1, max(0, scrollOffset / (heroHeight * 0.62))) * zoomT
        let f = heroFrame
        return ZStack { RemoteImage(path: event.img, maxPixel: 1100) }   // no placeholder fill: the card shows through until the photo is ready
            .frame(width: f.width, height: f.height)
            .clipShape(RoundedRectangle(cornerRadius: 14 * (1 - zoomT), style: .continuous))
            .opacity((1 - 0.4 * fade) * (centerPose ? (contentShown ? 1 : 0) : 1))
            .offset(x: f.minX, y: f.minY - min(max(scrollOffset, 0), heroHeight) * 0.3 * zoomT)
            .accessibilityHidden(true)
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
                Button { app.goHome() } label: { linkLabel("house", app.T("Về trang chính", "Back to home")) }
                    .buttonStyle(.plain)
                    .padding(.bottom, 10)
            }
            criteriaSection
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
            // Real-event-maps-link fix pass (2026-09-28) — `event.lat != nil`
            // added: a real event with no confirmed coordinates yet (an
            // older event, or one whose host explicitly skipped
            // confirmation at creation) has nothing for this action to
            // open — honest omission instead of a button that silently
            // no-ops (`openEventOnMap`'s own guard).
            if app.eventBackScreen == .home, event.lat != nil, event.lng != nil {
                Button { app.openEventOnMap(event) } label: { linkLabel("map", app.T("Xem trên bản đồ", "Open in map")) }
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
                    linkLabel("camera", app.storyCreateBusy ? app.T("Đang đăng…", "Posting…") : app.T("Chia sẻ lên Story", "Share to Story"))
                        .opacity(app.storyCreateBusy ? 0.6 : 1)
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
                // Strict invite-only events (migration 113) — leftover
                // "+1" claim from the old static demo catalogue's own
                // fictional flavor text (removed); no such mechanism
                // exists, and this now renders for REAL invite-only
                // events, so it needs to be true, not invented.
                Text(app.T("Sự kiện này chỉ dành cho người được mời.", "This event is invite-only."))
                    .font(.system(size: 12.5)).padding(.top, 6)
            }

            Text(event.desc)
                .font(.system(size: 14))
                .lineSpacing(4)
                .padding(.top, 20)

            VStack(spacing: 0) {
                Divider().overlay(app.palette.rule)
                // Intro/included-parity fix pass (2026-09-28) — was plain
                // text via `detailRow` with no tap target at all. Only
                // shown when there's actually something to open (an intro
                // or at least one structured item) — an event with
                // neither shows nothing here at all, same as before this
                // pass for an event whose `included` string was empty
                // (never a broken empty section).
                if event.intro != nil || !(event.includedItems?.isEmpty ?? true) {
                    Button { introIncludedSheetOpen = true } label: {
                        includedRow
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("event.includedSection")
                    .accessibilityLabel(app.T("Giới thiệu và bao gồm, xem thêm", "Introduction and included, view more"))
                } else if !event.included.isEmpty {
                    detailRow(app.T("Bao gồm", "Included"), value: event.included)
                }
                Button { app.openEventOrganizer(eventKey: app.eventKey) } label: { organizerRow }
                .buttonStyle(.plain)
                .accessibilityIdentifier("event.organizer")
                // Moved here from the retired standalone organizer page.
                Button { app.goChat() } label: {
                    detailRow(app.T("Liên hệ", "Contact"), leading: AnyView(rowIcon("bubble.left")),
                              value: app.T("Nhắn cho", "Message") + " \(event.orgName.isEmpty ? event.hostShort : event.orgName) ›")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("event.messageHost")
                if let stats = app.eventOrganizerID[event.key].flatMap({ app.organizerStats[$0] }), stats.count > 0 {
                    detailRow(app.T("Uy tín", "Track record"), value: stats.sinceYear.map { year in
                        app.T("Tổ chức từ \(year) ▪︎ \(stats.count) sự kiện", "Hosting since \(year) ▪︎ \(stats.count) events")
                    } ?? app.T("\(stats.count) sự kiện", "\(stats.count) events"))
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
        .padding(.top, 30)
        .padding(.bottom, 30)
    }

    /// Small icon + text link used for the quick actions above the title.
    private func linkLabel(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 12.5, weight: .regular))
            Text(text).font(.system(size: 12))
        }
        .foregroundStyle(app.palette.ink.opacity(0.72))
    }

    /// Leading icon for a detail row (a fixed-width column so labels line up).
    private func rowIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .regular))
            .frame(width: 22, height: 22)
            .foregroundStyle(app.palette.ink.opacity(0.8))
    }

    /// The host's small round photo (their initial when there is none), for the Organizer row.
    private var organizerAvatar: some View {
        let stats = app.eventOrganizerID[event.key].flatMap { app.organizerStats[$0] }
        let url = MediaURLs.organizerAvatar(path: stats?.avatarPath, r2Ref: stats?.avatarR2Ref, variant: .thumb)
        return ZStack {
            Circle().fill(app.palette.field)
            if let url {
                RemoteImage(path: url.absoluteString, maxPixel: 96)
            } else {
                Text(String(event.orgName.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .frame(width: 24, height: 24)
        .clipShape(Circle())
        .overlay(Circle().stroke(app.palette.rule, lineWidth: 0.5))
    }

    /// "Organizer ……… (Following) Visit (round photo) Name ›": an icon leads the row like the others, and the host's
    /// round photo sits between the word "Visit" and the name.
    private var organizerRow: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                rowIcon("person.crop.circle")
                Text(app.T("Người tổ chức", "Organizer")).font(.system(size: 13))
                Spacer(minLength: 0)
                if app.isFollowing(app.eventOrganizerID[event.key]) {
                    Text("✓ " + app.T("Đang theo dõi", "Following")).font(.system(size: 13))
                }
                HStack(spacing: 6) {
                    Text(app.T("Ghé", "Visit")).font(.system(size: 13))
                    organizerAvatar
                    Text("\(event.orgName) ›").font(.system(size: 13))
                }
            }
            .padding(.vertical, 12)
            .foregroundStyle(app.palette.ink)
            Divider().overlay(app.palette.rule)
        }
        .contentShape(Rectangle())
    }

    private func detailRow(_ label: String, leading: AnyView? = nil, value: String) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                if let leading { leading.padding(.trailing, -6) }
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

    // Intro/included-parity fix pass (2026-09-28) — same visual shape as
    // `detailRow` above (label left, value right, divider below), but with
    // an explicit "›" chevron so the row reads as navigable at a glance —
    // `detailRow` itself has no chevron since most of its callers (Price,
    // Track record) aren't tappable at all.
    private var includedRow: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                rowIcon("checklist").padding(.trailing, -6)
                Text(app.T("Bao gồm", "Included")).font(.system(size: 13))
                Spacer(minLength: 0)
                Text(includedRowSummary)
                    .font(.system(size: 13))
                    .multilineTextAlignment(.trailing)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .opacity(0.45)
            }
            .padding(.vertical, 12)
            .foregroundStyle(app.palette.ink)
            Divider().overlay(app.palette.rule)
        }
        .contentShape(Rectangle())
    }

    /// The row's own right-aligned preview text — item labels if there are
    /// any, else a generic "has an introduction" hint (an event can have
    /// an intro with zero included items, e.g. a free meetup).
    private var includedRowSummary: String {
        let items = event.includedItems ?? []
        if !items.isEmpty { return items.map(\.label).joined(separator: " ▪︎ ") }
        return app.T("Xem thêm", "View more")
    }

    private var introIncludedSheetContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let intro = event.intro {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(app.T("Giới thiệu sự kiện", "About this event"))
                                .font(.system(size: 11.5, weight: .semibold))
                            // Paragraph breaks on blank lines, same
                            // convention web's own `introParagraphs`
                            // (EventDetail.jsx) uses for the same field.
                            ForEach(Array(intro.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                                Text(paragraph.trimmingCharacters(in: .whitespacesAndNewlines))
                                    .font(.system(size: 13.5))
                                    .lineSpacing(5)
                            }
                        }
                    }
                    let items = event.includedItems ?? []
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(app.T("Bao gồm", "Included"))
                                .font(.system(size: 11.5, weight: .semibold))
                            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.label).font(.system(size: 13.5, weight: .medium))
                                    if !item.detail.isEmpty {
                                        Text(item.detail).font(.system(size: 12.5)).opacity(0.7)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .foregroundStyle(app.palette.ink)
        .accessibilityIdentifier("event.includedSheet")
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
                InkButton(title: app.T("Giữ chỗ ▪︎ ", "Reserve ▪︎ ") + app.trStatus(event.price),
                          enabled: app.reserveEligibilityBlock == nil) {
                    app.goReserve()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .accessibilityIdentifier("event.actionBar")
    }

    /// Shares the event through `/api/photo-share?eid=` (api/photo-share.js), which serves Open Graph tags
    /// with the event's COVER photo as the preview (banbe.app no longer exists, so the old link was dead).
    /// The share sheet itself previews the cover straight from the cache via `PhotoShareSource`.
    private func share() {
        let origin = AppConfig.publicWebOrigin
        guard let id = event.key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(origin)/api/photo-share?eid=\(id)") else { return }
        let text = [event.name, event.where].filter { !$0.isEmpty }.joined(separator: " ▪︎ ")
        Task {
            let image = event.img.isEmpty ? nil : await PhotoLoader.load(path: event.img, maxPixel: 1600)
            await MainActor.run {
                let items: [Any] = [text, PhotoShareSource(image: image, title: event.name, url: url)]
                let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
                UIApplication.shared.topViewController?.present(activity, animated: true)
            }
        }
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
