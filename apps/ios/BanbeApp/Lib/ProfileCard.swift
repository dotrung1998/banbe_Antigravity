import SwiftUI

/// The personal profile identity card (note 68): one role line, de-duplicated chips, the stats strip, the Upcoming
/// list and the card surface. Pure logic, port of src/lib/profileCard.js through the shared
/// tests/fixtures/profile-card.json (tests: ProfileCardTests.swift and tests/unit/profileCard.test.mjs) — change both
/// together. The admin role is never shown here: this page is public (get_public_profile has an anon grant).
enum ProfileCard {
    /// "Host · Founder of Bếp Nhỏ" while this profile owns an organizer AND organizer mode is on, else "Member".
    static func roleLabel(organizerName: String?, organizerMode: Bool, vi: Bool) -> String {
        if let name = organizerName, !name.isEmpty, organizerMode {
            return vi ? "Host · Founder tổ chức \(name)" : "Host · Founder of \(name)"
        }
        return vi ? "Thành viên" : "Member"
    }

    private static func norm(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    /// Interest chips with repeats and anything already said on the card removed (regression: banbetestadmin's
    /// interests are ["Admin", "Admin"], shown as two identical chips). Keeps the first of any repeat.
    static func dedupeChips(_ chips: [String], alreadyShown: [String?]) -> [String] {
        var seen = Set(alreadyShown.map(norm).filter { !$0.isEmpty })
        var out: [String] = []
        for c in chips {
            let k = norm(c)
            if k.isEmpty || seen.contains(k) { continue }
            seen.insert(k)
            out.append(c)
        }
        return out
    }

    struct Stat: Equatable { let id: String; let value: Int }

    /// The stats strip inside the card, or [] when fewer than two would show. Public numbers only for visitors (a
    /// host's events and followers); the owner also sees their own badges (Rewards switch on) and upcoming count.
    static func stats(eventCount: Int?, followerCount: Int?, hostingSinceYear: Int?, isHost: Bool, isOwner: Bool,
                      rewardsOn: Bool, badgeCount: Int?, upcomingCount: Int?) -> [Stat] {
        var out: [Stat] = []
        if isHost {
            out.append(Stat(id: "hosted", value: eventCount ?? 0))
            out.append(Stat(id: "followers", value: followerCount ?? 0))
        }
        if isOwner, let upcomingCount, !isHost { out.append(Stat(id: "upcoming", value: upcomingCount)) }
        if isOwner, rewardsOn, let badgeCount { out.append(Stat(id: "badges", value: badgeCount)) }
        else if isHost, let year = hostingSinceYear { out.append(Stat(id: "since", value: year)) }
        return out.count >= 2 ? Array(out.prefix(3)) : []
    }

    struct UpcomingInput: Equatable {
        let key: String
        let name: String
        let organizerId: String?
        let start: Double?
        let ended: Bool
        let cancelled: Bool
    }

    struct Upcoming: Equatable {
        let event: UpcomingInput
        /// "hosting" or "going".
        let role: String
    }

    /// This profile's own hosted events still ahead (public), plus — for the owner only — the events they are going
    /// to. Never another person's bookings. Sorted by start (unknown last), at most `limit`.
    static func upcoming(_ events: [UpcomingInput], organizerId: String?, organizerMode: Bool, isOwner: Bool,
                         goingKeys: [String], limit: Int = 5) -> [Upcoming] {
        let going = Set(isOwner ? goingKeys : [])
        var out: [Upcoming] = []
        for e in events where !e.ended && !e.cancelled {
            if let organizerId, organizerMode, e.organizerId == organizerId { out.append(Upcoming(event: e, role: "hosting")) }
            else if going.contains(e.key) { out.append(Upcoming(event: e, role: "going")) }
        }
        let sorted = out.enumerated().sorted { a, b in
            let x = a.element.event.start ?? .infinity, y = b.element.event.start ?? .infinity
            return x == y ? a.offset < b.offset : x < y
        }.map(\.element)
        return Array(sorted.prefix(limit))
    }

    /// The card surface: the theme's surface2, the person's palette colour as a light tint, and a soft clay glow in the
    /// charm's corner (contrast-tested against every palette in both themes).
    static let tint: Double = 0.18
    static let glow: Double = 0.1
}
