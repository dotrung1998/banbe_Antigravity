import SwiftUI
import UIKit

private struct PulseSourceFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct PulsePanelContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct PulsePressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .offset(y: configuration.isPressed ? 2 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // iOS/Map UX pass (2026-09-27) — Pulse used to be a `.fullScreenCover`,
    // a wholly separate UIKit presentation layer with no access to
    // whatever was behind it. Both dismiss gestures below used to drive a
    // `@GestureState` (which snaps back to 0 the INSTANT a gesture ends,
    // committed or not — it has no way to continue an animation past
    // release) purely as visual feedback, then call `app.closePulseViewer()`
    // to actually close — which just flips `app.pulseOpen`, triggering
    // `.fullScreenCover`'s own separate, unrelated system dismiss transition
    // (a downward/cover-style slide). That's the confirmed root cause of
    // both bugs this ticket named: the X button had no transition of its
    // own at all (straight to the system's downward cover-dismiss), and a
    // completed edge-swipe visually snapped back to 0 for one frame before
    // that same downward slide took over — "a second slide after
    // releasing." Root cause confirmed by reading the code (GestureState's
    // documented reset-on-end behavior + `.fullScreenCover`'s own default
    // transition), not guessed from the symptom.
    //
    // Fix: PulseViewerView is no longer a `.fullScreenCover` at all — it's
    // a plain ZStack sibling in RootView, exactly like `PhotoViewerView`,
    // so Home stays mounted directly underneath it the whole time (see
    // RootView.swift). Both dismiss paths below now drive the SAME plain
    // `@State` `dragTranslation` (not `@GestureState`, mirroring RootView's
    // own proven `edgeSwipe`/`dragTranslation`/`isCommitting` pattern
    // exactly) so a committed dismiss — from either the X tap or a crossed
    // edge-swipe — animates ONE continuous rightward slide that
    // continuously reveals the real Home view underneath, then removes
    // this view entirely once that single animation finishes. No second,
    // unrelated system transition ever plays.
    @State private var dragTranslation: CGFloat = 0
    @State private var isDragTracking = false
    @State private var isCommitting = false
    private let edgeZoneWidth: CGFloat = 20

    // Loading-GIF pass (same-day real-device follow-up) — root cause of
    // "GIF never shown during image load/tab switch" on iOS: every
    // thumbnail here used a bare `AsyncImage(url:){...} placeholder:
    // {Color.clear}` — a transparent placeholder that only ever avoided a
    // literal white flash because it sits inside a ZStack with
    // `app.palette.field` painted first (a themed fallback fill, matching
    // web's own equivalent fix), never the actual loading asset. The
    // `loading`-gated `BanbeLoadingVisual` further up this file only ever
    // covers "this tab has zero ranked items yet" — a data-loading state
    // — never "these items exist but their photos are still
    // downloading/decoding," which is the real gap this pass closes.
    // These two sets track, per photo URL STRING (stable across a
    // re-render, unlike `AsyncImagePhase` itself), which photos in the
    // CURRENTLY active tab have finished loading or definitively failed —
    // used below to gate ONE section-level loader for the whole tab
    // (never one per thumbnail) and to stop that loader the instant
    // there's nothing left to wait for.
    @State private var loadedPhotoURLs: Set<String> = []
    @State private var erroredPhotoURLs: Set<String> = []
    @State private var pulseSourceFrames: [String: CGRect] = [:]
    @State private var expandedPanelProgress: CGFloat = 1
    @State private var expandedPanelKey: String?
    @State private var expandedPanelHapticKey: String?
    @State private var expandedPanelImage: UIImage?
    @State private var expandedPanelContentHeight: CGFloat = 1

    private func pulseSourceKey(_ id: String) -> String { "pulse-item-\(id)" }
    private func pulsePhotoSourceKey(_ id: String) -> String { "pulse-photo-\(id)" }

    private func prepareExpandedPanel(key: String) {
        expandedPanelKey = key
        expandedPanelProgress = reduceMotion ? 1 : 0
        expandedPanelImage = nil
        expandedPanelContentHeight = 1
        guard expandedPanelHapticKey != key else { return }
        expandedPanelHapticKey = key
        Haptics.light()
    }

    private func markPhotoLoaded(_ url: String) { loadedPhotoURLs.insert(url) }
    private func markPhotoErrored(_ url: String) { erroredPhotoURLs.insert(url) }

    /// Only the currently active tab's own items (never "everything") —
    /// mirrors web's `activeTabPhotoUrls`.
    private var activeTabPhotoURLs: [String] {
        let source: [String?] = app.pulseTab == .photos
            ? app.pulsePhotos.map { eventPhotoURL($0.photoPath) }
            : items.map { eventPhotoURL($0.photoPath) }
        return source.compactMap { $0 }
    }
    private var anyPhotoReady: Bool { activeTabPhotoURLs.contains { loadedPhotoURLs.contains($0) } }
    private var allPhotosSettled: Bool {
        !activeTabPhotoURLs.isEmpty
            && activeTabPhotoURLs.allSatisfy { loadedPhotoURLs.contains($0) || erroredPhotoURLs.contains($0) }
    }
    /// The one gate this pass adds: real items exist, but none of their
    /// photos have loaded yet, and at least one is still genuinely in
    /// flight (never spins forever once every photo has settled one way
    /// or the other — a genuinely broken/empty section falls back to the
    /// existing per-tile `app.palette.field` fill instead, same as web).
    private var sectionImagesLoading: Bool {
        !activeTabPhotoURLs.isEmpty && !anyPhotoReady && !allPhotosSettled
    }

    private var slideOffset: CGFloat {
        isCommitting ? UIScreen.main.bounds.width : dragTranslation
    }

    /// Shared by the X button (a plain tap) and a crossed edge-swipe — the
    /// ONE dismiss animation this ticket asks for, never a second/different
    /// one depending on which control triggered it.
    private func commitDismiss() {
        guard !isCommitting else { return }
        withAnimation(.easeOut(duration: 0.22)) { isCommitting = true }
    }

    private var edgeSwipe: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                guard !isCommitting else { return }
                isDragTracking = true
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    dragTranslation = max(0, value.translation.width)
                }
            }
            .onEnded { value in
                defer { isDragTracking = false }
                guard !isCommitting else { return }
                let width = UIScreen.main.bounds.width
                let crossedDistance = value.translation.width > width * 0.3
                let flicked = value.predictedEndTranslation.width > width * 0.6
                if crossedDistance || flicked {
                    commitDismiss()
                } else {
                    withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.86)) { dragTranslation = 0 }
                }
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
                    // A/1 (real-device follow-up) — logo FOLLOWED BY
                    // visible text "Pulse", one title: the logo alone read
                    // as just "banbe," nothing naming this specific
                    // screen. Grouped via `.accessibilityElement(children:
                    // .combine)` + one `.accessibilityLabel` so VoiceOver
                    // announces the pair once, as "Banbe Pulse" — matches
                    // web's `role="heading"` fix exactly.
                    HStack(spacing: 8) {
                        BanbeLogo(kind: .wordmark, width: 100)
                        Text(app.T("Pulse", "Pulse")).font(BanbeTheme.display(20))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Banbe Pulse")
                    Spacer()
                    Button { commitDismiss() } label: {
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
            ScrollView {
                VStack(spacing: 10) {
                        // White-flash fix (2026-09-28 pass) — root cause
                        // confirmed by reading this exact branch: the loading
                        // GIF used to be gated purely on `loading`, which
                        // discarded a tab's own already-valid, already-loaded
                        // items the instant a background refresh started
                        // (`pulseDailyLoading`/`pulseWeeklyLoading`/
                        // `pulsePhotosLoading` flip true again on every
                        // `loadPulse`/`loadPulsePhotos` call, even a quiet
                        // re-fetch of a tab already showing real content) —
                        // blanking real cards back to a spinner is exactly the
                        // "flash" this pass fixes. The GIF now shows ONLY when
                        // there's genuinely nothing displayable yet.
                        if app.pulseTab == .photos {
                            if app.pulsePhotos.isEmpty {
                                if loading {
                                    BanbeLoadingVisual(size: 64)
                                        .padding(.top, 44)
                                        .accessibilityIdentifier("pulse.loading")
                                } else {
                                    Text(app.T("Chưa có dữ liệu xếp hạng.", "Nothing ranked yet."))
                                        .font(.system(size: 13)).foregroundStyle(app.palette.ink.opacity(0.7))
                                        .padding(.top, 60)
                                        .accessibilityIdentifier("pulse.empty")
                                }
                            } else {
                                ForEach(Array(app.pulsePhotos.enumerated()), id: \.element.id) { i, item in
                                    pulsePhotoCard(item, rank: i + 1)
                                }
                            }
                        } else if items.isEmpty {
                            if loading {
                                BanbeLoadingVisual(size: 64)
                                    .padding(.top, 44)
                                    .accessibilityIdentifier("pulse.loading")
                            } else {
                                Text(app.T("Chưa có dữ liệu xếp hạng.", "Nothing ranked yet."))
                                    .font(.system(size: 13)).foregroundStyle(app.palette.ink.opacity(0.7))
                                    .padding(.top, 60)
                                    .accessibilityIdentifier("pulse.empty")
                            }
                        } else {
                            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                                pulseCard(item, rank: i + 1)
                            }
                        }
                }
                // Loading-GIF pass — ONE section-level loader for the
                // whole tab's list (never one per thumbnail), shown only
                // while genuine items exist but none of their photos have
                // loaded yet (`sectionImagesLoading`'s own doc comment
                // above has the exact gate). `.overlay` sizes itself to
                // match this VStack exactly, so the real cards underneath
                // stay laid out at their full, already-reserved size —
                // this only ever visually covers that space, never
                // replaces it with something a different height, so
                // lifting it causes no layout jump.
                .overlay {
                    if sectionImagesLoading {
                        app.palette.paper
                            .overlay(BanbeLoadingVisual(size: 56))
                            .accessibilityIdentifier("pulse.imagesLoading")
                    }
                }
                .padding(20)
            }
        }
        .background(app.palette.paper.ignoresSafeArea())
        .offset(x: slideOffset)
        // A sliver of dimming that fades out as the dismiss progresses —
        // the same depth cue RootView's own edge-swipe gives every other
        // screen (see that gesture's `peekOffset`/dimming comment).
        .overlay(Color.black.opacity(max(0, 0.12 - Double(slideOffset) / 1400)).ignoresSafeArea().allowsHitTesting(false))

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

            // Expanded-panel redesign (2026-10-02) — both popups used to be
            // native `.sheet`s (system bottom-anchored presentations); a
            // centered floating card instead needs to be a plain overlay
            // inside this same view, not a separate presentation layer.
            // Reduce Motion: the panel still appears/disappears (never
            // skipped — this is content, not decoration), just without the
            // scale/opacity transition's own motion.
            if let item = app.pulseOrganizerSheet {
                organizerSheet(item)
                    .zIndex(20)
            }
            if let item = app.pulsePhotoSheet {
                photoSheet(item)
                    .zIndex(20)
            }
        }
        .coordinateSpace(name: "pulse.overlay")
        .onPreferenceChange(PulseSourceFramePreferenceKey.self) { pulseSourceFrames = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: app.pulseOrganizerSheet)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: app.pulsePhotoSheet)
        // Mirrors RootView's own `.onChange(of: isCommittingBack)` exactly —
        // let the single slide-to-edge animation actually finish playing
        // (0.22s) before removing this view from RootView's ZStack at all.
        // `app.pulseOpen = false` here is what makes it disappear (see
        // RootView.swift's `if app.pulseOpen { PulseViewerView() }`) — no
        // separate transition plays on removal since that conditional uses
        // `.transition(.identity)`.
        .onChange(of: isCommitting) { _, committing in
            guard committing else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                app.closePulseViewer()
            }
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
            .fixedSize()
            // Teaser "Ảnh nổi bật: Bấm xem thêm" deep-link pass — lets a UI
            // test (and any future caller) confirm which tab is actually
            // selected after jumping straight into this destination, since
            // the visual selected-state above (ink background) isn't itself
            // queryable.
            .accessibilityIdentifier("pulse.tab.\(tab.rawValue)")
            .accessibilityAddTraits(app.pulseTab == tab ? .isSelected : [])
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
            prepareExpandedPanel(key: pulseSourceKey(item.id))
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
                    // Loading-GIF pass — reports success/failure per photo
                    // URL into the shared `loadedPhotoURLs`/`erroredPhotoURLs`
                    // sets above, which gate the ONE section-level loader
                    // for the whole tab. A still-loading tile shows the
                    // themed `app.palette.field` fallback fill from the
                    // previous pass (never a naked/transparent placeholder,
                    // never a per-tile GIF of its own).
                    if let urlStr = eventPhotoURL(item.photoPath), let url = URL(string: urlStr) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                                    .onAppear { markPhotoLoaded(urlStr) }
                            case .failure:
                                Color.clear.onAppear { markPhotoErrored(urlStr) }
                            default:
                                Color.clear
                            }
                        }
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
        .buttonStyle(PulsePressButtonStyle())
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        // Left-corner-rounding fix (2026-09-28 pass) — real root cause:
        // `.background(_, in: shape)` only clips the BACKGROUND fill to
        // that shape, never the view's own content on top of it. The
        // flush-left 88x88 photo tile (a plain rectangle, `.clipped()`
        // only clips it to its OWN frame, not to any rounding) was never
        // actually being clipped to the card's rounded corners at all —
        // it just happened to look "rounded on the right" because the
        // text/breakdown columns there never extend flush to that edge to
        // begin with. Adding `.clipShape` here clips the WHOLE HStack
        // (including that photo tile) to the same rounded rect the
        // background already uses, making left/right symmetric.
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: PulseSourceFramePreferenceKey.self, value: [pulseSourceKey(item.id): proxy.frame(in: .named("pulse.overlay"))])
            }
        }
        .accessibilityIdentifier("pulse.card")
    }

    // Expanded-panel redesign (2026-10-02) — "IMG_6770 still has wide
    // filler panels around the featured photo" + an iOS "expanded media
    // control" (Now Playing card) as the VISUAL/interaction reference, not
    // an audio player. Replaces BOTH the oversized `.sheet` bottom-sheet
    // (Featured Photos' `photoSheet`, below) and the plain no-image
    // `.height(300)` sheet (ranked event rows' `organizerSheet`, this same
    // function, now image-aware) with ONE shared, centered floating glass
    // card: a rounded `.ultraThinMaterial` surface (auto-respects Reduce
    // Transparency — falls back to an opaque material automatically, no
    // manual check needed), over a dimmed/blurred scrim, bounded to the
    // real viewport with margins rather than a fixed-fraction/fixed-height
    // box. The photo area sizes itself to the photo's OWN aspect ratio
    // (`.scaledToFit()` with only MAX constraints, never an exact fixed
    // frame) up to an available-height cap — never stretched, never
    // cropped, and never leaving a visible separate "border panel": the
    // one soft backdrop this card uses is the SAME loaded image, blurred,
    // behind the whole card (one surface), not a second boxed media
    // region. Card content (image optional) + title/subtitle/meta +
    // actions are all parameters, so both callers below share one
    // implementation instead of two parallel layouts that can drift.
    @ViewBuilder
    private func pulseExpandedPanel<Actions: View>(
        photoURLString: String?,
        title: String,
        subtitle: String?,
        metaLine: String?,
        sourceKey: String,
        accessibilityCloseID: String,
        onClose: @escaping () -> Void,
        @ViewBuilder actions: @escaping () -> Actions
    ) -> some View {
        GeometryReader { geo in
            let panelWidth = min(geo.size.width * 0.8, 520)
            let maxImageWidth = max(1, panelWidth - 32)
            let maxImageHeight = max(120, geo.size.height * 0.42)
            let sourceRect = pulseSourceFrames[sourceKey]
            let validSource = sourceRect.map { $0.width > 1 && $0.height > 1 } ?? false
            let sourceScale = validSource ? min(sourceRect!.width / panelWidth, sourceRect!.height / 160) : 0.96
            let sourceOffsetX = validSource ? sourceRect!.midX - geo.size.width / 2 : 0
            let sourceOffsetY = validSource ? sourceRect!.midY - geo.size.height / 2 : 0
            let progress = reduceMotion ? 1 : expandedPanelProgress

            ZStack {
                // The scrim has its own fade, independent of the panel's
                // source expansion, so the underlying Pulse screen stays put.
                Rectangle()
                    .fill(.black.opacity(0.38 * Double(progress)))
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { closeExpandedPanel(onClose: onClose) }
                    .accessibilityHidden(true)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        if let image = expandedPanelImage {
                            let aspect = max(image.size.width / max(image.size.height, 1), 0.1)
                            let imageWidth = min(maxImageWidth, maxImageHeight * aspect)
                            let imageHeight = imageWidth / aspect
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: imageWidth, height: imageHeight)
                                .shadow(color: .black.opacity(0.24), radius: 10, y: 5)
                                .scaleEffect(0.97 + 0.03 * progress)
                                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                                }
                                .padding(.top, 16)
                        } else if photoURLString != nil {
                            ProgressView().frame(width: maxImageWidth, height: min(160, maxImageHeight)).padding(.top, 16)
                        }

                        VStack(spacing: 8) {
                            Text(title).font(BanbeTheme.display(18)).multilineTextAlignment(.center).lineLimit(3)
                            if let subtitle, !subtitle.isEmpty {
                                Text(subtitle).font(.subheadline).foregroundStyle(app.palette.ink.opacity(0.75))
                                    .multilineTextAlignment(.center)
                            }
                            if let metaLine, !metaLine.isEmpty {
                                Text(metaLine).font(.footnote).foregroundStyle(app.palette.ink.opacity(0.6))
                                    .multilineTextAlignment(.center)
                            }
                            actions().padding(.top, 6)
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 14)
                        .padding(.bottom, 18)
                    }
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(key: PulsePanelContentHeightPreferenceKey.self, value: proxy.size.height)
                        }
                    }
                }
                .frame(width: panelWidth)
                .frame(height: min(max(expandedPanelContentHeight, 1), geo.size.height - 32))
                .onPreferenceChange(PulsePanelContentHeightPreferenceKey.self) { height in
                    expandedPanelContentHeight = height
                }
                .background {
                    ZStack {
                        if let image = expandedPanelImage {
                            Image(uiImage: image).resizable().scaledToFill().blur(radius: 28).opacity(0.08)
                        }
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(app.palette.paper.opacity(0.28))
                        if #available(iOS 26.0, *), !reduceTransparency {
                            GlassEffectContainer {
                                Color.clear.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                                    .opacity(app.glassOpacity)
                            }
                        } else {
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .fill(app.palette.paper.opacity(0.28 * app.glassOpacity))
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                                .opacity(app.glassOpacity)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.28), radius: 22, y: 12)
                .foregroundStyle(app.palette.ink)
                .overlay(alignment: .topTrailing) {
                    Button { closeExpandedPanel(onClose: onClose) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(app.palette.ink)
                            .frame(width: 44, height: 44)
                            .background(.regularMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .accessibilityIdentifier(accessibilityCloseID)
                    .accessibilityLabel(app.T("Đóng", "Close"))
                }
                .scaleEffect(sourceScale + (1 - sourceScale) * progress)
                .offset(x: sourceOffsetX * (1 - progress), y: sourceOffsetY * (1 - progress))
                .task(id: photoURLString) {
                    guard let photoURLString else { return }
                    let image = await PhotoLoader.load(path: photoURLString, maxPixel: 1800)
                    guard !Task.isCancelled, expandedPanelKey == sourceKey else { return }
                    expandedPanelImage = image
                }
                .onAppear {
                    guard expandedPanelKey == sourceKey else { return }
                    guard !reduceMotion else { return }
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { expandedPanelProgress = 1 }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .transition(.opacity)
    }

    private func closeExpandedPanel(onClose: @escaping () -> Void) {
        guard !reduceMotion, expandedPanelProgress > 0.01 else { onClose(); return }
        withAnimation(.spring(response: 0.26, dampingFraction: 0.9), completionCriteria: .logicallyComplete, {
            expandedPanelProgress = 0
        }, completion: onClose)
    }

    // B3 — two large, equal-width, side-by-side rounded buttons instead of
    // a solid Follow pill + a separately-sized underlined "Xem sự kiện"
    // link. "Xem sự kiện" is now always a solid filled primary button
    // (matches web); "Theo dõi"/"Đang theo dõi" keeps its existing
    // filled/outline toggle look. Image-aware pass (2026-10-02) — this
    // sheet used to show no photo at all; now uses the shared
    // `pulseExpandedPanel` with the event's own real photo, rank, category
    // and the real booking/check-in/follow breakdown already loaded for
    // the row (never fabricated) — plus a new "Xem trang tổ chức"/"View
    // host" action alongside the existing Follow/"Xem sự kiện".
    @ViewBuilder
    private func organizerSheet(_ item: PulseItem) -> some View {
        let metaParts = [
            item.catLabel,
            app.T("\(item.bookingCount) vé", "\(item.bookingCount) bookings"),
            app.T("\(item.checkinCount) check-in", "\(item.checkinCount) check-ins"),
        ].compactMap { $0 }.filter { !$0.isEmpty }
        pulseExpandedPanel(
            photoURLString: eventPhotoURL(item.photoPath),
            title: item.eventName,
            subtitle: item.organizerName + (item.organizerVerified ? " ✓" : ""),
            metaLine: metaParts.joined(separator: " ▪︎ "),
            sourceKey: pulseSourceKey(item.id),
            accessibilityCloseID: "pulse.organizerSheet.close",
            onClose: { app.closePulseOrganizerSheet() }
        ) {
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
                        .frame(minHeight: 44)
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
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pulse.viewEvent")
            }
            Button {
                app.closePulseOrganizerSheet()
                app.closePulseViewer()
                app.openOrganizerProfile(organizerID: item.organizerId, back: .profile)
            } label: {
                Text(app.T("Xem trang tổ chức", "View host page"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .underline()
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pulse.viewHost")
        }
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
                // Loading-GIF pass — same success/failure reporting as
                // `pulseCard` above, into the same shared sets (this tab's
                // `activeTabPhotoURLs` switches source based on
                // `app.pulseTab == .photos`, see that computed property).
                if let urlStr = eventPhotoURL(item.photoPath), let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                                .onAppear { markPhotoLoaded(urlStr) }
                        case .failure:
                            Color.clear.onAppear { markPhotoErrored(urlStr) }
                        default:
                            Color.clear
                        }
                    }
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
        .onTapGesture {
            prepareExpandedPanel(key: pulsePhotoSourceKey(item.id))
            app.openPulsePhotoSheet(item)
        }
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        // Left-corner-rounding fix — same root cause/fix as `pulseCard`
        // above: `.background(_, in:)` never clipped the actual content.
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: PulseSourceFramePreferenceKey.self, value: [pulsePhotoSourceKey(item.id): proxy.frame(in: .named("pulse.overlay"))])
            }
        }
        .accessibilityIdentifier("pulse.photoCard")
    }

    // Expanded-panel redesign (2026-10-02) — was a native `.sheet` at a
    // fixed 2/3-of-screen fraction with a hardcoded 2:1 media/footer split
    // regardless of the real photo's aspect ratio — exactly the "wide
    // filler panels around the featured photo" this pass removes. Now uses
    // the shared `pulseExpandedPanel` (image-aware sizing, one glass
    // surface, no separate boxed media region). Like/Share/View behavior,
    // permissions, and counts are completely unchanged — only the
    // surrounding chrome moved.
    @ViewBuilder
    private func photoSheet(_ item: PulsePhotoItem) -> some View {
        let eng = engagement(item)
        pulseExpandedPanel(
            photoURLString: eventPhotoURL(item.photoPath),
            title: item.eventName,
            subtitle: item.organizerName + (item.organizerVerified ? " ✓" : ""),
            metaLine: nil,
            sourceKey: pulsePhotoSourceKey(item.id),
            accessibilityCloseID: "pulse-photo-sheet-close",
            onClose: { app.closePulsePhotoSheet() }
        ) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    // Heart rule (Task 3) — the glyph only ever renders
                    // filled (liked) or not at all; no outline/empty heart
                    // state. Reads/writes the canonical `photoEngagement`
                    // map, so this matches whatever the quick-action column
                    // and EventDetail/Organizer/PhotoViewer already show for
                    // the same photo id.
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
                        .frame(minHeight: 44)
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
                            .frame(minHeight: 44)
                            .overlay(Capsule().stroke(app.palette.rule))
                            .foregroundStyle(app.palette.ink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("pulse.photoShare")
                }

                Button(app.T("Xem sự kiện / trang tổ chức", "View event / host page")) {
                    app.closePulsePhotoSheet()
                    app.closePulseViewer()
                    app.goEvent(item.eventId)
                }
                .font(.system(size: 12)).foregroundStyle(app.palette.ink).underline()
                .frame(minHeight: 44)
                .accessibilityIdentifier("pulse.photoViewEvent")
            }
        }
    }
}
