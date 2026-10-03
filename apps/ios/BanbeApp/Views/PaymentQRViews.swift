import SwiftUI
import PhotosUI
import Supabase

/// Wraps a QR so that LONG-PRESSING it reads the code and switches to the
/// matching payment app (the payer often has no second device to scan from).
/// `payload` supplies the QR's content lazily — already-known text, or a
/// decode of the shown image.
struct PaymentQRPressable<Content: View>: View {
    @EnvironmentObject private var app: AppState
    let payload: () async -> String?
    var showHint = true
    @ViewBuilder var content: () -> Content
    @State private var note: String?
    @State private var busy = false

    var body: some View {
        VStack(spacing: 8) {
            content()
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.45) { trigger() }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(app.T("Nhấn giữ để mở app thanh toán", "Press and hold to open your payment app"))
            if let note {
                Text(note)
                    .font(.system(size: 11.5)).foregroundStyle(app.palette.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("paymentQR.note")
            } else if showHint {
                Text(app.T("Nhấn giữ mã QR để mở app thanh toán", "Press and hold the QR to open your payment app"))
                    .font(.system(size: 11)).foregroundStyle(app.palette.ink.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func trigger() {
        guard !busy else { return }
        busy = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            defer { busy = false }
            guard let text = await payload(), !text.isEmpty else {
                note = app.T("Không đọc được mã QR này.", "Couldn't read this QR code.")
                return
            }
            switch await PaymentQR.open(payload: text) {
            case .opened(let copied):
                note = copied
                    ? app.T("Đang mở app thanh toán · đã sao chép số tài khoản", "Opening your payment app · account number copied")
                    : app.T("Đang mở app thanh toán…", "Opening your payment app…")
            case .copiedText:
                note = app.T("Chưa nhận ra app thanh toán — đã sao chép nội dung mã.", "Couldn't tell which app to open — QR content copied.")
            case .failed:
                note = app.T("Không mở được app thanh toán.", "Couldn't open a payment app.")
            }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            note = nil
        }
    }
}

/// A QR image stored in one of the private buckets (`pay-qr`, `refund-qr`),
/// downloaded under the viewer's own storage RLS. Long-press opens the
/// payment app via the stored `payload`, or by decoding the image itself
/// when none was saved.
struct PaymentQRImageView: View {
    let bucket: String
    let path: String
    var payload: String? = nil
    var size: CGFloat = 210
    var showHint = true

    @State private var image: UIImage?
    @State private var failed = false

    private static let cache = NSCache<NSString, UIImage>()

    var body: some View {
        PaymentQRPressable(payload: resolvePayload, showHint: showHint) {
            ZStack {
                Color.white
                if let image {
                    Image(uiImage: image).resizable().scaledToFit().padding(4)
                } else if failed {
                    Image(systemName: "qrcode").font(.system(size: 36)).foregroundStyle(.gray)
                } else {
                    ProgressView()
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .task(id: path) { await load() }
    }

    private func resolvePayload() async -> String? {
        if let payload, !payload.isEmpty { return payload }
        if image == nil { await load() }
        guard let image else { return nil }
        return await PaymentQR.decode(image)
    }

    private func load() async {
        let key = "\(bucket)/\(path)" as NSString
        if let hit = Self.cache.object(forKey: key) { image = hit; failed = false; return }
        do {
            let data = try await SupabaseService.client.storage.from(bucket).download(path: path)
            if let img = UIImage(data: data) {
                Self.cache.setObject(img, forKey: key)
                image = img
                failed = false
            } else { failed = true }
        } catch {
            print("PaymentQRImageView load failed:", error)
            failed = true
        }
    }
}

/// "Upload a QR" control: a photo picker that reads the QR out of the chosen
/// image first (so a screenshot of Zelle / Venmo / a bank's own QR works),
/// rejects images with no readable QR, then hands the prepared JPEG +
/// decoded payload to `onPrepared`.
struct PaymentQRUploadControl: View {
    @EnvironmentObject private var app: AppState
    let hasQR: Bool
    var busy: Bool = false
    let onPrepared: (PaymentQR.Prepared) async -> Void
    var onRemove: (() -> Void)? = nil

    @State private var item: PhotosPickerItem?
    @State private var working = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                PhotosPicker(selection: $item, matching: .images) {
                    HStack(spacing: 8) {
                        Image(systemName: working || busy ? "hourglass" : "qrcode.viewfinder")
                        Text(hasQR ? app.T("Thay mã QR", "Replace QR code") : app.T("Tải mã QR lên", "Upload a QR code"))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(app.palette.field, in: Capsule())
                    .foregroundStyle(app.palette.ink)
                }
                .disabled(working || busy)
                .accessibilityIdentifier("paymentQR.upload")
                if hasQR, let onRemove {
                    Button(app.T("Xoá", "Remove")) { onRemove() }
                        .font(.system(size: 12.5))
                        .foregroundStyle(BanbeTheme.alert)
                        .buttonStyle(.plain)
                        .disabled(working || busy)
                        .accessibilityIdentifier("paymentQR.remove")
                }
            }
            if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(BanbeTheme.alert)
            }
        }
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            Task { await handle(newItem) }
        }
    }

    private func handle(_ pickerItem: PhotosPickerItem) async {
        working = true
        error = nil
        defer { working = false; item = nil }
        do {
            guard let data = try await pickerItem.loadTransferable(type: Data.self) else {
                error = app.T("Không đọc được ảnh.", "Couldn't read that image.")
                return
            }
            let prepared = try await PaymentQR.prepare(imageData: data)
            await onPrepared(prepared)
        } catch PaymentQR.PrepareError.noQR {
            error = app.T("Không tìm thấy mã QR trong ảnh này. Hãy chọn ảnh chụp rõ mã QR.",
                          "No QR code found in that image. Pick a clear picture of the QR.")
        } catch {
            self.error = app.T("Không đọc được ảnh.", "Couldn't read that image.")
        }
    }
}

/// The QR an attendee attached to the refund account they chose, frozen in
/// the claim's recipient snapshot. Shown to the host who owes the refund —
/// press and hold opens their payment app, so they can pay without a second
/// device. Renders nothing when the snapshot has no QR.
struct RefundRecipientQRView: View {
    @EnvironmentObject private var app: AppState
    let snapshot: RecipientSnapshot
    var size: CGFloat = 150

    var body: some View {
        if let path = snapshot.qrPath, !path.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(app.T("Mã QR của khách", "Guest's QR code"))
                    .font(.system(size: 11, weight: .semibold)).opacity(0.75)
                PaymentQRImageView(bucket: "refund-qr", path: path, payload: snapshot.qrPayload, size: size)
                    .accessibilityIdentifier("refund.recipientQR")
            }
            .padding(.top, 4)
        }
    }
}
