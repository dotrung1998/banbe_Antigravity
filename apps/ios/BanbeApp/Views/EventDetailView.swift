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

/// The event title's on-screen frame (global), for the title hand-off into the nav bar.
private struct EventTitleFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private struct EventScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Create-event "Public preview" (owner, 2026-10-21): the real Event Detail rendered from an unsaved draft, so the
/// host sees exactly what guests will. Nothing here is fetched or saved; every guest control (save, share, ⋯, the
/// calendar pill, host actions, seat chips, Reserve) is shown but inert. Web twin: `EventDetail({ preview })`.
struct EventDetailPreview {
    enum Photo: Identifiable {
        case local(id: String, image: UIImage)
        case remote(id: String, url: String)
        var id: String { switch self { case .local(let id, _), .remote(let id, _): return id } }
    }
    let event: CatalogEvent
    /// Cover first.
    let photos: [Photo]
    /// Seats the host offered; nothing is booked in a draft, so the bar reads "all free".
    let capacity: Int?
    let backLabel: String
    let onBack: () -> Void
    /// Sits under the (inert) reserve bar: the review sheet's Confirm & submit.
    let footer: AnyView
}

/// Port of src/screens/EventDetail.jsx — hero photo with back/share pills,
/// the address as a Maps link, details, organizer row, photo strip, and the
/// bottom action bar (which shows your ticket if you already hold one).
struct EventDetailView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.openURL) private var openURL
    /// Non-nil = the create-event Public preview (see `EventDetailPreview`).
    let preview: EventDetailPreview?
    private var isPreview: Bool { preview != nil }

    init(preview: EventDetailPreview? = nil) {
        self.preview = preview
    }
    @State private var shareStoryMessage: String?
    @State private var shareConfirmOpen = false
    // Intro/included-parity fix pass (2026-09-28) — "Bao gồm"/Included was
    // plain, non-tappable text; now opens a sheet showing the event's own
    // "Giới thiệu sự kiện"/introduction FIRST, then the structured
    // Included items below it — same content web already has, just
    // surfaced differently there (an always-visible intro section plus
    // its own separate included-only sheet) vs. here (one sheet, both).
    @State private var introIncludedSheetOpen = false
    /// "Link copied" flash after the ⋯ menu's Copy link.
    @State private var linkCopied = false
    /// L8 "Copied. Paste it in Zalo." flash after the ⋯ menu's Copy invite for Zalo.
    @State private var zaloCopied = false
    /// Phase 1 Q3: "Next from this host" on an ended page (up to 3 live events still ahead).
    @State private var hostNext: [AppState.HostUpcomingEvent] = []
    /// Where the in-sheet title is right now (global), measured from its layout frame (its own fade/shrink transforms
    /// don't move that, so there is no feedback loop).
    @State private var titleFrame: CGRect = .zero
    /// Bumped by the blocked bar's "see why" tap; the scroll view scrolls the criteria card into view.
    @State private var criteriaScrollRequest = 0
    /// About's "Read more" expanded the description in place (note 68).
    @State private var aboutExpanded = false

    // Airbnb-style layout: the photo is a fixed backdrop that fades out while the rounded info sheet scrolls up over it.
    /// 320 (was 400, note 68): with the sheet's overlap, Date / Time / Place, the Host row and the CTA fit a 6.1" phone.
    private let heroHeight: CGFloat = 320
    private let sheetOverlap: CGFloat = 40
    // Matches the iPhone's own screen-corner curvature (~47-55pt on current models).
    private let sheetRadius: CGFloat = 46
    /// With the info fully pulled up, this much of the photo (from the top of the screen) stays visible above it.
    private let pinnedStrip: CGFloat = 120
    @State private var scrollOffset: CGFloat = 0
    // Drag-down-to-close (only from the very top of the scroll view).
    @State private var dismissDrag: CGFloat = 0
    @State private var isDismissDragging = false
    /// The drag has passed the point where letting go closes the screen (the one haptic tick of a close, note 47).
    @State private var dismissArmed = false
    @State private var isDismissing = false
    /// Whether the current touch started with the scroll view already at the very top. Closing is only allowed
    /// then: scrolling up to the top and carrying on in the SAME drag must not close the screen.
    @State private var dragBeganAtTop: Bool?
    /// 0 = shrunk into the card it opened from, 1 = full screen. Flipped (animated) on appear and on close.
    @State private var presented = false
    /// The page itself (background, info sheet, buttons): fades in after the photo starts growing, out before it shrinks.
    @State private var contentShown = false
    /// Where the cover photo actually was on screen the moment a close began (drag pose included). The close then
    /// runs from here straight into the card — the same path as the Back button — instead of unwinding the drag
    /// pose on top of the shrink, which made the photo dip below the card until the screen switched (note 47).
    @State private var closeStart: CGRect?
    /// Centre (global) of the page layers the drag pose scales around; the photo is posed with the same numbers.
    @State private var poseAnchor: CGPoint = .zero
    private var screenSize: CGSize { UIScreen.main.bounds.size }
    private var bottomInset: CGFloat {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.keyWindow?.safeAreaInsets.bottom ?? 0
    }
    /// Where this screen zooms out of / back into: the tapped card's photo (nil when opened from somewhere with none).
    /// Only meaningful while zooming (opening: the rect captured at the tap; closing: the card's live frame, or that
    /// same rect if the card has scrolled away). At rest, and for opens that did not start from a card, it is nil.
    private var zoomOrigin: CGRect? {
        // Opened from Map: no card to zoom from; the screen opens from, and closes toward, the centre of the screen.
        guard !isPreview, app.eventBackScreen != .mapExplore else { return nil }
        // Closing wins over a still-flagged open (closed within 1.4s of opening): shrink into the card's live frame.
        if isDismissing { return app.zoomOrigin(for: event.key) ?? app.eventOriginRect }
        if app.eventOpening { return app.eventOriginRect }
        return nil
    }
    /// True when there is no card to zoom from/into: the whole screen then scales up from the centre and fades.
    private var centerPose: Bool { zoomOrigin == nil }
    private var zoomT: CGFloat { presented ? 1 : 0 }
    /// The cover photo's frame (screen coordinates): the tapped card's photo at 0, the full-bleed cover at 1. With no
    /// card to come from it grows from a slightly inset copy of the cover.
    private var heroFrame: CGRect {
        let full = closeStart ?? CGRect(x: 0, y: 0, width: screenSize.width, height: topInset + heroHeight)
        let from = zoomOrigin ?? full
        func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * zoomT }
        return CGRect(x: lerp(from.minX, full.minX), y: lerp(from.minY, full.minY),
                      width: lerp(from.width, full.width), height: lerp(from.height, full.height))
    }
    /// Drag-down pose: shrink around the page centre and follow the finger at a third of its travel.
    private var dragScale: CGFloat { 1 - 0.16 * dismissProgress }
    private func dragPosed(_ r: CGRect) -> CGRect {
        let s = dragScale, a = poseAnchor, dy = dismissDrag * 0.35
        return CGRect(x: a.x + (r.minX - a.x) * s, y: a.y + (r.minY - a.y) * s + dy,
                      width: r.width * s, height: r.height * s)
    }
    /// The cover photo's on-screen frame: the zoom frame, its scroll parallax and (while dragged) the drag pose. The
    /// photo is NOT inside the posed layers, so nothing but this decides where it is.
    private var heroScreenFrame: CGRect {
        let f = heroFrame
        guard closeStart == nil else { return f }
        let parallax = min(max(scrollOffset, 0), heroHeight) * 0.3 * zoomT
        return dragPosed(f.offsetBy(dx: 0, dy: -parallax))
    }
    private func closeAnimated() {
        guard !isDismissing else { return }
        isDismissing = true
        // Freeze the photo where it is right now; the page layers keep their drag pose and just fade.
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { closeStart = heroScreenFrame }
        // RootView draws a stand-in underneath only when there is no live screen there (publishing this would make
        // every screen re-render, Home included, mid-animation).
        let live = app.eventHasLiveUnderlay
        if !live { app.eventDismissProgress = max(app.eventDismissProgress, 0.001) }
        withAnimation(.easeIn(duration: centerPose ? 0.34 : 0.22)) { contentShown = false }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.92)) { presented = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.62) {
            app.backFromEvent()
            DispatchQueue.main.async {
                if app.eventDismissProgress != 0 { app.eventDismissProgress = 0 }
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { closeStart = nil; dismissDrag = 0 }
                isDismissing = false
            }
        }
    }
    private var topInset: CGFloat {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.keyWindow?.safeAreaInsets.top ?? 0
    }
    private var dismissProgress: CGFloat { min(1, max(0, dismissDrag / 320)) }
    /// Letting go past this pull closes the screen.
    private let dismissCloseDistance: CGFloat = 140

    private var event: CatalogEvent { preview?.event ?? app.currentEvent }
    /// Event type profiles (migration 203): only while the switch is on; a type without a profile renders as before.
    private var typeProfile: EventTypeProfile? { app.eventTypesEnabled ? EventTypes.profile(event.catKey) : nil }
    private var typeFacts: [EventTypes.Fact] {
        typeProfile.map { EventTypes.detailFacts($0, event.details, lang: app.isEN ? "en" : "vi") } ?? []
    }
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
        guard !isPreview, let booking = app.booking,
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(GeometryReader { g in
                    Color.clear
                        .onAppear { poseAnchor = CGPoint(x: g.frame(in: .global).midX, y: g.frame(in: .global).midY) }
                        .onChange(of: g.frame(in: .global)) { _, f in poseAnchor = CGPoint(x: f.midX, y: f.midY) }
                })
                .modifier(dragPose)
            // The photo is a layer of the screen itself (not inside the stack below), so it can reach the very top
            // edge, under the status bar, and both side edges. It is also the shared element: its frame runs from
            // the tapped card's photo to the full-bleed cover (see `heroFrame`).
            heroBackdrop
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .ignoresSafeArea(edges: .top)
            // Top scrim: keeps the round controls legible on bright covers (they used to rely on a dark sample photo).
            LinearGradient(colors: [.black.opacity(0.34), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: topInset + 124)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
                .opacity(contentShown && !collapsed ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: collapsed)
                .modifier(dragPose)
                .accessibilityHidden(true)
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
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
                    // Remembers the offset per event and, when coming back (not a fresh open), puts it straight back.
                    .background(ScaffoldScrollProbe(restoreOffsetY: app.eventOpening || isPreview ? nil : app.eventScrollOffsets[event.key],
                                                    onOffset: { [key = event.key, isPreview] y in if !isPreview { app.eventScrollOffsets[key] = y } },
                                                    onChange: { _, _ in }))
                }
                .coordinateSpace(name: "eventScroll")
                .onPreferenceChange(EventScrollOffsetKey.self) { if #unavailable(iOS 18.0) { scrollOffset = $0 } }
                .trackingScrollOffset($scrollOffset)
                .scrollDisabled(isDismissDragging)
                .simultaneousGesture(dismissGesture, including: isPreview ? .subviews : .all)
                .onChange(of: criteriaScrollRequest) { _, _ in
                    withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo("event.criteria", anchor: .center) }
                }
                }
                // The scrolling area starts `pinnedStrip` down the screen, with the sheet's own rounded top corners,
                // so a band of the photo stays visible above the info however far it is pulled up.
                .mask { UnevenRoundedRectangle(topLeadingRadius: sheetRadius, topTrailingRadius: sheetRadius, style: .continuous) }
                .padding(.top, max(0, pinnedStrip - topInset))
                if let preview {
                    // What guests will see, shown but inert; then the host's own Confirm & submit.
                    VStack(spacing: 0) {
                        actionBar.allowsHitTesting(false).accessibilityHidden(true)
                        preview.footer
                    }
                } else {
                    actionBar
                }
            }
            .opacity(contentShown ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .modifier(dragPose)
            // Task 3 follow-up: back/share used to live INSIDE `hero`,
            // which scrolls away with the rest of the content the instant
            // the user scrolls the photo out of view. Rendered here
            // instead — a ZStack sibling of the ScrollView, not a
            // descendant of it — so they float persistently regardless of
            // scroll position, the same floating-pill treatment the map
            // screen's own back/compass buttons already get.
            // Solid nav bar once the title has scrolled away (mockup "02 · Khi cuộn xuống").
            navBar
                .opacity(contentShown ? 1 : 0)
                .modifier(dragPose)
            backShareRow.opacity(contentShown ? 1 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .modifier(dragPose)
            // Left-edge swipe back: the page follows the finger with the same shrink as pull-down, and closes the same
            // way as Back (into the card it came from) — never the generic sideways slide (RootView leaves .event alone).
            Color.clear
                .frame(width: isPreview ? 0 : 22)
                .contentShape(Rectangle())
                .gesture(edgeSwipeGesture, including: isPreview ? .none : .all)
                .padding(.top, topInset + 64)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .ignoresSafeArea(edges: .bottom)
                .accessibilityHidden(true)
        }
        // No card to come from (Map): the whole screen grows from / shrinks toward the middle of the screen.
        .scaleEffect(centerPose ? 0.84 + 0.16 * zoomT : 1)
        .onAppear {
            // Coming BACK (host page, chat, Reserve…), not a fresh open: everything is simply already there, at the
            // same scroll position — no grow-in, no fade, no pop.
            guard app.eventOpening, !isPreview else {
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { presented = true; contentShown = true }
                return
            }
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
        .task(id: event.key) { if !isPreview { await app.loadEventPhotos(eventID: event.key) } }
        .task(id: event.key) { if !isPreview { await app.loadEventOrgStats(forEventKey: event.key) } }
        // Reservation criteria (migration 162): small per-event read; only a
        // restricted event triggers the eligibility pre-check (Everyone = no
        // extra calls/UI). Re-runs when the guest saves new preferences.
        .task(id: "\(event.key)|\(app.eventPrefsVersion)|\(app.isSignedIn)") {
            guard !isPreview else { return }
            app.reserveEligibilityBlock = nil
            await app.loadEventCriteria(eventKey: event.key)
            if app.isSignedIn, let c = app.eventCriteriaByKey[event.key], !c.isEveryone {
                await app.recheckReservationEligibility(eventKey: event.key)
            }
        }
    }

    private var edgeSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                guard !isDismissing else { return }
                let dx = value.translation.width
                if !isDismissDragging {
                    guard dx > 0, dx > abs(value.translation.height) else { return }
                    isDismissDragging = true
                }
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) {
                    dismissDrag = max(0, dx)
                    if !app.eventHasLiveUnderlay { app.eventDismissProgress = max(0.001, dismissProgress) }
                }
                let armed = dismissDrag > dismissCloseDistance
                if armed != dismissArmed {
                    dismissArmed = armed
                    if armed { Haptics.light() }
                }
            }
            .onEnded { value in
                defer { dismissArmed = false }
                guard isDismissDragging else { return }
                isDismissDragging = false
                if dismissDrag > dismissCloseDistance || value.predictedEndTranslation.width > 360 {
                    closeAnimated()
                } else {
                    withAnimation(.spring(response: 0.46, dampingFraction: 0.86)) { dismissDrag = 0 }
                    if app.eventDismissProgress != 0 { app.eventDismissProgress = 0 }
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
                // One tick when the drag passes the close point (and again if it comes back and crosses it again);
                // nothing on release or when the screen underneath settles.
                let armed = dismissDrag > dismissCloseDistance
                if armed != dismissArmed {
                    dismissArmed = armed
                    if armed { Haptics.light() }
                }
            }
            .onEnded { value in
                defer { dragBeganAtTop = nil; dismissArmed = false }
                guard isDismissDragging else { return }
                isDismissDragging = false
                if dismissDrag > dismissCloseDistance || value.predictedEndTranslation.height > 420 {
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
            VStack(alignment: .leading, spacing: BanbeTheme.Space.m) {
                Text(app.T("Ai được đặt chỗ: ", "Who can reserve: ") + c.summary(vi: !app.isEN))
                    .font(.footnote.weight(.semibold))
                    .accessibilityIdentifier("event.criteria.summary")
                if let block = app.reserveEligibilityBlock {
                    CriteriaUnmetCard(eligibility: block, returnTo: .event, idPrefix: "event")
                }
            }
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

    private var canOpenInMap: Bool { app.eventBackScreen == .home && event.lat != nil && event.lng != nil }
    /// Scrolled this far, the title has gone under the top edge: the solid nav bar (mockup "02 · Khi cuộn xuống")
    /// takes over and the glass controls turn into plain clay glyphs.
    private var collapseAt: CGFloat { topInset + heroHeight - sheetOverlap - pinnedStrip + 70 }
    /// 0 while the title is comfortably below the bar, 1 once it has fully passed under it. Drives the hand-off: the
    /// in-sheet title rises, shrinks and fades while the bar's title grows into place — the name moves up and shrinks
    /// rather than being covered and swapped.
    private var titleProgress: CGFloat {
        guard titleFrame.height > 0 else { return scrollOffset > collapseAt ? 1 : 0 }
        let lead: CGFloat = 36
        return min(1, max(0, (navBarHeight + lead - titleFrame.minY) / (titleFrame.height + lead)))
    }
    private var collapsed: Bool { titleProgress > 0.6 }
    /// Height of the band above the scroll view (the pinned photo strip), which the nav bar covers.
    private var navBarHeight: CGFloat { max(topInset, pinnedStrip) }

    /// Back pill "‹ {where you came from}", then ⋯ / Share / Save discs (mockup). Once the nav bar is solid the back
    /// pill shrinks to its chevron to give the event name room.
    private var backShareRow: some View {
        HStack(spacing: 8) {
            Button { if let preview { preview.onBack() } else { closeAnimated() } } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                    if !collapsed {
                        Text(preview?.backLabel ?? backLabel).font(.system(size: 15, weight: .semibold)).lineLimit(1).frame(maxWidth: 124, alignment: .leading)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .padding(.leading, 11).padding(.trailing, collapsed ? 11 : 14)
                .frame(minWidth: 40, minHeight: 40)
                .modifier(ControlChrome(collapsed: collapsed, clay: app.palette.clay, shape: AnyShape(Capsule())))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            // Follow-up bug 2: an explicit, map-specific label so VoiceOver users get the same "this returns to the map,
            // not Home" clarity.
            .accessibilityLabel(preview?.backLabel ?? (app.eventBackScreen == .mapExplore ? app.T("Quay lại bản đồ", "Back to map") : backLabel))
            .accessibilityIdentifier("event.back")
            Spacer(minLength: 0)
            Group {
            // ⋯ is a native pop-up menu, exactly like the calendar pill beside the title (EventPlanTitleRow).
            Menu { moreMenuItems } label: { discLabel("ellipsis") }
                .accessibilityIdentifier("event.more")
                .accessibilityLabel(app.T("Thêm", "More"))
            Button { share() } label: { discLabel("square.and.arrow.up") }
                .buttonStyle(.plain)
                .accessibilityLabel(app.T("Chia sẻ", "Share"))
                .accessibilityIdentifier("event.share")
            // Save uses the same isSaved/toggleFavorite Home's own EventCard does (keys off `favorites` by id).
            Button { app.toggleFavorite(event.key) } label: { discLabel(app.isSaved(event.key) ? "heart.fill" : "heart") }
                .buttonStyle(.plain)
                .accessibilityLabel(app.isSaved(event.key) ? app.T("Đã lưu", "Saved") : app.T("Lưu", "Save"))
                .accessibilityAddTraits(app.isSaved(event.key) ? .isSelected : [])
                .accessibilityIdentifier("event.save")
            }
            // Preview: the guest's controls are shown as they will look, but do nothing for a draft.
            .allowsHitTesting(!isPreview)
        }
        .overlay(alignment: .topTrailing) {
            if app.sharedFlash || linkCopied || zaloCopied {
                Text(zaloCopied ? app.T(CoreLoops.zaloCopied.vi, CoreLoops.zaloCopied.en) : app.T("Đã sao chép link", "Link copied"))
                    .font(.system(size: 12))
                    .foregroundStyle(app.palette.ink)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(app.palette.paper.opacity(0.94), in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                    .offset(y: 48)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .animation(.easeOut(duration: 0.2), value: collapsed)
    }

    private func discLabel(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .frame(width: 40, height: 40)
            .modifier(ControlChrome(collapsed: collapsed, clay: app.palette.clay, shape: AnyShape(Circle())))
            .contentShape(Circle())
    }

    @ViewBuilder
    private var moreMenuItems: some View {
        // Only when reached from Home (and the event has confirmed coordinates); `openEventOnMap` reuses Map Explore's
        // own restored-snapshot mechanism, so its selected-pin card appears automatically.
        if canOpenInMap {
            Button { app.openEventOnMap(event) } label: { Label(app.T("Xem trên bản đồ", "Open in map"), systemImage: "map") }
                .accessibilityIdentifier("event.openInMap")
        }
        if app.eventBackScreen != .home {
            Button { app.goHome() } label: { Label(app.T("Về trang chính", "Back to home"), systemImage: "house") }
                .accessibilityIdentifier("event.backHome")
        }
        // Only for the account that owns this event's organizer (re-checked server-side); opens the confirm step.
        if app.myOrgEventKeys.contains(event.key) {
            Button { shareConfirmOpen = true } label: {
                Label(app.storyCreateBusy ? app.T("Đang đăng…", "Posting…") : app.T("Chia sẻ lên Story", "Share to Story"), systemImage: "camera")
            }
            .disabled(app.storyCreateBusy)
            .accessibilityIdentifier("event.shareToStory")
        }
        Divider()
        Button { copyLink() } label: { Label(app.T("Sao chép link", "Copy link"), systemImage: "link") }
            .accessibilityIdentifier("event.copyLink")
        // L8 market sharing (switch market_share), beside Copy link: Vietnam events copy an invite for Zalo (there is
        // no verified Zalo share URL, so it is pasted), US events open Messages with it.
        switch inviteMarket {
        case "VN":
            Button { copyZaloInvite() } label: { Label(app.T("Chép lời mời cho Zalo", "Copy invite for Zalo"), systemImage: "doc.on.doc") }
                .accessibilityIdentifier("event.copyZalo")
        case "US":
            Button { textAFriend() } label: { Label(app.T("Nhắn tin cho bạn bè", "Text a friend"), systemImage: "message") }
                .accessibilityIdentifier("event.textFriend")
        default:
            EmptyView()
        }
    }

    /// "VN" | "US" while the market_share switch is on, else nil. The demo catalogue is Saigon; a real event without a
    /// country reads from its currency (same rule as web EventDetail.jsx).
    private var inviteMarket: String? {
        guard !isPreview, FeatureFlags.isOn(app.featureFlags, "market_share") else { return nil }
        guard let loc = event.location else { return "VN" }
        let country = (loc.countryCode ?? "").isEmpty ? (event.currency == "USD" ? "US" : "VN") : loc.countryCode
        return CoreLoops.shareMarket(country)
    }

    /// "name ▪︎ when" + newline + the same link the system share sends (core-loops.json `shareText`).
    private func inviteText(market: String) -> String? {
        guard let id = event.key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        let zone = event.timeZoneID.flatMap { TimeZone(identifier: $0) } ?? EventMarket.vnTimeZone
        let when = event.startDate.map { CoreLoops.shareWhen(startsAt: $0, timeZone: zone, market: market) }
            ?? (market == "VN" ? event.when : "")
        return CoreLoops.shareInviteText(name: event.name, when: when, url: "\(AppConfig.publicWebOrigin)/api/photo-share?eid=\(id)")
    }

    private func copyZaloInvite() {
        guard let text = inviteText(market: "VN") else { return }
        UIPasteboard.general.string = text
        Analytics.track(.shareCompleted(channel: "zalo_copy", context: "event"))
        Haptics.light()
        withAnimation { zaloCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { withAnimation { zaloCopied = false } }
    }

    private func textAFriend() {
        guard let text = inviteText(market: "US"), let url = URL(string: CoreLoops.smsInviteLink(text)) else { return }
        UIApplication.shared.open(url) { opened in
            if opened { Analytics.track(.shareCompleted(channel: "sms", context: "event")) }
        }
    }

    private func copyLink() {
        guard let id = event.key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
        UIPasteboard.general.string = "\(AppConfig.publicWebOrigin)/api/photo-share?eid=\(id)"
        Haptics.light()
        withAnimation { linkCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { withAnimation { linkCopied = false } }
    }

    /// Solid paper bar over the pinned photo strip, repeating the event name once the title has scrolled away.
    private var navBar: some View {
        let p = titleProgress
        return ZStack(alignment: .top) {
            app.palette.paper
                .overlay(alignment: .bottom) { softRule.frame(height: 0.5) }
                .opacity(p)
            Text(event.name)
                .font(BanbeTheme.display(16))
                .foregroundStyle(app.palette.ink)
                .lineLimit(1)
                .opacity(p)
                .scaleEffect(1 + 0.6 * (1 - p), anchor: .bottom)
                .offset(y: (1 - p) * 30)
                .padding(.leading, 66).padding(.trailing, 160)
                .frame(maxWidth: .infinity, minHeight: 40)
                .padding(.top, topInset + 16)
        }
        .frame(height: navBarHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(!collapsed)
    }

    /// The cover photo, full-bleed to the top and side edges, pinned behind the scrolling sheet. It fades to the
    /// page colour as the sheet rises over it, and drifts up a little more slowly than the content.
    private var heroBackdrop: some View {
        // Fades only part-way (never to nothing): the strip left above the pulled-up info stays clearly visible.
        let fade = min(1, max(0, scrollOffset / (heroHeight * 0.62))) * zoomT
        let f = heroScreenFrame
        // Card corners while zoomed in; while dragged, the posed page's own rounding (the page mask no longer covers
        // the photo, see `dragPose`).
        let radius = max(14 * (1 - zoomT), closeStart == nil ? min(sheetRadius, dismissProgress * 120) * dragScale : 0)
        return ZStack { heroImage }   // no placeholder fill: the card shows through until the photo is ready
            .frame(width: f.width, height: f.height)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            // Gone once the solid nav bar covers the strip, so it never peeks through the sheet's rounded corners.
            .opacity((1 - 0.4 * fade) * (centerPose ? (contentShown ? 1 : 0) : 1) * (titleProgress >= 1 && closeStart == nil ? 0 : 1))
            .offset(x: f.minX, y: f.minY)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var heroImage: some View {
        if case .local(_, let image)? = preview?.photos.first {
            Image(uiImage: image).resizable().scaledToFill()
        } else if case .remote(_, let url)? = preview?.photos.first {
            RemoteImage(path: url, maxPixel: 1100)
        } else {
            RemoteImage(path: event.img, maxPixel: 1100)
        }
    }

    /// The preview's photo strip: same tiles as `photoStrip`, from the draft's local/uploaded photos (no viewer).
    private func previewPhotoStrip(_ photos: [EventDetailPreview.Photo]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(photos) { photo in
                    Group {
                        switch photo {
                        case .local(_, let image): Image(uiImage: image).resizable().scaledToFill()
                        case .remote(_, let url): CatalogPhoto(path: url, height: 166, width: 132, cornerRadius: 0)
                        }
                    }
                    .frame(width: 132, height: 166)
                    .clipShape(RoundedRectangle(cornerRadius: BanbeTheme.Radius.thumb, style: .continuous))
                }
            }
        }
    }

    /// Drag-down-to-close for the page layers (background, info sheet, buttons): shrink toward the middle, round off
    /// and follow the finger while the screen underneath shows through. Each layer fills the same frame, so they all
    /// scale around the same centre (`poseAnchor`), which `dragPosed` uses for the photo. A mask that ignores the safe
    /// area (a plain clipShape would cut the background off at the status bar).
    private var dragPose: DragPoseModifier {
        DragPoseModifier(radius: min(sheetRadius, dismissProgress * 120), scale: dragScale, offsetY: dismissDrag * 0.35)
    }

    /// One hairline weight for the page's own dividers: softer than `rule`, so sections read as one surface.
    private var softRule: Color { app.palette.ink.opacity(0.10) }
    private var hostName: String { event.orgName.isEmpty ? event.hostShort : event.orgName }
    /// About (note 68): description (else the intro's first paragraph) clamped to 3 lines; a blank intro is no intro.
    private var about: EventDetailPresentation.About {
        EventDetailPresentation.aboutSection(desc: event.desc, intro: event.intro, includedCount: event.includedItems?.count ?? 0)
    }
    /// `where` is "area ▪︎ distance ▪︎ day ▪︎ time"; the date and time have their own tiles, so the place tile keeps
    /// only the area and, once located, the distance.
    private var placeLine: String {
        let parts = app.stripKm(event.where, event: event).components(separatedBy: " ▪︎ ")
        return app.trStatus(parts.enumerated().filter { $0.offset == 0 || $0.element.contains(" km") }.map(\.element).joined(separator: " ▪︎ "))
    }
    /// Ngày / Giờ: `when` is "Th 4, 04.11 ▪︎ 20:00" for catalogue and real events alike.
    private var whenParts: (date: String?, time: String?) {
        let parts = event.when.components(separatedBy: " ▪︎ ").filter { !$0.isEmpty }
        return (parts.first, parts.count > 1 ? parts[1] : nil)
    }
    /// Capacity and seats still free: the live fill only (never an invented capacity); a draft has every seat free.
    private var seatCounts: (capacity: Int?, remaining: Int?) {
        if let preview { return (preview.capacity, preview.capacity) }
        guard let fill = app.eventFill[event.key], fill.capacity > 0 else { return (nil, nil) }
        return (fill.capacity, max(0, fill.capacity - fill.booked))
    }
    /// One seat status beside the price (note 68): "You're going" for a ticket holder, "Sold out" (also at 0 left),
    /// else "N left" (honey when few). The bar only shows while seats are actually open.
    private var seat: EventDetailPresentation.SeatStatus {
        EventDetailPresentation.seatStatus(capacity: seatCounts.capacity, remaining: seatCounts.remaining,
                                           soldOut: event.soldOut, going: barState == .ticket)
    }
    private var seatPill: (text: String, fg: Color, bg: Color)? {
        switch seat.kind {
        case .going: return (app.T("Bạn sẽ tham gia", "You're going"), app.palette.clay, app.palette.clayBg)
        case .soldOut: return (app.trStatus("Hết chỗ"), app.palette.ink2, app.palette.surface2)
        case .few: return (app.T("Còn \(seat.left ?? 0) chỗ", "\(seat.left ?? 0) left"), app.palette.honey, app.palette.honeyBg)
        case .open: return (app.T("Còn \(seat.left ?? 0) chỗ", "\(seat.left ?? 0) left"), app.palette.ink2, app.palette.surface2)
        case .unknown:
            let text = app.trStatus(event.seatsLong)
            return text.isEmpty ? nil : (text, app.palette.ink2, app.palette.surface2)
        }
    }
    /// Event type facts: minimum age is a restriction, so it sits beside the category; alcohol + dietary are chips.
    private var facts: EventDetailPresentation.SplitFacts { EventDetailPresentation.splitFacts(typeFacts) }
    private var includedChips: [String] {
        if let items = event.includedItems, !items.isEmpty { return items.map(\.label) }
        return event.included.components(separatedBy: CharacterSet(charactersIn: "▪︎,·")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var details: some View {
        // One spacing scale (note 68): 24 between sections, 8–12 inside one.
        VStack(alignment: .leading, spacing: BanbeTheme.Space.xl) {
            if let shareStoryMessage {
                Text(shareStoryMessage)
                    .font(.footnote)
                    .foregroundStyle(app.palette.ink3)
            }

            // Header: category + minimum age + invite pills, the title with the calendar pill, then price and seat status.
            VStack(alignment: .leading, spacing: BanbeTheme.Space.s) {
                FlowRow(spacing: BanbeTheme.Space.s) {
                    // Category as an ink chip (mockup); minimum age beside it (a restriction, seen first); invite in clay.
                    if !app.trStatus(event.cat).isEmpty {
                        Text(app.trStatus(event.cat).uppercased())
                            .font(.footnote.weight(.semibold)).tracking(0.5)
                            .foregroundStyle(app.palette.paper)
                            .padding(.horizontal, 12).padding(.vertical, 4)
                            .background(app.palette.ink, in: Capsule())
                            .accessibilityIdentifier("event.category")
                    }
                    if let age = facts.minAge {
                        Text(age.value)
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 11).padding(.vertical, 3)
                            .overlay(Capsule().stroke(app.palette.ink, lineWidth: 1))
                            .accessibilityLabel("\(age.label) \(age.value)")
                            .accessibilityIdentifier("event.typeFact.\(age.id)")
                    }
                    if event.inviteOnly {
                        Text(app.T("Riêng tư ▪︎ theo lời mời", "Private ▪︎ invite only"))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(app.palette.clay)
                            .padding(.horizontal, 12).padding(.vertical, 4)
                            .background(app.palette.clayBg, in: Capsule())
                            .accessibilityIdentifier("event.inviteChip")
                    }
                }

                // Note 46 — the title with the calendar pill (banbe Schedule / Apple Calendar).
                EventPlanTitleRow(event: event)
                    .allowsHitTesting(!isPreview)
                    .opacity(1 - titleProgress)
                    .scaleEffect(1 - 0.3 * titleProgress, anchor: .bottomLeading)
                    .offset(y: -12 * titleProgress)
                    .background(GeometryReader { g in
                        Color.clear.preference(key: EventTitleFrameKey.self, value: g.frame(in: .global))
                    })
                    .onPreferenceChange(EventTitleFrameKey.self) { titleFrame = $0 }

                // Price left, one seat status right (note 68); the thin bar under them only while seats are open.
                if !event.price.isEmpty || seatPill != nil {
                    VStack(alignment: .leading, spacing: BanbeTheme.Space.s) {
                        HStack(alignment: .center, spacing: BanbeTheme.Space.m) {
                            if !event.price.isEmpty {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(app.trStatus(event.price)).font(BanbeTheme.display(26))
                                    if !event.isFree { Text(app.T("/ vé", "/ ticket")).font(.footnote).foregroundStyle(app.palette.ink3) }
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier("event.price")
                            }
                            Spacer(minLength: 0)
                            if let pill = seatPill {
                                Text(pill.text)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(pill.fg)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(pill.bg, in: Capsule())
                                    .accessibilityIdentifier("event.seatStatus")
                            }
                        }
                        if let ratio = seat.ratio {
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(app.palette.ink.opacity(0.08))
                                    Capsule().fill(seat.kind == .few ? app.palette.clay : app.palette.ink.opacity(0.35))
                                        .frame(width: max(4, g.size.width * ratio))
                                }
                            }
                            .frame(height: 4)
                            .accessibilityHidden(true)
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("event.fact.seats")
                }
            }

            // Ngày / Giờ / Địa điểm: three equal tiles; directions is an icon-only button in the place tile's corner. The
            // venue-time note is one quiet line under them, only when this device's clock reads the time differently.
            VStack(alignment: .leading, spacing: BanbeTheme.Space.s) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: BanbeTheme.Space.s) { dateTile; timeTile; placeTile }
                        .fixedSize(horizontal: false, vertical: true)
                    // Accessibility text sizes: one tile per row, never clipped.
                    VStack(spacing: BanbeTheme.Space.s) { dateTile; timeTile; placeTile }
                }
                if let note = venueTimeNote {
                    Text(note).font(.footnote).foregroundStyle(app.palette.ink3)
                        .accessibilityIdentifier("event.fact.venueTime")
                }
            }

            // The host, once (note 68): avatar, name, real stats, a Message icon button; the row opens the host's page.
            hostSection.allowsHitTesting(!isPreview)

            // What kind of evening it is (event type profiles): alcohol + dietary as icon chips, the type's other facts
            // as an aligned label/value list. Minimum age is the pill in the header.
            if !facts.chips.isEmpty || !facts.rows.isEmpty {
                VStack(alignment: .leading, spacing: BanbeTheme.Space.m) {
                    if !facts.chips.isEmpty {
                        FlowRow(spacing: BanbeTheme.Space.s) {
                            ForEach(facts.chips, id: \.id) { f in
                                Label {
                                    Text(f.value)
                                } icon: {
                                    Image(systemName: f.id == "alcohol" ? "wineglass" : "leaf").foregroundStyle(app.palette.clay)
                                }
                                .font(.footnote)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(app.palette.surface2, in: Capsule())
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(f.label): \(f.value)")
                                .accessibilityIdentifier("event.typeFact.\(f.id)")
                            }
                        }
                    }
                    if !facts.rows.isEmpty {
                        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: BanbeTheme.Space.l, verticalSpacing: BanbeTheme.Space.s) {
                            ForEach(facts.rows, id: \.id) { f in
                                GridRow {
                                    Text(f.label).font(.footnote).foregroundStyle(app.palette.ink3)
                                    Text(f.value).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier("event.typeFact.\(f.id)")
                            }
                        }
                    }
                }
                .foregroundStyle(app.palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("event.typeFacts")
            }

            criteriaSection
                .id("event.criteria")

            // About (note 68): the description clamped to 3 lines ("Read more" expands it here), then the included
            // line. "More ›" on the heading opens the About & Included sheet. Never a heading with nothing under it.
            if about.visible { aboutSection }

            // L2 (switch event_recap): a guest who went opens their recap card, where the private feedback lives.
            if barState == .endedAttended, !isPreview, app.eventRecapEnabled, (app.realEventsByID[event.key] ?? nil) != nil {
                InkButton(title: app.T("Xem tổng kết và gửi cảm nhận", "See the recap and share feedback")) {
                    app.openEventRecap(event.key, back: .event)
                }
                .accessibilityIdentifier("event.openRecap")
            }
            if isOver, !isPreview, let orgID = endedOrganizerID {
                endedNextSection(orgID)
            }

            VStack(alignment: .leading, spacing: BanbeTheme.Space.s) {
                // "Hình ảnh": the horizontal photo strip.
                HStack(alignment: .firstTextBaseline) {
                    Text(app.T("Hình ảnh", "Photos")).font(BanbeTheme.display(17))
                    Spacer()
                    let photoCount = preview?.photos.count ?? realPhotos.count
                    if photoCount > 0 { Text("\(photoCount)").font(.footnote).foregroundStyle(app.palette.ink3) }
                }
                // STAGE D (2026-09-25) — real event_photos rows, not the static demo `event.gallery`. A genuinely
                // photo-less real event shows plain text, never a fake/demo photo standing in for a real one.
                if let preview {
                    if preview.photos.isEmpty {
                        Text(app.T("Chưa có ảnh nào cho sự kiện này.", "No photos for this event yet."))
                            .font(.footnote).foregroundStyle(app.palette.ink3)
                    } else {
                        previewPhotoStrip(preview.photos)
                    }
                } else if app.eventPhotosLoading {
                    Text(app.T("Đang tải…", "Loading…"))
                        .font(.footnote).foregroundStyle(app.palette.ink3)
                } else if realPhotos.isEmpty {
                    Text(app.T("Chưa có ảnh nào cho sự kiện này.", "No photos for this event yet."))
                        .font(.footnote).foregroundStyle(app.palette.ink3)
                } else {
                    photoStrip
                }
            }
            }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 22)
        .padding(.top, BanbeTheme.Space.xl)
        .padding(.bottom, BanbeTheme.Space.xl + 8)
    }

    /// Ngày / Giờ / Địa điểm tile (note 68): clay icon, the value (what you came for) over a quiet label. All three
    /// share one width (each takes `maxWidth: .infinity`) and one height (the row is `fixedSize` vertically); the
    /// Simple Shell surface2 fill (= the light block), no hairline.
    private func tile<Content: View>(_ symbol: String, _ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: BanbeTheme.Space.xs) {
            Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(app.palette.clay)
                .padding(.bottom, BanbeTheme.Space.xs)
                .accessibilityHidden(true)
            content().font(.subheadline.weight(.semibold))
            Text(label).font(.footnote).foregroundStyle(app.palette.ink3)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(BanbeTheme.Space.m)
        .background(app.palette.surface2, in: RoundedRectangle(cornerRadius: BanbeTheme.Radius.tile, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var dateTile: some View {
        if let date = whenParts.date {
            tile("calendar", app.T("Ngày", "Date")) { Text(date) }
                .accessibilityIdentifier("event.fact.when")
        }
    }

    @ViewBuilder private var timeTile: some View {
        if let time = whenParts.time {
            tile("clock", app.T("Giờ", "Time")) { Text(time) }
                .accessibilityIdentifier("event.fact.time")
        }
    }

    /// Real events show the VENUE's wall clock (migration 195); when this device reads it differently, the viewer's
    /// own clock as one quiet line under the tiles (web `viewerTimeNote`).
    private var venueTimeNote: String? {
        guard let zone = event.eventTimeZone, let start = event.startDate else { return nil }
        return SchedulePresentation.viewerTimeNote(start: start, venueZone: zone, vi: !app.isEN)
    }

    private var placeTile: some View {
        tile("mappin.and.ellipse", app.T("Địa điểm", "Place")) { Text(placeLine).fixedSize(horizontal: false, vertical: true) }
            .accessibilityIdentifier("event.fact.where")
            .overlay(alignment: .topTrailing) {
                if let mapsURL = event.mapsURL {
                    // Icon-only (no text, to save space): opens directions in Maps.
                    Button {
                        // Opening directions is the natural moment to also offer the distance, if never decided.
                        if app.located == nil { app.askLocation() }
                        openURL(mapsURL)
                    } label: {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(app.palette.clay)
                            .frame(width: 28, height: 28)
                            .background(app.palette.clayBg, in: Circle())
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(-2)
                    .accessibilityLabel(app.T("Xem bản đồ", "Directions"))
                    .accessibilityIdentifier("event.address")
                }
            }
    }

    /// About (note 68): heading ("More ›" opens the About & Included sheet when it has an intro or items), the
    /// description clamped to 3 lines with "Read more" expanding it in place, then the included line.
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: BanbeTheme.Space.s) {
            Button { if about.hasSheet { introIncludedSheetOpen = true } } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text(app.T("Giới thiệu", "About")).font(BanbeTheme.display(17))
                    Spacer()
                    if about.hasSheet {
                        Text(app.T("Xem thêm", "More") + " ›").font(.footnote.weight(.semibold)).foregroundStyle(app.palette.clay)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!about.hasSheet)
            .accessibilityIdentifier("event.includedSection")
            .accessibilityLabel(about.hasSheet ? app.T("Giới thiệu và bao gồm, xem thêm", "Introduction and included, view more") : app.T("Giới thiệu", "About"))
            if !about.body.isEmpty {
                Text(about.body)
                    .font(.system(size: 15))
                    .lineSpacing(4)
                    .opacity(0.85)
                    .lineLimit(about.clampable && !aboutExpanded ? EventDetailPresentation.aboutLines : nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("event.description")
                if about.clampable && !aboutExpanded {
                    Button { aboutExpanded = true } label: {
                        Text(app.T("Xem thêm", "Read more")).font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("event.readMore")
                }
            }
            if !includedChips.isEmpty {
                let title = typeProfile?.detail?.includedTitle?.text(app.isEN ? "en" : "vi") ?? app.T("Bao gồm", "Included")
                includedChips.enumerated().reduce(Text(title + ": ").fontWeight(.semibold)) { line, item in
                    item.offset == 0 ? line + Text(item.element)
                        : line + Text("  ▪︎  ").foregroundColor(app.palette.clay) + Text(item.element)
                }
                .font(.system(size: 15))
                .lineSpacing(3)
                .multilineTextAlignment(.leading)
                .accessibilityIdentifier("event.includedLine")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(app.palette.ink)
    }

    /// Host subline in the card (real stats only).
    private var hostSubline: String {
        let stats = app.eventOrganizerID[event.key].flatMap { app.organizerStats[$0] }
        var parts: [String] = []
        if let year = stats?.sinceYear { parts.append(app.T("Tham gia từ \(year)", "Joined \(year)")) }
        if let stats, stats.count > 0 { parts.append(app.T("\(stats.count) sự kiện", stats.count == 1 ? "1 event" : "\(stats.count) events")) }
        return parts.joined(separator: " · ")
    }

    // MARK: Phase 1 Q3 — an ended page is not a dead end

    private var isOver: Bool { barState == .ended || barState == .endedAttended }
    /// Real events only: a demo event without an organizer id shows neither the follow button nor the list.
    private var endedOrganizerID: String? { app.eventOrganizerID[event.key] ?? event.organizerId }

    /// Follow host, then up to 3 of the host's live events still ahead ("Next from this host"); the photos section
    /// below already shows the recap (event_photos stays readable for ended events, migration 084).
    private func endedNextSection(_ organizerID: String) -> some View {
        let following = app.isFollowing(organizerID)
        return VStack(alignment: .leading, spacing: 0) {
            Button { Task { await app.toggleFollowOrganizer(organizerID) } } label: {
                Label(following ? app.T("Đang theo dõi host ✓", "Following this host ✓") : app.T("Theo dõi host", "Follow host"),
                      systemImage: "person")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(app.palette.clay)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(following ? app.palette.clay.opacity(0.12) : .clear, in: Capsule())
                    .overlay(Capsule().stroke(app.palette.clay, lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(following ? .isSelected : [])
            .accessibilityIdentifier("event.ended.follow")
            if !hostNext.isEmpty {
                Text(app.T("Sự kiện tiếp theo của host", "Next from this host"))
                    .font(BanbeTheme.display(20))
                    .padding(.top, 24)
                VStack(spacing: 0) {
                    ForEach(Array(hostNext.enumerated()), id: \.element.id) { index, e in
                        Button { app.goEvent(e.id) } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.name).font(BanbeTheme.display(15)).lineLimit(1)
                                    Text(app.discoveryWhenLabel(e.startsAt, timeZone: EventMarket.timeZone(e.timeZoneID)))
                                        .font(.system(size: 12.5)).opacity(0.65)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(app.palette.clay).accessibilityHidden(true)
                            }
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .top) { if index > 0 { Rectangle().fill(softRule).frame(height: 1) } }
                        .accessibilityIdentifier("event.ended.next.\(index)")
                    }
                }
                .padding(.top, 8)
            }
        }
        .foregroundStyle(app.palette.ink)
        .accessibilityIdentifier("event.ended.section")
        .task(id: "\(event.key)|\(organizerID)") {
            hostNext = []
            let rows = await app.nextFromHost(organizerID: organizerID, excluding: event.key)
            hostNext = rows
        }
    }

    /// "Người tổ chức": its own section — heading, then a soft card with the host and two actions (same outlined clay
    /// buttons as before).
    /// The host, once (note 68): avatar, name (wraps to two lines), real stats, a 44pt Message icon button. The whole
    /// row opens the host's page.
    private var hostSection: some View {
        HStack(spacing: BanbeTheme.Space.m) {
            Button { app.openEventOrganizer(eventKey: app.eventKey) } label: {
                HStack(spacing: BanbeTheme.Space.m) {
                    organizerAvatar
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: BanbeTheme.Space.s) {
                            Text(hostName.isEmpty ? app.T("Người tổ chức", "Host") : hostName)
                                .font(BanbeTheme.display(17)).lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            if app.isFollowing(app.eventOrganizerID[event.key]) {
                                Text("✓ " + app.T("Đang theo dõi", "Following")).font(.caption.weight(.semibold))
                                    .foregroundStyle(app.palette.clay)
                            }
                        }
                        Text(hostSubline.isEmpty ? app.T("Người tổ chức", "Host") : hostSubline)
                            .font(.footnote).foregroundStyle(app.palette.ink3)
                            .accessibilityIdentifier("event.organizerStats")
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(app.palette.ink3)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([app.T("Người tổ chức", "Host"), hostName, hostSubline].filter { !$0.isEmpty }.joined(separator: ", "))
            .accessibilityHint(app.T("Mở trang", "Opens profile"))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("event.organizer")
            // Moved here from the retired standalone organizer page: message the host straight from the event.
            Button { app.goChat() } label: {
                Image(systemName: "bubble.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(app.palette.clay)
                    .frame(width: 44, height: 44)
                    .background(app.palette.clayBg, in: Circle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(app.T("Nhắn cho ", "Message ") + hostName)
            .accessibilityIdentifier("event.messageHost")
        }
        .foregroundStyle(app.palette.ink)
    }

    /// The host's round photo (their initial when there is none).
    private var organizerAvatar: some View {
        let stats = app.eventOrganizerID[event.key].flatMap { app.organizerStats[$0] }
        let url = MediaURLs.organizerAvatar(path: stats?.avatarPath, r2Ref: stats?.avatarR2Ref, variant: .thumb)
        return ZStack {
            Circle().fill(app.palette.surface2)
            if let url {
                RemoteImage(path: url.absoluteString, maxPixel: 144)
            } else {
                Text(String(hostName.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                    .font(.system(size: 16, weight: .semibold))
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }

    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                ForEach(Array(realPhotos.enumerated()), id: \.element.id) { index, photo in
                    // GeometryReader so the tap can read `geo.frame(in: .global)`: the origin rect the photo viewer's
                    // dismiss animation shrinks back to.
                    GeometryReader { geo in
                        Button {
                            app.openPhoto(gallery: realPhotos, index: index, organizer: event.orgName, originRect: geo.frame(in: .global))
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                CatalogPhoto(path: photo.url, height: 166, width: 132, cornerRadius: BanbeTheme.Radius.thumb)
                                // A liked photo gets a filled heart badge; an unliked one shows none here (the
                                // full-screen viewer's like button is the discoverable way, matching web).
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
                        .onAppear { app.photoThumbFrames[photo.id] = geo.frame(in: .global) }
                        .onChange(of: geo.frame(in: .global)) { _, f in app.photoThumbFrames[photo.id] = f }
                        .onDisappear { app.photoThumbFrames[photo.id] = nil }
                    }
                    .frame(width: 132, height: 166)
                    .accessibilityIdentifier("event.photo.\(index)")
                }
            }
        }
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

    /// One state for the sticky bar (Lib/ReserveBar.swift, mirrored on web). Cancelled is checked before ended/sold
    /// out because a cancelled event's stale `seatsRemaining` can still read as available or sold out; a held booking
    /// is NOT a ticket until `Booking.isTicket` (TASK B, 2026-10-01).
    private var barState: ReserveBar.State {
        // A checked-in booking ("attended", migration 021) is still that same paid ticket (Phase 1 Q3 "You went ✓").
        let ticket = myBooking.map { $0.isTicket || ($0.status == "attended" && $0.paymentState == .confirmed) } ?? false
        return ReserveBar.state(booking: myBooking != nil, ticket: ticket,
                         cancelled: event.cancelled, ended: ended, soldOut: event.soldOut,
                         currencyUnavailable: !event.paidBookingAvailable,
                         blocked: !isPreview && app.reserveEligibilityBlock != nil)
    }

    /// Sticky action area (mockup): seat chips + stepper, the refund promise, and the CTA with the live total — always
    /// on screen, so the decision can happen wherever the reader is convinced. Reserve opens pre-filled via `app.qty`.
    private var actionBar: some View {
        let state = barState
        // Preview: what a guest sees on arrival (1 ticket), not whatever the host last picked elsewhere.
        let qty = isPreview ? 1 : ReserveBar.clampQty(app.qty)
        return VStack(alignment: .leading, spacing: 10) {
            if state == .reserve {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        ForEach(ReserveBar.presets, id: \.self) { n in
                            Button {
                                app.qty = n
                                Haptics.light()
                            } label: { qtyChip(app.T("\(n) vé", n == 1 ? "1 ticket" : "\(n) tickets"), selected: qty == n) }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(qty == n ? .isSelected : [])
                            .accessibilityIdentifier("event.qty.\(n)")
                        }
                    }
                    Spacer(minLength: 0)
                    qtyStepper(qty)
                }
                Label {
                    Text(event.isOpen && !event.isFree
                         ? app.T("Hoàn tiền tự động 100% nếu sự kiện bị hủy", "Automatic full refund if the event is cancelled")
                         : app.T("Chỗ được giữ 30 phút để bạn xác nhận", "Seats are held for 30 minutes while you confirm"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(app.palette.ink.opacity(0.8))
                } icon: {
                    Image(systemName: "checkmark.shield").font(.system(size: 13)).foregroundStyle(app.palette.clay)
                }
                .accessibilityIdentifier("event.trustLine")
            }
            ctaButton(state, qty: qty)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous)
                .fill(app.palette.paper)
                .shadow(color: .black.opacity(0.10), radius: 12, y: -4)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func qtyChip(_ text: String, selected: Bool) -> some View {
        Text(text)
            .font(.system(size: 14, weight: selected ? .semibold : .medium))
            .foregroundStyle(selected ? app.palette.paper : app.palette.ink)
            .padding(.horizontal, 13)
            .frame(minHeight: 34)
            .background(selected ? app.palette.ink : app.palette.ink.opacity(0.06), in: Capsule())
            .contentShape(Capsule())
            .animation(.easeOut(duration: 0.15), value: selected)
    }

    /// Compact outlined − n + (mockup); drives the same `app.qty` as the chips, clamped to 1…6.
    private func qtyStepper(_ qty: Int) -> some View {
        HStack(spacing: 0) {
            Button { app.qty = ReserveBar.clampQty(qty - 1) } label: {
                Image(systemName: "minus").font(.system(size: 13, weight: .semibold)).frame(width: 34, height: 34).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(qty <= 1)
            .opacity(qty <= 1 ? 0.35 : 1)
            .accessibilityIdentifier("event.qty.minus")
            Text("\(qty)").font(.system(size: 15, weight: .semibold)).foregroundStyle(app.palette.ink).frame(minWidth: 18)
                .accessibilityIdentifier("event.qty.value")
            Button { app.qty = ReserveBar.clampQty(qty + 1) } label: {
                Image(systemName: "plus").font(.system(size: 13, weight: .semibold)).frame(width: 34, height: 34).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(qty >= ReserveBar.maxQty)
            .opacity(qty >= ReserveBar.maxQty ? 0.35 : 1)
            .accessibilityIdentifier("event.qty.plus")
        }
        .foregroundStyle(app.palette.clay)
        .overlay(Capsule().stroke(app.palette.clay, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.T("Số vé", "Tickets"))
        .accessibilityValue("\(qty)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: app.qty = ReserveBar.clampQty(qty + 1)
            case .decrement: app.qty = ReserveBar.clampQty(qty - 1)
            @unknown default: break
            }
        }
    }

    /// The CTA itself carries `event.actionBar` (ReserveButtonRegressionUITests taps the first element with it, so it
    /// must not sit on a container whose seat chips would inherit it).
    @ViewBuilder
    private func ctaButton(_ state: ReserveBar.State, qty: Int) -> some View {
        switch state {
        case .ticket:
            // The action, with the entry code as a quiet second line (note 68).
            InkButton(title: app.T("Xem vé của bạn", "View your ticket"), subtitle: app.T("Mã \(myBooking?.code ?? "")", "Code \(myBooking?.code ?? "")")) {
                app.openHeld()
            }
            .accessibilityIdentifier("event.actionBar")
        case .pending:
            InkButton(title: app.T("Xem trạng thái thanh toán", "View payment status")) { app.openHeld() }
                .accessibilityIdentifier("event.actionBar")
        case .reserve:
            // Outcome + total before the tap: the guest knows what they are about to hold and pay.
            let total = app.trStatus(ReserveBar.totalPrice(amount: event.isFree ? 0 : event.priceVnd, currency: event.currency, qty: qty))
            InkButton(title: qty == 1 ? app.T("Giữ chỗ ▪︎ ", "Reserve ▪︎ ") + total
                                      : app.T("Giữ \(qty) chỗ ▪︎ ", "Reserve \(qty) seats ▪︎ ") + total) {
                app.goReserve()
            }
            .accessibilityIdentifier("event.actionBar")
        case .cancelled:
            fieldLabel(app.T("Sự kiện đã bị huỷ", "Event has been cancelled"))
                .accessibilityIdentifier("event.actionBar")
        case .endedAttended:
            fieldLabel(app.T("Bạn đã tham gia ✓", "You went ✓"))
                .accessibilityIdentifier("event.actionBar")
        case .ended:
            fieldLabel(app.T("Sự kiện đã kết thúc", "This event has ended"))
                .accessibilityIdentifier("event.actionBar")
        case .soldOut:
            Button { app.goChat() } label: { fieldLabel(app.T("Hết chỗ ▪︎ nhắn để vào danh sách chờ", "Sold out ▪︎ message for waitlist")) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("event.actionBar")
        case .currencyUnavailable:
            // Paid USD events (migration 195): shown with their price, but booking isn't open yet. Disabled with the
            // reason in place (note 48's disabledReason pattern), never an error after a tap.
            InkButton(title: app.T("Giữ chỗ ▪︎ ", "Reserve ▪︎ ") + app.trStatus(event.price), enabled: false,
                      disabledReason: app.T("Đặt vé trả phí cho sự kiện tại Mỹ sẽ sớm mở", "Paid booking for US events opens soon")) {}
                .accessibilityIdentifier("event.actionBar")
        case .blocked:
            // The bar says WHY it can't be used, and tapping scrolls to the full explanation card instead of a dead tap.
            Button { criteriaScrollRequest += 1 } label: { fieldLabel(app.T("Chưa đủ điều kiện ▪︎ xem lý do", "Not eligible yet ▪︎ see why")) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("event.actionBar")
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .foregroundStyle(app.palette.ink)
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
                activity.completionWithItemsHandler = { type, completed, _, _ in
                    guard completed else { return } // share_completed only for a share that really went out
                    Analytics.track(.shareCompleted(channel: AppEventRules.shareChannel(type), context: "event"))
                }
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

private struct DragPoseModifier: ViewModifier {
    let radius: CGFloat
    let scale: CGFloat
    let offsetY: CGFloat
    func body(content: Content) -> some View {
        content
            .mask { RoundedRectangle(cornerRadius: radius, style: .continuous).ignoresSafeArea() }
            .scaleEffect(scale)
            .offset(y: offsetY)
    }
}

/// The look of the controls over the cover photo: clay-tinted glass with a white glyph (legible on bright, busy and
/// dark covers), or — once the solid nav bar has taken over — no chrome at all and a clay glyph.
private struct ControlChrome: ViewModifier {
    let collapsed: Bool
    let clay: Color
    let shape: AnyShape

    func body(content: Content) -> some View {
        content
            .foregroundStyle(collapsed ? clay : .white)
            .background {
                if !collapsed {
                    ZStack {
                        shape.fill(.ultraThinMaterial)
                        shape.fill(clay.opacity(0.72))
                    }
                }
            }
            .overlay { if !collapsed { shape.stroke(Color.white.opacity(0.32), lineWidth: 0.5) } }
            .shadow(color: .black.opacity(collapsed ? 0 : 0.2), radius: 8, y: 3)
    }
}
