import Foundation
import SwiftUI
import UIKit
import CoreLocation
import PhotosUI
import Supabase

/// Which screen is showing. The web app (src/App.jsx) keys one screen at a
/// time off a string and remembers explicit "back" targets rather than using
/// a router stack; this keeps the same model so the back behaviour matches.
enum Screen: String {
    case splash, langPick, themePick, home, profile, inbox, event, organizer
    case reserve, confirmed, refunded, login, chat, dashboard, hostIntro
    case create, attendance, preferences, editName, notifications, eventList
    case security
    case paymentDetails, billing, payout, documents, documentView
    case verifications, disputes, adminEvents
    case policy
    case mapExplore
    case refundAccounts, myRefunds
    case editProfile, publicProfile, organizerProfile
    case reports
    case organizerTeam
    case accountGroup
    case surveyPublic
    case surveysHosting
}

/// Which set of events EventListView shows — ports the same split used by
/// the "Going"/"Saved" counters and the "Completed events" row on Account.
enum EventListMode: String {
    case going, saved, completed
}

/// Predefined reasons an organizer must pick from before reversing a
/// check-in or cancelling a paid booking — ports UNDO_CHECKIN_REASONS /
/// CANCEL_BOOKING_REASONS. No free text, so the guest's notification always
/// says something concrete.
struct ReasonOption: Identifiable {
    let key: String
    let vi: String
    let en: String
    var id: String { key }

    static let undoCheckin: [ReasonOption] = [
        .init(key: "wrong_person", vi: "Nhầm người", en: "Wrong person"),
        .init(key: "tapped_by_mistake", vi: "Bấm nhầm", en: "Tapped by mistake"),
        .init(key: "not_arrived", vi: "Khách chưa thực sự có mặt", en: "Guest hasn't actually arrived"),
        .init(key: "other", vi: "Khác", en: "Other"),
    ]
    static let cancelBooking: [ReasonOption] = [
        .init(key: "event_changed", vi: "Sự kiện đổi lịch hoặc huỷ", en: "Event rescheduled or cancelled"),
        .init(key: "guest_requested", vi: "Khách yêu cầu huỷ", en: "Guest asked to cancel"),
        .init(key: "payment_incomplete", vi: "Không thanh toán đúng hạn", en: "Payment not completed in time"),
        .init(key: "policy_violation", vi: "Vi phạm quy định", en: "Policy violation"),
        .init(key: "other", vi: "Khác", en: "Other"),
    ]
    /// 14-organizer-checkin.md (Bug 2b) — ports REJECT_GUEST_REASONS.
    static let rejectGuest: [ReasonOption] = [
        .init(key: "no_seats_left", vi: "Hết chỗ thật sự", en: "Actually out of seats"),
        .init(key: "payment_mismatch", vi: "Không khớp với sao kê", en: "Doesn't match the statement"),
        .init(key: "suspected_fraud", vi: "Nghi ngờ gian lận", en: "Suspected fraud"),
        .init(key: "other", vi: "Khác", en: "Other"),
    ]
}

struct ReasonPrompt: Equatable {
    // 14-organizer-checkin.md: .rejectGuest (Bug 2b) picks a reason like the
    // other two; .confirmCheckin (Bug 3) has no reason list at all — a
    // plain yes/no, handled separately in ReasonSheetView.
    enum Kind { case undoCheckin, cancelBooking, rejectGuest, confirmCheckin }
    let kind: Kind
    let bookingID: UUID
    let guestName: String
}

/// One photo in a gallery handed to the viewer — the real `event_photos.id`,
/// its resolved public URL, and its OWN owning event's id (not necessarily
/// the screen's currently-viewed event — Organizer's photo grid spans every
/// event an organizer has ever posted to, see loadOrganizerPhotos's own doc
/// comment). Photo-interactions redesign (2026-09-26) — replaces the old
/// bare `[String]` URL gallery, which had no way to identify a photo's real
/// database row at all (the root cause of the like/save/share-vs-Pulse
/// mismatch this pass fixes).
struct PhotoGalleryItem: Equatable, Identifiable {
    let id: String
    let url: String
    let eventId: String
}

/// A gallery opened in the viewer — the whole set of photos it was tapped
/// from, so a left/right swipe can move through the rest, plus which one is
/// showing and the organizer it belongs to (shown as the faint credit).
struct PhotoViewerItem: Equatable {
    let gallery: [PhotoGalleryItem]
    var index: Int
    let organizer: String
    /// The tapped thumbnail's on-screen frame (global coordinate space) at
    /// the moment it was opened — where the dismiss animation shrinks back
    /// to (14-photo-viewer.md), rather than fading/sliding away generically.
    let originRect: CGRect
    var current: PhotoGalleryItem { gallery[index] }
}

/// Photo-interactions redesign (2026-09-26) — the canonical per-photo
/// engagement snapshot, keyed by the real `event_photos.id` (lowercased
/// UUID text, matching what every RPC in this schema returns and decodes
/// as). ONE shared model read by EventDetail's/Organizer's grids, the
/// full-screen PhotoViewerView, AND Pulse's photo tab — a like/share done
/// on any surface is immediately correct everywhere else, including after
/// Pulse re-loads. Mirrors src/state/GocContext.jsx's own `photoEngagement`
/// map entry shape exactly.
struct PhotoEngagement: Equatable {
    var likeCount: Int
    var shareCount: Int
    var likedByMe: Bool
}

/// A chat photo opened in ITS OWN fullscreen viewer (07-notifications.md /
/// 14-photo-viewer.md) — deliberately a separate type/state from
/// PhotoViewerItem above (different action set: Save/Share/Forward, not
/// Like/Save-event; must never be confused with an Event Detail photo).
struct ChatPhotoViewerItem: Equatable {
    let messageId: UUID?
    let attachmentPath: String
    let url: URL
    let width: Int?
    let height: Int?
    let senderLabel: String
    var forwardOpen: Bool = false
    // Task 2.3a (2026-09-22 follow-up) — a real review step before
    // "Post to Story" actually publishes.
    var postToStoryConfirm: Bool = false
}

/// BUG 5 fix (2026-09-22 follow-up) — the FULL ordered global deck (the
/// same array + order as HomeView's own story row / AccountView's own-
/// story-first sort — `homeStories` itself, not a re-derived copy) plus
/// `groupIndex` (which host) and `storyIndex` (which of that host's
/// stories) — an "Instagram-style deck," not one organizer's stories in
/// isolation (the previous `organizerId`/`index`/`stories` shape).
struct StoryViewerState: Equatable {
    let groups: [StoryGroup]
    var groupIndex: Int
    var storyIndex: Int
    // Task 1 (2026-09-22 twelfth follow-up) — the tapped ring's own global
    // frame (HomeView.swift's storyRow, via StoryRingFramePreferenceKey),
    // for StoryViewerView's expand-from-ring entrance. Carried through
    // every storyNext/storyPrev/storyNextHost/storyPrevHost update below
    // (each passes `originRect: v.originRect` along) exactly like web's
    // GocContext.jsx spreads `...v` — see openStoryViewer()'s own comment
    // for why dismissing toward a ring is a SEPARATE live lookup, not this.
    var originRect: CGRect?
}

struct AttendanceGuest: Identifiable, Equatable {
    let id: UUID
    let name: String
    let qty: Int
    var checkedIn: Bool
    /// Paid means the organizer confirmed the money arrived — which is also
    /// what issued the receipt. Status alone isn't the answer: hold_seats
    /// marks instant-approval bookings 'confirmed' before anyone has paid.
    var paid: Bool = false
    var totalVnd: Int = 0
    var code: String = ""
    /// Whether the guest already sent a transfer screenshot — the strongest
    /// signal there is that this is the right row to mark paid.
    var hasProof: Bool = false
    /// Whether a live receipt document already exists for this booking —
    /// upload_payment_document() (migration 056) requires a reason exactly
    /// when this is true (08-payment-documents.md's 2026-09-17 follow-up
    /// #5). Mirrors the web's AttendanceGuest.hasReceipt.
    var hasReceipt: Bool = false
    /// Live (0 or 1) + superseded-but-still-queryable (056's 24h soft-delete
    /// window) receipt rows for this booking.
    var receiptVersionCount: Int = 0
    var receiptPendingDelete: Int = 0
    /// Each individually tappable/openable (08-payment-documents.md's
    /// 2026-09-17 follow-up #7 — BUG 1), not just counted.
    var receipts: [AttendanceReceipt] = []
}

struct AttendanceReceipt: Identifiable, Equatable {
    let id: UUID
    let isLive: Bool
}

struct InboxThread: Identifiable, Equatable {
    let id: UUID
    let eventKey: String
    let name: String
    let img: String
    // Task 3a (07-notifications.md, 2026-09-21) — the OTHER participant's
    // own profiles.avatar_url (host's when I'm the guest, guest's when I'm
    // the organizer), for InboxView's merged-avatar badge. nil falls back
    // to an initial-letter circle, never a broken image URL.
    let otherAvatarURL: String?
    let snippet: String
    let lastAt: Date?
    // Task 3 (2026-09-21 follow-up) — same unread signal the dock badge's
    // own poll uses, reused here per-row so InboxView can bold an unread row
    // instead of a second computation.
    var unread: Bool = false
}

/// Per-participant star/archive state for one thread (thread_preferences,
/// migration 065) — NOT on `threads` itself, since a guest and the
/// organizer on the same thread need independent state.
struct ThreadPreference: Equatable {
    var starred: Bool = false
    var archived: Bool = false
}

enum InboxViewMode { case active, archived }

/// The whole app's state and behaviour — the iOS counterpart of
/// src/state/GocContext.jsx. Deliberately one object, like the web app, so
/// the two stay easy to compare; screens read it from the environment.
@MainActor
final class AppState: ObservableObject {
    // Account extension (2026-09-27, Stage 1) — the internal, organizer-
    // mode-gated management screens: real event creation/editing, the
    // organizer management dashboard, and event check-in. Deliberately
    // EXCLUDES verifications/payout/documents/refund-queue screens, which
    // stay reachable regardless of organizerMode (gated on canHost alone).
    static let hostOnlyScreens: Set<Screen> = [.dashboard, .create, .attendance]

    // MARK: Navigation
    @Published var screen: Screen = .home
    // Bottom tab bar (BottomTabBar.swift) — shrinks a bit while scrolling
    // down, same idea as iOS 26's `.tabBarMinimizeBehavior(.onScrollDown)`,
    // hand-rolled because this app's deployment target is iOS 17. Driven by
    // ScreenScaffold's own scroll-offset tracking via noteScaffoldScroll(),
    // and reset to false on every screen change (see RootView).
    @Published var bottomBarCollapsed: Bool = false
    // Refresh-indicator fix pass (2026-09-27, follow-up A) — shared pull-
    // to-refresh state for whichever of the five root tabs is currently on
    // screen (ScreenScaffold's own custom pull mechanism, replacing plain
    // `.refreshable{}` so its system spinner can be replaced with
    // RootRefreshIndicator's icon-outline travel — see that view's own
    // doc comment for why `.refreshable` itself can't be reskinned). One
    // shared pair of fields is enough since only one root tab is ever
    // interactive at a time; each screen still owns its OWN reload
    // closure, passed to `ScreenScaffold(onRefresh:)`.
    @Published var rootPullProgress: CGFloat = 0
    @Published var rootRefreshing = false
    // TASK 1 (2026-09-22 twenty-first follow-up) — the single shared signal
    // `BottomTabBarOverlay.applyVisibility()` (BottomTabBarOverlay.swift)
    // drives for EVERY dock hide/show case (screen change, StoryViewer,
    // modal action sheets, etc. — all already funnel through that one
    // function). `BottomTabBarOverlayRoot` animates its offset/opacity off
    // this single bool via `.animation(_:value:)`, instead of each call
    // site owning its own transition flag.
    @Published var dockVisible: Bool = true
    private var lastScaffoldScrollOffset: CGFloat = 0
    // Blocker fix (retention roadmap follow-up) — mirrors web's own
    // useEffect on s.eventKey (GocContext.jsx): whenever this is set to a
    // real, non-catalogue event id, kick off the canonical realEventsByID
    // fetch so `currentEvent` (below) has something real to resolve to
    // instead of sitting on the loading placeholder indefinitely.
    @Published var eventKey: String = "bepnho" {
        didSet {
            guard eventKey != oldValue, EventCatalog.find(eventKey)?.key != eventKey else { return }
            Task { await loadRealEventsByID([eventKey]) }
        }
    }
    @Published var eventBackScreen: Screen = .home
    // BUG 3 fix (2026-09-22 follow-up) — true only while the currently-open
    // Event Detail was reached via goEventFromStory(); the single source of
    // truth EventDetailView's back-label override and backFromEvent()'s own
    // routing both read.
    @Published var eventBackIsStory = false
    // The story's own host name at the moment goEventFromStory() was
    // called — read by EventDetailView's back-label override.
    @Published var storyReturnHostName: String?
    @Published var authReturnScreen: Screen = .home
    @Published var authBackScreen: Screen = .home
    /// True only when Login was reached by force (the mandatory post-
    /// splash/post-onboarding gate, or the guard in RootView catching an
    /// unauthenticated screen change) rather than a deliberate "sign in to
    /// do X" prompt that already has a real screen to fall back to —
    /// LoginView hides its Back link when this is true.
    @Published var authMandatory = false
    /// Task 1's consent checkbox (LoginView) — unticked by default, gates
    /// the submit button alongside the existing field-validity checks.
    @Published var policyConsent = false
    @Published var policyBackScreen: Screen = .login
    func openPolicy() { policyBackScreen = screen; screen = .policy }
    /// True only for a brand-new OAuth profile with no policyAcceptedAt yet
    /// (AppState+Data.swift's applySession()) — PolicyView renders as a
    /// mandatory, no-back-out gate instead of the ordinary "view the
    /// policy" screen while this is set.
    @Published var policyGateActive = false
    /// Every screen a signed-out visitor may ever legitimately be on —
    /// RootView's guard redirects anything else to .login. The
    /// enforcement point for "no guest browsing of any screen" (Task 1).
    // Personal-vs-organizer hierarchy pass (2026-09-27) — `.organizerProfile`
    // must work for a signed-out visitor (get_organizer_profile is granted
    // to anon, migration 095), same as a shared organizer link on web.
    // Organizer Team pass (2026-09-27, Stage 2) — .publicProfile was
    // missing despite get_public_profile() being anon-granted (a
    // pre-existing gap, out of scope in the prior ticket); now directly
    // in scope, since a signed-out Team page visitor must be able to tap
    // a member card through to their public profile.
    static let guestAllowedScreens: Set<Screen> = [.splash, .langPick, .themePick, .login, .policy, .organizerProfile, .organizerTeam, .publicProfile, .surveyPublic]

    // MARK: - Screenshot Catalog (docs/demo-screenshots)
    // Test-only launch flags for `scripts/capture_ios_catalog.sh` /
    // `BanbeAppUITests/ScreenshotCatalogTests.swift`. Same `-key value` ->
    // `UserDefaults.standard` convention `-banbe.onboarded` already uses
    // above (`hasOnboarded`), not a new mechanism. `isUITesting` gates any
    // live-timing behavior that would make a screenshot non-deterministic
    // (the story auto-advance timer, Home's countdown tick) — it is never
    // read outside a UI-testing launch. `demoRole`/`demoScenario` are
    // accepted and stored for a future pass to consume; this pass has no
    // demo/mock data model to switch on them (see that script's own
    // comment on why "not captured yet" is used for backend-data-dependent
    // flows instead of inventing one here).
    static let isUITesting = UserDefaults.standard.bool(forKey: "uiTesting")
    // TASK A point 4 — only these two screens are ever restorable from
    // `banbe.lastScreen`; any other/stale/unrecognized value is ignored.
    static func restorableScreen(from raw: String?) -> Screen? {
        switch raw {
        case "refundAccounts": return .refundAccounts
        case "myRefunds": return .myRefunds
        default: return nil
        }
    }
    static let isScreenshotCatalog = UserDefaults.standard.bool(forKey: "screenshotCatalog")
    static let demoRole = UserDefaults.standard.string(forKey: "demoRole")
    static let demoScenario = UserDefaults.standard.string(forKey: "demoScenario")

    @Published var chatBack: Screen = .organizer
    @Published var mode: String = "goer"
    // Inbox and Dashboard are each reachable from more than one place (Home's
    // message icon/host link vs Account's "Messages" row/hosting card), so a
    // single hardcoded back target sends at least one of those callers
    // somewhere it didn't come from.
    @Published var inboxBack: Screen = .home
    @Published var dashboardBack: Screen = .home
    // Stage 1 (2026-09-27 nav/discovery pass) — the real root screen/tab
    // dock + (or Dashboard's "Sửa & gửi lại") was entered from; createBack()
    // and backTarget's own `.create` case (below) both read this instead of
    // hard-routing to a fixed `.dashboard`/`.hostIntro`, which used to send
    // Back from Create to Dashboard even when the host had opened + from
    // Home, Map, Inbox, or Account.
    @Published var createOriginScreen: Screen = .home
    @Published var eventListMode: EventListMode = .going
    // Sub-section-of-a-group back-navigation fix (2026-09-29, second pass)
    // — same `documentsListBack`-style convention: `.eventList` is shared
    // by three entry points (Going/Saved, from AccountView's own root
    // counters — correctly `.profile`; Completed events, from
    // AccountGroupView's "activity" group page — was incorrectly always
    // `.profile` too, skipping that group page). Each `goXList()` function
    // now sets this explicitly instead of `backFromEventList()` hardcoding
    // one target for all three.
    @Published var eventListBack: Screen = .profile

    // MARK: Preferences (persisted per-device and, once signed in, per-account)
    @Published var lang: String = UserDefaults.standard.string(forKey: "banbe.lang") ?? "vi" {
        didSet { UserDefaults.standard.set(lang, forKey: "banbe.lang") }
    }
    @Published var theme: String = UserDefaults.standard.string(forKey: "banbe.theme") ?? "light" {
        didSet { UserDefaults.standard.set(theme, forKey: "banbe.theme") }
    }
    // Location hierarchy (migration 112) — now a `LocationHierarchy` node
    // ID ("all", "c:VN", "c:VN|a:Quận 1", …) instead of one of six
    // hardcoded keys. Still purely in-memory (it never was persisted —
    // confirmed by grep: no UserDefaults key for it), so a relaunch resets
    // to "all" exactly as before. Any legacy key that still reaches it
    // (q1/thaodien/binhthanh/other/danang/all) is mapped to its new ID by
    // the pure `LocationHierarchy.migrateSelection` instead of breaking.
    @Published var area: String = LocationHierarchy.allID {
        didSet {
            let migrated = LocationHierarchy.migrateSelection(area)
            if migrated != area { area = migrated }
        }
    }
    /// The area sheet's expand/collapse state, by stable node ID — kept
    /// here (not view-local) so it survives the sheet closing/reopening
    /// and is shared by Home's and Map's copies of the picker. Never
    /// touches `area`: expanding is not selecting.
    @Published var areaExpanded: Set<String> = ["c:VN"]
    /// Live DB location of each demo-catalogue event, keyed by slug —
    /// populated by `loadHomeLiveEvents()` (same rows Map reads).
    @Published var homeEventLocations: [String: EventLocation] = [:]
    @Published var filter: String = "all"
    // Home's second, independent chip row (12-home-filters.md) — multi-select,
    // AND-combined with `filter`/`area` above, not folded into either.
    @Published var filterAttending = false
    @Published var filterSaved = false
    @Published var filterSoldOut = false
    // 2026-09-21 follow-up — rounds out the chip set (07-notifications.md).
    // notAttending/notSaved existed briefly then were removed the same day
    // per a follow-up ticket (redundant inverses cluttering the row).
    @Published var filterNotConfirmed = false
    @Published var filterUpcoming = false
    @Published var filterEnded = false

    // MARK: Session
    @Published var user: Profile?
    @Published var userID: UUID?
    @Published var userEmail: String?
    @Published var accountType: String = "participant"
    @Published var organizerMode = false
    @Published var organizerModeError = ""
    @Published var organizerModeBusy = false
    // BUG 1 (2026-10-07 fix pass) — a plain (non-`@Published`) re-entrancy
    // lock for `applyOrganizerMode`, deliberately separate from the
    // `@Published organizerModeBusy` above. The guard against a second tap
    // racing an in-flight call must be set the INSTANT the first call is
    // accepted — before any `await`, including the `Task.yield()`
    // `applyOrganizerMode` now starts with (see its own comment) — or a
    // second tap landing in that same window would pass the same guard
    // check and start a second, overlapping request. Setting `@Published
    // organizerModeBusy` itself that early is exactly what reintroduces
    // the "publishing changes from within view updates" warning this fix
    // pass removes, so the synchronous, warning-free lock lives here, and
    // the UI-facing published flag is set only after the yield.
    var organizerModeInFlight = false
    // Stage 1 (retention roadmap P0, real favorites) — which account's
    // `favorites` rows are currently loaded/loading, mirroring web's own
    // favoritesUidRef (GocContext.jsx): applySession() re-runs on every
    // sign-in AND on the app returning to the foreground with an existing
    // session, so this stops a same-account re-run from re-clearing/
    // reloading (no flash), while a genuine account switch still does.
    var favoritesLoadedForUID: UUID?
    // Dedupe rapid repeat taps on the same event's save toggle — see
    // toggleFavorite()'s own comment.
    var favoriteToggleInFlight: Set<String> = []
    @Published var hasHosted = false
    // TASK 1 real-device follow-up — whether the dock "+"'s creation tray
    // is open. Lives on AppState (not local @State in DockCreateButtonView)
    // because the tray itself renders in RootView's own main-window ZStack
    // (see that file), a different view entirely from the button that
    // opens it (DockCreateButtonView, inside BottomTabBarOverlay's separate
    // UIWindow) — both need to read/drive the same boolean. A native
    // SwiftUI `Menu` was tried here first and reverted — see
    // DockCreateButtonView's own doc comment for the real-device clipping
    // bug that caused.
    @Published var dockCreateMenuOpen = false
    // MARK: Feed state
    @Published var favorites: [String] = []
    @Published var following: [String] = []
    @Published var attending: [String] = []
    @Published var tickets: [String: Int] = [:]
    @Published var myOrgEventKeys: [String] = []
    @Published var myOrganizerIDs: [String] = []
    /// Refund-discoverability investigation — mirrors web's `myOrganizerIdsStatus`.
    /// `loadMyEvents()`'s own `catch` already left `myOrganizerIDs` untouched
    /// on a failed lookup (confirmed by reading — iOS never had web's "no
    /// error check, silently writes []" bug), but there was still no way for
    /// a reader (loadRefundQueue's own gate, diagnostics) to tell "still
    /// loading"/"failed" apart from "confirmed owns zero organizers" just
    /// from `myOrganizerIDs.isEmpty`. 'idle' | 'loading' | 'loaded' | 'error'.
    @Published var myOrganizerIdsStatus = "idle"
    // Part B audit (2026-09-28) — Dashboard-identity-mismatch fix (mirrors
    // web's GocContext.jsx `myOrgEventOrganizerId`). `myOrgEventKeys` above
    // stays the full union across every organizer row this account owns
    // on purpose — it's the real per-event ownership gate elsewhere (the
    // dual-role-account check in the notification handlers below) — but
    // DashboardView's own branded "upcoming"/"past" shelf must show only
    // the ONE organizer it brands (`myOrganizerID`), not every organizer
    // this account happens to own (only ever produced by migration 020's
    // per-event-random seed; a real user only ever has one). This maps
    // each owned event id to its real organizer_id so `myOrgEvents` below
    // can filter to just the branded organizer's own events.
    @Published var myOrgEventOrganizerID: [String: String] = [:]
    // Host tab's own profile card (Stage D, migration 090) — this
    // account's single organizer id + its real avatar_path. Only one
    // organizer per account is supported (same standing assumption
    // create_event_draft's own `ORDER BY created_at LIMIT 1` already
    // makes).
    @Published var myOrganizerID: String?
    @Published var myOrganizerAvatarPath = ""
    // Stage 1 (2026-09-27 nav/discovery pass) — Account host card's own
    // "Tổ chức từ <year> ▪︎ <N> sự kiện", read straight from real event
    // rows by organizer_id (never a stored/static total), same published-
    // only rule (status IN live/ended) as get_public_profile's event_count/
    // hosting_since_year (migration 091) so both places always agree. nil
    // means "not loaded yet"; 0 is a real, honest zero.
    @Published var myOrgPublishedEventCount: Int?
    @Published var myOrgHostingSinceYear: Int?
    // iPhone fix pass (2026-09-26) — AccountView's own Cá nhân/Tổ chức tab,
    // lifted out of local `@State` (which reset to "personal" every time
    // AccountView's switch-statement case was re-entered — e.g. after
    // opening the new public-profile link and coming back) into here.
    @Published var accountTab = "personal"
    // Account IA pass (2026-09-27) — which group AccountGroupView shows:
    // "team" | "activity" | "payments" | "preferences" | "hostOps" |
    // "adminReview". `accountTab` itself is untouched by opening a group.
    @Published var accountGroupKey: String?
    @Published var orgProfileSaving = false
    @Published var orgProfileError = ""
    // Retention roadmap follow-up — canonical real-event cache, keyed by
    // real `events.id`. `nil` (key absent, i.e. `realEventsByID[key] ==
    // nil` AND `realEventsByID.index(forKey: key) == nil`) means not yet
    // requested; an explicit `.some(nil)` means requested but the row
    // doesn't exist or RLS denied it (an honest "unavailable", never
    // silently dropped); `.some(event)` is the shaped real row as a
    // CatalogEvent (CatalogEvent.fromReal) — see loadRealEventsByID.
    @Published var realEventsByID: [String: CatalogEvent?] = [:]
    var realEventsInFlight: Set<String> = []
    // Retention roadmap P1 — Home's "Cuối tuần này" section.
    @Published var weekendEvents: [CatalogEvent] = []
    @Published var weekendEventsLoading = false
    // Home-visibility fix (2026-09-29) — root cause of "an approved real
    // event never shows on Home" on iOS, confirmed by grepping this whole
    // file/HomeView.swift before assuming: unlike web (GocContext.jsx's
    // `discoveryEvents`/`loadDiscoveryEvents`), iOS's `feed` (below) was
    // built ONLY from `EventCatalog.all` — the static demo catalogue —
    // with no real-event data source merged in AT ALL. `weekendEvents`
    // above only covers THIS weekend; any real event outside that narrow
    // window (including one submitted/approved on any other day) could
    // never appear on Home no matter its status. This is the iOS port of
    // web's identical `discoveryEvents`/`loadDiscoveryEvents`.
    @Published var discoveryEvents: [CatalogEvent] = []
    @Published var discoveryEventsLoading = false
    // Event review queue (event submission -> review -> publish) — this
    // account's own REAL (non-catalogue) events, raw (status, rejection
    // reason, submitted/reviewed timestamps included) rather than shaped
    // into a public-facing CatalogEvent, since DashboardView needs to
    // distinguish 'review'/'draft'+reason from 'live'/'ended', which
    // CatalogEvent alone can't (it only ever carries derived booleans).
    @Published var myOrgEventSummaries: [RealEventSummary] = []
    // Admin-only "Sự kiện chờ duyệt" queue.
    @Published var adminEvents: [RealEventSummary] = []
    @Published var adminEventsLoading = false
    @Published var adminEventBusy: String?
    @Published var adminEventError = ""
    // TASK 5 (Account badges pass) — count-only sibling of `adminEvents`,
    // powering the "adminReview" group-card badge; see
    // `loadPendingEventsCount()`'s own comment.
    @Published var pendingEventsCount = 0

    // MARK: Location
    @Published var located: Bool?
    @Published var userCoords: Coordinates?
    @Published var askingLocation = false
    @Published var areaAsking = false

    // MARK: Booking
    @Published var qty: Int = 1
    // ReserveView's Name field, ONLY used for the empty-display_name case
    // (01-hold-payment.md's 2026-09-17 follow-up #6): once a real
    // profiles.display_name exists it's shown read-only from user.displayName
    // instead, never free-typed. formEmail is gone entirely — the email
    // field is always a read-only display of userEmail now.
    @Published var formName = ""
    @Published var reserveNameSaving = false
    @Published var reserveNameError = ""
    @Published var booking: Booking?
    @Published var holdDeadline: Date?
    // The real `events` row's own status for whichever event is currently
    // open — see `applyingLiveStatus`/`loadLiveEventStatus`. Unlike
    // `booking`, this is fetched regardless of sign-in.
    @Published var liveEventStatus: LiveEventStatus?
    // 2026-09-21 follow-up — batched across every catalogue key Home might
    // show, keyed by catalogue key (== events.slug). Fixes a real bug:
    // `CatalogEvent.endedHoursAgo` (generated from src/data/events.js's own
    // hardcoded STATUS map) is baked in at build time and never increases
    // as real time passes — `savedStrip`'s "Clears after 48h" caption was
    // checking against that frozen number, so an event could sit at, say,
    // "10 hours ago" forever and never actually clear.
    @Published var homeLiveEvents: [String: LiveEventStatus] = [:]
    // STAGE B (2026-09-25) — OrganizerView's real photo library, replacing
    // the static `orgGallery` render. See loadOrganizerPhotos's own doc
    // comment (AppState+Data.swift).
    @Published var organizerPhotos: [OrganizerPhoto] = []
    @Published var organizerPhotosLoading = false
    // STAGE D (2026-09-25) — EventDetailView's real gallery: one event's
    // own event_photos rows. See loadEventPhotos's own doc comment
    // (AppState+Data.swift).
    @Published var eventPhotos: [OrganizerPhoto] = []
    @Published var eventPhotosLoading = false
    // Strict invite-only events (migration 113) — resolved display URL per
    // photo id, populated by loadEventPhotos (AppState+Data.swift). A
    // public event's photo resolves via the cheap synchronous
    // getPublicURL(); an invite-only event's photo (storage_path prefixed
    // 'event-photos-private/') needs a real signed-URL network call
    // instead, which OrganizerPhoto's own Decodable init can't do inline —
    // hence a separate map rather than a field on the model itself.
    @Published var eventPhotoURLs: [UUID: URL] = [:]
    // STAGE C (2026-09-25) — Dashboard's real "add photo" upload flow.
    @Published var eventPhotoUploadBusy: [String: Bool] = [:]
    @Published var eventPhotoUploaded: [String: Bool] = [:]
    @Published var eventPhotoUploadError = ""
    @Published var now = Date()
    @Published var reserveError = ""
    @Published var loading = false
    // submitCreateEvent's own synchronous submit-in-flight guard (task 1) —
    // plain, non-`@Published` (same reasoning as `organizerModeInFlight`,
    // 17-ux-foundation-release.md's 2026-10-07 fix pass): a repeated tap on
    // the submit button can fire its second call before SwiftUI has
    // re-rendered `loading`'s new value, so only a synchronously-readable
    // flag actually stops it. This is a NICETY, not the real guard —
    // migration 107's server-side duplicate-pending-event check and atomic
    // row lock are what actually make a duplicate/concurrent submission
    // impossible.
    var submitCreateEventInFlight = false
    @Published var calAdded = false
    // Bug 3 (15-organizer-checkin.md follow-up): the event the calendar
    // picker confirmation dialog is currently open for, or nil when closed.
    @Published var calendarPickerEvent: CatalogEvent?
    @Published var calendarError = ""
    @Published var sharedFlash = false

    // MARK: Chat
    @Published var chatThreadID: UUID?
    @Published var chatMessages: [ChatMessage] = []
    @Published var chatDraft = ""
    // The other participant's own name for ChatView's header (host name for
    // a guest, guest name for an organizer) — set once per openThread()/
    // openChat(for:) call, mirrors src/screens/Chat.jsx's chatOtherName.
    @Published var chatOtherName = ""
    // Id of the first unread message at the moment this thread was opened —
    // drives ChatView's "— Chưa đọc —" divider. Captured once by
    // loadChatMessages(_:computeDivider:) and never recomputed by the 4s
    // poll, so it doesn't move while the thread stays open.
    @Published var chatUnreadDividerID: UUID?
    // path -> signed URL (10min), for chat message attachments (Task 4,
    // 2026-09-21 follow-up) — mirrors `proofUrls`'s own pattern for the
    // private payment-proof bucket.
    @Published var chatAttachmentUrls: [String: URL] = [:]
    // Task 2 (07-notifications.md) — a chat photo open in its own fullscreen
    // viewer. Separate from `photoViewer` above — see ChatPhotoViewerItem.
    @Published var chatPhotoViewer: ChatPhotoViewerItem?
    // Task 5 (2026-09-22 twelfth follow-up) — set by sendChatViewerReply()/
    // sendChatAttachment(replyToMessageId:) right when a reply/reaction sent
    // FROM ChatPhotoViewerView lands, so ChatView (already there underneath
    // — the viewer is a ZStack overlay, not a separate `screen`) can scroll
    // that message into view and clear the flag; chatFocusComposer only
    // true for a typed reply, never a one-tap quick reaction. Mirrors web's
    // GocContext.jsx chatScrollToMessageId/chatFocusComposer exactly.
    @Published var chatScrollToMessageID: UUID?
    @Published var chatFocusComposer = false
    // Task 3 (07-notifications.md) — active stories, grouped by organizer,
    // from loadHomeStories(). Own progression viewer state, own creation
    // preview state — kept separate from photoViewer/chatPhotoViewer.
    @Published var homeStories: [StoryGroup] = []
    @Published var storyViewer: StoryViewerState?
    // Task 1 (2026-09-22 twelfth follow-up) — HomeView's story row publishes
    // each ring's own global frame here (StoryRingFramePreferenceKey, via
    // .onPreferenceChange) so StoryViewerView can do a LIVE lookup by
    // organizerId at dismiss time (the currently active host's ring may
    // differ from whichever one was tapped to open — see openStoryViewer()'s
    // own comment). Home stays mounted underneath StoryViewerView the whole
    // time (RootView.swift's ZStack), so this dictionary keeps updating even
    // while visually covered.
    @Published var storyRingFrames: [String: CGRect] = [:]
    // Pulse teaser pass (2026-09-27), reworked by the same-space pass
    // (2026-09-28, after a second real-device report of the bubble sitting
    // fixed on screen while the ring scrolled) — the teaser's own sequence
    // position, published by `PulseTeaserBubbleView` (RootView.swift — it
    // stays a RootView sibling so its timers keep running while Home isn't
    // the mounted screen) and rendered by `HomeView.storyRow`, which draws
    // the bubble INSIDE the story row's own content — the very same
    // scrolling coordinate space as the Pulse ring it points at — so UIKit
    // moves the two together with no callback, KVO, coordinate conversion
    // or SwiftUI render commit in the path. Because of that, this is only
    // ever written on a real state change (a step advance, a tap, a
    // dismiss), never once per scroll frame, so a plain `@Published` read
    // in HomeView is all the bubble needs.
    //
    // This REPLACES the previous pair of properties here — `pulseRingFrame`
    // (the ring's own on-screen frame, measured via the now-deleted
    // `RingFrameProbe` in Components.swift and written straight from its KVO
    // callback in HomeView) and `pulseBubbleFrameSink` (an imperative
    // `UIView.frame` write into a hosted bubble, via the now-deleted
    // `PulseBubblePositioningHost`). Both were attempts to keep a
    // screen-positioned overlay in sync with the ring through callbacks,
    // and both still left the bubble frozen at a fixed screen position
    // during a real finger-drag; see `PulseTeaserBubbleView`'s own
    // "Same-space pass" doc comment for the full history. Nothing reads a
    // ring frame any more, so there is no replacement for them.
    @Published var pulseTeaserStep: Int = -1
    /// The two tap actions the bubble calls — `advanceOrDismiss()` (a tap
    /// anywhere on the bubble) and `openFeaturedPhotos()` (the final step's
    /// "Bấm xem thêm" link). Both still live in `PulseTeaserBubbleView`,
    /// which owns the sequence; these are just the handles Home needs to
    /// reach them without owning (or duplicating) that state machine. A tap
    /// is a one-off event, never a per-scroll-frame one, so a plain closure
    /// is immune to every timing problem the positioning code used to fight.
    var pulseTeaserAdvance: (() -> Void)?
    var pulseTeaserOpenPhotos: (() -> Void)?
    @Published var storyCreatePreviewImage: UIImage?
    @Published var storyCreateBusy = false
    // TASK 1 (dock "+" native-menu pass) — moved up from AccountView's own
    // local @State so both AccountView's "Đăng story" menu AND the dock
    // "+" menu (DockCreateButtonView, a different view entirely, inside
    // BottomTabBarOverlay's separate UIWindow) can drive the same
    // picker/camera trigger; the actual `.photosPicker`/`.fullScreenCover`
    // presentation is attached once, centrally, in RootView so it works
    // regardless of which screen/menu set the flag.
    @Published var storyLibraryPickerOpen = false
    @Published var storyCameraOpen = false
    @Published var storyPhotoItem: PhotosPickerItem?
    @Published var storyViewedIds: Set<UUID> = []
    // Cached by loadHomeStories()/currentOrganizerIds() — iOS has no
    // upfront-loaded organizer-id list the way web's GocContext.jsx does,
    // so AccountView's story ring reads this instead of awaiting an async
    // call from inside a computed `View` property.
    @Published var myOrganizerIdsCache: [String] = []
    @Published var inboxThreads: [InboxThread] = []
    // Keyed by thread id — Task 2 (2026-09-21 follow-up).
    @Published var inboxThreadPrefs: [UUID: ThreadPreference] = [:]
    // Which InboxView is currently showing — Task 1b.
    @Published var inboxView: InboxViewMode = .active
    // Unread message count for the Inbox tab badge (BottomTabBar.swift) —
    // mirrors unreadNotifications below, but there's no client-loaded
    // `messages` array to derive it from client-side (inboxThreads only
    // carries each thread's latest message, not every unread one), so this
    // is refreshed by its own query — see refreshUnreadMessageCount() in
    // AppState+Data.swift, piggybacked on the same 5s poll loop
    // startNotificationPolling() already runs (there's no realtime
    // subscription anywhere in this app to hook into instead).
    @Published var unreadMessages: Int = 0
    // BUG 1 (2026-09-22 fourteenth follow-up) — the timestamp of the most
    // recent successful messages.read_at write, mirrors web's
    // GocContext.jsx `lastReadWriteAtRef` exactly: markThreadMessagesRead()
    // stamps this on success; loadInboxThreads()/refreshUnreadMessageCount()
    // (AppState+Data.swift) each capture their OWN request's start time and
    // discard their result if it started before this — a request whose
    // query began before a mark-read committed can resolve AFTER it with a
    // stale, pre-write unread snapshot, silently reverting a thread's row/
    // the dock badge back to unread a few seconds after it was genuinely
    // marked read. Not `@Published` — nothing renders from this directly.
    var lastReadWriteAt: Date = .distantPast
    // BUG 1 (2026-09-22 fifteenth follow-up) — the timestamp guard above
    // covers "a response older than the last mark-read," but not "a
    // response older than a NEWER request for the same resource" (e.g. two
    // overlapping loadInboxThreads() calls from InboxView's `.task`
    // restarting) — a generation token per resource, incremented at the
    // START of each request; a request only ever commits its result if its
    // OWN generation still matches the current one when it resolves. Also
    // the mechanism that makes a cancelled request's result inert without
    // needing to inspect the error at all: cancelling-and-superseding a
    // request bumps the generation, so even a cancelled request that
    // somehow still returned a stale value would be rejected here anyway.
    var inboxThreadsGeneration = 0
    var chatMessagesGeneration = 0
    var unreadCountGeneration = 0

    // MARK: Notifications
    @Published var notifications: [AppNotification] = []
    var unreadNotifications: Int { notifications.filter { $0.readAt == nil }.count }
    // Batch-fetched by loadNotifications() alongside `notifications` itself
    // — avatarSource(for:maps:accountType:) (Lib/NotificationPresentation.swift)
    // reads this instead of a join per row.
    @Published var notificationAvatarMaps = NotificationAvatarMaps()
    // TASK 2 (2026-09-22 seventeenth follow-up) — NotificationsView's
    // selection/edit mode state, web parity (Notifications.jsx). Kept here
    // (not view-local @State) only because deleteNotifications() itself
    // needs to know which ids are selected when the bulk delete action
    // fires; NotificationsView.swift (out of this pass's file scope) is
    // where the actual checkbox/"Chọn"/"Xoá (n)" UI reads and mutates
    // these. `selectedNotificationIDs` only ever holds ids currently
    // present in `notifications` (whatever's actually loaded on screen) —
    // "Select all" must populate it from that same array, never a
    // hidden/paginated set the user never saw.
    @Published var notificationSelectionMode = false
    @Published var selectedNotificationIDs: Set<UUID> = []

    // TASK 3 (2026-09-22 seventeenth follow-up) — true for the duration of
    // ANY modal action sheet/menu presented over a screen that also needs
    // the dock hidden underneath it (starting with NotificationsView's own
    // "•••" action sheet — see BottomTabBarOverlay.swift's own comment on
    // why its UIWindow needs an explicit signal, not just a SwiftUI zIndex
    // change, to actually stop rendering above a sheet). Not scoped to
    // Notifications specifically so any other screen's future modal sheet
    // can reuse the same flag instead of inventing a parallel one.
    @Published var modalActionSheetPresented = false

    // Ephemeral in-app toasts — mirrors src/screens/ToastStack.jsx on web.
    // Separate from `notifications` (the permanent, pull-based inbox): this
    // is what proactively surfaces an event while the app is open. See
    // .claude/notes/07-notifications.md.
    @Published var toasts: [ToastItem] = []
    var notificationPollTask: Task<Void, Never>?

    // Set by openNotification() for a 'dispute_message' notification —
    // DisputeChatPanel.swift reads this itself (rather than every parent
    // view threading it through) to scroll to and briefly highlight
    // `messageID`, or just scroll to the bottom if it's nil (an older
    // notification row from before migration 050 added message_id).
    // Cleared once DisputeChatPanel has actually applied it.
    @Published var chatHighlight: (bookingID: UUID, messageID: UUID?)?
    func clearChatHighlight() { chatHighlight = nil }

    /// Set by openNotification()'s "receipt_requested" case — the same
    /// scroll-to-and-highlight idea as chatHighlight above, but for
    /// AttendanceView's per-guest "Upload receipt" control. Cleared once
    /// AttendanceView has actually applied it.
    @Published var attendanceHighlightBookingID: UUID?

    /// Notification banner fix pass (2026-09-30 third) — named constant
    /// (was a bare 2.5s `Task.sleep`), matching web's `TOAST_DURATION_MS`
    /// (GocContext.jsx) value-for-value.
    static let toastDurationSeconds: TimeInterval = 8.0

    /// Real per-toast timer bookkeeping (pause/resume needs a cancellable
    /// task + a remaining-budget, not just a plain sleep). Not `@Published`
    /// — a `Task` handle isn't renderable data.
    private struct ToastTimerState {
        var task: Task<Void, Never>?
        var remaining: TimeInterval
        var startedAt: Date
        var paused: Bool
    }
    private var toastTimers: [UUID: ToastTimerState] = [:]

    private func armToastTimer(id: UUID, remaining: TimeInterval) {
        let task = Task {
            try? await Task.sleep(nanoseconds: UInt64(max(0, remaining) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            finishToastAutoDismiss(id)
        }
        toastTimers[id] = ToastTimerState(task: task, remaining: remaining, startedAt: Date(), paused: false)
    }

    private func finishToastAutoDismiss(_ id: UUID) {
        toastTimers[id] = nil
        toasts.removeAll { $0.id == id }
    }

    /// Called by ToastOverlay's own per-toast `.onAppear` — the moment a
    /// toast is actually painted on screen (not merely appended to the
    /// queue, which may have happened earlier if it sat behind "Xem thêm").
    /// Idempotent: an already-ticking toast is never restarted.
    func markToastVisible(_ id: UUID) {
        guard toastTimers[id] == nil else { return }
        armToastTimer(id: id, remaining: Self.toastDurationSeconds)
    }

    /// Pause on interaction (an active press on the banner, ToastOverlay's
    /// own long-press-as-press-state gesture) — a real timer pause: the
    /// pending `Task` is cancelled and its remaining budget recorded, not
    /// merely a visual state.
    func pauseToastTimer(_ id: UUID) {
        guard var timer = toastTimers[id], !timer.paused else { return }
        timer.task?.cancel()
        timer.remaining = max(0, timer.remaining - Date().timeIntervalSince(timer.startedAt))
        timer.paused = true
        timer.task = nil
        toastTimers[id] = timer
    }

    /// Resume once the press ends — the remaining budget from when the
    /// press started resumes counting down (not a fresh full window).
    func resumeToastTimer(_ id: UUID) {
        guard let timer = toastTimers[id], timer.paused else { return }
        armToastTimer(id: id, remaining: timer.remaining)
    }

    /// Account deletion (Task 2, Account/Settings pass) — drives
    /// `DeleteAccountView`'s `.fullScreenCover` presentation from
    /// `RootView`. The wizard's own step/reason/phrase/reauth state lives
    /// locally in that view (plain `@State`, not here) — this is the one
    /// piece of state another screen (AccountGroupView's `preferences`
    /// case) needs to reach in to flip.
    @Published var deleteAccountOpen = false

    /// Shows a small toast and fires a light (not the heavier .success/
    /// .warning system) haptic alongside it, so it feels gentle — see
    /// startNotificationPolling() in AppState+Data.swift for what triggers
    /// this. Carries the whole notification (not just title/body) so
    /// tapping it can route the same way NotificationsView's rows do.
    /// Queue/dedup by stable id: a new arrival for the SAME notification
    /// already shown/queued (and not yet dismissed) is dropped rather than
    /// replacing/resetting the visible banner mid-read.
    func pushToast(_ notification: AppNotification) {
        if toasts.contains(where: { $0.notification.id == notification.id }) { return }
        let item = ToastItem(id: UUID(), notification: notification)
        toasts.append(item)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // The auto-dismiss timer is armed by markToastVisible(_:), called
        // from ToastOverlay's own onAppear — NOT here — so the duration
        // starts when the banner is actually visible, not at enqueue time.
    }

    /// Tapping a toast shouldn't sit around for its own auto-dismiss timer.
    /// Cancels the pending timer FIRST (synchronously) so a race with
    /// openNotification's own async work can never let the banner vanish
    /// out from under an in-flight tap before it resolves.
    func dismissToast(_ id: UUID) {
        toastTimers[id]?.task?.cancel()
        toastTimers[id] = nil
        toasts.removeAll { $0.id == id }
    }

    /// "Tắt tất cả" (ToastOverlay.swift) — clears the whole local toast
    /// queue at once. Same local-only contract as dismissToast: this NEVER
    /// touches `notifications`/`read_at` on the server — the bell inbox's
    /// unread state and badge count are untouched by clearing this ephemeral
    /// queue. See .claude/notes/07-notifications.md.
    func dismissAllToasts() {
        for (_, timer) in toastTimers { timer.task?.cancel() }
        toastTimers.removeAll()
        toasts.removeAll()
    }

    // MARK: Display name
    @Published var editNameValue = ""
    @Published var editNameError = ""
    @Published var editNameSaving = false
    // TASK 4 (Reserve→edit-name pass) — where `goEditName()` was actually
    // called from (Account's own "Đổi tên" sets this to `.profile`;
    // ReserveView's "Đổi trong Tài khoản" sets it to `.reserve`), read by
    // `saveDisplayName()`, `EditNameView`'s Back link, and `goBack()`/
    // `backTargetScreen` below. Mirrors `createOriginScreen`'s own pattern.
    @Published var editNameReturnScreen: Screen = .profile

    // MARK: Attendance / check-in
    @Published var attendanceEventKey: String?
    @Published var attendanceGuests: [AttendanceGuest] = []
    @Published var attendanceLoading = false
    // TASK D — only the newest loadAttendanceGuests() call may write
    // attendanceGuests/attendanceLoading; see that function's own doc
    // comment (AppState+Data.swift).
    var attendanceGuestsSeq = 0
    @Published var photoViewer: PhotoViewerItem?
    /// Photo-interactions redesign (2026-09-26) — the canonical engagement
    /// map (see `PhotoEngagement`'s own doc comment) + a busy-set guarding a
    /// double-tap/racing toggle on the same photo id. Replaces the old
    /// local-only, URL-keyed `photoLikes` UserDefaults array (which was
    /// structurally disconnected from Pulse's real `photo_likes`/
    /// `photo_shares` tables — see 17-ux-foundation-release.md's
    /// 2026-10-03 fix pass for the original trace) — this is now the ONE
    /// real per-photo like/share source of truth, live migration 083/086.
    @Published var photoEngagement: [String: PhotoEngagement] = [:]
    @Published var photoEngagementBusy: Set<String> = []
    @Published var scanningQr = false
    @Published var reasonPrompt: ReasonPrompt?
    @Published var reasonPromptBusy = false
    @Published var reasonPromptError = ""

    // MARK: Payments & documents (supabase migration 024)
    @Published var paymentBookings: [PayableBooking] = []
    @Published var paymentsLoading = false
    @Published var paymentBookingID: UUID?
    @Published var paymentCopied = ""
    @Published var paymentProofUploading = false
    @Published var paymentProofError = ""
    // 14-organizer-checkin.md: the guest's rate-limited nudge while
    // awaiting the organizer's confirm window.
    @Published var nudgeSending = false
    @Published var nudgeError = ""
    // 15-organizer-checkin.md follow-up: ConfirmedView's "Xem Receipt".
    // `receiptChecked` distinguishes "haven't looked yet" from "looked and
    // there genuinely isn't one" — `receiptDoc == nil` alone can't, since
    // that's also the not-yet-checked state.
    @Published var receiptDoc: PaymentDocument?
    @Published var receiptChecked = false
    @Published var receiptRequestSending = false
    @Published var receiptRequestError = ""
    @Published var receiptRequestSent = false
    @Published var paymentBack: Screen = .profile
    @Published var billingName = ""
    @Published var billingAddress = ""
    @Published var billingPhone = ""
    @Published var billingTaxCode = ""
    @Published var billingSaving = false
    @Published var billingSaved = false
    @Published var billingError = ""
    @Published var payoutBankName = ""
    @Published var payoutAccountName = ""
    @Published var payoutAccountNo = ""
    @Published var payoutMomo = ""
    @Published var payoutNote = ""
    @Published var payoutAddress = ""
    @Published var payoutTaxCode = ""
    @Published var payoutSaving = false
    @Published var payoutSaved = false
    @Published var payoutError = ""
    @Published var documents: [PaymentDocument] = []
    @Published var documentsLoading = false
    /// Which of the two Account rows opened the list, and from which side.
    @Published var documentsKind = "invoice"
    @Published var documentsRole = "guest"
    @Published var documentID: UUID?
    // Bug 2 (15-organizer-checkin.md follow-up): which screen opened the
    // viewer — .documents (the Receipts/Invoices list, the old fixed
    // behavior) or .confirmed (the ticket screen's own "Xem Receipt").
    // goBack()/backTargetScreen read this instead of a single hardcoded
    // target.
    @Published var documentBack: Screen = .documents
    // Sub-section-of-a-group back-navigation fix (2026-09-29) — `.documents`
    // (the Invoices/Receipts LIST, opened from AccountGroupView's
    // "payments" group page) used to hardcode its own back button AND
    // `goBack()`/`backTargetScreen` straight to `.profile` (Account's own
    // root), skipping the "Thanh toán & giấy tờ"/"Payments & documents"
    // group page it was actually opened from — both the explicit back
    // button and the edge-swipe-back gesture landed one level too far up.
    // Same `documentBack`-style back-target convention, just for the LIST
    // screen instead of the single-document viewer. Defaults to
    // `.accountGroup` since that's this screen's only real entry point
    // today (see `openDocuments`'s own doc comment).
    @Published var documentsListBack: Screen = .accountGroup
    // Same documentBack/paymentBack pattern, extended (07-notifications.md's
    // 2026-09-18 follow-up) so every screen openNotification() can route to
    // remembers "opened from Notifications" and returns there specifically
    // — not Home, not wherever else. Each defaults to this screen's own
    // previous fixed behavior (unchanged for every non-notification entry
    // point) unless a caller opts in with a different `back` value.
    @Published var attendanceBack: Screen = .dashboard
    @Published var verificationsBack: Screen = .profile
    @Published var confirmedBack: Screen = .home
    // Signed URL for the current document's uploaded file (migration 056)
    // — nil while loading/absent (a legacy document has no file_path and
    // falls back to the old rendered-HTML viewer instead).
    @Published var documentFileURL: URL?
    /// 15-organizer-checkin.md follow-up (Bug 1): distinguishes "still
    /// fetching the signed URL" (nil, ProgressView) from "fetch actually
    /// failed or timed out" (true, DocumentViewerView shows a real error +
    /// retry instead of spinning forever).
    @Published var documentFileURLFailed = false
    /// 08-payment-documents.md 2026-09-17 follow-up: `documentFileURLFailed`
    /// alone gives no signal on WHY — a signing/auth error, an expired
    /// session, or a non-2xx response from the file itself all collapse
    /// into the same generic retry banner, which is why two straight
    /// investigation passes couldn't narrow a real-device repro any
    /// further from this end. Surfaced (in small print, next to the retry
    /// button) so the next real-device failure is self-diagnosing instead
    /// of needing another data-layer investigation pass.
    @Published var documentFileURLErrorDetail = ""
    @Published var documentUploading = false
    @Published var documentUploadError = ""
    // Task 4 (migration 056): one-time, account-level opt-in — mirrors
    // profiles.auto_email_documents, loaded alongside locale/theme.
    @Published var autoEmailDocuments = false
    // BUG 4 (07-notifications.md's 2026-09-18 follow-up): the "•••" menu's
    // "Tắt loại thông báo này" action — filtered client-side only (see
    // loadNotifications()/the toast poll), no insert-side change to any of
    // the ~15 RPCs that write a notifications row.
    @Published var mutedNotificationKinds: [String] = []
    // Two-phase payment machine (migrations 026/027).
    @Published var paymentTxnId = ""
    @Published var verifications: [PendingVerification] = []
    @Published var verificationsLoading = false
    @Published var verificationBusy: UUID?
    // 14-organizer-checkin.md: set by openVerificationDetail() (Attendance's
    // "Check payment" button) — narrows the queue to exactly one booking.
    @Published var verificationsFocusBookingID: UUID?
    // 'pay-proof' storage path -> signed viewable URL, for whichever rows
    // loadVerifications last loaded — see signProofUrls.
    @Published var proofUrls: [String: URL] = [:]
    // Flow 2 (host refund -> guest confirmation): organizer's own refund
    // queue (owed/disputed only), and one guest-side claim for whichever
    // booking PaymentDetailsView is currently showing.
    @Published var refundQueue: [RefundClaim] = []
    @Published var refundQueueLoading = false
    /// Distinct from refundQueueLoading (in flight) — a transport error or
    /// RPC success:false, surfaced in VerificationsView instead of
    /// silently rendering as an empty queue.
    @Published var refundQueueError = ""
    /// Dev-diagnostics only — the exact reason loadRefundQueue() took the
    /// branch it took: "ok" | "awaiting-organizer-discovery" |
    /// "organizer-discovery-failed" | "no-organizers" | "rpc-error" |
    /// "success-false" | "skipped-stale".
    @Published var refundQueueGateReason = ""
    /// Refund-discoverability fix — a dedicated "Refunds" row sets this to
    /// "refundSection" so VerificationsView (via ScreenScaffold's existing
    /// `scrollPositionID` mechanism, same one HomeView already uses to
    /// restore scroll position) scrolls straight to the refund section
    /// instead of landing at the top of the payment-verification list.
    @Published var verificationsScrollAnchorID: String?
    // TASK A (2026-09-30 pass) — only the newest loadRefundQueue() call may
    // write refundQueue; see that function's own doc comment
    // (AppState+Payments.swift). Same pattern as attendanceGuestsSeq above.
    var refundQueueSeq = 0
    @Published var refundActionBusy: UUID?
    @Published var paymentRefundClaim: RefundClaim?
    // Set by openNotification()'s refund_confirmed/_disputed/_overdue cases
    // — highlights the one claim tapped from a notification, same idea as
    // verificationsFocusBookingID above but a separate field (the refund
    // queue isn't filtered by it, only scrolled/flashed to).
    @Published var refundQueueFocusClaimID: UUID?
    // iPhone fix pass (2026-09-27), Issue 1 — same "scroll/flash to the one
    // tapped from a notification" idea, for Account's own pending Team
    // invite / event-credit invite lists (teamInvitesAndMemberships,
    // AccountView.swift). `openNotification()`'s organizer_invite/
    // event_credit_invite cases set these; AccountView clears each one
    // once consumed (`.onAppear`/`.onDisappear`) so it never re-triggers on
    // a later, unrelated visit.
    @Published var teamInviteHighlightOrganizerId: String?
    @Published var eventCreditHighlightId: UUID?
    // Refund MVP — goer's own saved refund destinations (many, migration 074).
    @Published var refundDestinations: [RefundDestination] = []
    @Published var refundDestinationBusy = false
    @Published var refundDestinationError = ""
    @Published var refundDestinationsReordering = false
    // Set when RefundAccountsView was opened FROM a specific refund claim's
    // "Thêm tài khoản mới" — on successful save, the goer is returned
    // straight to that claim with the new account auto-selected.
    @Published var refundAccountsReturnToClaimID: UUID?
    @Published var refundAccountsReturnToBookingID: UUID?
    @Published var refundAccountsBackScreen: Screen = .profile
    // Refund MVP — the goer's own persistent "Refunds" list (product rule
    // A), independent of any one booking/notification.
    @Published var myRefunds: [RefundClaim] = []
    @Published var myRefundsLoading = false
    @Published var myRefundsBackScreen: Screen = .profile
    // TASK D (2026-10-01 UX foundation pass) — shareable profile card.
    @Published var editProfileHandle = ""
    @Published var editProfileName = ""
    @Published var editProfileBio = ""
    @Published var editProfileCity = ""
    @Published var editProfileInterests = ""
    // Organizer Team pass (2026-09-27, Stage 3).
    @Published var editProfileIntroLong = ""
    @Published var editProfileLinks: [SocialLink] = []
    @Published var editProfileLinksOpen = false
    @Published var editProfileTheme = "default"
    @Published var editProfileError = ""
    @Published var editProfileBusy = false
    // Personal-vs-organizer hierarchy pass (2026-09-27) — PERSONAL-ONLY
    // (own display_name, own QR/edit — never an organizer edit/guest-
    // preview affordance; see PublicProfileView's own comment).
    @Published var publicProfile: PublicProfile?
    @Published var publicProfileLoading = false
    @Published var publicProfileError = ""
    @Published var publicProfileBackScreen: Screen = .profile
    @Published var publicProfileHandle = ""
    // The organizer's own, separate public profile — a standalone screen,
    // reachable by organizer id (never the owner's personal handle) so a
    // shared /org/<id> link works without knowing who owns it.
    @Published var organizerProfile: OrganizerProfile?
    @Published var organizerProfileLoading = false
    @Published var organizerProfileError = ""
    @Published var organizerProfileBackScreen: Screen = .profile
    @Published var organizerProfileID = ""
    @Published var organizerProfileUpcoming: [OrganizerUpcomingEvent] = []
    @Published var organizerProfilePhotos: [OrganizerPhoto] = []
    @Published var organizerProfileExtrasLoadedFor = ""
    // Interest surveys (Slice B, migration 114) — mirrors web's
    // GocContext.jsx state field-for-field. `surveyPublic` is exactly
    // get_survey_public()'s return shape (never raw table rows).
    @Published var surveyPublic: SurveyPublic?
    @Published var surveyPublicLoading = false
    @Published var surveyPublicError = ""
    @Published var surveyPublicBackScreen: Screen = .home
    @Published var surveyPublicID = ""
    @Published var mySurveyResponse: SurveyResponseRow?
    @Published var mySurveyResponseLoading = false
    @Published var surveyDraft = SurveyDraft()
    @Published var surveyResponseSubmitting = false
    @Published var surveyResponseError = ""
    @Published var surveyResponseSuccess = false
    @Published var mySurveys: [SurveySummary] = []
    @Published var mySurveysLoading = false
    @Published var mySurveyCreateBusy = false
    @Published var mySurveyCreateError = ""
    // Already-answered respondents land on a read-only summary first; this
    // flips open the editable form (reset to false on every fresh load).
    @Published var surveyEditMode = false
    // Section 5 — public (non-follower) survey-story discovery ("Help Shape
    // Upcoming Events"), built in loadHomeStories() alongside homeStories.
    @Published var homeSurveyDiscovery: [SurveyDiscoveryCard] = []
    // Section 2 — a story's "Answer Survey" CTA opens SurveyPublicView
    // inside a `.fullScreenCover` instead of navigating `screen` away, so
    // whatever's underneath (the story, paused via StoryViewerView's
    // existing `isSuspended`) stays exactly where it was. Non-nil = modal
    // is presented, for THIS public_id.
    @Published var storySurveyModalPublicID: String?
    // Section 3 — lightweight, no-password/no-profile respondent email
    // verification. Reuses the existing OTP-by-email mechanism
    // (AuthAPIService, mode: "respond") — see AppState+Surveys.swift.
    @Published var surveyRespondStep = "idle"
    @Published var surveyRespondEmail = ""
    @Published var surveyRespondCode = ""
    @Published var surveyRespondSending = false
    @Published var surveyRespondError = ""
    @Published var surveyRespondIsNewAccount = false
    @Published var surveyRespondConsent = false
    // Task 4 — "Share To Story": an explicit preview-then-Publish step.
    @Published var surveyShareToStoryTarget: SurveySummary?
    @Published var surveyShareToStoryBusy = false
    @Published var surveyShareToStoryError = ""
    // Account extension (2026-09-27, Stage 3) — one role-scoped KPI
    // dashboard (get_account_kpis, migration 097), reused for on-screen
    // cards, CSV/PDF/JSON export and PNG chart snapshots alike — see
    // AppState+Reports.swift for the actual fetch/export logic.
    @Published var reportsScope = "personal"
    @Published var reportsOrganizerId = ""
    @Published var reportsBackScreen: Screen = .profile
    @Published var reportsRangeDays: ReportsRangeDays = .days30
    @Published var reportsCustomStart: Date = Date()
    @Published var reportsCustomEnd: Date = Date()
    @Published var reportsData: AccountKpiReport?
    @Published var reportsLoading = false
    @Published var reportsError = ""
    @Published var reportsExpanded: Set<String> = []
    @Published var reportsExportBusy = ""
    // A `ShareLink` binds to this the instant an export (CSV/JSON/PDF)
    // finishes writing its temp file — the native iOS share sheet.
    @Published var reportsExportedFileURL: URL?
    // Organizer Team pass (2026-09-27, Stage 1) — see AppState+Team.swift.
    @Published var myOrganizerInvites: [OrganizerMembership] = []
    @Published var myTeamMemberships: [OrganizerMembership] = []
    @Published var orgTeamRoster: [OrganizerTeamRosterRow] = []
    @Published var orgTeamRosterLoading = false
    @Published var orgTeamInviteHandle = ""
    @Published var orgTeamInviteRole = ""
    @Published var orgTeamInviteError = ""
    @Published var orgTeamInviteBusy = false
    // Organizer Team pass (2026-09-27, Stage 2) — see AppState+Team.swift.
    @Published var organizerTeam: OrganizerTeam?
    @Published var organizerTeamLoading = false
    @Published var organizerTeamError = ""
    @Published var organizerTeamBackScreen: Screen = .organizerProfile
    @Published var organizerTeamOrganizerId = ""
    @Published var myEventCredits: [EventCreditInvite] = []
    // iPhone fix pass (2026-09-27), Issue 5 — the confirmed half of the
    // same real-credit model; `myEventCredits` above only ever loaded
    // `status = 'invited'`, so Account had no load path at all for a
    // credit this account already ACCEPTED (the public-profile side,
    // get_public_profile's own `credited_events`, already existed and is
    // already privacy-correct — see loadMyConfirmedEventCredits()'s own
    // comment). Never a second model: same `event_credits` table, same
    // RLS, just the other status value.
    @Published var myConfirmedEventCredits: [EventCreditInvite] = []
    // TASK E (2026-10-01 UX foundation pass) — Banbe Pulse.
    @Published var pulseDaily: [PulseItem] = []
    @Published var pulseWeekly: [PulseItem] = []
    @Published var pulseOpen = false
    @Published var pulseTab: PulseTab = .daily
    @Published var pulseOrganizerSheet: PulseItem?
    // 2026-10-03 fix pass — per-tab loading state (rule A5: a still-
    // fetching tab must never read as "genuinely empty"), and per-period
    // sequence guards so reopening Pulse quickly can't let an older
    // response land after a newer one. See AppState+Pulse.swift.
    @Published var pulseDailyLoading = false
    @Published var pulseWeeklyLoading = false
    var pulseDailySeq = 0
    var pulseWeeklySeq = 0
    // 2026-09-25 fix pass — third Pulse tab: individual event photos ranked
    // by real engagement (photo_likes/photo_shares, migration 083), a
    // separate ranking from pulseDaily/pulseWeekly above, never merged into
    // the same signals/list. See AppState+Pulse.swift.
    @Published var pulsePhotos: [PulsePhotoItem] = []
    @Published var pulsePhotosLoading = false
    @Published var pulsePhotoSheet: PulsePhotoItem?
    // 2026-09-26 photo-interactions redesign — the old Pulse-local
    // `pulsePhotoLiked`/`pulsePhotoBusy` maps are gone; every like/busy
    // read for a ranked photo now goes through the canonical
    // `photoEngagement`/`photoEngagementBusy` above (see PhotoEngagement's
    // own doc comment) — one shared source of truth instead of two.
    var pulsePhotosSeq = 0
    // Refund MVP — host's per-event Refund Center (AttendanceView's own new
    // "Hoàn tiền" section): owed/disputed (+ resolved, for the progress
    // summary) claims for ONE event. Recipient info comes from each claim's
    // OWN recipientSnapshot/selectedDestinationID (migration 074), never a
    // live destinations join — see loadRefundCenter()'s own doc comment for
    // why (root cause of the "0đ / disappearing / reappearing" bug).
    @Published var refundCenterClaims: [RefundCenterClaim] = []
    @Published var refundCenterLoading = false
    // Same reasoning as refundQueueSeq above — only the newest
    // loadRefundCenter() call may write refundCenterClaims.
    var refundCenterSeq = 0
    @Published var refundCenterSelected: Set<UUID> = []
    @Published var refundBatchBusy = false
    @Published var refundBatchInFlight = false
    @Published var refundBatchError = ""
    @Published var refundBatchResult: RefundBatchResult?
    @Published var refundResendBusy: UUID?
    @Published var refundResendInFlight: Set<UUID> = []
    // The temporary dispute chat — one per escalated booking.
    @Published var disputeChatBookingId: UUID?
    @Published var disputeChatMessages: [DisputeMessage] = []
    @Published var disputeChatLoading = false
    @Published var disputeChatDraft = ""
    @Published var disputeChatError = ""
    // resolved_at/purge_after off the dispute_threads row — read-only,
    // drives the retention countdown label (DisputeChatPanel.swift)
    // instead of a delete button, since dispute_messages must survive
    // until the 72h purge (05-notify-retention.md). nil for an open thread.
    @Published var disputeChatThread: (resolvedAt: Date?, purgeAfter: Date?)?
    @Published var openDisputes: [DisputeRow] = []
    // The admin dashboard (AdminDashboardView) — every dispute this account
    // can see; RLS makes that "every dispute, period" only when
    // accountType == "admin", same v_disputes query as openDisputes above.
    @Published var adminDisputes: [DisputeRow] = []
    @Published var adminDisputesLoading = false
    @Published var disputeBusy: UUID?
    @Published var disputeEmailError = ""
    @Published var auditTrail: [PaymentAuditEntry] = []
    @Published var auditBookingId: UUID?
    /// How many buyers are currently holding a seat on this account's own
    /// events, and how soon the nearest one lapses — the organizer half of
    /// the Home countdown banners (verifications above is the other half:
    /// PHASE 2, not PHASE 1). nil until loadOrganizerHoldingSummary() runs.
    @Published var organizerHoldingSummary: OrganizerHoldingSummary?

    // MARK: Create event
    @Published var orgRegName = ""
    @Published var orgRegIg = ""
    @Published var orgRegDesc = ""
    // Organizer Team pass (2026-09-27, Stage 3).
    @Published var orgRegIntroLong = ""
    @Published var orgRegLinks: [SocialLink] = []
    @Published var orgRegLinksOpen = false
    @Published var createName = ""
    @Published var createDesc = ""
    // "Giới thiệu sự kiện" (migration 088) — a separate, longer editorial
    // write-up, never conflated with createDesc ("Mô tả") or the "Bao gồm"
    // items EventDetailView already shows via includedItems.
    @Published var createIntro = ""
    // "Bao gồm" item-editing parity fix (2026-09-29) — mirrors web's
    // identical `createIncludedItems` (GocContext.jsx): up to 3 { label,
    // detail } items, sent as `p_included_items` to the same
    // create_event_draft/resubmit_event_for_review RPCs. iOS previously
    // had no editing UI for this at all, so it never had anywhere to keep
    // the state either — every real event created on iOS silently
    // submitted an empty included list even when the host clearly
    // intended one (this was a real, reported gap, not a placeholder).
    @Published var createIncludedItems: [IncludedItem] = []
    // Keyword-search fix (migration 108) — mirrors web's identical
    // `createKeywords` (GocContext.jsx): free-text, comma-separated. Left
    // blank, `submitCreateEvent` defaults it to the event's own selected
    // category label(s), so an event is never left with nothing to match
    // on beyond its literal name/district in Map's search box.
    @Published var createKeywords = ""
    // Address-autocomplete fix pass (2026-09-28) — `createLoc` is now
    // purely the live search box's own text (mirrors web's identical
    // GocContext.jsx change, same pass). A SELECTED suggestion's
    // decomposed fields live separately below, so the concise location
    // line can show just the district while the full structured address
    // is still available for validation/re-editing. `createLocConfirmed`
    // is the same trust gate migration 094 introduced for lat/lng (never
    // silently trusting free text), now doubling as migration 105's own
    // `p_address_verified` — see `submitCreateEvent`'s own comment. There
    // is no more "skip" — publishing now REQUIRES a verified address
    // (this ticket's own explicit requirement); an unresolved location
    // simply blocks submit with a clear inline message instead.
    @Published var createLoc = ""
    @Published var createLat: Double?
    @Published var createLng: Double?
    @Published var createLocLabel = ""
    @Published var createAddressLine = ""
    @Published var createDistrict = ""
    @Published var createCity = ""
    @Published var createPostalCode = ""
    // Location hierarchy (migration 112) — from the picked
    // `AddressSuggestion`; nil = not (re)picked this session, see
    // `selectCreateAddressSuggestion`/`goEditEvent`.
    @Published var createCountryCode: String?
    @Published var createStateProvince: String?
    @Published var createNeighborhood: String?
    @Published var createLocConfirmed = false
    @Published var createAddressSuggestions: [AddressSuggestion] = []
    @Published var createAddressSearching = false
    @Published var createAddressSearchError = ""
    /// Stale-response guard for `searchCreateAddress` (AppState+Data.swift)
    /// — not `@Published`, purely internal bookkeeping the UI never reads.
    var createAddressSeq = 0
    // Date/time picker fix (Stage B, 2026-09-26) — REPLACES the old
    // free-text `createDate` ("11.07 19:00", hand-parsed with a regex and a
    // hardcoded year) with two real Date values, always interpreted in
    // Asia/Ho_Chi_Minh (EventDateTimeSheet's own timezone), matching what
    // the RPC itself does server-side.
    @Published var createEventDate: Date?
    @Published var createEventTime: Date?
    @Published var createPrice = ""
    @Published var createSeats = ""
    // Strict invite-only events (migration 113) — "public" | "invite",
    // same field/values as web's `s.createVisibility` (GocContext.jsx).
    // Deliberately separate from `events.approval` (not exposed in this
    // form): visibility is who can even see/book the event; approval is
    // whether a booking still needs the host's manual OK.
    @Published var createVisibility = "public"
    @Published var createCats: [String] = []
    @Published var createSent = false
    @Published var createError = ""
    // Media-parity pass (Stage A, 2026-09-26) — a photo upload/removal
    // failure never blocks the already-submitted event row (see
    // reconcileEventMedia's own comment), so this is a separate, non-fatal
    // notice next to createError rather than another failure mode of it.
    @Published var createMediaError = ""
    // Event review queue — set while editing/resubmitting a previously-
    // REJECTED event rather than creating a new one; submitCreateEvent()
    // branches on this. Cleared whenever "create a new event" is entered
    // fresh (goCreate's own reset, mirroring web's GocContext.jsx).
    @Published var createEditEventId: String?
    @Published var orgVerifyRequested = false

    // MARK: Map explore (11-realtime-map.md)
    /// Real `events` rows for whatever the map's current query is (initial
    /// density-hotspot area, or the last "search here" bbox) — separate
    /// from `CatalogEvent.all` (the bundled cosmetic catalogue), joined
    /// back to it per-row in MapExploreView since seats/status here are
    /// live and the catalogue's are not.
    @Published var mapEvents: [MapEventRow] = []
    @Published var mapEventsLoading = true
    // Real-cover-photo fix (2026-10-19) — resolved cover-photo URL per
    // event id, keyed by `MapEventRow.id`, populated by `loadMapEvents()`.
    // MapExploreView reads this instead of `EventCatalog.find(ev.id)?.img`,
    // which always falls back to the FIRST demo catalogue event's photo
    // for any real (non-demo) event id — see loadMapEvents' own comment.
    @Published var mapEventCoverURLs: [String: URL] = [:]
    /// Mirrors `locationService.authorizationStatus` as a `@Published` so
    /// the compass button's opacity (full vs. the app's 0.16 disabled
    /// token) updates the instant permission changes, granted or revoked.
    @Published var locationAuthStatus: CLAuthorizationStatus = .notDetermined
    /// Snapshot of MapExploreView's own local state, saved right before its
    /// preview card's CTA navigates to Event Detail — `MapExploreView` is a
    /// plain SwiftUI View struct RootView re-instantiates from scratch every
    /// time `screen` becomes `.mapExplore` again, so its own `@State` can't
    /// survive that round trip on its own. `AppState` itself is never torn
    /// down across screen switches, so this is where it has to live.
    /// Explicitly cleared (not just left stale) on an intentional exit via
    /// the "← Đóng" button, so reopening the map from Home later starts
    /// fresh rather than silently resuming an unrelated past session.
    @Published var mapExploreState: MapExploreState?

    /// Home task 3 (2026-09-21 follow-up) — the feed event id nearest the
    /// top of Home's scroll view; survives HomeView being torn down and
    /// recreated on navigating to Event Detail and back (the same reason
    /// `mapExploreState` isn't a plain `@State` either), via
    /// `ScreenScaffold`'s `.scrollPosition(id:)` binding. `nil` means "no
    /// scroll to restore" — top of the feed.
    @Published var homeScrollAnchorID: String?
    /// TASK C — same mechanism, for AccountView (see its own doc comment):
    /// the id of whichever section was at the top of Account's own scroll
    /// view; survives AccountView being torn down/recreated on navigating
    /// to a child screen (Refund accounts, My refunds, Preferences, …) and
    /// back. `nil` means "no scroll to restore" — top of Account, which is
    /// also always true the FIRST time Account is ever opened (nothing
    /// but the user's own scrolling ever sets this).
    @Published var accountScrollAnchorID: String?

    /// Task 1 (11-realtime-map.md follow-up): mirrors `RootView`'s own
    /// edge-swipe-back gesture progress (0 at rest, 1 at full commit) so
    /// `MapExploreView`'s sheet can track the Map-Explore-closing-to-Home
    /// drag live, without a second/independent gesture recognizer anywhere
    /// else. `RootView`'s own `@State` (`dragTranslation`/`isCommittingBack`)
    /// remains the sole source of truth for the gesture itself — this is
    /// only where its already-computed progress is exposed to a screen that
    /// can't see RootView's private state. Written by RootView's gesture
    /// handlers AND by `MapExploreView.closeMap()` (the explicit "← Đóng"
    /// button uses the exact same signal for the same visual, rather than
    /// inventing its own).
    @Published var mapCloseSwipeProgress: CGFloat = 0

    // Accidental-tap-during-swipe fix (2026-09-29, third follow-up) —
    // `SwipeSafeButton` (Components.swift) needs to know whether an actual
    // screen-level swipe (tab-swipe or edge-swipe-back) is/was in
    // progress, but can't reliably measure that itself: `DragGesture`
    // measured in `.local` space is fooled because the CONTENT is being
    // offset live, 1:1 with the finger, during the very swipe it's trying
    // to detect (relative to the row's own moving frame, the touch barely
    // displaces); `.global` space fixed that but broke ScrollView, because
    // any raw `DragGesture` attached at the row competes with the
    // ScrollView's own pan gesture; `onLongPressGesture`'s built-in
    // `maximumDistance` avoids the ScrollView conflict but has no
    // coordinate-space parameter at all, so it's ALSO fooled by the same
    // "content chasing the finger" effect `.local` was. RootView's OWN
    // swipe-tracking gestures don't have this problem — they're attached
    // to an ANCESTOR that ISN'T itself being offset, so they measure real
    // screen-space movement correctly by construction. This is that
    // already-correct signal, mirrored out (same idiom as
    // `mapCloseSwipeProgress` above) so a row anywhere can defer to it
    // instead of re-deriving its own possibly-fooled measurement.
    @Published var isRootSwipeActive: Bool = false

    // Gesture-arbitration fix pass (2026-09-28) — `horizontalSwipeRowFrames`
    // used to live here: three successive attempts to let RootView's
    // `tabSwipeGesture` detect "this touch started on a live Inbox row" via
    // published row geometry, each fixing a real bug in that detection
    // (a coarse Y-band, then a coordinate-space mismatch, then a preference-
    // propagation dead end via `.listRowBackground`) without ever actually
    // stopping the on-device conflict. Removed for good along with
    // `.swipeActions` itself — Inbox's Star/Archive now live behind a tap-
    // only "…" menu (`InboxRow`'s own doc comment, MessagingViews.swift),
    // which cannot race `tabSwipeGesture` at all, so there is nothing left
    // here for this property to guard.

    /// Follow-up (11-realtime-map.md, bug 1): a distinct, one-shot signal
    /// from a CONFIRMED close (swipe past the threshold, or the "← Đóng"
    /// button) — separate from the continuous `mapCloseSwipeProgress`
    /// above, which can't reliably distinguish "genuinely confirmed" from
    /// "just live-dragged all the way to the edge without releasing yet".
    /// `MapExploreView` observes this to trigger a REAL native sheet
    /// dismiss (`sheetPresented = false`) instead of relying only on its
    /// own `.scaleEffect`/`.offset` fake-collapse, which was letting
    /// `.presentationDetents` treat the shrinking content as a resize
    /// request and re-snap through each of its three fixed detents on the
    /// way down instead of animating straight to fully closed.
    @Published var mapCloseConfirmed: Bool = false

    /// Follow-up (11-realtime-map.md, task 2): a one-shot signal from an
    /// INTERRUPTED left-edge swipe (released before crossing the dismiss
    /// threshold) — `MapExploreView` observes this to hide and then
    /// re-reveal its sheet, reusing the exact same delayed-reveal
    /// mechanism as returning from Event Detail (`scheduleSheetReveal(after:)`),
    /// rather than the old "spring the content transform back" behavior.
    /// Consumed (reset to `false`) by `MapExploreView` itself the instant
    /// it reacts, so it stays a genuine one-shot pulse.
    @Published var mapCloseSwipeCancelled: Bool = false

    /// Follow-up (11-realtime-map.md, task 1): the ONE shared "confirmed
    /// close" path — both the "← Đóng" button (`MapExploreView.closeMap()`)
    /// and a completed left-edge swipe (`RootView`'s `edgeSwipe` commit
    /// branch) call this SAME function, not two parallel implementations
    /// that happen to agree. Animates the fast, direct sheet-shrink
    /// (`mapCloseSwipeProgress`) and sets `mapCloseConfirmed` (which
    /// `MapExploreView` observes to flip its own `sheetPresented` false —
    /// see that flag's own doc comment for why a real dismiss is needed
    /// instead of just the content transform), clears the snapshot, and
    /// performs the actual navigation after the animation's own duration.
    func confirmMapExploreClose() {
        guard screen == .mapExplore else { return }
        withAnimation(.easeOut(duration: 0.22)) { mapCloseSwipeProgress = 1 }
        mapCloseConfirmed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            self.mapExploreState = nil
            self.mapCloseSwipeProgress = 0
            self.mapCloseConfirmed = false
            self.goBack()
        }
    }

    private let locationService = LocationService()
    private var tickTimer: Timer?
    private var chatPollTimer: Timer?

    init() {
        locationService.onUpdate = { [weak self] coords in
            self?.userCoords = coords
        }
        locationAuthStatus = locationService.authorizationStatus
        locationService.onAuthorizationChange = { [weak self] status in
            self?.locationAuthStatus = status
        }
        // The splash always shows now (Task 2) — `screen` always starts
        // .splash regardless of whether this device has been through
        // onboarding before. `hasOnboarded` (read fresh, not cached, since
        // finishOnboarding() can flip it mid-session) is just what
        // dismissSplash() reads to decide whether to route into .langPick
        // or straight to .home/.login.
        screen = .splash
        if UserDefaults.standard.object(forKey: "banbe.located") != nil {
            let allowed = UserDefaults.standard.bool(forKey: "banbe.located")
            located = allowed
            if allowed { locationService.request() }
        }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.now = Date()
                self?.forfeitLapsedHoldIfNeeded()
            }
        }
    }

    /// A watchdog for every screen that ISN'T one of the three watching its
    /// own local countdown (ConfirmedView, PaymentDetailsView, HomeView).
    /// EventDetailView and EventListView, in particular, only ever read
    /// booking.status/attending — they never notice a lapse themselves — so
    /// staying on one of those past the deadline used to leave "Going" and
    /// the ticket code showing forever, since nothing else was on screen to
    /// call forfeitExpiredHold. This runs unconditionally off the same
    /// once-a-second timer that already drives `now`, regardless of which
    /// screen is on top, and is naturally idempotent with the per-screen
    /// checks (all of them route through the same forfeitExpiredHold, which
    /// itself only acts once per lapse since paymentState flips to .expired
    /// immediately).
    private func forfeitLapsedHoldIfNeeded() {
        // `booking` covers whichever event is currently open in
        // EventDetailView/ConfirmedView even before paymentBookings has
        // loaded at all (e.g. a cold launch landing straight on
        // EventDetailView, before HomeView's .task ever runs) — it's
        // populated as soon as the event resolves, independent of
        // loadPaymentBookings(). paymentBookings covers every OTHER hold
        // this account has open elsewhere, which `booking` alone can't see.
        if let current = booking, current.paymentState == .holding, let deadline = current.holdExpiresAt,
           Countdown.secondsUntil(deadline, now: now) == 0 {
            forfeitExpiredHold(current)
            return
        }
        guard let justLapsed = paymentBookings.first(where: {
            $0.paymentState == .holding && $0.holdExpiresAt != nil
                && Countdown.secondsUntil($0.holdExpiresAt, now: now) == 0
        }) else { return }
        forfeitExpiredHold(justLapsed)
    }

    deinit {
        tickTimer?.invalidate()
        chatPollTimer?.invalidate()
    }

    // MARK: - Localization

    var isEN: Bool { lang == "en" }

    /// The web app's T(vi, en).
    func T(_ vi: String, _ en: String) -> String { isEN ? en : vi }

    /// Ports trStatus() — the catalogue's status strings are written in
    /// Vietnamese, and English mode rewrites the handful of recurring
    /// phrases rather than duplicating the whole catalogue.
    func trStatus(_ input: String) -> String {
        guard isEN else { return input }
        var s = input
        let patterns: [(String, String)] = [
            ("Còn (\\d+) chỗ", "$1 seats left"),
            ("Còn (\\d+) ngày", "In $1 days"),
            ("Hôm nay", "Today"),
            ("Ngày mai", "Tomorrow"),
            ("(\\d+) giờ trước", "$1h ago"),
            ("(\\d+) ngày trước", "$1d ago"),
            ("Hết chỗ", "Sold out"),
            ("Đã hủy", "Cancelled"),
            ("Đã hoàn tiền", "Refunded"),
            ("Đã diễn ra", "Ended"),
            ("Đang giữ", "On hold"),
            ("Đã thanh toán", "Paid"),
            ("Đã lưu", "Saved"),
            ("Đang tham gia", "Going"),
            ("Trả để xác nhận", "Pay to confirm"),
            ("(\\d+) vé", "$1 tix"),
            ("Miễn phí", "Free"),
            (" km từ bạn", " km away"),
            ("từ bạn", "away"),
            ("Thời trang", "Fashion"),
            ("Phòng tranh", "Gallery"),
            ("Nhạc", "Music"),
        ]
        for (pattern, replacement) in patterns {
            s = s.replacingOccurrences(
                of: pattern, with: replacement, options: [.regularExpression], range: nil
            )
        }
        return s
    }

    /// Ports stripKm(): with no location permission the km segment is
    /// removed entirely rather than showing the catalogue's placeholder as
    /// if it meant something; with permission it's replaced by the real
    /// computed distance.
    ///
    /// BUG 2 fix (2026-09-22 follow-up) — real bug, confirmed by reading:
    /// the `guard let event, let km = ... else { return input }` branch
    /// returned the RAW, UNMODIFIED input — meaning whenever `located` was
    /// true but a real distance wasn't actually available yet (userCoords
    /// still nil while CoreLocation's async fix is in flight, OS-level
    /// denial after the app's own optimistic `located = true`, or an event
    /// with no real coordinates), the catalogue's baked-in placeholder km
    /// number stayed on screen looking exactly like a live value. Fixed:
    /// the stripped-segment string is now the fallback in EVERY case where
    /// a genuine live distance can't be computed, matching the `located ==
    /// false` branch's own "no invented number" contract instead of only
    /// applying it when permission was never granted at all.
    func stripKm(_ input: String, event: CatalogEvent? = nil) -> String {
        let stripped = input.replacingOccurrences(
            of: " ▪︎ \\d+[.,]\\d+ km( từ bạn| away)?",
            with: "", options: [.regularExpression], range: nil
        )
        guard located == true else { return stripped }
        guard let event, let km = haversineKm(from: userCoords, to: event) else { return stripped }
        let formatted = String(format: "%.1f", km).replacingOccurrences(of: ".", with: ",")
        return input.replacingOccurrences(
            of: "\\d+[.,]\\d+(?= km)", with: formatted, options: [.regularExpression], range: nil
        )
    }

    // MARK: - Derived

    // Blocker fix (retention roadmap follow-up) — a real, host-created
    // event (not one of the 20 static demo ones) resolves through the
    // canonical realEventsByID cache instead of EventCatalog.find's own
    // `?? EventCatalog.all[0]` fallback, which used to substitute a WRONG
    // demo event's name/price/photo/description in its place.
    var currentEvent: CatalogEvent {
        if let catalogEvent = EventCatalog.find(eventKey), catalogEvent.key == eventKey {
            return catalogEvent.applyingLiveStatus(liveEventStatus)
        }
        switch realEventsByID[eventKey] {
        case .some(.some(let real)): return real
        case .some(.none): return .unavailable(key: eventKey, T: T)
        case .none: return .unavailable(key: eventKey, loading: true, T: T)
        }
    }
    /// Short, disambiguating label for the current location selection
    /// (Home header, empty state, Map chip) — never a full breadcrumb.
    var currentAreaLabel: String { LocationHierarchy.shortLabel(for: area, roots: locationTree, T: T) }

    /// Location hierarchy — one event's structured location. Real events
    /// carry their own (`fromReal`); a demo-catalogue event uses its live
    /// DB row (`homeEventLocations`) and, until that has loaded, its
    /// bundled district label under VN (the whole bundled catalogue is a
    /// Ho Chi Minh City one, matching its live rows' country_code 'VN').
    func eventLocation(_ e: CatalogEvent) -> EventLocation {
        if let loc = e.location { return loc }
        if let loc = homeEventLocations[e.key] { return loc }
        return EventLocation(countryCode: "VN", stateProvince: nil, city: nil, area: e.locationLabel, neighborhood: nil)
    }

    func matchesArea(_ e: CatalogEvent) -> Bool {
        LocationHierarchy.matches(leafID: LocationHierarchy.leafID(for: eventLocation(e)), selection: area)
    }

    func matchesArea(_ row: MapEventRow) -> Bool {
        LocationHierarchy.matches(leafID: LocationHierarchy.leafID(for: row.location), selection: area)
    }

    /// Every discoverable (non-invite) event the tree is built from — the
    /// Home feed's own universe (real + demo) plus Map's live rows,
    /// deduped by event id so nothing is ever counted twice. Discovery
    /// only: a user's own tickets/bookings never come from here.
    var locationUniverse: [LocatedEvent] {
        var seen = Set<String>()
        var out: [LocatedEvent] = []
        let catalogKeys = Set(EventCatalog.all.map(\.key))
        let catalogFeed = discoveryEvents.filter { !catalogKeys.contains($0.key) } + EventCatalog.all
        for raw in catalogFeed {
            let e = withLive(raw)
            guard !e.inviteOnly, seen.insert(e.key).inserted else { continue }
            out.append(LocatedEvent(id: e.key, location: eventLocation(e), isOpen: e.isOpen))
        }
        for row in mapEvents where seen.insert(row.id).inserted {
            out.append(LocatedEvent(id: row.id, location: row.location, isOpen: row.status == "live"))
        }
        return out
    }

    var locationTree: [LocationNode] { LocationHierarchy.build(from: locationUniverse) }
    var isSignedIn: Bool { userID != nil }
    var canHost: Bool { organizerMode || accountType == "admin" || hasHosted }
    var isAdmin: Bool { accountType == "admin" }

    var displayName: String {
        if let name = user?.displayName, !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        if let email = userEmail { return String(email.split(separator: "@").first ?? "") }
        return T("Khách", "Guest")
    }

    func isSaved(_ key: String) -> Bool { favorites.contains(key) }
    // 2026-09-21 follow-up (Home filters, see 07-notifications.md) —
    // narrowed from `attending.contains(key)` (any booking that merely
    // HOLDS A SEAT: status pending/confirmed/attended, the canonical
    // "Going" set 12-home-filters.md deliberately chose for seat-holding
    // purposes) to genuinely PAID/confirmed only (`paymentState ==
    // .confirmed`, which a free/instant-confirm booking also gets
    // immediately). Requested explicitly this pass so the new
    // "notConfirmed" filter is meaningful against "attending" — otherwise
    // the two would overlap. `isGoing` has exactly two consumers
    // (HomeView.swift, this file's own `feed`) confirmed by repo-wide grep
    // before narrowing — `attending` itself (Account/EventList's own
    // "Going" counts) is UNCHANGED, still seat-holding, out of scope here.
    func isGoing(_ key: String) -> Bool {
        paymentBookings.contains { $0.eventKey == key && $0.paymentState == .confirmed }
    }
    /// The new "notConfirmed" filter's own predicate — has an active
    /// booking for this event that ISN'T confirmed yet (still holding, or
    /// awaiting the organizer's verification). Reuses `paymentBookings`
    /// Home already loads — no new query.
    func isAwaitingConfirmation(_ key: String) -> Bool {
        paymentBookings.contains {
            $0.eventKey == key && ["pending", "confirmed", "attended"].contains($0.status)
                && ($0.paymentState == .holding || $0.paymentState == .pendingVerification)
        }
    }

    /// Merges a real DB row's live status onto a static catalogue event —
    /// the batched counterpart of `curEvent`'s own single-event
    /// `applyingLiveStatus` call, applied to every event Home might list.
    private func withLive(_ e: CatalogEvent) -> CatalogEvent { e.applyingLiveStatus(homeLiveEvents[e.key]) }

    /// TASK 3 (organizer Check-in ended-event filtering) — the organizer's
    /// own events (Dashboard's "upcoming"/"past" lists and the Check-in
    /// entry point they feed), with the same real `withLive` merge `feed`/
    /// `savedStrip` already use. Without this, DashboardView's own
    /// `myEvents` read `CatalogEvent.endedHoursAgo` straight off the static
    /// bundled catalogue — frozen at build time — so a real, DB-backed
    /// event that has actually ended never lost its "Điểm danh"/Check-in
    /// button.
    // Blocker fix (event review queue follow-up) — a real, host-created
    // event only ever belongs here once it's actually 'live'/'ended'
    // (bookable or already happened) — 'review'/'draft' rows show in
    // DashboardView's own separate pending/needsFix sections instead (see
    // myPendingEvents/myNeedsFixEvents below), never mixed into "Upcoming".
    // Part B audit (2026-09-28) — narrowed to events whose real
    // organizer_id (myOrgEventOrganizerID) actually matches the ONE
    // organizer this screen brands (myOrganizerID), not the full
    // multi-organizer union `myOrgEventKeys` covers — see both
    // properties' own doc comments. `myOrganizerID == nil` (never signed
    // in as a real organizer yet) falls through to the untouched
    // name-matched demo fallback below.
    var myOrgEvents: [CatalogEvent] {
        let scopedKeys = myOrgEventKeys.filter { myOrgEventOrganizerID[$0] == myOrganizerID }
        if scopedKeys.isEmpty {
            return EventCatalog.all.filter { $0.orgName == currentEvent.orgName }.map(withLive)
        }
        let catalogOwned = EventCatalog.all.filter { scopedKeys.contains($0.key) }.map(withLive)
        let realOwned = myOrgEventSummaries
            .filter { scopedKeys.contains($0.id) }
            .filter { $0.status == "live" || $0.status == "ended" || $0.status == "cancelled" }
            .map { CatalogEvent.fromReal($0) }
        return catalogOwned + realOwned
    }

    // Withdrawal (migration 107) + resubmission-limit surfacing — iOS
    // port of web's identical GocContext.jsx state (withdrawEventBusy/
    // withdrawEventError/resubmissionStatusByEvent). A banbe PRODUCT
    // POLICY limit (2 successful resubmissions per rolling 24h), never a
    // legal/Ticketbox requirement.
    @Published var withdrawEventBusy = false
    @Published var withdrawEventError = ""
    @Published var resubmissionStatusByEvent: [String: ResubmissionStatus] = [:]

    /// Real submissions still awaiting an admin decision.
    var myPendingEvents: [RealEventSummary] { myOrgEventSummaries.filter { $0.status == "review" } }
    /// Real submissions an admin sent back for correction (rejection_reason set).
    var myNeedsFixEvents: [RealEventSummary] {
        myOrgEventSummaries.filter { $0.status == "draft" && !($0.rejectionReason ?? "").isEmpty }
    }

    /// The home feed — same filter and ordering as src/screens/Home.jsx:
    /// invite-only events never appear, and cancelled ones sink to the end.
    var feed: [CatalogEvent] {
        // Home-visibility fix (2026-09-29) — `discoveryEvents` (real,
        // organizer-created events, see its own doc comment) is placed
        // AHEAD of the static demo catalogue, mirroring web's identical
        // fix (Home.jsx's `realEventsSorted`/`feed`) — real events were
        // previously not merged in at all; now they're not merely appended
        // after ~20 unrelated demo cards either, which would have made a
        // newly-approved event technically present but practically
        // undiscoverable. `discoveryEvents` already arrives sorted
        // chronologically (the query's own `order("starts_at")`). Deduped
        // by key against the static catalogue defensively, even though a
        // real event's generated id can't structurally collide with one.
        let realKeys = Set(EventCatalog.all.map(\.key))
        let combined = discoveryEvents.filter { !realKeys.contains($0.key) } + EventCatalog.all
        // Split into intermediate steps — Swift's type-checker couldn't
        // resolve the original single chained expression (this many
        // `.filter` closures in one statement) in reasonable time.
        let categoryAndArea = combined
            .map(withLive)
            .filter { !$0.inviteOnly }
            .filter { filter == "all" || $0.catKey == filter || $0.cat2Key == filter }
            .filter { matchesArea($0) }
        let attendance = categoryAndArea
            .filter { !filterAttending || isGoing($0.key) }
            .filter { !filterNotConfirmed || isAwaitingConfirmation($0.key) }
        let savedAndStatus = attendance
            .filter { !filterSaved || isSaved($0.key) }
            .filter { !filterSoldOut || $0.soldOut }
            .filter { !filterUpcoming || (!$0.cancelled && $0.endedHoursAgo == nil) }
            .filter { !filterEnded || $0.endedHoursAgo != nil }
        return savedAndStatus.sorted { a, b in demoted(a) < demoted(b) }
    }

    private func demoted(_ e: CatalogEvent) -> Int {
        (e.cancelled && (e.cancelledHoursAgo ?? 99) >= 2) ? 1 : 0
    }

    /// The "Your events" strip: saved + attending + invited + held, minus
    /// anything that ENDED more than 48h ago (never an upcoming/ongoing
    /// event — `endedHoursAgo` is only ever non-nil once `withLive` sees a
    /// real `status == "ended"` row, see `applyingLiveStatus`/
    /// `Countdown.liveEventOverrides`).
    ///
    /// 2026-09-21 follow-up: `withLive` added here — `CatalogEvent.
    /// endedHoursAgo` on its own is the STATIC catalogue's baked-in-at-
    /// build-time number (Tools/generate-catalog.mjs, from src/data/
    /// events.js's own hardcoded STATUS map) and never increases as real
    /// time passes, so this filter previously never actually cleared
    /// anything once true.
    // Blocker fix (retention roadmap follow-up) — a saved/attending/held
    // event that isn't one of the 20 static demo ones (a real, host-created
    // event) used to just vanish here (EventCatalog.all.first returns nil,
    // dropped by compactMap) even though the underlying favorite/booking
    // row was completely real. Falls back through the SAME canonical
    // realEventsByID cache the weekend section and `currentEvent` use — see
    // resolvedEvent(for:). `nil` here (still loading) is skipped quietly,
    // never flashed as "unavailable".
    private func resolvedEvent(for key: String) -> CatalogEvent? {
        if let catalogEvent = EventCatalog.all.first(where: { $0.key == key }) {
            return withLive(catalogEvent)
        }
        switch realEventsByID[key] {
        case .some(.some(let real)): return real
        case .some(.none): return .unavailable(key: key, T: T)
        case .none: return nil // not yet requested/still loading — quiet
        }
    }

    /// Kicks off the canonical real-event fetch for any of `keys` not in the
    /// bundled catalogue and not yet cached — call from a View's `.task`
    /// (see HomeView/EventListView) alongside loadHomeLiveEvents.
    func loadMissingRealEvents(for keys: [String]) async {
        let missing = keys.filter { key in
            EventCatalog.all.first(where: { $0.key == key }) == nil && realEventsByID.index(forKey: key) == nil
        }
        guard !missing.isEmpty else { return }
        await loadRealEventsByID(missing)
    }

    var savedStrip: [CatalogEvent] {
        var keys: [String] = []
        for key in favorites + attending where !keys.contains(key) { keys.append(key) }
        if let heldKey = heldEvent?.key, !keys.contains(heldKey) { keys.append(heldKey) }
        return keys.compactMap(resolvedEvent(for:))
            .filter { ($0.endedHoursAgo ?? 0) <= 48 }
    }

    var heldEvent: CatalogEvent? {
        guard let deadline = holdDeadline, deadline > now else { return nil }
        return resolvedEvent(for: eventKey)
    }

    // MARK: Payment countdown banners (both phases, both roles — Home)

    /// PHASE 1, as a buyer: the soonest seat this account is still holding,
    /// across every booking it has (not just the one most recently reserved
    /// in this session — heldEvent above only ever knows about that one).
    var myHolding: PayableBooking? {
        Countdown.pickSoonest(paymentBookings, phase: .holding) { $0.holdExpiresAt }
    }

    /// PHASE 2, as a buyer: whichever booking has waited longest for the
    /// organizer to confirm it. There is no buyer-facing deadline to sort by
    /// — the clock stopped — so this is ordered by how long ago proof went
    /// in, not by time remaining.
    var myPendingVerification: PayableBooking? {
        paymentBookings
            .filter { $0.paymentState == .pendingVerification }
            .sorted { ($0.proofUploadedAt ?? .distantPast) < ($1.proofUploadedAt ?? .distantPast) }
            .first
    }

    /// PHASE 2, as an organizer: how many of my events' bookings are waiting
    /// on me, and the soonest SLA deadline among them.
    var organizerPendingCount: Int { verifications.count }
    var organizerSoonestVerifyDue: Date? {
        verifications.compactMap(\.verifyDueAt).min()
    }

    /// What EventListView shows for the current `eventListMode` — the
    /// "Going"/"Saved" cards and "Completed events" row on Account each open
    /// this filtered to their own set.
    // 2026-09-25 fix pass (Task 0 audit) — real bug: Account's own "Going"/
    // "Saved"/"Completed" lists used the raw static catalogue — both the
    // Going/Completed split below (`endedHoursAgo`) and every displayed
    // date (`meta`) came from the frozen catalogue, never live status. Same
    // `applyingLiveStatus` merge `feed`/`myOrgEvents` already use.
    private func liveListEvent(_ key: String) -> CatalogEvent? {
        if let catalogEvent = EventCatalog.all.first(where: { $0.key == key }) {
            return catalogEvent.applyingLiveStatus(homeLiveEvents[key])
        }
        // Blocker fix (retention roadmap follow-up) — same real-event
        // fallback resolvedEvent(for:) uses (savedStrip's own comment).
        switch realEventsByID[key] {
        case .some(.some(let real)): return real
        case .some(.none): return .unavailable(key: key, T: T)
        case .none: return nil
        }
    }

    var eventListEvents: [CatalogEvent] {
        switch eventListMode {
        case .going:
            // Once an event ends it belongs in Completed instead of sitting
            // in Going forever.
            return attending.compactMap(liveListEvent)
                .filter { $0.endedHoursAgo == nil }
        case .saved: return favorites.compactMap(liveListEvent)
        case .completed:
            var keys: [String] = []
            for key in favorites + attending where !keys.contains(key) { keys.append(key) }
            // "Completed" means it already happened — anything still
            // upcoming (or just favorited but never actually attended)
            // doesn't belong here.
            return keys.compactMap(liveListEvent)
                .filter { $0.endedHoursAgo != nil }
        }
    }

    /// The heading of whichever list is showing. Shared so the back pill on
    /// an event opened from one can name it too — before this existed that
    /// pill fell through to its "banbe" default and claimed it went Home,
    /// while actually (and correctly) returning to the list.
    var eventListTitle: String {
        switch eventListMode {
        case .going: return T("Đang tham gia", "Going")
        case .saved: return T("Đã lưu", "Saved")
        case .completed: return T("Sự kiện đã hoàn thành", "Completed events")
        }
    }

    /// Backs the count on Account's "Going" card — attending minus anything
    /// that's already over (that belongs in Completed instead).
    var goingEventsCount: Int {
        attending.compactMap(liveListEvent)
            .filter { $0.endedHoursAgo == nil }.count
    }

    /// Backs the count on Account's "Sự kiện đã lưu"/"Completed events" row.
    var completedEventsCount: Int {
        var keys: [String] = []
        for key in favorites + attending where !keys.contains(key) { keys.append(key) }
        return keys.compactMap(liveListEvent)
            .filter { $0.endedHoursAgo != nil }.count
    }

    // MARK: - Onboarding

    private var hasOnboarded: Bool { UserDefaults.standard.bool(forKey: "banbe.onboarded") }

    /// Task 1 — no guest browsing of any screen: lands on the mandatory
    /// Login gate instead of Home when not actually signed in.
    /// authReturnScreen/authBackScreen point at where onboarding was
    /// actually headed, so signing in lands there instead of always Home.
    private func postAuthDestination(isSignedIn: Bool) {
        // TASK A point 4 — "the route must survive app relaunch", same
        // convention as web's own `banbe.lastScreen` (GocContext.jsx):
        // only these two screens persist themselves (openRefundAccounts/
        // openMyRefunds below), restored here on cold start rather than
        // building a general route-restoration system this ticket didn't
        // ask for. Only trusted when actually signed in.
        let restored: Screen? = isSignedIn ? Self.restorableScreen(from: UserDefaults.standard.string(forKey: "banbe.lastScreen")) : nil
        let target: Screen = restored ?? .home
        if isSignedIn {
            screen = target
        } else {
            screen = .login
            authMandatory = true
            authReturnScreen = target
            authBackScreen = target
        }
    }

    func dismissSplash(isSignedIn: Bool) {
        guard screen == .splash else { return }
        // First-ever launch still goes through language/theme regardless
        // of auth — the mandatory-login gate applies once that's done
        // (finishOnboarding), not before.
        if !hasOnboarded { screen = .langPick; return }
        postAuthDestination(isSignedIn: isSignedIn)
    }

    /// The "I agree" button PolicyView shows only while policyGateActive
    /// (applySession()'s post-OAuth-redirect consent gate for a brand-new
    /// Google/Facebook profile — see note 10). Stamps consent for real,
    /// then hands off to the exact same postAuthDestination() every other
    /// sign-in path uses, so this doesn't need its own bespoke "where do I
    /// go now".
    func acceptPolicyGate() {
        guard let uid = userID else { return }
        Task {
            do {
                let update = ConsentUpdate(policyAcceptedAt: ISO8601DateFormatter().string(from: Date()), policyVersion: PolicyView.version)
                try await SupabaseService.client.from("profiles").update(update).eq("id", value: uid).execute()
            } catch {
                print("Failed to record policy consent:", error)
                return
            }
            policyGateActive = false
            postAuthDestination(isSignedIn: true)
        }
    }
    func pickLang(_ value: String) {
        lang = value
        screen = .themePick
        persistPreference(["locale": value])
    }
    func pickTheme(_ value: String) {
        theme = value
        persistPreference(["theme": value])
    }
    func toggleAutoEmailDocuments() {
        autoEmailDocuments.toggle()
        guard let uid = userID else { return }
        let update = AutoEmailDocumentsUpdate(autoEmailDocuments: autoEmailDocuments)
        Task {
            do {
                try await SupabaseService.client.from("profiles").update(update).eq("id", value: uid).execute()
            } catch {
                print("Failed to save auto_email_documents:", error)
            }
        }
    }
    func finishOnboarding(isSignedIn: Bool) {
        UserDefaults.standard.set(true, forKey: "banbe.onboarded")
        postAuthDestination(isSignedIn: isSignedIn)
    }
    func toggleLang() {
        let next = isEN ? "vi" : "en"
        lang = next
        persistPreference(["locale": next])
    }

    /// Once signed in, language & theme are account preferences, not just
    /// this device's — persist every change so they follow the account
    /// anywhere, exactly as persistAccountPreference() does on the web.
    func persistPreference(_ patch: [String: String]) {
        guard let uid = userID else { return }
        let update = ProfilePreferenceUpdate(
            locale: patch["locale"], theme: patch["theme"], prefsSaved: true
        )
        Task {
            do {
                try await SupabaseService.client.from("profiles")
                    .update(update)
                    .eq("id", value: uid)
                    .execute()
            } catch {
                print("Failed to save preferences to account:", error)
            }
        }
    }

    // MARK: - Navigation

    /// `offsetY` is the scrolled content's minY in ScreenScaffold's own
    /// "scaffoldScroll" coordinate space — 0 at the top, increasingly
    /// negative the further down the user has scrolled. Mirrors src/App.jsx
    /// Shell's handleScroll(): pinned back open at (or near) the top or
    /// while scrolling up, shrinks once a real scroll-down is detected.
    ///
    /// BUG 1 follow-up (64f2719 real-device report): the PreferenceKey this
    /// feeds fires on every scroll frame (up to ProMotion's 120Hz), and this
    /// used to mutate `bottomBarCollapsed` unanimated on every single one —
    /// a rapid back-and-forth scroll could flip the flag several times a
    /// frame, each flip snapping the bar's size with no interpolation at
    /// all, which is what actually read as "laggy" rather than smooth.
    /// Two independent fixes: (1) throttled to ~30 updates/sec — plenty to
    /// feel live, far fewer than 120/sec of redundant work; (2) the actual
    /// mutation is now wrapped in `withAnimation(.spring(...))` and skipped
    /// entirely when the value wouldn't change, so it can't restart the
    /// same animation mid-flight against itself.
    private var lastScaffoldScrollUpdate = Date.distantPast

    /// Refresh-indicator fix pass (2026-09-27, follow-up A) — the one
    /// trigger point `ScreenScaffold`'s custom pull gesture and
    /// `MapExploreView`'s own local pull both call once a real release
    /// crosses the pull threshold; guards against a second overlapping
    /// reload the same way `applyOrganizerMode`'s own busy-guard already
    /// does elsewhere in this file.
    // Refresh-indicator fix pass (2026-09-27, follow-up B) — the real state
    // machine (idle -> pulling -> armed -> refreshing -> idle) driving
    // `rootPullProgress`/`rootRefreshing`. Every call site (ScreenScaffold,
    // Inbox's List, Map's list) now goes through these four instead of
    // poking `rootPullProgress` from a raw `UIScrollView.contentOffset` KVO
    // callback — the old approach fired on ANY negative offset (a momentum
    // bounce past the top, a `.scrollPosition(id:)` restore, the very first
    // layout pass), which is exactly why the icon could appear while a tab
    // was idle or right after switching to it. `ScaffoldScrollProbe` now
    // only calls these from its own pan-gesture target, gated on the
    // gesture having genuinely BEGUN while that scroll view's own
    // `contentOffset.y` was already at/above the top — so a pull that
    // started mid-scroll, or any programmatic/momentum offset change, never
    // reaches this at all.
    func beginRootPull() {
        guard !rootRefreshing else { return }
        rootPullProgress = 0
    }
    func updateRootPull(_ translationY: CGFloat) {
        guard !rootRefreshing else { return }
        rootPullProgress = min(1, max(0, translationY) / screenScaffoldPullTriggerDistance)
    }
    func endRootPull(trigger: @escaping () async -> Void) {
        guard !rootRefreshing else { return }
        if rootPullProgress >= 1 {
            runRootRefresh(trigger)
        } else {
            // Pull-to-refresh hold fix (2026-09-29) — an insufficient pull
            // (released before crossing the trigger distance) now springs
            // back instead of snapping instantly; matches the genuine
            // completion spring-back below instead of being the one case
            // left unanimated.
            withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.86)) { rootPullProgress = 0 }
        }
    }
    // Also dismisses a genuinely in-flight refresh's indicator — ticket's
    // own "dismiss on ... tab switch" clause; the underlying reload task
    // itself is left to finish (its own `defer` in `runRootRefresh` is a
    // harmless no-op by then), only the affordance on the screen the user
    // just left is cleared.
    func cancelRootPull() {
        rootPullProgress = 0
        rootRefreshing = false
    }

    // Pull-to-refresh hold fix (2026-09-29) — the actual scrollable
    // content (not just the indicator overlay) reads this to offset
    // itself: follows the pull 1:1 up to the trigger distance while
    // dragging (`rootPullProgress`), then HOLDS at that same distance for
    // the WHOLE `rootRefreshing` duration — previously nothing held the
    // content down at all, so it sprang back to its resting position the
    // instant the finger released, well before the actual reload had
    // finished, which is what read as "the screen still shifts upward [[
    // right after releasing]] and [only then] the loading icon appears."
    // Every screen using `ScaffoldScrollProbe` (ScreenScaffold, InboxView,
    // MapExploreView's own list) applies this to its own scrollable
    // content, one shared definition so they can't drift apart.
    var rootPullContentOffset: CGFloat {
        rootRefreshing ? screenScaffoldPullTriggerDistance : rootPullProgress * screenScaffoldPullTriggerDistance
    }

    func runRootRefresh(_ action: @escaping () async -> Void) {
        guard !rootRefreshing else { return }
        rootRefreshing = true
        Task {
            await action()
            await MainActor.run {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    rootRefreshing = false
                    rootPullProgress = 0
                }
            }
        }
    }

    func noteScaffoldScroll(_ offsetY: CGFloat) {
        let now = Date()
        guard now.timeIntervalSince(lastScaffoldScrollUpdate) > 0.033 else { return }
        lastScaffoldScrollUpdate = now

        // BUG 3 follow-up (623ec1e real-device report): re-verified this
        // sign convention against the spec ("scrolling further down the
        // page shrinks the bar; scrolling back toward the top restores
        // it") rather than assuming it needed flipping. `offsetY` gets MORE
        // NEGATIVE the further down the page you scroll (see doc comment
        // above), so a negative `delta` here already means "scrolled
        // further down" — that's the `shouldCollapse = true` branch below,
        // which was already correct, not inverted. Tightened the trigger
        // from 6pt to 4pt to match the web fix's own threshold change and
        // register a real scroll more reliably.
        let delta = offsetY - lastScaffoldScrollOffset
        lastScaffoldScrollOffset = offsetY

        let shouldCollapse: Bool
        if offsetY >= -4 { shouldCollapse = false }
        else if delta < -4 { shouldCollapse = true }
        else if delta > 4 { shouldCollapse = false }
        else { return }

        guard shouldCollapse != bottomBarCollapsed else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            bottomBarCollapsed = shouldCollapse
        }
    }

    func goHome() { screen = .home }
    func goMapExplore() { screen = .mapExplore }
    func goProfile() { screen = .profile }
    // "organizer" is a pass-through, exactly like "event" itself already
    // is: entering an event from an organizer page keeps whatever back
    // target brought us into this event/organizer cluster in the first
    // place.
    //
    // Pointing back at "organizer" instead is what trapped the two screens
    // in an inescapable loop. Organizer has no back target of its own — its
    // back link just re-opens whichever event is current — so event's back
    // would go to organizer, organizer's back would come straight back to
    // the same event, forever, with no way to reach Home. That's true
    // whichever row of its "Current events" list is tapped, including the
    // event you arrived from (that list contains it too).
    func goEvent(_ key: String) {
        // A fresh, non-story-originated event open discards any RETAINED
        // story viewer (BUG 1, 2026-09-22 tenth follow-up: `storyViewer`
        // now stays live/retained across an event opened FROM a story —
        // see goEventFromStory()'s own comment — so a later, unrelated
        // event open must explicitly close it out, or it would linger and
        // pop back up over whatever screen this new event later returns
        // to) — before `eventBackIsStory` is even checked, so this also
        // covers the (rare) case of opening a second event directly from
        // Event Detail's own "other events" list while the first one was
        // itself story-suspended.
        if eventBackIsStory { closeStoryViewer() }
        if screen != .event && screen != .organizer { eventBackScreen = screen }
        eventKey = key
        screen = .event
        eventBackIsStory = false
        storyReturnHostName = nil
        Task { await loadBookingForCurrentEvent() }
        Task { await loadLiveEventStatus() }
    }
    /// Task 4C / BUG 3 (2026-09-22 follow-up) — tapping an event-share
    /// story's card/CTA. `screen` was never changed while the story
    /// overlay was up (StoryViewerView renders independently of `screen`,
    /// see RootView), so the current `screen` here is already whichever
    /// screen the story was opened from (Home/Profile) — exactly what
    /// `eventBackScreen` already wants, reused verbatim rather than a
    /// second back-target concept. `eventBackIsStory` is the single source
    /// of truth EventDetailView's own back-label override AND
    /// backFromEvent()'s routing below both read, instead of each
    /// independently inferring "did this come from a story" from whether a
    /// snapshot happens to be present (the real bug this ticket reported:
    /// the label said "banbe"/Home while the tap actually reopened the
    /// story).
    ///
    /// BUG 1 fix (2026-09-22 tenth follow-up) — real regression, confirmed
    /// by reading: this used to null out `storyViewer` and stash a
    /// SEPARATE `storyReturnSnapshot` to reconstruct it later. That
    /// supports a COMPLETED back action fine, but not an INTERACTIVE one —
    /// during a slow edge-swipe, `RootView`'s peek renders
    /// `screenView(for: app.backTargetScreen, isPreview: true)`, and
    /// StoryViewer isn't a `Screen` at all (it's a separate overlay, see
    /// RootView's own `if app.storyViewer != nil` block) — so the peek
    /// could only ever show `eventBackScreen` itself (Home), never
    /// StoryViewer, no matter what. Fixed at the state-model level:
    /// `storyViewer` is no longer cleared here — it stays the SAME live,
    /// retained instance the whole time Event Detail is showing (paused,
    /// not visibly on top — see RootView's own `storyUnderlaysEvent`
    /// handling), so an interactive peek has a genuine live view to
    /// reveal, not a throwaway reconstruction. `storyReturnSnapshot` is
    /// gone entirely — nothing to snapshot when the original is retained.
    func goEventFromStory(_ key: String) {
        if screen != .event && screen != .organizer { eventBackScreen = screen }
        eventBackIsStory = true
        if let v = storyViewer, v.groups.indices.contains(v.groupIndex) {
            storyReturnHostName = v.groups[v.groupIndex].orgName
        } else {
            storyReturnHostName = nil
        }
        eventKey = key
        screen = .event
        Task { await loadBookingForCurrentEvent() }
        Task { await loadLiveEventStatus() }
    }
    /// Follow-up bug 2: `goBack()`'s `.event` case (the edge-swipe path) and
    /// EventDetailView's explicit back-button both call this SAME function
    /// — neither maintains its own separate "how do I get back to the map"
    /// logic, per the ticket's "one shared returnToMapExplore() path"
    /// requirement. It only special-cases the destination screen actually
    /// being `.mapExplore`; every other `eventBackScreen` target is an
    /// ordinary screen switch, unchanged from before.
    ///
    /// BUG 1 fix (2026-09-22 tenth follow-up) — `storyViewer` was never
    /// cleared by `goEventFromStory()` above, so there's nothing to
    /// restore here any more; it's already sitting there, exactly where it
    /// was, and simply becomes the top-most visible overlay again the
    /// moment `screen` stops being `.event` (RootView's own
    /// `storyUnderlaysEvent` check).
    func backFromEvent() {
        if eventBackScreen == .mapExplore {
            returnToMapExplore()
        } else {
            screen = eventBackScreen
        }
        eventBackIsStory = false
        storyReturnHostName = nil
    }

    /// The one path both back mechanisms use to return to a retained Map
    /// Explore. Kept as its own named function (rather than inlining `screen
    /// = .mapExplore` into `backFromEvent()`) so it's a single, greppable
    /// seam if a future pass needs to attach more return-specific behavior
    /// here (e.g. a dedicated transition) without touching both call sites.
    /// `mapExploreState` itself is untouched here — MapExploreView's own
    /// `init(restored:)`/`.task` (11-realtime-map.md) read and clear it once
    /// the view is actually back on screen.
    func returnToMapExplore() {
        screen = .mapExplore
    }
    /// "Open in Map" (Event Detail, home-entry only) — the reverse
    /// direction of `MapExploreView.openEventDetail`'s own snapshot
    /// capture (which saves the live map's state right before leaving for
    /// Event Detail): this builds a `MapExploreState` from scratch, using
    /// just the event's own lat/lng, so `MapExploreView.init(restored:)`
    /// mounts the map already centered/zoomed on this pin with its info
    /// card showing — reusing that same restore mechanism rather than a
    /// second, parallel "open on this event" code path. `0.01`° span
    /// matches `selectEvent(_:)`'s own `zoomSpan` for a focused single-pin
    /// view; `sheetFraction: 0.72` matches a fresh (non-restored) open's
    /// default "tall" detent.
    func openEventOnMap(_ event: CatalogEvent) {
        // Real-event-maps-link fix pass (2026-09-28) — `event.lat`/`.lng`
        // are `Double?` now (an event may genuinely have no confirmed pin
        // yet); this action makes no sense at all without real
        // coordinates, so it's a no-op rather than falling back to 0,0.
        // The caller (EventDetailView's own "Xem trên bản đồ" button) also
        // hides itself in that case — see that call site's own comment.
        guard let lat = event.lat, let lng = event.lng else { return }
        mapExploreState = MapExploreState(
            cameraCenterLat: lat, cameraCenterLng: lng,
            cameraSpanLat: 0.01, cameraSpanLng: 0.01,
            // Task 6 (2026-09-21 follow-up): mid (0.45), not tall (0.72) —
            // this arrives with an event already selected/its card
            // showing, same reasoning as `selectEvent`'s own snap-down:
            // don't squeeze the map into a sliver right when the card most
            // needs room to be seen.
            sheetFraction: 0.45, catFilter: "all", openNowOnly: false, sortByDistance: false,
            selectedId: event.key, singleEventFocus: true
        )
        screen = .mapExplore
    }
    // Home quick event search (2026-09-27) — reuses the EXISTING
    // MapExploreView list/filter/event-detail experience (region/status
    // filters, real events already loaded there) rather than a second
    // search index/screen — the only genuinely missing piece was a
    // by-name text filter (see that view's own `searchQuery`). Leaves
    // `mapExploreState` nil (a normal fresh open, its own density-hotspot
    // centering), unlike `openEventOnMap(_:)` above.
    @Published var mapExploreFocusSearch = false
    func openEventSearch() { mapExploreFocusSearch = true; screen = .mapExplore }
    func goOrganizer() { screen = .organizer }
    func backToEvent() { screen = .event }
    func openHeld() { screen = .confirmed }
    /// Tapping a photo in either gallery ("Hình ảnh" on an event, "Ảnh của
    /// X" on an organizer page) opens it larger, over a dimmed backdrop —
    /// with a light tap of haptic feedback, which is the part the web
    /// version can't do (navigator.vibrate isn't implemented on iOS Safari).
    /// Photo-interactions redesign (2026-09-26) — `gallery` is now
    /// `[PhotoGalleryItem]` (real id + url + OWNING event id per photo, see
    /// its own doc comment), no separate `eventKey` param — each gallery
    /// entry carries its own `eventId`.
    func openPhoto(gallery: [PhotoGalleryItem], index: Int, organizer: String, originRect: CGRect) {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
        photoViewer = PhotoViewerItem(gallery: gallery, index: index, organizer: organizer, originRect: originRect)
    }
    func closePhoto() { photoViewer = nil }

    // Task 2 (07-notifications.md) — chat photo viewer open/close, a
    // separate state slice from photoViewer above (see ChatPhotoViewerItem).
    func openChatPhoto(messageId: UUID?, attachmentPath: String, url: URL, width: Int?, height: Int?, senderLabel: String) {
        chatPhotoViewer = ChatPhotoViewerItem(messageId: messageId, attachmentPath: attachmentPath, url: url, width: width, height: height, senderLabel: senderLabel)
    }
    func closeChatPhoto() { chatPhotoViewer = nil }
    func openChatForward() { chatPhotoViewer?.forwardOpen = true }
    func closeChatForward() { chatPhotoViewer?.forwardOpen = false }
    func openPostToStoryConfirm() { chatPhotoViewer?.postToStoryConfirm = true }
    func closePostToStoryConfirm() { chatPhotoViewer?.postToStoryConfirm = false }

    // Task 3 (07-notifications.md) — story viewer open/close/progression.
    /// BUG 5 fix (2026-09-22 follow-up) — filters out any group left with
    /// zero stories up front so storyNext()/storyPrev() never have to
    /// special-case an empty one mid-navigation (ticket's own "skip it
    /// safely" requirement).
    func openStoryViewer(_ organizerId: String, originRect: CGRect? = nil) {
        let groups = homeStories.filter { !$0.stories.isEmpty }
        guard let groupIndex = groups.firstIndex(where: { $0.organizerId == organizerId }) else { return }
        storyViewer = StoryViewerState(groups: groups, groupIndex: groupIndex, storyIndex: 0, originRect: originRect)
        Task { await viewStoryTick(groups[groupIndex].stories[0].id) }
    }
    func closeStoryViewer() { storyViewer = nil }
    /// Auto-advance / manual "next": within the current host's stories
    /// first; at that host's last story, the first story of the NEXT host
    /// with any stories left; at the very last host's last story, dismiss.
    func storyNext() {
        guard let v = storyViewer else { return }
        let group = v.groups[v.groupIndex]
        if v.storyIndex + 1 < group.stories.count {
            storyViewer = StoryViewerState(groups: v.groups, groupIndex: v.groupIndex, storyIndex: v.storyIndex + 1, originRect: v.originRect)
            return
        }
        for gi in (v.groupIndex + 1)..<v.groups.count where !v.groups[gi].stories.isEmpty {
            storyViewer = StoryViewerState(groups: v.groups, groupIndex: gi, storyIndex: 0, originRect: v.originRect)
            return
        }
        storyViewer = nil
    }
    /// Manual "previous": within the current host first; at that host's
    /// FIRST story, the previous host's LAST story; at the very first
    /// host's first story, a no-op.
    func storyPrev() {
        guard let v = storyViewer else { return }
        if v.storyIndex > 0 {
            storyViewer = StoryViewerState(groups: v.groups, groupIndex: v.groupIndex, storyIndex: v.storyIndex - 1, originRect: v.originRect)
            return
        }
        var gi = v.groupIndex - 1
        while gi >= 0 {
            if !v.groups[gi].stories.isEmpty {
                storyViewer = StoryViewerState(groups: v.groups, groupIndex: gi, storyIndex: v.groups[gi].stories.count - 1, originRect: v.originRect)
                return
            }
            gi -= 1
        }
    }
    /// PRODUCT CHANGE 3 (2026-09-22 tenth follow-up) — the horizontal
    /// DRAG/swipe gesture must move between HOST GROUPS only, never
    /// between individual posts of the SAME host (that's still exclusively
    /// the timer's/tap-zones' job, via `storyNext()`/`storyPrev()` above,
    /// unchanged). A separate pair of functions — only ever called from
    /// `StoryViewerView.swift`'s horizontal-drag commit branch — so the
    /// two gestures' semantics can never accidentally re-merge.
    ///
    /// "next host's current/first UNSEEN story" — resumes at whichever
    /// story in that host hasn't been watched yet, or its first if none have.
    func storyNextHost() {
        guard let v = storyViewer else { return }
        for gi in (v.groupIndex + 1)..<v.groups.count where !v.groups[gi].stories.isEmpty {
            let idx = v.groups[gi].stories.firstIndex(where: { !$0.viewed }) ?? 0
            storyViewer = StoryViewerState(groups: v.groups, groupIndex: gi, storyIndex: idx, originRect: v.originRect)
            return
        }
        // No next host — StoryViewerView's own gesture handler decides
        // what happens here (BUG 4: reveal Home instead of advancing), so
        // this is intentionally a no-op, not a dismiss.
    }
    /// "previous host's appropriate current/last-viewed story" — resumes
    /// at the LAST story in that host the viewer had already reached (so
    /// swiping back lands where they left off, not at the start again); if
    /// none were viewed yet, its final story (mirrors `storyPrev()`'s own
    /// "enter a host from its last story" convention above).
    func storyPrevHost() {
        guard let v = storyViewer else { return }
        var gi = v.groupIndex - 1
        while gi >= 0 {
            let g = v.groups[gi]
            if !g.stories.isEmpty {
                let lastViewed = g.stories.lastIndex(where: { $0.viewed })
                storyViewer = StoryViewerState(groups: v.groups, groupIndex: gi, storyIndex: lastViewed ?? (g.stories.count - 1), originRect: v.originRect)
                return
            }
            gi -= 1
        }
        // No previous host — nothing to do; the gesture always springs
        // back in this case (see BUG 4's own "beginning of the deck" symmetry).
    }
    func showPhoto(at index: Int) {
        guard var item = photoViewer else { return }
        item.index = max(0, min(index, item.gallery.count - 1))
        photoViewer = item
    }

    // 2026-09-26 photo-interactions redesign — the old local-only
    // `isPhotoLiked`/`togglePhotoLike(_ path:)` pair (UserDefaults, keyed by
    // raw photo path/URL, zero Supabase calls) is gone. The real, unified
    // `togglePhotoLike(_ photoId:)` lives in AppState+PhotoEngagement.swift,
    // next to `loadPhotoEngagement`/`logPhotoShare`.

    /// Opens a shared organizer link — banbe://organizer/<eventKey>. The
    /// scheme is registered in project.yml; a plain https:// link can't
    /// reach the app without Universal Links, which need an entitlement and
    /// an Apple Team ID this project doesn't have yet, so the web page
    /// shared alongside offers this as an explicit "Open" button.
    func handleDeepLink(_ url: URL) {
        guard url.scheme == "banbe" else { return }
        let parts = ([url.host] + url.pathComponents.filter { $0 != "/" }).compactMap { $0 }
        guard parts.first == "organizer", let key = parts.dropFirst().first,
              EventCatalog.find(key) != nil
        else { return }
        photoViewer = nil
        eventKey = key
        screen = .organizer
    }

    func openPreferences() { screen = .preferences }
    func openSecurity() { screen = .security }
    func goLogin() { requireAuth(returnTo: .profile, backTo: .home) }

    func goInbox() {
        guard isSignedIn else { return requireAuth(returnTo: .inbox, backTo: .home) }
        inboxBack = screen == .profile ? .profile : .home
        screen = .inbox
        Task { await loadInboxThreads() }
    }
    func backFromInbox() { screen = inboxBack }

    // Re-fetches on every open, not just once at sign-in — mirrors the same
    // fix on the web side (GocContext.jsx's goGoingList). Nothing else
    // invalidates `attending` in between (no realtime subscription, no
    // polling), so without this a dispute resolved against the guest by an
    // admin in a different session never clears this list until the app
    // relaunches.
    func goGoingList(back: Screen = .profile) { eventListMode = .going; eventListBack = back; screen = .eventList; Task { await loadMyEvents() } }
    func goSavedList(back: Screen = .profile) { eventListMode = .saved; eventListBack = back; screen = .eventList }
    func goCompletedList(back: Screen = .accountGroup) { eventListMode = .completed; eventListBack = back; screen = .eventList }
    func backFromEventList() { screen = eventListBack }

    func goReserve() {
        guard isSignedIn else { return requireAuth(returnTo: .reserve, backTo: .event) }
        formName = user?.displayName ?? ""
        reserveNameError = ""
        screen = .reserve
    }

    func goDashboard(back: Screen? = nil) {
        if let back { dashboardBack = back }
        screen = .dashboard
        Task { await loadMyOrgEventSummaries() }
    }

    func goCreate() {
        guard isSignedIn else { return requireAuth(returnTo: .create, backTo: .hostIntro) }
        if !canHost { Task { await applyOrganizerMode(true) } }
        mode = "host"
        // A fresh "create a new event" entry, distinct from goEditEvent's
        // own resubmission entry — always clears any prior edit target so
        // this never accidentally resubmits over a different event.
        createEditEventId = nil
        createSent = false
        createError = ""
        createOriginScreen = screen
        // TASK 3 (event creation validation pass) — "Create another event"
        // (the post-submission chooser, CreateEventView) reuses this SAME
        // function, and unlike every previous caller (always arriving here
        // from a genuinely different screen), it can now fire while
        // `.create` is ALREADY showing — no view teardown, so nothing else
        // would otherwise clear the previous event's own name/description/
        // date/price/seats/category/intro. Reset all of them here, not
        // just the address/edit-id/included-items fields this already
        // cleared, so "Create another" truly starts blank.
        createName = ""
        createCats = []
        createDesc = ""
        createEventDate = nil
        createEventTime = nil
        createPrice = ""
        createSeats = ""
        createVisibility = "public"
        createIntro = ""
        // Never carry a previous session's confirmed address/coordinates
        // into an unrelated fresh event.
        createLoc = ""
        createLat = nil
        createLng = nil
        createLocLabel = ""
        createAddressLine = ""
        createDistrict = ""
        createCity = ""
        createPostalCode = ""
        createCountryCode = nil
        createStateProvince = nil
        createNeighborhood = nil
        createLocConfirmed = false
        createAddressSuggestions = []
        createAddressSearching = false
        createAddressSearchError = ""
        createIncludedItems = []
        createKeywords = ""
        screen = .create
    }

    // "Bao gồm" item editing (mirrors web's addCreateIncludedItem/
    // removeCreateIncludedItem/setCreateIncludedItem, GocContext.jsx) —
    // same cap (3) migration 087 itself enforces server-side; this only
    // avoids a round trip for an obviously-full list.
    func addCreateIncludedItem() {
        guard createIncludedItems.count < 3 else { return }
        createIncludedItems.append(IncludedItem(label: "", detail: ""))
    }
    func removeCreateIncludedItem(at index: Int) {
        guard createIncludedItems.indices.contains(index) else { return }
        createIncludedItems.remove(at: index)
    }
    func setCreateIncludedItemLabel(_ index: Int, _ value: String) {
        guard createIncludedItems.indices.contains(index) else { return }
        createIncludedItems[index] = IncludedItem(label: value, detail: createIncludedItems[index].detail)
    }
    func setCreateIncludedItemDetail(_ index: Int, _ value: String) {
        guard createIncludedItems.indices.contains(index) else { return }
        createIncludedItems[index] = IncludedItem(label: createIncludedItems[index].label, detail: value)
    }

    func goHostIntro() {
        guard isSignedIn else { return requireAuth(returnTo: .hostIntro, backTo: .profile) }
        if !canHost { Task { await applyOrganizerMode(true) } }
        screen = .hostIntro
    }

    func createBack() { screen = createOriginScreen }

    func switchToHost(back: Screen = .home) {
        guard isSignedIn else { return requireAuth(returnTo: .dashboard, backTo: .home) }
        if !canHost { Task { await applyOrganizerMode(true) } }
        mode = "host"
        dashboardBack = back
        screen = .dashboard
        Task { await loadMyEvents() }
    }
    func backFromDashboard() { screen = dashboardBack }

    func switchToGoer() {
        mode = "goer"
        screen = .home
    }

    func requireAuth(returnTo: Screen, backTo: Screen) {
        authReturnScreen = returnTo
        authBackScreen = backTo
        screen = .login
    }

    /// Whether an edge swipe should do anything on the current screen — the
    /// entry/onboarding screens and Home (nothing to go back to) opt out.
    /// `.login` opts out too (both its Login and Signup tabs — they're the
    /// same `Screen` case, distinguished only by LoginView's own local
    /// state): Task 1's mandatory-login gate hides the Back link there for
    /// exactly this reason (nowhere legitimate for it to go when
    /// `authMandatory` is set), and swiping back used to reach
    /// `authBackScreen` regardless, bypassing that gate entirely.
    /// A rejected/cancelled booking is over — every exit from
    /// PaymentDetailsView must land on Home directly, not whatever screen
    /// sent the guest here (which can itself still be mid-transition off a
    /// now-dead timer UI). This app has no real NavigationStack (screen is
    /// a flat single published enum, see goBack()'s own comment below), but
    /// there are still TWO separate exit paths that both need this check:
    /// the in-view BackLink (PaymentViews.swift) and this edge-swipe
    /// gesture's goBack()/backTargetScreen below — a single shared
    /// computed property means neither can drift out of sync with the
    /// other again.
    var paymentDetailsBackTarget: Screen {
        let booking = paymentBookings.first { $0.id == paymentBookingID }
        // Bug 3 (15-organizer-checkin.md follow-up): a confirmed booking is
        // as terminal here as a cancelled one — the "Paid" card's own
        // button (not this back path) is how a guest reaches their ticket
        // now, so leaving via back/swipe should land on Home directly too,
        // same reasoning as the cancelled case above.
        switch booking?.paymentState {
        case .cancelled, .confirmed: return .home
        default: return paymentBack
        }
    }

    // Review-sheet-swipe-back destination fix (2026-09-29) — `CreateEventReviewSheet`
    // is no longer a `.fullScreenCover` (see its own doc comment), so
    // it's now inside the SAME `.create` screen hierarchy this root-level
    // edge-swipe gesture already owns. Without this flag, an edge swipe
    // while the review sheet is open was captured by THIS gesture first
    // (`.highPriorityGesture`) and ran `createBack()` — popping the whole
    // Create Event screen, past the review sheet AND its edit form, back
    // to wherever Create was opened from — instead of the review sheet's
    // own local swipe-back gesture, which correctly just closes the
    // review sheet back to the edit form. Set by `CreateEventView` itself
    // whenever its `reviewOpen` changes.
    @Published var isCreateReviewOpen = false

    var canSwipeBack: Bool {
        switch screen {
        case .splash, .langPick, .themePick, .home, .login: return false
        case .create: return !isCreateReviewOpen
        default: return true
        }
    }

    /// Drives the right-edge swipe gesture in RootView — mirrors whatever
    /// each screen's own back/"Done" control already does, since this app
    /// switches one explicit `screen` at a time instead of using a
    /// NavigationStack (which is what gives UIKit apps swipe-to-back for
    /// free).
    func goBack() {
        switch screen {
        case .profile: goHome()
        // Bug 5 (2026-09-21 follow-up) — Archived (`inboxView == .archived`)
        // isn't a separate `Screen`, just a sub-state of `.inbox` (opened
        // from Inbox's own settings menu, 1c62d4c) — the edge-swipe used to
        // ignore that entirely and always run `backFromInbox()` (exiting
        // all the way to Home/Profile), skipping the "return to the
        // regular Inbox list first" step its own on-screen "‹ Quay lại Tin
        // nhắn" link already does correctly. Same
        // documentBack/verificationsBack-style back-target convention this
        // app already uses elsewhere — just one level, since Archived has
        // nowhere further to fall back to but Inbox itself.
        case .inbox: if inboxView == .archived { inboxView = .active } else { backFromInbox() }
        case .eventList: backFromEventList()
        case .event: backFromEvent()
        case .organizer, .reserve: backToEvent()
        case .chat: chatBackAction()
        case .dashboard: backFromDashboard()
        case .hostIntro: goProfile()
        case .create: createBack()
        case .attendance: screen = attendanceBack
        // Sub-section-of-a-group back-navigation fix (2026-09-29, second
        // pass) — `.preferences`/`.security` are only ever reached from
        // AccountGroupView's "preferences" group page, so `.profile`
        // skipped that group page, same class of bug as `.documents`'s own
        // fix.
        case .preferences, .security: screen = .accountGroup
        // TASK 4 (Reserve→edit-name pass) — `.editName` is now reachable
        // from more than one place (AccountView's own root identity card,
        // AND ReserveView's "Đổi trong Tài khoản"), so its back target is
        // no longer always `.profile` — `editNameReturnScreen` (set by
        // `goEditName()`, see its own comment) tracks whichever one it was.
        case .editName: screen = editNameReturnScreen
        case .login: screen = authBackScreen
        case .confirmed: screen = confirmedBack
        case .refunded, .notifications: goHome()
        case .paymentDetails: screen = paymentDetailsBackTarget
        case .billing: screen = .paymentDetails
        // Sub-section-of-a-group back-navigation fix (2026-09-29, second
        // pass) — `.payout` is only ever reached from AccountGroupView's
        // "hostOps" group page (its own only call site, openPayout()).
        case .payout: screen = .accountGroup
        case .documents: screen = documentsListBack
        case .documentView: screen = documentBack
        case .verifications: screen = verificationsBack
        case .disputes, .adminEvents: screen = .profile
        case .mapExplore: goHome()
        // TASK A fix — these two cases were simply missing, so the shared
        // edge-swipe gesture's goBack() fell to `default: break` and did
        // nothing at all for RefundAccountsView/MyRefundsView (the reported
        // "swipe-back doesn't return to Account, at any speed" — there was
        // no missing gesture-recognition tuning to fix, just two absent
        // switch cases). Reuses the exact same functions the in-view
        // BackLink already calls, so both exit paths can never drift apart
        // again (same reasoning as paymentDetailsBackTarget's own doc
        // comment above).
        case .refundAccounts: backFromRefundAccounts()
        case .myRefunds: backFromMyRefunds()
        case .editProfile: backFromEditProfile()
        case .publicProfile: backFromPublicProfile()
        case .organizerProfile: backFromOrganizerProfile()
        // iPhone fix pass (2026-09-27), Issue 4 — the other half of the
        // same confirmed bug: `.organizerTeam` fell to `default: break`
        // (a real no-op) here too, so `app.screen` never actually changed
        // on a completed edge-swipe — RootView's own `isCommittingBack`
        // handler still played the slide-off animation and then reset
        // `isCommittingBack`/`dragTranslation` regardless, reading as
        // "snaps back to Team" once that animation finished.
        case .organizerTeam: backFromOrganizerTeam()
        case .surveyPublic: screen = surveyPublicBackScreen
        case .surveysHosting: screen = .profile
        case .reports: backFromReports()
        // Account IA pass (2026-09-27) — `accountTab` is never touched by
        // AccountGroupView, so returning to `.profile` always lands back
        // on whichever tab was already showing.
        case .accountGroup: screen = .profile
        default: break
        }
    }

    /// The title AccountGroupView shows for a given group key — pulled out
    /// so a `BackLink` label can say "Payments & documents"/"Tickets &
    /// activity"/etc. instead of a generic "Account" whenever the actual
    /// back target is a specific group page. AccountGroupView's own
    /// `title` computed property calls this too, so the two never drift.
    // Account IA reorg (2026-09-30) — "activity"'s visible label changed
    // to "Tickets & Bookings" (its content is now this account's REAL
    // bookings, see `AccountGroupView.activityContent`) and "preferences"
    // relabeled to "Settings" for accuracy — mirrors web's
    // `AccountGroup.jsx` GROUP_META exactly. The keys themselves ("activity"/
    // "preferences") are UNCHANGED, only these display strings.
    func accountGroupTitle(for key: String?) -> String {
        switch key {
        case "team": return T("Hồ Sơ & Team", "Profile & Team")
        case "activity": return T("Vé & Đặt Chỗ", "Tickets & Bookings")
        case "payments": return T("Thanh Toán & Giấy Tờ", "Payments & Documents")
        case "preferences": return T("Cài Đặt", "Settings")
        case "hostOps": return T("Vận Hành & Thanh Toán Tổ Chức", "Event Operations & Payments")
        case "adminReview": return T("Duyệt & Kiểm Duyệt", "Review & Moderation")
        default: return ""
        }
    }

    /// The label a `BackLink`/back button should show for a given
    /// destination screen — so every subsection's back button names the
    /// section it's actually returning to (2026-09-29 follow-up: several
    /// subsections under Account hardcoded "Account" even when their real
    /// back target, via a `backScreen`/`goBack()` target, was a specific
    /// group page).
    func backLabel(for target: Screen) -> String {
        switch target {
        case .accountGroup: return accountGroupTitle(for: accountGroupKey)
        case .notifications: return T("Thông báo", "Notifications")
        default: return T("Tài khoản", "Account")
        }
    }

    /// Where goBack() would land, computed without any of its side effects
    /// (no mutation, no network calls) — lets RootView render that screen
    /// peeking in behind the current one while an edge swipe is in
    /// progress, the same way UIKit reveals the real previous view instead
    /// of blank space.
    var backTargetScreen: Screen {
        switch screen {
        case .profile: return .home
        // Bug 5 (2026-09-21 follow-up) — matches `goBack()`'s own case
        // above: from Archived, swiping back stays on `.inbox` itself
        // (just drops back to the active list), never jumps straight to
        // `inboxBack`.
        case .inbox: return inboxView == .archived ? .inbox : inboxBack
        case .eventList: return eventListBack
        case .event: return eventBackScreen
        case .organizer, .reserve: return .event
        case .chat: return chatBack == .inbox || chatBack == .notifications ? chatBack : .organizer
        case .dashboard: return dashboardBack
        case .hostIntro: return .profile
        case .create: return createOriginScreen
        case .attendance: return attendanceBack
        case .preferences, .security: return .accountGroup
        case .editName: return editNameReturnScreen
        case .login: return authBackScreen
        case .confirmed: return confirmedBack
        case .refunded, .notifications: return .home
        case .paymentDetails: return paymentDetailsBackTarget
        case .billing: return .paymentDetails
        case .payout: return .accountGroup
        case .documents: return documentsListBack
        case .documentView: return documentBack
        case .verifications: return verificationsBack
        case .disputes, .adminEvents: return .profile
        case .mapExplore: return .home
        // TASK A fix — same missing-case bug as goBack() above: without
        // these, an in-progress edge swipe from RefundAccounts/MyRefunds
        // peeked Home behind the dragged screen instead of Account, which
        // would have looked like landing on the wrong screen even on the
        // rare swipe that DID complete.
        case .refundAccounts: return refundAccountsBackScreen
        case .myRefunds: return myRefundsBackScreen
        case .editProfile: return .profile
        case .publicProfile: return publicProfileBackScreen
        case .organizerProfile: return organizerProfileBackScreen
        case .surveyPublic: return surveyPublicBackScreen
        case .surveysHosting: return .profile
        // iPhone fix pass (2026-09-27), Issue 4 — CONFIRMED root cause of
        // "edge-swipe on Team reveals Home instead of OrganizerProfile,
        // then snaps back to Team": `.organizerTeam` had no case here at
        // all, so it fell to `default: return .home` — the edge-swipe
        // peek (RootView.swift's `screenView(for: app.backTargetScreen,
        // isPreview: true)`) always previewed Home underneath, regardless
        // of where Team was actually opened from.
        case .organizerTeam: return organizerTeamBackScreen
        case .reports: return reportsBackScreen
        case .accountGroup: return .profile
        default: return .home
        }
    }

    // MARK: - Feed interactions

    // Stage 1 (retention roadmap P0) — persists to the real `favorites`
    // table (owner-only RLS, 003_social_chat.sql), mirrors web's own
    // toggleFav (GocContext.jsx) exactly: optimistic UI flip, in-flight
    // dedupe per event key so a fast double-tap can't fire two opposite
    // writes for the same row, and a rollback that only applies if this is
    // still the same signed-in account by the time the request settles.
    func toggleFavorite(_ key: String) {
        guard !favoriteToggleInFlight.contains(key) else { return }
        let wasSaved = favorites.contains(key)
        if let index = favorites.firstIndex(of: key) { favorites.remove(at: index) } else { favorites.append(key) }
        guard let uid = userID else { return } // signed-out: local-only, same as before this ticket
        favoriteToggleInFlight.insert(key)
        Task { await persistFavoriteToggle(eventKey: key, uid: uid, wasSaved: wasSaved) }
    }

    // 2026-09-21 follow-up (stories, 07-notifications.md) — REAL bug found
    // while wiring stories' audience, mirrors the same fix on web
    // (GocContext.jsx): this was local-only, never persisted to the real
    // `follows(user_id, organizer_id)` table (003_social_chat.sql). Local
    // `following` (by event key) stays as the optimistic UI toggle
    // OrganizerView.swift already reads — now ALSO persists, resolved via
    // the event's real organizer_id, best-effort (a demo-catalogue event
    // with no real DB row only updates local state, same as before).
    func toggleFollow(_ key: String) {
        let wasFollowing = following.contains(key)
        if let index = following.firstIndex(of: key) { following.remove(at: index) } else { following.append(key) }
        guard let uid = userID else { return }
        Task { await persistFollowToggle(eventKey: key, uid: uid, wasFollowing: wasFollowing) }
    }

    func pickFilter(_ key: String) { filter = key }
    func clearFilters() {
        filter = "all"; area = "all"
        filterAttending = false; filterSaved = false; filterSoldOut = false
        filterNotConfirmed = false
        filterUpcoming = false; filterEnded = false
    }

    /// Home's second chip row (12-home-filters.md, extended 2026-09-21) —
    /// each independent, AND-combined with `filter`/`area` and with each
    /// other, not mutually exclusive.
    func toggleHomeFilter(_ key: String) {
        switch key {
        case "attending": filterAttending.toggle()
        case "notConfirmed": filterNotConfirmed.toggle()
        case "saved": filterSaved.toggle()
        case "soldOut": filterSoldOut.toggle()
        case "upcoming": filterUpcoming.toggle()
        case "ended": filterEnded.toggle()
        default: break
        }
    }
    func openArea() { areaAsking = true }
    func pickArea(_ key: String) { area = LocationHierarchy.migrateSelection(key); areaAsking = false }

    func askLocation() { if located == nil { askingLocation = true } }

    func allowLocation() {
        askingLocation = false
        areaAsking = false
        located = true
        UserDefaults.standard.set(true, forKey: "banbe.located")
        locationService.request()
    }

    func denyLocation() {
        askingLocation = false
        located = false
        userCoords = nil
        UserDefaults.standard.set(false, forKey: "banbe.located")
    }

    /// Distance line shown under each card once location is shared.
    func metaLine(for event: CatalogEvent) -> String {
        trStatus(event.catDisplay) + " ▪︎ " + trStatus(stripKm(event.meta, event: event))
    }

    /// Seats/status label for a feed card — mirrors the web feed's rules.
    func seatsLabel(for event: CatalogEvent) -> String {
        if event.cancelled { return trStatus("Đã hủy") }
        if event.soldOut { return trStatus("Hết chỗ") }
        if let ended = event.endedHoursAgo { return trStatus(EventLabels.ago(ended)) }
        if event.until != nil {
            let suffix = event.untilLabel.replacingOccurrences(of: "^Còn ", with: "", options: [.regularExpression])
            return trStatus(event.seats + " ▪︎ " + suffix)
        }
        return trStatus(event.seats)
    }
}
