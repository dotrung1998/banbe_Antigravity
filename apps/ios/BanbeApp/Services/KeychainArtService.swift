import UIKit
import ImageIO
import UniformTypeIdentifiers
import Supabase

/// Custom keychain art: local validation + re-encode (pure, testable) and the
/// contract upload flow (`/api/media` keychain_init -> signed upload ->
/// keychain_finalize). No remote URL is ever fetched from user input and SVG
/// is never accepted — only PNG/WebP by MAGIC BYTES (extension/UTType ignored).
enum KeychainArtError: Error, Equatable {
    case unsupportedType, fileTooLarge, decodeFailed, animated, badDimensions
    case tooLargeAfterEncode, quotaExceeded, rateLimited, notSignedIn, network, server

    func message(_ T: (String, String) -> String) -> String {
        switch self {
        case .unsupportedType: return T("Chỉ hỗ trợ ảnh PNG hoặc WebP (không nhận SVG, GIF, HEIC).", "Only PNG or WebP images are supported (no SVG, GIF or HEIC).")
        case .fileTooLarge: return T("Tệp quá lớn. Hãy chọn ảnh nhỏ hơn 12 MB.", "That file is too large. Pick an image under 12 MB.")
        case .decodeFailed: return T("Không đọc được ảnh này.", "That image couldn't be read.")
        case .animated: return T("Ảnh động không được hỗ trợ.", "Animated images aren't supported.")
        case .badDimensions: return T("Kích thước ảnh không hợp lệ.", "That image size isn't valid.")
        case .tooLargeAfterEncode: return T("Ảnh vẫn quá nặng (tối đa 256 KB) sau khi thu nhỏ.", "The image is still over 256 KB after resizing.")
        case .quotaExceeded: return T("Bạn đã đạt giới hạn ảnh tuỳ chỉnh. Hãy xoá ảnh cũ rồi thử lại.", "You've reached the custom art limit. Remove an old one and try again.")
        case .rateLimited: return T("Bạn thao tác quá nhanh. Vui lòng thử lại sau ít phút.", "You're going too fast. Please try again in a few minutes.")
        case .notSignedIn: return T("Hãy đăng nhập để tải ảnh lên.", "Sign in to upload art.")
        case .network: return T("Lỗi mạng. Vui lòng thử lại.", "Network problem. Please try again.")
        case .server: return T("Không thể xử lý ảnh trên máy chủ. Hãy thử ảnh khác.", "The server couldn't process that image. Try another one.")
        }
    }
}

struct KeychainPreparedArt: Equatable {
    var data: Data
    var width: Int
    var height: Int
    var contentType: String { "image/png" }
}

enum KeychainArtValidator {
    static let maxInputBytes = 12 * 1024 * 1024
    static let maxOutputBytes = 256 * 1024
    static let maxLongEdge = 512
    /// Source pixels guard (decompression bomb).
    static let maxSourceSide = 8192
    static let allowedTypes: [UTType] = [.png, .webP]

    enum Sniffed { case png, webp }

    static func sniff(_ d: Data) -> Sniffed? {
        let b = [UInt8](d.prefix(12))
        if b.count >= 8, Array(b[0..<8]) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] { return .png }
        if b.count >= 12, Array(b[0..<4]) == [0x52, 0x49, 0x46, 0x46], Array(b[8..<12]) == [0x57, 0x45, 0x42, 0x50] { return .webp }
        return nil
    }

    /// Validate + downscale + re-encode to a metadata-free PNG (<= 256 KB, long edge <= 512).
    static func prepare(_ input: Data) throws -> KeychainPreparedArt {
        guard input.count <= maxInputBytes else { throw KeychainArtError.fileTooLarge }
        guard sniff(input) != nil else { throw KeychainArtError.unsupportedType }
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(input as CFData, opts) else { throw KeychainArtError.decodeFailed }
        guard CGImageSourceGetCount(src) == 1 else { throw KeychainArtError.animated }
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, opts) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int
        else { throw KeychainArtError.decodeFailed }
        guard w > 0, h > 0, w <= maxSourceSide, h <= maxSourceSide else { throw KeychainArtError.badDimensions }

        var edge = min(maxLongEdge, max(w, h))
        while edge >= 128 {
            let thumbOpts = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: edge,
            ] as CFDictionary
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts) else { throw KeychainArtError.decodeFailed }
            let out = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { throw KeychainArtError.decodeFailed }
            CGImageDestinationAddImage(dest, cg, nil)          // nil properties: no EXIF/GPS/ICC text
            guard CGImageDestinationFinalize(dest) else { throw KeychainArtError.decodeFailed }
            if out.length <= maxOutputBytes {
                return KeychainPreparedArt(data: out as Data, width: cg.width, height: cg.height)
            }
            edge = Int(Double(edge) * 0.8)
        }
        throw KeychainArtError.tooLargeAfterEncode
    }

    /// Reads a fileImporter URL (security scoped) with a hard byte cap, then prepares it.
    static func prepare(fileURL: URL) throws -> KeychainPreparedArt {
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
        guard fileURL.isFileURL, let handle = try? FileHandle(forReadingFrom: fileURL) else { throw KeychainArtError.decodeFailed }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: maxInputBytes + 1)) ?? Data()
        return try prepare(data)
    }
}

struct KeychainUploadedAsset: Equatable { let assetId: String; let path: String; let width: Int; let height: Int }

enum KeychainArtService {
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil
        c.timeoutIntervalForRequest = 45
        return URLSession(configuration: c)
    }()

    static func map(status: Int, error: String?) -> KeychainArtError {
        let e = (error ?? "").lowercased()
        if status == 401 { return .notSignedIn }
        if status == 429 || e.contains("rate") { return .rateLimited }
        if e.contains("quota") || e.contains("limit") || status == 409 { return .quotaExceeded }
        if status == 0 { return .network }
        return .server
    }

    private static func post(_ body: [String: Any]) async throws -> [String: Any] {
        guard let token = try? await SupabaseService.client.auth.session.accessToken else { throw KeychainArtError.notSignedIn }
        guard let url = URL(string: AppConfig.apiBaseURL + "/api/media") else { throw KeychainArtError.network }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data, resp: URLResponse
        do { (data, resp) = try await session.data(for: req) } catch { throw KeychainArtError.network }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status) else {
            throw map(status: status, error: (json["error"] as? String) ?? (json["code"] as? String))
        }
        return json
    }

    /// init -> signed upload -> finalize. Does NOT save the keychain config.
    static func upload(_ art: KeychainPreparedArt) async throws -> KeychainUploadedAsset {
        let initRes = try await post(["op": "keychain_init", "contentType": art.contentType, "bytes": art.data.count])
        guard let assetId = initRes["assetId"] as? String, let path = initRes["path"] as? String,
              let token = initRes["token"] as? String else { throw KeychainArtError.server }
        do {
            try await SupabaseService.client.storage.from("keychain-art")
                .uploadToSignedURL(path, token: token, data: art.data, options: FileOptions(contentType: art.contentType, upsert: true))
        } catch {
            _ = try? await post(["op": "keychain_delete", "assetId": assetId])   // best-effort cleanup
            throw KeychainArtError.network
        }
        let fin = try await post(["op": "keychain_finalize", "assetId": assetId])
        return KeychainUploadedAsset(assetId: (fin["assetId"] as? String) ?? assetId,
                                     path: (fin["path"] as? String) ?? path,
                                     width: (fin["width"] as? Int) ?? art.width,
                                     height: (fin["height"] as? Int) ?? art.height)
    }

    @discardableResult
    static func delete(assetId: String) async -> Bool {
        (try? await post(["op": "keychain_delete", "assetId": assetId])) != nil
    }

    /// Signed read URL for a custom asset (1h). Never logged.
    static func signedURL(path: String) async -> URL? {
        do {
            let results = try await SupabaseService.client.storage.from("keychain-art")
                .createSignedURLs(paths: [path], expiresIn: 3600)
            for r in results { if case let .success(p, url) = r, p == path { return url } }
        } catch {}
        return nil
    }
}
