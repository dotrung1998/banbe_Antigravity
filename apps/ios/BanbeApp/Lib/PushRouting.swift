import Foundation

/// A tapped APNs push → the same `AppNotification` the bell list holds, so a push tap routes through the existing
/// `openNotification(_:)` exactly like a bell tap. Payload contract (api/_lib push sender, migration 194):
/// `{"aps":{"alert":{"title":T,"body":B},"sound":"default","badge":N,"thread-id":KIND},
///   "nid":"<notifications.id>","kind":"<kind>","data":{…notifications.data…}}` — title/body already localized.
/// Pure: no UIKit, no AppState.
enum PushRouting {
    /// nil when the payload isn't one of ours (no valid `nid` uuid or no `kind`). `title`/`body` fall back to what
    /// the system parsed (UNNotificationContent) when `aps.alert` is a plain string or missing.
    static func notification(from userInfo: [AnyHashable: Any], title fallbackTitle: String = "", body fallbackBody: String = "",
                             recipientID: UUID?, now: Date = Date()) -> AppNotification? {
        guard let nid = (userInfo["nid"] as? String).flatMap(UUID.init(uuidString:)),
              let kind = userInfo["kind"] as? String, !kind.isEmpty else { return nil }
        let aps = userInfo["aps"] as? [AnyHashable: Any]
        let alert = aps?["alert"] as? [AnyHashable: Any]
        let title = (alert?["title"] as? String) ?? fallbackTitle
        let body = (alert?["body"] as? String) ?? (aps?["alert"] as? String) ?? fallbackBody
        var data: [String: AnyCodableValue] = [:]
        if let raw = userInfo["data"] as? [AnyHashable: Any] {
            for (k, v) in raw { if let key = k as? String { data[key] = value(v) } }
        }
        return AppNotification(id: nid, recipientId: recipientID ?? UUID(), kind: kind, title: title, body: body,
                               data: data, readAt: nil, createdAt: now)
    }

    /// Phase 2-3 kinds (event reminders, recaps, follow alerts, the weekly digest): where a tapped push lands, the same
    /// table a bell tap uses (`openNotification(_:)` → `CoreLoops.route`, shared with web via
    /// tests/fixtures/core-loops.json). nil for every other kind.
    static func coreLoopDestination(_ notification: AppNotification) -> CoreLoops.Destination? {
        CoreLoops.route(kind: notification.kind, data: notification.data)
    }

    /// One JSON value the way `AnyCodableValue`'s decoder would read it (nested objects/arrays → `.null`, same as
    /// decoding the jsonb column). APNs hands over Foundation types: NSString, NSNumber (incl. booleans), NSNull.
    static func value(_ any: Any) -> AnyCodableValue {
        if let s = any as? String { return .string(s) }
        if let n = any as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            if CFNumberIsFloatType(n) {
                let d = n.doubleValue
                return d == d.rounded() && abs(d) < 9e15 ? .int(Int(d)) : .double(d)
            }
            return .int(n.intValue)
        }
        return .null
    }
}
