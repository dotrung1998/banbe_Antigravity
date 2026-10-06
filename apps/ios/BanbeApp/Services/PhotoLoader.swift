import UIKit
import ImageIO

/// Loads catalogue photos, with three things AsyncImage doesn't do:
///
/// 1. Asks for the WebP derivative (public/photos/optimized, produced by
///    Tools/optimize-photos.sh) and falls back to the original JPEG if it
///    isn't deployed yet — same pixels, about a quarter of the bytes.
/// 2. Downsamples while decoding, so a 52pt avatar doesn't decode a
///    1000px image into memory at full size.
/// 3. Keeps decoded images in memory and raw responses on disk, and does
///    not re-validate on every scroll: these files never change under a
///    given name, but the host sends `must-revalidate`, which otherwise
///    costs a round trip per image every single time.
enum PhotoLoader {

    private static let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 64 * 1024 * 1024   // ~64MB of decoded pixels
        return cache
    }()

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 16 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            diskPath: "banbe.photos"
        )
        // The photos are immutable per filename, so a cached copy is always
        // good; this is what turns a second launch into an instant feed.
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.protocolClasses = [StorageImageCache.self] + (configuration.protocolClasses ?? [])
        return URLSession(configuration: configuration)
    }()

    /// Synchronous memory-cache peek, so an already-loaded photo paints on
    /// the first frame instead of flashing its placeholder again.
    static func cached(path: String, maxPixel: CGFloat) -> UIImage? {
        memory.object(forKey: key(path, maxPixel) as NSString)
    }

    /// In-flight loads keyed the same way as `memory`, so two callers racing
    /// for the same (path, maxPixel) — e.g. a list cell and its preload —
    /// share one network fetch instead of each downloading it separately.
    /// Actor-isolated since it's mutated from concurrent `load` callers.
    private actor InFlight {
        static let shared = InFlight()
        private var tasks: [String: Task<UIImage?, Never>] = [:]

        func run(_ key: String, _ work: @escaping () async -> UIImage?) async -> UIImage? {
            if let existing = tasks[key] { return await existing.value }
            let task = Task { await work() }
            tasks[key] = task
            let result = await task.value
            tasks[key] = nil
            return result
        }
    }

    static func load(path: String, maxPixel: CGFloat) async -> UIImage? {
        let cacheKey = key(path, maxPixel)
        if let hit = memory.object(forKey: cacheKey as NSString) { return hit }

        return await InFlight.shared.run(cacheKey) {
            if let hit = memory.object(forKey: cacheKey as NSString) { return hit }

            // STAGE B (2026-09-25) — a real event_photos row's storage_path,
            // already resolved to a full Supabase Storage public URL by the
            // caller (OrganizerView's real photo library), is NOT one of this
            // catalogue's own bundled/optimized assets — skip straight to a
            // plain fetch of that exact URL. Any relative catalogue path (the
            // overwhelmingly common case, e.g. "/photos/DSCF4423.jpg") is
            // unaffected, unchanged from before.
            let data: Data?
            if path.hasPrefix("http://") || path.hasPrefix("https://") {
                data = await fetchAbsolute(path)
            } else if let bundled = bundledData(for: path) {
                data = bundled
            } else {
                data = await fetch(path: path)
            }
            guard let data, let image = downsample(data, maxPixel: maxPixel) else { return nil }

            let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
            memory.setObject(image, forKey: cacheKey as NSString, cost: cost)
            return image
        }
    }

    /// Drops every decoded image and raw HTTP response this process has
    /// cached — used by sign-out (private media must not survive an account
    /// switch on a shared device) and the Settings "Clear Image Cache"
    /// action. Does not touch any other persisted state (drafts, sessions,
    /// tickets, …) — those live elsewhere entirely.
    static func clearCache() {
        memory.removeAllObjects()
        StorageImageCache.clear()
        session.configuration.urlCache?.removeAllCachedResponses()
    }

    /// "/photos/DSCF4423.jpg" -> the bundled optimized/DSCF4423.webp.
    private static func bundledData(for path: String) -> Data? {
        let base = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        guard !base.isEmpty else { return nil }
        guard let url = Bundle.main.url(forResource: base, withExtension: "webp", subdirectory: "optimized")
                ?? Bundle.main.url(forResource: base, withExtension: "webp")
        else { return nil }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }

    /// STAGE B (2026-09-25) — a real, already-absolute Storage URL, no
    /// optimized/bundled derivative to try first (there isn't one).
    private static func fetchAbsolute(_ urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) { return nil }
            return data.isEmpty ? nil : data
        } catch {
            return nil
        }
    }

    /// Optimized derivative first, original as the fallback.
    private static func fetch(path: String) async -> Data? {
        for candidate in [optimizedURL(for: path), CatalogEvent.photoURL(path)].compactMap({ $0 }) {
            do {
                let (data, response) = try await session.data(from: candidate)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    continue
                }
                if !data.isEmpty { return data }
            } catch {
                continue
            }
        }
        return nil
    }

    /// "/photos/DSCF4423.jpg" -> ".../photos/optimized/DSCF4423.webp"
    private static func optimizedURL(for path: String) -> URL? {
        let name = (path as NSString).lastPathComponent
        let base = (name as NSString).deletingPathExtension
        guard !base.isEmpty else { return nil }
        return URL(string: AppConfig.apiBaseURL + "/photos/optimized/" + base + ".webp")
    }

    private static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixel, 1),
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Strips a signed Storage URL's query string (the token + expiry that
    /// rotate on every re-sign, even though the underlying object hasn't
    /// changed — web/BanBeContext.jsx re-signs on a 10min-1h TTL) so the
    /// identity used for both caches is the stable bucket/object path, not
    /// a value that churns on a timer. Safe because every upload in this
    /// app writes a brand-new, timestamped path (`Date.now()`-based) rather
    /// than overwriting an existing one — see
    /// .claude/notes/22-supabase-bandwidth-optimization.md — so a path
    /// alone is already a correct "this exact content" identity; re-signing
    /// never changes it, and an edited photo always gets a different path.
    private static func key(_ path: String, _ maxPixel: CGFloat) -> String {
        let stable = path.hasPrefix("http://") || path.hasPrefix("https://")
            ? (URLComponents(string: path).map { c -> String in
                var c2 = c
                c2.query = nil
                return c2.string ?? path
              } ?? path)
            : path
        return "\(stable)@\(Int(maxPixel))"
    }
}
