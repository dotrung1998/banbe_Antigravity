import SwiftUI
import UIKit
import PassKit

/// The look the holder picked for their Apple Wallet ticket, remembered on this
/// device so the next ticket starts from the same design.
struct WalletPassStyle: Codable, Equatable {
    var backgroundHex: String
    var foregroundHex: String
    /// 750x246 PNG, or nil for the plain card.
    var bannerPNG: Data?

    static let presets: [(name: String, nameEN: String, style: WalletPassStyle)] = [
        ("Mực", "Ink", .init(backgroundHex: "#1C1C1E", foregroundHex: "#FFFFFF", bannerPNG: nil)),
        ("Giấy", "Paper", .init(backgroundHex: "#F7F4EC", foregroundHex: "#1C1C1E", bannerPNG: nil)),
        ("Đất nung", "Terracotta", .init(backgroundHex: "#C9592F", foregroundHex: "#FFFFFF", bannerPNG: nil)),
        ("Rừng", "Forest", .init(backgroundHex: "#2F5D50", foregroundHex: "#FFFFFF", bannerPNG: nil)),
        ("Biển", "Ocean", .init(backgroundHex: "#2B4C7E", foregroundHex: "#FFFFFF", bannerPNG: nil)),
        ("Tím", "Plum", .init(backgroundHex: "#5B3A6B", foregroundHex: "#FFFFFF", bannerPNG: nil)),
    ]

    static let `default` = presets[0].style

    private static let storageKey = "walletPassStyle.v1"

    static func load() -> WalletPassStyle {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let style = try? JSONDecoder().decode(WalletPassStyle.self, from: data)
        else { return .default }
        return style
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

extension Color {
    init(hex: String) {
        let n = UInt32(hex.dropFirst(), radix: 16) ?? 0
        self.init(red: Double((n >> 16) & 255) / 255, green: Double((n >> 8) & 255) / 255, blue: Double(n & 255) / 255)
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}

enum WalletPassError: LocalizedError {
    case notSignedIn
    case notConfigured
    case notAvailable
    case server(String)

    func message(isEN: Bool) -> String {
        switch self {
        case .notSignedIn:
            return isEN ? "Sign in again to add this ticket to Wallet." : "Hãy đăng nhập lại để thêm vé vào Wallet."
        case .notConfigured:
            return isEN ? "Apple Wallet isn't switched on for banbe yet. Your ticket and QR still work as usual."
                        : "banbe chưa bật Apple Wallet. Vé và mã QR của bạn vẫn dùng bình thường."
        case .notAvailable:
            return isEN ? "Apple Wallet isn't available on this device." : "Thiết bị này không hỗ trợ Apple Wallet."
        case .server(let code):
            switch code {
            case "TICKET_GIFTED": return isEN ? "This ticket was gifted, so it can't be added to your Wallet." : "Vé này đã được tặng nên không thể thêm vào Wallet."
            case "TICKET_NOT_READY": return isEN ? "Your ticket isn't confirmed yet." : "Vé của bạn chưa được xác nhận."
            case "BANNER_MUST_BE_PNG_UNDER_1_5MB": return isEN ? "That banner image is too large. Try another one." : "Ảnh banner quá lớn. Hãy thử ảnh khác."
            default: return isEN ? "Couldn't create the Wallet pass. Please try again." : "Không tạo được vé Wallet. Vui lòng thử lại."
            }
        }
    }
}

enum WalletPassService {
    /// Asks the server for a signed .pkpass for this booking. The server checks
    /// that the booking is the caller's and still a live, un-gifted ticket.
    static func fetchPass(bookingID: UUID, style: WalletPassStyle) async throws -> PKPass {
        guard PKPassLibrary.isPassLibraryAvailable() else { throw WalletPassError.notAvailable }
        guard let token = try? await SupabaseService.client.auth.session.accessToken,
              let url = URL(string: AppConfig.apiBaseURL + "/api/wallet-pass")
        else { throw WalletPassError.notSignedIn }

        var design: [String: String] = [
            "background": style.backgroundHex,
            "foreground": style.foregroundHex,
        ]
        if let banner = style.bannerPNG { design["banner"] = banner.base64EncodedString() }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "bookingId": bookingID.uuidString,
            "design": design,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            if status == 503 { throw WalletPassError.notConfigured }
            let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw WalletPassError.server(code ?? "WALLET_PASS_FAILED")
        }
        return try PKPass(data: data)
    }

    /// Tells the server this ticket changed (it was just gifted), so the pass
    /// already in the holder's Wallet is voided straight away rather than at the
    /// next daily sweep. Best effort and silent: the gift has already succeeded,
    /// and a missing/unconfigured Wallet service must never look like it failed.
    static func refreshPass(bookingID: UUID) async {
        guard let token = try? await SupabaseService.client.auth.session.accessToken,
              let url = URL(string: AppConfig.apiBaseURL + "/api/wallet-refresh")
        else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["bookingId": bookingID.uuidString])
        _ = try? await URLSession.shared.data(for: request)
    }

    /// Centre-crops (aspect fill) to the 750x246 strip Wallet draws behind the
    /// event name, and returns it as the PNG the pass format requires.
    static func bannerPNG(from image: UIImage) -> Data? {
        let target = CGSize(width: 750, height: 246)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let scale = max(target.width / image.size.width, target.height / image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(x: (target.width - drawSize.width) / 2,
                                  y: (target.height - drawSize.height) / 2,
                                  width: drawSize.width, height: drawSize.height))
        }
        return rendered.pngData()
    }
}
