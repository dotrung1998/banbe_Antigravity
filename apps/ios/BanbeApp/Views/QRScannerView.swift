import SwiftUI
import AVFoundation

/// Full-screen camera scanner for check-in — the iOS counterpart of
/// src/screens/sheets/QrScanSheet.jsx. A guest's ticket QR encodes their
/// booking id, so a scan calls the exact same check_in_guest() RPC the
/// manual list uses, sharing one authorization and notification path.
struct QRScannerView: View {
    @EnvironmentObject var app: AppState
    @State private var status: (ok: Bool, message: String)?
    @State private var busy = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview { code in handle(code) }
                .ignoresSafeArea()

            VStack {
                HStack {
                    Text(app.T("Quét mã QR của khách", "Scan a guest's QR"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button(app.T("Đóng", "Close")) { app.scanningQr = false }
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.white.opacity(0.15), in: Capsule())
                        .buttonStyle(.plain)
                }
                .padding(20)
                Spacer()
                if let status {
                    Text(status.message)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 18).padding(.vertical, 14)
                        .background(
                            status.ok ? app.palette.ink : BanbeTheme.alert,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 30)
                }
            }
        }
    }

    private func handle(_ code: String) {
        guard !busy else { return }
        busy = true
        Task {
            let ok = await app.checkInByScan(code)
            status = ok
                ? (true, app.T("Đã điểm danh ✓", "Checked in ✓"))
                : (false, app.T("Mã không hợp lệ hoặc đã điểm danh rồi.", "Invalid code, or already checked in."))
            // Brief pause so the same code isn't re-scanned many times a
            // second while it's still in frame.
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            status = nil
            busy = false
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
