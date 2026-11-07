import Foundation

/// Event Project Hub, team channels (note 76): up to 5 external links (Zoom, Meet, Zalo…) the Host adds so the team
/// can talk outside banbe. Web twin: src/lib/projectChannels.js. Shared vectors: tests/fixtures/project-channel-links.json
/// (also run against sanitize_project_channels in SQL, migration 210).
///
/// Same URL rule as sanitize_social_links (migration 102:43): https only, a real host name, nothing else in the host
/// part (no port, no user@). Stricter than 102 on platforms: the host must BE the platform domain or a subdomain of
/// it. One bad entry rejects the whole list, like the server. Lengths count Unicode scalars, like JS and Postgres.
enum ProjectChannels {
    struct Channel: Equatable, Codable {
        var platform: String
        var label: String
        var url: String
        var primary: Bool
    }

    enum Failure: String, Error, Equatable { case url, platform, label, list, count, primary, duplicate }

    /// Platform -> accepted domains, in the order the picker lists them. `link` takes any https host.
    static let platforms: [(id: String, domains: [String])] = [
        ("zoom", ["zoom.us"]),
        ("meet", ["meet.google.com"]),
        ("zalo", ["zalo.me"]),
        ("messenger", ["m.me", "messenger.com"]),
        ("whatsapp", ["chat.whatsapp.com", "wa.me"]),
        ("telegram", ["t.me"]),
        ("discord", ["discord.gg", "discord.com"]),
        ("teams", ["teams.microsoft.com", "teams.live.com"]),
        ("slack", ["slack.com"]),
        ("link", []),
    ]

    /// Display names (product names, shown as text; never logos). `link` is translated by the caller.
    static let names: [String: String] = [
        "zoom": "Zoom", "meet": "Google Meet", "zalo": "Zalo", "messenger": "Messenger", "whatsapp": "WhatsApp",
        "telegram": "Telegram", "discord": "Discord", "teams": "Microsoft Teams", "slack": "Slack",
    ]

    private static let urlRegex = try! NSRegularExpression(
        pattern: #"^https://[a-z0-9]([a-z0-9.-]*[a-z0-9])?\.[a-z]{2,}(/.*)?(\?.*)?$"#, options: [.caseInsensitive])
    private static let badChars = try! NSRegularExpression(pattern: #"[\s\x{0000}-\x{001f}\x{007f}]"#)

    private static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    /// Lower-cased host of an https URL that passes the URL rule, else nil.
    static func host(of url: String) -> String? {
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty, u.unicodeScalars.count <= ProjectLimits.shared.channelUrlMax,
              !matches(badChars, u), matches(urlRegex, u) else { return nil }
        let rest = u.dropFirst("https://".count)
        return String(rest.prefix { $0 != "/" && $0 != "?" && $0 != "#" }).lowercased()
    }

    private static func hostMatches(_ host: String, _ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }

    /// The platform a pasted URL belongs to ("link" for any other valid https URL), or nil when the URL is invalid.
    static func detectPlatform(_ url: String) -> String? {
        guard let h = host(of: url) else { return nil }
        return platforms.first { $0.domains.contains { hostMatches(h, $0) } }?.id ?? "link"
    }

    /// One channel. An empty label becomes the platform name (or "" for `link`; the caller shows its translated "Link").
    static func validate(platform rawPlatform: String?, label rawLabel: String?, url rawURL: String?, primary: Bool) -> Result<Channel, Failure> {
        let url = (rawURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let h = host(of: url) else { return .failure(.url) }
        let given = (rawPlatform ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let platform = given.isEmpty ? detectPlatform(url) : given,
              let entry = platforms.first(where: { $0.id == platform }) else { return .failure(.platform) }
        if !entry.domains.isEmpty && !entry.domains.contains(where: { hostMatches(h, $0) }) { return .failure(.platform) }
        let trimmed = (rawLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let label = trimmed.isEmpty ? (names[platform] ?? "") : trimmed
        guard label.unicodeScalars.count <= ProjectLimits.shared.channelLabelMax else { return .failure(.label) }
        return .success(Channel(platform: platform, label: label, url: url, primary: primary))
    }

    /// The whole list: same verdict as the server's sanitize_project_channels. `index` is the failing entry, or -1.
    static func sanitize(_ list: [(platform: String?, label: String?, url: String?, primary: Bool)]) -> Result<[Channel], ListFailure> {
        guard list.count <= ProjectLimits.shared.channelsMax else { return .failure(ListFailure(error: .count, index: -1)) }
        var out: [Channel] = []
        for (i, raw) in list.enumerated() {
            switch validate(platform: raw.platform, label: raw.label, url: raw.url, primary: raw.primary) {
            case .failure(let f): return .failure(ListFailure(error: f, index: i))
            case .success(let c):
                if out.contains(where: { $0.url.lowercased() == c.url.lowercased() }) {
                    return .failure(ListFailure(error: .duplicate, index: i))
                }
                out.append(c)
            }
        }
        if out.filter(\.primary).count > 1 { return .failure(ListFailure(error: .primary, index: -1)) }
        return .success(out)
    }

    struct ListFailure: Error, Equatable { let error: Failure; let index: Int }

    /// Display order: the starred channel first, the rest as the Host ordered them.
    static func ordered(_ channels: [Channel]) -> [Channel] { channels.filter(\.primary) + channels.filter { !$0.primary } }
}
