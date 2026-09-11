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
        return URLSession(configuration: configuration)
    }()

    /// Synchronous memory-cache peek, so an already-loaded photo paints on
    /// the first frame instead of flashing its placeholder again.
    static func cached(path: String, maxPixel: CGFloat) -> UIImage? {
        memory.object(forKey: key(path, maxPixel) as NSString)
    }

    static func load(path: String, maxPixel: CGFloat) async -> UIImage? {
        let cacheKey = key(path, maxPixel) as NSString
        if let hit = memory.object(forKey: cacheKey) { return hit }

        // The catalogue's own photos ship in the bundle, so the common case
        // never touches the network at all. Anything else (a future
        // user-uploaded photo from storage) falls through to fetch().
        let data: Data?
        if let bundled = bundledData(for: path) {
            data = bundled
        } else {
            data = await fetch(path: path)
        }
        guard let data, let image = downsample(data, maxPixel: maxPixel) else { return nil }

        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        memory.setObject(image, forKey: cacheKey, cost: cost)
        return image
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

    private static func key(_ path: String, _ maxPixel: CGFloat) -> String {
        "\(path)@\(Int(maxPixel))"
    }
}
