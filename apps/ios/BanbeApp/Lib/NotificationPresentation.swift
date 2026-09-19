import Foundation

/// Notification-bell presentation helpers — kept separate from AppState so
/// NotificationsView's row renderer doesn't need per-kind branching
/// scattered through its body. Mirrors src/lib/notifications.js.

/// Kinds where the notification is fundamentally ABOUT A SPECIFIC GUEST from
/// the organizer's own perspective — these prefer the guest's own avatar
/// (profiles.avatar_url, joined via data.booking_id -> bookings.user_id)
/// over the event's cover photo. Every other kind (about an event from the
/// guest's own perspective, or with no specific actor at all) prefers the
/// event's cover photo, falling back to a plain glyph when neither resolves.
private let guestAvatarKinds: Set<String> = [
    "booking_requested",
    "payment_awaiting_verification",
    "receipt_requested",
    "payment_verification_nudge",
    "guest_renamed",
]

enum NotificationAvatarSource: Equatable {
    case image(URL)
    /// A catalogue photo (findEvent()/EVENTS equivalent — CatalogEvent.img),
    /// rendered via CatalogPhoto's own specialized loader (WebP derivative,
    /// downsampling, disk cache) rather than a plain URL — see BUG 1 below.
    case catalogPhoto(String)
    case fallback
}

/// Lookup tables AppState.loadNotifications() batch-fetches once per
/// screen-open — booking_id -> (eventId, userId), event_id -> cover photo
/// URL, user_id -> avatar URL.
struct NotificationAvatarMaps {
    var bookingById: [UUID: (eventId: String, userId: UUID?)] = [:]
    var eventPhotoByEventId: [String: URL] = [:]
    var avatarByUserId: [UUID: URL] = [:]
    /// 2026-09-19 follow-up: document ids confirmed to still exist, fetched
    /// alongside the other batch joins above purely so
    /// loadNotifications() can prune a stale payment_document_uploaded/
    /// _replaced notification without a second round trip.
    var liveDocumentIds: Set<UUID> = []
}

/// Resolves what a notification row's left-side circle should show. Never
/// returns a broken/missing image URL — `.fallback` is the "render a plain
/// glyph instead" signal the caller acts on.
func avatarSource(for notification: AppNotification, maps: NotificationAvatarMaps, accountType: String) -> NotificationAvatarSource {
    let bookingIDString = notification.data["booking_id"]?.stringValue
    let booking = bookingIDString.flatMap(UUID.init(uuidString:)).flatMap { maps.bookingById[$0] }
    // dispute_message goes to whichever party didn't send it — an organizer
    // receiving one is being told about a specific guest's message, so the
    // guest's avatar reads the same way booking_requested's does; a guest
    // receiving one is being told about their own event, so it falls
    // through to the ordinary event-photo case below like everything else.
    let wantsGuestAvatar = guestAvatarKinds.contains(notification.kind) || (notification.kind == "dispute_message" && accountType == "organizer")
    if wantsGuestAvatar, let userId = booking?.userId, let url = maps.avatarByUserId[userId] {
        return .image(url)
    }
    let eventId = notification.data["event_id"]?.stringValue ?? booking?.eventId
    if let eventId, let url = maps.eventPhotoByEventId[eventId] {
        return .image(url)
    }
    // 2026-09-18 follow-up (BUG 1): `event_photos` has never had a single
    // real row written to it by any code path in this app — confirmed by
    // repo-wide grep, the only inserts anywhere are migration 010's
    // one-time seed for 4 demo events. Every real event a real account
    // books against is a catalogue event (EventCatalog/CatalogEvent.img) —
    // the same photo shown on HomeView/EventDetailView/DashboardView
    // everywhere else in the app — so that's the fallback that actually
    // has real data for a real account, not a second empty table.
    // EventCatalog.find() itself falls back to the first catalogue event
    // for an unrecognized key (deliberate elsewhere, so a screen always has
    // something to render) — wrong for this use: showing a random OTHER
    // event's photo for a genuinely non-catalogue event_id would be
    // misleading, worse than the honest bell fallback. Matched directly
    // against EventCatalog.all instead.
    if let eventId, let catalogImg = EventCatalog.all.first(where: { $0.key == eventId })?.img {
        return .catalogPhoto(catalogImg)
    }
    return .fallback
}

/// Instagram/Facebook-style bucketing: unread always lands in its own
/// section regardless of age (checked by the caller, not here — this only
/// buckets by age), everything else buckets by createdAt relative to now.
/// Extends EventLabels.ago()'s "hours ago" concept with the coarser buckets
/// a long notification list actually needs to stay scannable.
enum NotificationAgeBucket { case today, week, older }

func notificationAgeBucket(_ createdAt: Date, now: Date = Date()) -> NotificationAgeBucket {
    let hours = now.timeIntervalSince(createdAt) / 3600
    if hours < 24 { return .today }
    if hours < 24 * 7 { return .week }
    return .older
}

// 2026-09-19 follow-up: within "7 ngày qua"/"Cũ hơn", a finer per-calendar-
// day header — "Thứ Năm, 18 Thg 9"/"Thursday, Sep 18" — instead of one flat
// block for the whole range. Local calendar day (the device's own
// Calendar.current), so a notification just after local midnight starts a
// new group rather than staying lumped with the previous day's items.
private let viWeekdays = ["Chủ Nhật", "Thứ Hai", "Thứ Ba", "Thứ Tư", "Thứ Năm", "Thứ Sáu", "Thứ Bảy"]

func notificationDayKey(_ createdAt: Date) -> DateComponents {
    Calendar.current.dateComponents([.year, .month, .day], from: createdAt)
}

func notificationDayLabel(_ createdAt: Date, lang: String) -> String {
    if lang == "en" {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: createdAt)
    }
    let calendar = Calendar.current
    let weekday = viWeekdays[calendar.component(.weekday, from: createdAt) - 1]
    let day = calendar.component(.day, from: createdAt)
    let month = calendar.component(.month, from: createdAt)
    return "\(weekday), \(day) Thg \(month)"
}

struct NotificationDayGroup: Identifiable {
    let id: String
    let label: String
    let items: [AppNotification]
}

/// Groups an already newest-first-sorted list into per-day buckets (also
/// newest-day-first, since insertion order follows the input). Pure
/// grouping — collapsing is a separate concern, see collapseDayGroups().
func groupNotificationsByDay(_ items: [AppNotification], lang: String) -> [NotificationDayGroup] {
    var order: [String] = []
    var byKey: [String: (label: String, items: [AppNotification])] = [:]
    for n in items {
        let comps = notificationDayKey(n.createdAt)
        let key = "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
        if byKey[key] == nil {
            byKey[key] = (label: notificationDayLabel(n.createdAt, lang: lang), items: [])
            order.append(key)
        }
        byKey[key]?.items.append(n)
    }
    return order.map { key in
        let entry = byKey[key]!
        return NotificationDayGroup(id: key, label: entry.label, items: entry.items)
    }
}

/// Collapses whole day-groups at a time, never mid-day — accumulates full
/// days until adding the next one would cross `limit` total items, then
/// cuts there. The first day is always kept in full even if it alone
/// exceeds `limit` (a single very active day still isn't split in half).
func collapseDayGroups(_ dayGroups: [NotificationDayGroup], limit: Int) -> (visible: [NotificationDayGroup], hidden: [NotificationDayGroup]) {
    var count = 0
    var cutIndex = dayGroups.count
    for i in dayGroups.indices {
        if count > 0 && count + dayGroups[i].items.count > limit { cutIndex = i; break }
        count += dayGroups[i].items.count
        if count >= limit { cutIndex = i + 1; break }
    }
    return (Array(dayGroups.prefix(cutIndex)), Array(dayGroups.suffix(from: cutIndex)))
}
