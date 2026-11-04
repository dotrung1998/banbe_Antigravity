import Foundation

/// Event Project Hub invites (note 76): what a scanned QR, a pasted link or a typed code points at.
/// Web twin: src/lib/projectInviteLink.js. Shared vectors: tests/fixtures/project-invite-links.json.
///
/// The link only ever carries an opaque value. The role and lane live with the invite on the server, so editing a link
/// can never change them. Two forms:
/// - token: 22 URL-safe base64 characters (128 random bits), used in links and QR codes;
/// - code: "BB-" + 4 characters from a 31-symbol alphabet with no 0/O/1/I/L, for typing by hand.
/// Links: https://www.banbe.app/join/<value>, https://banbe.app/join/<value> and banbe://join/<value>, where value is a
/// token or a code. This is not the referral link (https://www.banbe.app/?ref=CODE), which stays separate.
enum ProjectInviteLink {
    enum Invite: Equatable {
        case token(String)
        case code(String)
    }

    static let codeAlphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
    static let joinURLBase = "https://www.banbe.app/join/"

    private static func re(_ p: String, _ o: NSRegularExpression.Options = []) -> NSRegularExpression { try! NSRegularExpression(pattern: p, options: o) }
    private static let tokenRe = re(#"^[A-Za-z0-9_-]{22}$"#)
    private static let codeBodyRe = re("^[\(codeAlphabet)]{4}$")
    private static let webRe = re(#"^https://(?:www\.)?banbe\.app/join/([^/?#]+)/?(?:[?#].*)?$"#, .caseInsensitive)
    private static let appRe = re(#"^banbe://join/([^/?#]+)/?(?:[?#].*)?$"#, .caseInsensitive)
    private static let schemeRe = re(#"^[a-z][a-z0-9+.-]*:"#, .caseInsensitive)

    private static func full(_ r: NSRegularExpression, _ s: String) -> Bool { r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil }
    private static func capture(_ r: NSRegularExpression, _ s: String) -> String? {
        guard let m = r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), let g = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[g])
    }

    /// "bb h3qd", "BB–H3QD", "bbh3qd" or "h3qd" -> "BB-H3QD"; nil when it is not a valid code.
    static func normalizeCode(_ input: String) -> String? {
        let dashes: ClosedRange<UInt32> = 0x2010...0x2015
        var s = String(String.UnicodeScalarView(input.uppercased().unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0) && $0 != "-" && !dashes.contains($0.value)
        }))
        if s.hasPrefix("BB") && s.count == 6 { s = String(s.dropFirst(2)) }
        return full(codeBodyRe, s) ? "BB-\(s)" : nil
    }

    private static func value(_ raw: String) -> Invite? {
        guard let v = raw.removingPercentEncoding else { return nil }
        if full(tokenRe, v) { return .token(v) }
        return normalizeCode(v).map(Invite.code)
    }

    /// A join link, a bare token or a typed code.
    static func parse(_ input: String) -> Invite? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if let v = capture(webRe, s) ?? capture(appRe, s) { return value(v) }
        if full(schemeRe, s) { return nil } // some other link: never guess
        return value(s)
    }

    /// Only the link forms (https://(www.)banbe.app/join/…, banbe://join/…): what a QR scanner may treat as an invite.
    /// A bare token or code is nil here, so a ticket QR (a booking id) can never be read as one.
    static func joinLink(_ input: String) -> Invite? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return (capture(webRe, s) ?? capture(appRe, s)).flatMap(value)
    }

    /// The shareable link (and QR content) for a token; nil for anything that is not a token.
    static func joinURL(token: String) -> String? { full(tokenRe, token) ? joinURLBase + token : nil }
}
