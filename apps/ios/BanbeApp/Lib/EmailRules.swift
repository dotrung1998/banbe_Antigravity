import Foundation

/// One email rule for Login and Sign up. The old check (x@y.z) let "ban@gmail.c" and "ban@gmail.co" through, so the
/// person only found out when the code never arrived.
/// - Format: a real-looking domain whose last part is 2+ letters (or punycode).
/// - Typos of the big mailbox providers ("gmail.co", "gmial.com", "yahoo.con") are refused with a one-tap
///   suggestion: those domains never receive mail.
/// Twin: src/lib/emailRules.js (same lists, same results; cases in tests/unit/emailRules.test.mjs).
enum EmailRules {
    private static let format =
        #"^[^\s@.]+(?:\.[^\s@.]+)*@(?:[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?\.)+(?:[A-Za-z]{2,}|[Xx][Nn]--[A-Za-z0-9-]+)$"#

    private static let providers: Set<String> = ["gmail", "yahoo", "hotmail", "outlook", "icloud"]
    private static let nameTypos: [String: String] = [
        "gmial": "gmail", "gmal": "gmail", "gmai": "gmail", "gamil": "gmail", "gnail": "gmail", "gmaill": "gmail",
        "gmali": "gmail", "gmil": "gmail", "gmsil": "gmail",
        "yaho": "yahoo", "yahooo": "yahoo", "yhoo": "yahoo",
        "hotmal": "hotmail", "hotmial": "hotmail", "hotmai": "hotmail", "homail": "hotmail",
        "outlok": "outlook", "outloo": "outlook", "oulook": "outlook",
        "iclod": "icloud", "icoud": "icloud", "iclould": "icloud",
    ]
    private static let comTypos: Set<String> = ["c", "co", "cm", "om", "con", "cmo", "comm", "vom", "xom", "cpm", "coom"]

    /// The corrected address when the domain is a known typo, else nil.
    static func typoSuggestion(_ value: String) -> String? {
        let email = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let at = email.lastIndex(of: "@"), at > email.startIndex else { return nil }
        let local = String(email[..<at])
        let domain = email[email.index(after: at)...].lowercased()
        let parts = domain.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, !parts[1].isEmpty else { return nil }
        let fixedName = nameTypos[parts[0]] ?? parts[0]
        guard providers.contains(fixedName) else { return nil }
        let tld = parts[1]
        let fixedTld: String? = tld == "com" || comTypos.contains(tld) ? "com" : (fixedName == "gmail" ? "com" : nil)
        guard let tldOut = fixedTld else { return nil }
        let fixed = "\(fixedName).\(tldOut)"
        return fixed == domain ? nil : "\(local)@\(fixed)"
    }

    static func formatValid(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).range(of: format, options: .regularExpression) != nil
    }

    /// Accepts an address only when its format is right and its domain is not a known typo.
    static func isValid(_ value: String) -> Bool { formatValid(value) && typoSuggestion(value) == nil }
}
