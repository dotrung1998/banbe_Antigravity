import Foundation
import CryptoKit

/// Disk cache for Supabase Storage images, keyed by object path with the
/// signed-URL query (`?token=`) stripped.
///
/// Why: `AsyncImage` loads through `URLSession.shared`, whose URLCache is keyed
/// by the full URL. Signed URLs re-sign every 10min-1h, so the same object is
/// downloaded again each time — that is Supabase cached egress. Every upload
/// writes a new timestamped path, so path-without-query is a permanent
/// identity for the bytes. See .claude/notes/22-supabase-bandwidth-optimization.md.
///
/// Registered once at launch (`StorageImageCache.install()`); it then applies to
/// `URLSession.shared` (AsyncImage) and to any session that lists it in
/// `protocolClasses` (PhotoLoader).
final class StorageImageCache: URLProtocol {

    private static let handledKey = "banbe.storageImageCache.handled"
    private static let maxBytes: Int64 = 300 * 1024 * 1024
    private static let maxFileBytes = 8 * 1024 * 1024

    private static let directory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("banbe.storage-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let upstream: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil
        return URLSession(configuration: c)
    }()

    static func install() { URLProtocol.registerClass(StorageImageCache.self) }

    /// Sign-out / "Clear Image Cache".
    static func clear() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: URLProtocol

    override class func canInit(with request: URLRequest) -> Bool {
        guard request.httpMethod == "GET",
              request.value(forHTTPHeaderField: "Range") == nil,
              URLProtocol.property(forKey: handledKey, in: request) == nil,
              let url = request.url, let host = url.host, host.hasSuffix(".supabase.co")
        else { return false }
        let p = url.path
        return p.hasPrefix("/storage/v1/object/public/")
            || p.hasPrefix("/storage/v1/object/sign/")
            || p.hasPrefix("/storage/v1/object/authenticated/")
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private var upstreamTask: URLSessionDataTask?

    private static func fileURL(for url: URL) -> URL {
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        c?.query = nil
        let stable = c?.string ?? url.absoluteString
        let hash = SHA256.hash(data: Data(stable.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash)
    }

    override func startLoading() {
        guard let url = request.url else { return }
        let file = Self.fileURL(for: url)

        if let data = try? Data(contentsOf: file), !data.isEmpty,
           let mime = try? String(contentsOf: file.appendingPathExtension("mime"), encoding: .utf8) {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": mime, "Content-Length": "\(data.count)"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        guard let marked = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else { return }
        URLProtocol.setProperty(true, forKey: Self.handledKey, in: marked)
        upstreamTask = Self.upstream.dataTask(with: marked as URLRequest) { [weak self] data, response, error in
            guard let self else { return }
            if let error { self.client?.urlProtocol(self, didFailWithError: error); return }
            guard let data, let http = response as? HTTPURLResponse else {
                self.client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
            }
            let mime = http.value(forHTTPHeaderField: "Content-Type") ?? ""
            if http.statusCode == 200, mime.hasPrefix("image/"), data.count <= Self.maxFileBytes {
                try? data.write(to: file, options: .atomic)
                try? mime.write(to: file.appendingPathExtension("mime"), atomically: true, encoding: .utf8)
                Self.trimIfNeeded()
            }
            self.client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        upstreamTask?.resume()
    }

    override func stopLoading() { upstreamTask?.cancel() }

    /// Evicts least-recently-used files once the directory passes `maxBytes`.
    private static func trimIfNeeded() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else { return }
        var entries = files.compactMap { f -> (URL, Int64, Date)? in
            guard let v = try? f.resourceValues(forKeys: Set(keys)) else { return nil }
            return (f, Int64(v.fileSize ?? 0), v.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(0) { $0 + $1.1 }
        guard total > maxBytes else { return }
        entries.sort { $0.2 < $1.2 }
        for e in entries where total > maxBytes * 8 / 10 {
            try? FileManager.default.removeItem(at: e.0)
            total -= e.1
        }
    }
}
