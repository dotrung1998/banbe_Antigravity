import Foundation

/// Runtime config for the Supabase + Cloudflare R2 hybrid public-media path
/// (.claude/notes/28-r2-hybrid-media.md). Both values default to empty/off in
/// Info.plist, so with no configuration every resolver call returns the
/// legacy Supabase URL and the app behaves exactly as before.
struct MediaConfig: Equatable {
    var publicBaseURL: String
    var readsEnabled: Bool

    /// Live config, read once from Info.plist (`MEDIA_PUBLIC_BASE_URL`,
    /// `MEDIA_R2_READS` == "1"). Tests build their own `MediaConfig`.
    static let current: MediaConfig = {
        let info = Bundle.main.infoDictionary ?? [:]
        let base = (info["MEDIA_PUBLIC_BASE_URL"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let reads = (info["MEDIA_R2_READS"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) == "1"
        return MediaConfig(publicBaseURL: base, readsEnabled: reads)
    }()

    /// Base URL without trailing slashes, only if it is a valid https URL.
    var normalizedBase: String? {
        var s = publicBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        guard !s.isEmpty, let u = URL(string: s), u.scheme == "https", u.host != nil else { return nil }
        return s
    }

    var host: String? { normalizedBase.flatMap { URL(string: $0)?.host?.lowercased() } }
}

enum MediaVariant: String { case thumb, card, full }

/// Pure resolver: `r2:<scope>/<assetId>.<ext>` -> public CDN URL.
enum MediaResolver {

    struct ParsedRef: Equatable {
        let scope: String
        let assetId: String
        let ext: String
    }

    // scope = ev-/org- + safe chars; assetId = UUID; ext = jpg|jpeg|png|webp
    private static let refRegex = try! NSRegularExpression(
        pattern: "^r2:((?:ev|org)-[A-Za-z0-9_-]{1,100})/([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\\.(jpg|jpeg|png|webp)$")

    static func parse(_ ref: String?) -> ParsedRef? {
        guard let ref, ref.utf8.count <= 256 else { return nil }
        let range = NSRange(ref.startIndex..., in: ref)
        guard let m = refRegex.firstMatch(in: ref, range: range), m.numberOfRanges == 4,
              let r1 = Range(m.range(at: 1), in: ref),
              let r2 = Range(m.range(at: 2), in: ref),
              let r3 = Range(m.range(at: 3), in: ref) else { return nil }
        return ParsedRef(scope: String(ref[r1]), assetId: String(ref[r2]).lowercased(), ext: String(ref[r3]))
    }

    static func variantURL(ref: String?, variant: MediaVariant, config: MediaConfig = .current) -> URL? {
        guard let base = config.normalizedBase, let p = parse(ref) else { return nil }
        return URL(string: "\(base)/v1/\(p.scope)/\(p.assetId)/\(variant.rawValue).\(p.ext)")
    }

    /// R2 URL only when reads are enabled, the base URL is set and the ref
    /// parses; otherwise the legacy URL (instant rollback via the flag).
    static func resolve(r2Ref: String?, legacyURL: URL?, variant: MediaVariant, config: MediaConfig = .current) -> URL? {
        guard config.readsEnabled, let url = variantURL(ref: r2Ref, variant: variant, config: config) else { return legacyURL }
        return url
    }

    /// True when `ref` is an R2 ref (even if reads are off); used to skip
    /// Supabase Storage removal for assets that live in R2.
    static func isR2Ref(_ s: String?) -> Bool { parse(s) != nil }
}

/// Builds display URLs for public event photos / organizer avatars, preferring
/// the R2 variant when enabled. `storagePath` / `avatarPath` may themselves be
/// an `r2:` ref (brand-new R2-only uploads write the ref into the legacy
/// column too); in that case there is no Supabase object to fall back to.
enum MediaURLs {
    static func eventPhoto(storagePath: String, r2Ref: String?, variant: MediaVariant) -> URL? {
        let pathIsRef = MediaResolver.isR2Ref(storagePath)
        var legacy: URL?
        if !pathIsRef {
            let rel = storagePath.hasPrefix("event-photos/") ? String(storagePath.dropFirst("event-photos/".count)) : storagePath
            legacy = try? SupabaseService.client.storage.from("event-photos").getPublicURL(path: rel)
        }
        return MediaResolver.resolve(r2Ref: r2Ref ?? (pathIsRef ? storagePath : nil), legacyURL: legacy, variant: variant)
    }

    static func organizerAvatar(path: String?, r2Ref: String?, variant: MediaVariant) -> URL? {
        let p = (path?.isEmpty == false) ? path : nil
        let pathIsRef = MediaResolver.isR2Ref(p)
        var legacy: URL?
        if let p, !pathIsRef {
            legacy = try? SupabaseService.client.storage.from("organizer-photos").getPublicURL(path: p)
        }
        return MediaResolver.resolve(r2Ref: r2Ref ?? (pathIsRef ? p : nil), legacyURL: legacy, variant: variant)
    }
}

/// The `*_r2_ref` columns only exist after migration 153. Selects include
/// them optimistically; on an undefined-column error the query is retried
/// once without them and the app remembers for the rest of the session.
enum MediaColumns {
    private static let lock = NSLock()
    private static var _missing = false
    static var missing: Bool { lock.lock(); defer { lock.unlock() }; return _missing }

    static func markMissing() { lock.lock(); _missing = true; lock.unlock() }

    static func cols(_ base: String, _ extra: String, _ withR2: Bool) -> String {
        withR2 ? base + ", " + extra : base
    }

    static func isUndefinedColumn(_ error: Error) -> Bool {
        let s = String(describing: error).lowercased()
        return s.contains("42703") || (s.contains("r2_ref") && (s.contains("does not exist") || s.contains("could not find")))
    }

    static func retrying<T>(_ body: (_ withR2: Bool) async throws -> T) async throws -> T {
        if missing { return try await body(false) }
        do { return try await body(true) } catch {
            guard isUndefinedColumn(error) else { throw error }
            markMissing()
            return try await body(false)
        }
    }
}
