import Foundation
import SwiftUI
import UIKit
import CoreLocation
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
    case verifications, disputes
    case policy
    case mapExplore
}

/// Which set of events EventListView shows — ports the same split used by
/// the "Going"/"Saved" counters and the "Completed events" row on Account.
enum EventListMode: String {
    case going, saved, completed
}

/// Feed area filter — ports AREAS in src/state/GocContext.jsx. Labels stay
/// Vietnamese in both languages, as on the web.
struct AreaOption: Identifiable {
    let key: String
    let label: String
    let match: (CatalogEvent) -> Bool
    var id: String { key }

    static let all: [AreaOption] = [
        AreaOption(key: "all", label: "Toàn Sài Gòn", match: { _ in true }),
        AreaOption(key: "q1", label: "Quận 1", match: { $0.meta.contains("Quận 1") }),
        AreaOption(key: "thaodien", label: "Thảo Điền", match: { $0.meta.contains("Thảo Điền") }),
        AreaOption(key: "binhthanh", label: "Bình Thạnh", match: { $0.meta.contains("Bình Thạnh") }),
        AreaOption(key: "other", label: "Quận khác", match: {
            !$0.meta.contains("Quận 1") && !$0.meta.contains("Thảo Điền") && !$0.meta.contains("Bình Thạnh")
        }),
        AreaOption(key: "danang", label: "Đà Nẵng", match: { _ in false }),
    ]
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

/// A gallery opened in the viewer — the whole set of photos it was tapped
/// from, so a left/right swipe can move through the rest, plus which one is
/// showing and the organizer it belongs to (shown as the faint credit).
struct PhotoViewerItem: Equatable {
    let gallery: [String]
    var index: Int
    let organizer: String
    /// The event the photo belongs to — what the save button saves, and
    /// what the shared link points at.
    let eventKey: String
    /// The tapped thumbnail's on-screen frame (global coordinate space) at
    /// the moment it was opened — where the dismiss animation shrinks back
    /// to (14-photo-viewer.md), rather than fading/sliding away generically.
    let originRect: CGRect
    var path: String { gallery[index] }
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

    // MARK: Navigation
    @Published var screen: Screen = .home
    // Bottom tab bar (BottomTabBar.swift) — shrinks a bit while scrolling
    // down, same idea as iOS 26's `.tabBarMinimizeBehavior(.onScrollDown)`,
    // hand-rolled because this app's deployment target is iOS 17. Driven by
    // ScreenScaffold's own scroll-offset tracking via noteScaffoldScroll(),
    // and reset to false on every screen change (see RootView).
    @Published var bottomBarCollapsed: Bool = false
    private var lastScaffoldScrollOffset: CGFloat = 0
    @Published var eventKey: String = "bepnho"
    @Published var eventBackScreen: Screen = .home
    // Task 4C (2026-09-22 follow-up, 07-notifications.md) — set only by
    // goEventFromStory(), holds the exact StoryViewer position to restore
    // when backFromEvent() returns from an event opened via a story's own
    // card/CTA.
    @Published var storyReturnSnapshot: StoryViewerState?
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
    static let guestAllowedScreens: Set<Screen> = [.splash, .langPick, .themePick, .login, .policy]
    @Published var chatBack: Screen = .organizer
    @Published var mode: String = "goer"
    // Inbox and Dashboard are each reachable from more than one place (Home's
    // message icon/host link vs Account's "Messages" row/hosting card), so a
    // single hardcoded back target sends at least one of those callers
    // somewhere it didn't come from.
    @Published var inboxBack: Screen = .home
    @Published var dashboardBack: Screen = .home
    @Published var eventListMode: EventListMode = .going

    // MARK: Preferences (persisted per-device and, once signed in, per-account)
    @Published var lang: String = UserDefaults.standard.string(forKey: "banbe.lang") ?? "vi" {
        didSet { UserDefaults.standard.set(lang, forKey: "banbe.lang") }
    }
    @Published var theme: String = UserDefaults.standard.string(forKey: "banbe.theme") ?? "light" {
        didSet { UserDefaults.standard.set(theme, forKey: "banbe.theme") }
    }
    @Published var area: String = "all"
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
    @Published var hasHosted = false

    // MARK: Feed state
    @Published var favorites: [String] = []
    @Published var following: [String] = []
    @Published var attending: [String] = []
    @Published var tickets: [String: Int] = [:]
    @Published var myOrgEventKeys: [String] = []
    @Published var myOrganizerIDs: [String] = []

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
    @Published var now = Date()
    @Published var reserveError = ""
    @Published var loading = false
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
    // Task 3 (07-notifications.md) — active stories, grouped by organizer,
    // from loadHomeStories(). Own progression viewer state, own creation
    // preview state — kept separate from photoViewer/chatPhotoViewer.
    @Published var homeStories: [StoryGroup] = []
    @Published var storyViewer: StoryViewerState?
    @Published var storyCreatePreviewImage: UIImage?
    @Published var storyCreateBusy = false
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

    // MARK: Notifications
    @Published var notifications: [AppNotification] = []
    var unreadNotifications: Int { notifications.filter { $0.readAt == nil }.count }
    // Batch-fetched by loadNotifications() alongside `notifications` itself
    // — avatarSource(for:maps:accountType:) (Lib/NotificationPresentation.swift)
    // reads this instead of a join per row.
    @Published var notificationAvatarMaps = NotificationAvatarMaps()

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

    /// Shows a small toast and fires a light (not the heavier .success/
    /// .warning system) haptic alongside it, so it feels gentle — see
    /// startNotificationPolling() in AppState+Data.swift for what triggers
    /// this. Carries the whole notification (not just title/body) so
    /// tapping it can route the same way NotificationsView's rows do.
    func pushToast(_ notification: AppNotification) {
        let item = ToastItem(id: UUID(), notification: notification)
        toasts.append(item)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            toasts.removeAll { $0.id == item.id }
        }
    }

    /// Tapping a toast shouldn't sit around for its own auto-dismiss timer.
    func dismissToast(_ id: UUID) {
        toasts.removeAll { $0.id == id }
    }

    /// "Tắt tất cả" (ToastOverlay.swift) — clears the whole local toast
    /// queue at once. Same local-only contract as dismissToast: this NEVER
    /// touches `notifications`/`read_at` on the server — the bell inbox's
    /// unread state and badge count are untouched by clearing this ephemeral
    /// queue. See .claude/notes/07-notifications.md.
    func dismissAllToasts() {
        toasts.removeAll()
    }

    // MARK: Display name
    @Published var editNameValue = ""
    @Published var editNameError = ""
    @Published var editNameSaving = false

    // MARK: Attendance / check-in
    @Published var attendanceEventKey: String?
    @Published var attendanceGuests: [AttendanceGuest] = []
    @Published var attendanceLoading = false
    @Published var photoViewer: PhotoViewerItem?
    /// Liked photo paths. Local-only: there's no table to hang a photo like
    /// on, and inventing one would mean a migration that isn't live yet.
    @Published var photoLikes: [String] = UserDefaults.standard.stringArray(forKey: "banbe.photoLikes") ?? [] {
        didSet { UserDefaults.standard.set(photoLikes, forKey: "banbe.photoLikes") }
    }
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
    @Published var createName = ""
    @Published var createDesc = ""
    @Published var createLoc = ""
    @Published var createDate = ""
    @Published var createPrice = ""
    @Published var createSeats = ""
    @Published var createCats: [String] = []
    @Published var createSent = false
    @Published var createError = ""
    @Published var orgVerifyRequested = false

    // MARK: Map explore (11-realtime-map.md)
    /// Real `events` rows for whatever the map's current query is (initial
    /// density-hotspot area, or the last "search here" bbox) — separate
    /// from `CatalogEvent.all` (the bundled cosmetic catalogue), joined
    /// back to it per-row in MapExploreView since seats/status here are
    /// live and the catalogue's are not.
    @Published var mapEvents: [MapEventRow] = []
    @Published var mapEventsLoading = true
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

    var currentEvent: CatalogEvent {
        (EventCatalog.find(eventKey) ?? EventCatalog.all[0]).applyingLiveStatus(liveEventStatus)
    }
    var currentArea: AreaOption { AreaOption.all.first { $0.key == area } ?? AreaOption.all[0] }
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

    /// The home feed — same filter and ordering as src/screens/Home.jsx:
    /// invite-only events never appear, and cancelled ones sink to the end.
    var feed: [CatalogEvent] {
        // Split into intermediate steps — Swift's type-checker couldn't
        // resolve the original single chained expression (this many
        // `.filter` closures in one statement) in reasonable time.
        let categoryAndArea = EventCatalog.all
            .map(withLive)
            .filter { !$0.inviteOnly }
            .filter { filter == "all" || $0.catKey == filter || $0.cat2Key == filter }
            .filter { currentArea.match($0) }
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
    var savedStrip: [CatalogEvent] {
        var keys: [String] = []
        for key in favorites + attending where !keys.contains(key) { keys.append(key) }
        if let heldKey = heldEvent?.key, !keys.contains(heldKey) { keys.append(heldKey) }
        return keys.compactMap { key in EventCatalog.all.first { $0.key == key } }
            .map(withLive)
            .filter { ($0.endedHoursAgo ?? 0) <= 48 }
    }

    var heldEvent: CatalogEvent? {
        guard let deadline = holdDeadline, deadline > now else { return nil }
        return EventCatalog.all.first { $0.key == eventKey }
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
    var eventListEvents: [CatalogEvent] {
        switch eventListMode {
        case .going:
            // Once an event ends it belongs in Completed instead of sitting
            // in Going forever.
            return attending.compactMap { key in EventCatalog.all.first { $0.key == key } }
                .filter { $0.endedHoursAgo == nil }
        case .saved: return favorites.compactMap { key in EventCatalog.all.first { $0.key == key } }
        case .completed:
            var keys: [String] = []
            for key in favorites + attending where !keys.contains(key) { keys.append(key) }
            // "Completed" means it already happened — anything still
            // upcoming (or just favorited but never actually attended)
            // doesn't belong here.
            return keys.compactMap { key in EventCatalog.all.first { $0.key == key } }
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
        attending.compactMap { key in EventCatalog.all.first { $0.key == key } }
            .filter { $0.endedHoursAgo == nil }.count
    }

    /// Backs the count on Account's "Sự kiện đã lưu"/"Completed events" row.
    var completedEventsCount: Int {
        var keys: [String] = []
        for key in favorites + attending where !keys.contains(key) { keys.append(key) }
        return keys.compactMap { key in EventCatalog.all.first { $0.key == key } }
            .filter { $0.endedHoursAgo != nil }.count
    }

    // MARK: - Onboarding

    private var hasOnboarded: Bool { UserDefaults.standard.bool(forKey: "banbe.onboarded") }

    /// Task 1 — no guest browsing of any screen: lands on the mandatory
    /// Login gate instead of Home when not actually signed in.
    /// authReturnScreen/authBackScreen point at where onboarding was
    /// actually headed, so signing in lands there instead of always Home.
    private func postAuthDestination(isSignedIn: Bool) {
        let target: Screen = .home
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
        if screen != .event && screen != .organizer { eventBackScreen = screen }
        eventKey = key
        screen = .event
        // A fresh, non-story-originated event open invalidates any pending
        // story-return snapshot/back-label — see goEventFromStory()'s own
        // comment. BUG 3 fix (2026-09-22 follow-up): also clears
        // `eventBackIsStory` for the same reason.
        eventBackIsStory = false
        storyReturnSnapshot = nil
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
    func goEventFromStory(_ key: String) {
        if screen != .event && screen != .organizer { eventBackScreen = screen }
        eventBackIsStory = true
        storyReturnSnapshot = storyViewer
        if let v = storyViewer, v.groups.indices.contains(v.groupIndex) {
            storyReturnHostName = v.groups[v.groupIndex].orgName
        } else {
            storyReturnHostName = nil
        }
        storyViewer = nil
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
    func backFromEvent() {
        if eventBackScreen == .mapExplore {
            returnToMapExplore()
        } else {
            screen = eventBackScreen
        }
        if eventBackIsStory, let snapshot = storyReturnSnapshot {
            storyViewer = snapshot
        }
        eventBackIsStory = false
        storyReturnSnapshot = nil
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
        mapExploreState = MapExploreState(
            cameraCenterLat: event.lat, cameraCenterLng: event.lng,
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
    func goOrganizer() { screen = .organizer }
    func backToEvent() { screen = .event }
    func openHeld() { screen = .confirmed }
    /// Tapping a photo in either gallery ("Hình ảnh" on an event, "Ảnh của
    /// X" on an organizer page) opens it larger, over a dimmed backdrop —
    /// with a light tap of haptic feedback, which is the part the web
    /// version can't do (navigator.vibrate isn't implemented on iOS Safari).
    func openPhoto(gallery: [String], index: Int, organizer: String, eventKey: String, originRect: CGRect) {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
        photoViewer = PhotoViewerItem(gallery: gallery, index: index, organizer: organizer, eventKey: eventKey, originRect: originRect)
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
    func openStoryViewer(_ organizerId: String) {
        let groups = homeStories.filter { !$0.stories.isEmpty }
        guard let groupIndex = groups.firstIndex(where: { $0.organizerId == organizerId }) else { return }
        storyViewer = StoryViewerState(groups: groups, groupIndex: groupIndex, storyIndex: 0)
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
            storyViewer = StoryViewerState(groups: v.groups, groupIndex: v.groupIndex, storyIndex: v.storyIndex + 1)
            return
        }
        for gi in (v.groupIndex + 1)..<v.groups.count where !v.groups[gi].stories.isEmpty {
            storyViewer = StoryViewerState(groups: v.groups, groupIndex: gi, storyIndex: 0)
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
            storyViewer = StoryViewerState(groups: v.groups, groupIndex: v.groupIndex, storyIndex: v.storyIndex - 1)
            return
        }
        var gi = v.groupIndex - 1
        while gi >= 0 {
            if !v.groups[gi].stories.isEmpty {
                storyViewer = StoryViewerState(groups: v.groups, groupIndex: gi, storyIndex: v.groups[gi].stories.count - 1)
                return
            }
            gi -= 1
        }
    }
    func showPhoto(at index: Int) {
        guard var item = photoViewer else { return }
        item.index = max(0, min(index, item.gallery.count - 1))
        photoViewer = item
    }

    func isPhotoLiked(_ path: String) -> Bool { photoLikes.contains(path) }
    func togglePhotoLike(_ path: String) {
        if let index = photoLikes.firstIndex(of: path) { photoLikes.remove(at: index) } else { photoLikes.append(path) }
    }

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
    func goGoingList() { eventListMode = .going; screen = .eventList; Task { await loadMyEvents() } }
    func goSavedList() { eventListMode = .saved; screen = .eventList }
    func goCompletedList() { eventListMode = .completed; screen = .eventList }
    func backFromEventList() { screen = .profile }

    func goReserve() {
        guard isSignedIn else { return requireAuth(returnTo: .reserve, backTo: .event) }
        formName = user?.displayName ?? ""
        reserveNameError = ""
        screen = .reserve
    }

    func goDashboard() { screen = .dashboard }

    func goCreate() {
        guard isSignedIn else { return requireAuth(returnTo: .create, backTo: .hostIntro) }
        if !canHost { Task { await applyOrganizerMode(true) } }
        mode = "host"
        screen = .create
    }

    func goHostIntro() {
        guard isSignedIn else { return requireAuth(returnTo: .hostIntro, backTo: .profile) }
        if !canHost { Task { await applyOrganizerMode(true) } }
        screen = .hostIntro
    }

    func createBack() { screen = hasHosted ? .dashboard : .hostIntro }

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

    var canSwipeBack: Bool {
        switch screen {
        case .splash, .langPick, .themePick, .home, .login: return false
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
        case .preferences, .editName, .security: screen = .profile
        case .login: screen = authBackScreen
        case .confirmed: screen = confirmedBack
        case .refunded, .notifications: goHome()
        case .paymentDetails: screen = paymentDetailsBackTarget
        case .billing: screen = .paymentDetails
        case .payout: screen = .profile
        case .documents: screen = .profile
        case .documentView: screen = documentBack
        case .verifications: screen = verificationsBack
        case .disputes: screen = .profile
        case .mapExplore: goHome()
        default: break
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
        case .eventList: return .profile
        case .event: return eventBackScreen
        case .organizer, .reserve: return .event
        case .chat: return chatBack == .inbox || chatBack == .notifications ? chatBack : .organizer
        case .dashboard: return dashboardBack
        case .hostIntro: return .profile
        case .create: return hasHosted ? .dashboard : .hostIntro
        case .attendance: return attendanceBack
        case .preferences, .editName, .security: return .profile
        case .login: return authBackScreen
        case .confirmed: return confirmedBack
        case .refunded, .notifications: return .home
        case .paymentDetails: return paymentDetailsBackTarget
        case .billing: return .paymentDetails
        case .payout: return .profile
        case .documents: return .profile
        case .documentView: return documentBack
        case .verifications: return verificationsBack
        case .disputes: return .profile
        case .mapExplore: return .home
        default: return .home
        }
    }

    // MARK: - Feed interactions

    func toggleFavorite(_ key: String) {
        if let index = favorites.firstIndex(of: key) { favorites.remove(at: index) } else { favorites.append(key) }
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
    func pickArea(_ key: String) { area = key; areaAsking = false }

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
