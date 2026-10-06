import UIKit
import Supabase

/// Client for the hybrid R2 media API (`POST /api/media`, see
/// .claude/notes/28-r2-hybrid-media.md). Never logs tokens or URLs.
enum MediaUploader {

    enum Result: Equatable {
        /// Server said "use Supabase" or init failed: caller runs its legacy path.
        case legacy
        case uploaded(assetId: String, ref: String)
    }

    /// Thrown ONLY after bytes were PUT to R2 and finalize failed twice.
    struct PostUploadError: Error { let assetId: String }

    static let longEdges: [(MediaVariant, CGFloat)] = [(.thumb, 320), (.card, 800), (.full, 1600)]
    static var jpegQuality: CGFloat = 0.82

    // MARK: Public entry points

    static func uploadEventPhoto(image: UIImage, eventID: String, setCover: Bool = false, sortOrder: Int? = nil) async throws -> Result {
        try await upload(image: image, kind: "event_photo", ownerKey: "eventId", ownerID: eventID,
                         finalizeExtras: { var d: [String: Any] = ["setCover": setCover]
                             if let sortOrder { d["sortOrder"] = sortOrder }; return d })
    }

    static func uploadOrganizerAvatar(image: UIImage, organizerID: String) async throws -> Result {
        try await upload(image: image, kind: "organizer_avatar", ownerKey: "organizerId", ownerID: organizerID,
                         finalizeExtras: { [:] })
    }

    /// Best-effort owner-side delete of an R2 asset by ref. Returns success.
    @discardableResult
    static func delete(ref: String?) async -> Bool {
        guard let ref, let p = MediaResolver.parse(ref), let token = await accessToken() else { return false }
        let res = try? await post(["op": "delete", "assetId": p.assetId], token: token)
        return res?.status == 200
    }

    /// Fire-and-forget: asks the server to unpublish R2 copies of an event
    /// that is no longer public-eligible. Failures are ignored.
    static func reconcile(eventID: String) {
        Task.detached {
            guard let token = await accessToken() else { return }
            _ = try? await post(["op": "reconcile", "eventId": eventID], token: token)
        }
    }

    // MARK: Variant rendering (re-encoding also strips EXIF/GPS)

    static func makeVariants(from image: UIImage, quality: CGFloat = jpegQuality) -> [(variant: MediaVariant, data: Data)]? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let longest = max(size.width, size.height) * image.scale
        var out: [(MediaVariant, Data)] = []
        for (variant, edge) in longEdges {
            let ratio = min(1, edge / longest)           // never upscale
            let target = CGSize(width: max(1, (size.width * image.scale * ratio).rounded()),
                                height: max(1, (size.height * image.scale * ratio).rounded()))
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            format.opaque = true
            let rendered = UIGraphicsImageRenderer(size: target, format: format).image { ctx in
                UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: target))
                image.draw(in: CGRect(origin: .zero, size: target))
            }
            guard let data = rendered.jpegData(compressionQuality: quality) else { return nil }
            out.append((variant, data))
        }
        return out
    }

    // MARK: Flow

    private static func upload(image: UIImage, kind: String, ownerKey: String, ownerID: String,
                               finalizeExtras: () -> [String: Any]) async throws -> Result {
        guard let variants = makeVariants(from: image), let token = await accessToken() else { return .legacy }

        let initBody: [String: Any] = [
            "op": "init", "kind": kind, ownerKey: ownerID,
            "idempotencyKey": UUID().uuidString.lowercased(),
            "files": variants.map { ["variant": $0.variant.rawValue, "contentType": "image/jpeg", "bytes": $0.data.count] }
        ]
        guard let initRes = try? await post(initBody, token: token), initRes.status == 200,
              let obj = initRes.json, (obj["provider"] as? String) == "r2",
              let assetId = obj["assetId"] as? String,
              let uploads = obj["uploads"] as? [[String: Any]], !uploads.isEmpty else { return .legacy }

        // Resolve every PUT up front so a malformed init response falls back
        // to legacy BEFORE any bytes leave the device.
        var puts: [(URL, [String: String], Data)] = []
        for u in uploads {
            guard let name = u["variant"] as? String, let v = MediaVariant(rawValue: name),
                  let data = variants.first(where: { $0.variant == v })?.data,
                  let s = u["url"] as? String, let url = URL(string: s), url.scheme == "https",
                  (u["method"] as? String ?? "PUT") == "PUT" else { return .legacy }
            puts.append((url, (u["headers"] as? [String: String]) ?? [:], data))
        }
        guard puts.count == variants.count else { return .legacy }

        for (i, put) in puts.enumerated() {
            var req = URLRequest(url: put.0)
            req.httpMethod = "PUT"
            for (k, v) in put.1 { req.setValue(v, forHTTPHeaderField: k) }   // exact headers; no auth to R2
            do {
                let (_, resp) = try await rawSession.upload(for: req, from: put.2)
                guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
            } catch {
                // Nothing is visible until finalize; if the very first PUT
                // failed no bytes landed, so legacy is still safe.
                if i == 0 { return .legacy }
                throw PostUploadError(assetId: assetId)
            }
        }

        var fin: [String: Any] = ["op": "finalize", "assetId": assetId]
        for (k, v) in finalizeExtras() { fin[k] = v }
        for attempt in 0..<2 {
            if let tok = await accessToken(), let res = try? await post(fin, token: tok), res.status == 200,
               let ref = res.json?["ref"] as? String, MediaResolver.parse(ref) != nil {
                return .uploaded(assetId: assetId, ref: ref)
            }
            if attempt == 0 { try? await Task.sleep(nanoseconds: 600_000_000) }
        }
        throw PostUploadError(assetId: assetId)
    }

    // MARK: HTTP

    private static let rawSession: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil
        c.timeoutIntervalForRequest = 60
        return URLSession(configuration: c)
    }()

    private static func accessToken() async -> String? {
        try? await SupabaseService.client.auth.session.accessToken
    }

    private struct Response { let status: Int; let json: [String: Any]? }

    private static func post(_ body: [String: Any], token: String) async throws -> Response {
        guard let url = URL(string: AppConfig.apiBaseURL + "/api/media") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await rawSession.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        return Response(status: status, json: (try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
    }
}
