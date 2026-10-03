import SwiftUI
import AVFoundation

/// Check-in scanner as a pop-up card (same glass card + scrim language as the
/// Pulse panel), sized like a vertical photo viewer. The top of the card is the
/// live camera, edge to edge; below it sit the host's instruction line and the
/// "Confirm" / "Not now" buttons.
///
/// Flow: buttons start disabled -> a ticket QR is scanned and looked up (name +
/// date of birth for age checks) -> buttons enable -> "Confirm" checks the
/// guest in, shows a green message and disables the buttons again until the
/// next QR. One scan is acted on at a time (a QR stays in frame for many camera
/// frames; everything is ignored while a guest is pending or a lookup/check-in
/// is in flight, and the same code is ignored briefly after it resolves).
struct QRScannerView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var progress: CGFloat = 0
    @State private var guest: CheckInGuestInfo?
    @State private var pendingCode: String?
    @State private var lookingUp = false
    @State private var confirming = false
    @State private var greenMessage: String?
    @State private var errorMessage: String?
    @State private var lastResolvedCode: String?
    @State private var lastResolvedAt = Date.distantPast
    @State private var clearTask: Task<Void, Never>?

    private static let confirmGreen = Color(red: 0.13, green: 0.58, blue: 0.33)

    private var canConfirm: Bool { guest != nil && !(guest?.alreadyCheckedIn ?? true) && !confirming }
    private var canDismiss: Bool { guest != nil && !confirming }

    var body: some View {
        GeometryReader { geo in
            let panelWidth = min(geo.size.width - 40, 380)
            let panelHeight = min(geo.size.height - 90, panelWidth * 4 / 3 + 190)
            ZStack {
                Color.black.opacity(0.5 * Double(progress))
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { close() }

                card(panelWidth: panelWidth)
                    .frame(width: panelWidth, height: panelHeight)
                    .scaleEffect(0.94 + 0.06 * progress)
                    .opacity(Double(progress))
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear {
            guard !reduceMotion else { progress = 1; return }
            withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) { progress = 1 }
        }
        .onDisappear { clearTask?.cancel() }
    }

    // MARK: Card

    private func card(panelWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Camera: fills the card edge to edge (the card's rounded clip
            // shapes the top corners).
            ZStack {
                Color.black
                CameraPreview { code in handle(code) }
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(guest == nil ? 0.75 : 0.25), lineWidth: 2)
                    .frame(width: panelWidth * 0.62, height: panelWidth * 0.62)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                Button { close() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(app.palette.ink)
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(6)
                .accessibilityIdentifier("scanner.close")
                .accessibilityLabel(app.T("Đóng", "Close"))
            }

            controls
        }
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(app.palette.paper.opacity(0.92))
                if #available(iOS 26.0, *) {
                    GlassEffectContainer {
                        Color.clear.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                            .opacity(app.glassOpacity)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 22, y: 12)
    }

    // MARK: Instruction, result and buttons

    private var controls: some View {
        VStack(spacing: 12) {
            messageArea
                .frame(maxWidth: .infinity, minHeight: 58)
            HStack(spacing: 10) {
                Button { confirm() } label: {
                    Text(confirming ? app.T("Đang xác nhận…", "Confirming…") : app.T("Xác nhận", "Confirm"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(app.palette.paper)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canConfirm)
                .opacity(canConfirm ? 1 : 0.35)
                .accessibilityIdentifier("scanner.confirm")

                Button { notNow() } label: {
                    Text(app.T("Để sau", "Not now"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(app.palette.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(app.palette.rule))
                }
                .buttonStyle(.plain)
                .disabled(!canDismiss)
                .opacity(canDismiss ? 1 : 0.35)
                .accessibilityIdentifier("scanner.notNow")
            }
        }
        .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 18)
        .background(app.palette.paper.opacity(0.0))
    }

    @ViewBuilder
    private var messageArea: some View {
        if let greenMessage {
            Text(greenMessage)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity).padding(.vertical, 12).padding(.horizontal, 12)
                .background(Self.confirmGreen, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("scanner.success")
        } else if let errorMessage {
            Text(errorMessage)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(BanbeTheme.alert)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("scanner.error")
        } else if let guest {
            VStack(spacing: 4) {
                Text(guest.name.isEmpty ? app.T("Khách", "Guest") : guest.name)
                    .font(.system(size: 17, weight: .bold))
                Text(dobLine(guest))
                    .font(.system(size: 14))
                if guest.alreadyCheckedIn {
                    Text(app.T("Khách này đã được điểm danh.", "This guest is already checked in."))
                        .font(.system(size: 12.5)).foregroundStyle(BanbeTheme.alert)
                }
            }
            .foregroundStyle(app.palette.ink)
            .multilineTextAlignment(.center)
            .accessibilityIdentifier("scanner.guest")
        } else if lookingUp {
            Text(app.T("Đang kiểm tra vé…", "Checking ticket…"))
                .font(.system(size: 14)).foregroundStyle(app.palette.ink)
        } else {
            Text(app.T("Đưa mã QR của khách lên để quét", "Hold up and scan the goer's QR code"))
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(app.palette.ink)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("scanner.instruction")
        }
    }

    /// "Date of birth: 15/06/1998 · 28" — read from the server's ISO date, no
    /// time-zone conversion.
    private func dobLine(_ g: CheckInGuestInfo) -> String {
        guard let iso = g.dobISO else {
            return app.T("Chưa có ngày sinh trong hồ sơ", "No date of birth on file")
        }
        let parts = iso.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return app.T("Chưa có ngày sinh trong hồ sơ", "No date of birth on file") }
        let (y, m, d) = (parts[0], parts[1], parts[2])
        let today = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        var age = (today.year ?? y) - y
        if ((today.month ?? 0), (today.day ?? 0)) < (m, d) { age -= 1 }
        let date = String(format: "%02d/%02d/%04d", d, m, y)
        return app.T("Ngày sinh: \(date) · \(age) tuổi", "Date of birth: \(date) · age \(age)")
    }

    // MARK: Actions

    private func close() {
        guard !confirming else { return }
        guard !reduceMotion else { app.scanningQr = false; return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { progress = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { app.scanningQr = false }
    }

    /// Camera callback — fires for every frame the QR is visible.
    private func handle(_ code: String) {
        guard guest == nil, !lookingUp, !confirming else { return }
        // Same code that just resolved: ignore for a moment.
        if code == lastResolvedCode, Date().timeIntervalSince(lastResolvedAt) < 3 { return }
        lookingUp = true
        pendingCode = code
        clearTask?.cancel()
        greenMessage = nil
        errorMessage = nil
        Task {
            let (info, failure) = await app.lookupCheckInGuest(code: code)
            lookingUp = false
            lastResolvedCode = code
            lastResolvedAt = Date()
            if let info {
                guest = info
                Haptics.selection()
            } else {
                pendingCode = nil
                errorMessage = failureText(failure)
                Haptics.error()
                scheduleClear(after: 2.5)
            }
        }
    }

    private func confirm() {
        guard let code = pendingCode, let guest, canConfirm else { return }
        confirming = true
        Task {
            let ok = await app.checkInByScan(code)
            confirming = false
            let name = guest.name.isEmpty ? app.T("Khách", "Guest") : guest.name
            self.guest = nil
            pendingCode = nil
            lastResolvedAt = Date()
            if ok {
                greenMessage = app.T("✓ Đã điểm danh · \(name)", "✓ Checked in · \(name)")
                scheduleClear(after: 3.5)
            } else {
                Haptics.error()
                errorMessage = app.T("Chưa điểm danh được. Mã không hợp lệ hoặc khách đã được điểm danh.", "Couldn't check in. Invalid code, or already checked in.")
                scheduleClear(after: 3)
            }
        }
    }

    private func notNow() {
        guard canDismiss else { return }
        guest = nil
        pendingCode = nil
        lastResolvedAt = Date()
        greenMessage = nil
        errorMessage = nil
    }

    private func scheduleClear(after seconds: Double) {
        clearTask?.cancel()
        clearTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if Task.isCancelled { return }
            greenMessage = nil
            errorMessage = nil
        }
    }

    private func failureText(_ f: CheckInLookupFailure?) -> String {
        switch f {
        case .wrongEvent: return app.T("Vé này không thuộc sự kiện đang điểm danh.", "This ticket isn't for the event you're checking in.")
        case .rateLimited: return app.T("Bạn đã tra cứu quá nhiều. Thử lại sau.", "Too many lookups. Try again later.")
        case .network: return app.T("Không có kết nối. Thử quét lại.", "No connection. Try scanning again.")
        default: return app.T("Mã không hợp lệ hoặc không phải khách của sự kiện này.", "Invalid code, or not a guest of this event.")
        }
    }
}

/// Thin AVFoundation wrapper: a live camera preview that reports every QR
/// payload it sees.
struct CameraPreview: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onCode = onCode
        return controller
    }

    func updateUIViewController(_ controller: ScannerViewController, context: Context) {}
}

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    deinit { if session.isRunning { session.stopRunning() } }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !session.isRunning else { return }
        // startRunning blocks, so keep it off the main thread.
        DispatchQueue.global(qos: .userInitiated).async { [session] in session.startRunning() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning { session.stopRunning() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue
        else { return }
        onCode?(value)
    }
}
