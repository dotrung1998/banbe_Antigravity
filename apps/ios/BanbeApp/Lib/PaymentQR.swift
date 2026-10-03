import Foundation
import UIKit
import Vision

/// Reads a payment QR (from an uploaded image) and hands it to the right
/// payment app. Vietnam and the US both pay by QR, so this understands:
///   * VietQR / NAPAS (EMVCo "38" merchant account) — opened through
///     `dl.vietqr.io`, which routes to the payer's own banking app with the
///     account/amount/memo filled in.
///   * Anything that is a URL (Zelle `enroll.zellepay.com`, Venmo, Cash App,
///     PayPal, MoMo/ZaloPay links ...) — opened directly; iOS routes it to
///     the installed app through its universal link, else Safari.
///   * Anything else — copied to the clipboard so nothing is lost.
enum PaymentQR {

    // MARK: Decode

    /// First QR payload found in the image, or nil. Runs Vision off the main
    /// actor.
    static func decode(_ image: UIImage) async -> String? {
        guard let cg = image.cgImage else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> String? in
            let request = VNDetectBarcodesRequest()
            request.symbologies = [.qr]
            let handler = VNImageRequestHandler(cgImage: cg, orientation: CGImagePropertyOrientation(image.imageOrientation), options: [:])
            do { try handler.perform([request]) } catch { return nil }
            return request.results?.compactMap { $0.payloadStringValue }.first { !$0.isEmpty }
        }.value
    }

    // MARK: Classify

    struct VietQRInfo: Equatable {
        var bin: String
        var account: String
        var amountVnd: Int?
        var memo: String?
    }

    enum Kind: Equatable {
        case vietQR(VietQRInfo)
        case url(URL)
        case text(String)
    }

    static func classify(_ payload: String) -> Kind {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if let info = parseVietQR(trimmed) { return .vietQR(info) }
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
           ["http", "https", "momo", "zalopay", "venmo", "cashme", "paypal"].contains(scheme) {
            return .url(url)
        }
        return .text(trimmed)
    }

    /// EMVCo TLV: 2-char tag, 2-digit length, value.
    private static func tlv(_ s: String) -> [(String, String)] {
        var out: [(String, String)] = []
        let chars = Array(s)
        var i = 0
        while i + 4 <= chars.count {
            let tag = String(chars[i..<i + 2])
            guard let len = Int(String(chars[i + 2..<i + 4])), len >= 0, i + 4 + len <= chars.count else { break }
            out.append((tag, String(chars[i + 4..<i + 4 + len])))
            i += 4 + len
        }
        return out
    }

    static func parseVietQR(_ payload: String) -> VietQRInfo? {
        let top = tlv(payload)
        guard top.contains(where: { $0.0 == "00" }),
              let merchant = top.first(where: { $0.0 == "38" })?.1 else { return nil }
        let m = tlv(merchant)
        guard m.first(where: { $0.0 == "00" })?.1.uppercased() == "A000000727",
              let beneficiary = m.first(where: { $0.0 == "01" })?.1 else { return nil }
        let b = tlv(beneficiary)
        guard let bin = b.first(where: { $0.0 == "00" })?.1,
              let account = b.first(where: { $0.0 == "01" })?.1, !account.isEmpty else { return nil }
        let amount = top.first(where: { $0.0 == "54" })?.1.split(separator: ".").first.flatMap { Int($0) }
        let memo = top.first(where: { $0.0 == "62" }).flatMap { tlv($0.1).first(where: { $0.0 == "08" })?.1 }
        return VietQRInfo(bin: bin, account: account, amountVnd: amount, memo: memo)
    }

    /// NAPAS BIN -> the short bank code `dl.vietqr.io` uses as both `app=`
    /// and the `@bank` suffix of `ba=`.
    private static let binToCode: [String: String] = [
        "970436": "vcb", "970407": "tcb", "970422": "mb", "970415": "ctg",
        "970418": "bidv", "970405": "agribank", "970416": "acb", "970432": "vpb",
        "970423": "tpb", "970403": "stb", "970441": "vib", "970443": "shb",
        "970431": "eib", "970426": "msb", "970448": "ocb", "970440": "seab",
        "970437": "hdb", "970429": "scb", "970428": "nab", "970409": "bab",
        "970449": "lpb",
    ]

    static func vietQRLink(_ info: VietQRInfo) -> URL? {
        var comps = URLComponents(string: "https://dl.vietqr.io/pay")
        var items: [URLQueryItem] = []
        let code = binToCode[info.bin]
        if let code { items.append(URLQueryItem(name: "app", value: code)) }
        items.append(URLQueryItem(name: "ba", value: code.map { "\(info.account)@\($0)" } ?? info.account))
        if let amount = info.amountVnd, amount > 0 { items.append(URLQueryItem(name: "am", value: String(amount))) }
        if let memo = info.memo, !memo.isEmpty { items.append(URLQueryItem(name: "tn", value: memo)) }
        comps?.queryItems = items
        return comps?.url
    }

    // MARK: Open

    enum OpenResult: Equatable {
        /// Handed off to a payment app / browser. `copiedAccount` is true
        /// when the account number was also put on the clipboard as a
        /// fallback in case the app opens without pre-filling.
        case opened(copiedAccount: Bool)
        /// Not something we can route; the raw content was copied instead.
        case copiedText
        case failed
    }

    @MainActor
    static func open(payload: String) async -> OpenResult {
        switch classify(payload) {
        case .vietQR(let info):
            UIPasteboard.general.string = info.account
            guard let url = vietQRLink(info) else { return .copiedText }
            let ok = await UIApplication.shared.open(url)
            return ok ? .opened(copiedAccount: true) : .failed
        case .url(let url):
            let ok = await UIApplication.shared.open(url)
            return ok ? .opened(copiedAccount: false) : .failed
        case .text(let text):
            UIPasteboard.general.string = text
            return .copiedText
        }
    }

    // MARK: Prepare an upload

    enum PrepareError: Error { case unreadable, noQR }

    struct Prepared {
        var jpeg: Data
        var payload: String
    }

    /// Decodes the QR from the picked image (must contain one — the long-press
    /// feature depends on it), then downsizes/recompresses to fit the
    /// 1 MB bucket limit.
    static func prepare(imageData: Data) async throws -> Prepared {
        guard let image = UIImage(data: imageData) else { throw PrepareError.unreadable }
        guard let payload = await decode(image) else { throw PrepareError.noQR }
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, 1400 / max(longest, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        var quality: CGFloat = 0.9
        var data = resized.jpegData(compressionQuality: quality)
        while let d = data, d.count > 900_000, quality > 0.3 {
            quality -= 0.15
            data = resized.jpegData(compressionQuality: quality)
        }
        guard let jpeg = data, jpeg.count <= 1_000_000 else { throw PrepareError.unreadable }
        return Prepared(jpeg: jpeg, payload: payload)
    }
}

private extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
