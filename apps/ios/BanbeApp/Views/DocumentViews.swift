import SwiftUI
import WebKit

/// One list, four ways in: invoices or receipts, mine or the ones I issued.
/// Account opens it with the pair already chosen, so the screen itself never
/// needs a filter control.
struct DocumentsView: View {
    @EnvironmentObject private var app: AppState

    private var isReceipt: Bool { app.documentsKind == "receipt" }
    private var isHost: Bool { app.documentsRole == "host" }

    private var title: String {
        isReceipt ? app.T("Biên nhận", "Receipts") : app.T("Hoá đơn", "Invoices")
    }

    private var subtitle: String {
        if isHost {
            return isReceipt
                ? app.T("Biên nhận bạn đã phát hành khi đánh dấu khách đã thanh toán.",
                        "Receipts you issued when you marked a guest paid.")
                : app.T("Hoá đơn cho những chỗ đã đặt trong sự kiện của bạn.",
                        "Invoices for bookings on your events.")
        }
        return isReceipt
            ? app.T("Biên nhận cho những khoản bạn đã thanh toán.", "Receipts for what you have paid.")
            : app.T("Hoá đơn cho những chỗ bạn đã đặt.", "Invoices for the spots you booked.")
    }

    private var emptyText: String {
        isReceipt
            ? app.T("Chưa có biên nhận nào. Biên nhận xuất hiện khi người tổ chức xác nhận đã nhận tiền.",
                    "No receipts yet. One appears when an organizer confirms your payment.")
            : app.T("Chưa có hoá đơn nào.", "No invoices yet.")
    }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.T("Tài khoản", "Account")) { app.screen = .profile }
                    .padding(.top, 8)
                    .accessibilityIdentifier("documents.back")

                Text(title).font(BanbeTheme.display(24)).foregroundStyle(app.palette.ink)
                    .padding(.top, 14)
                    .accessibilityIdentifier("documents.title")
                Text(subtitle).font(.system(size: 12.5))
                    .foregroundStyle(app.palette.ink.opacity(0.75)).padding(.top, 8)

                VStack(spacing: 0) {
                    if app.documents.isEmpty {
                        Text(app.documentsLoading ? app.T("Đang tải…", "Loading…") : emptyText)
                            .font(.system(size: 12.5)).foregroundStyle(app.palette.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .accessibilityIdentifier("documents.empty")
                    }
                    ForEach(app.documents) { doc in
                        row(doc)
                        if doc.id != app.documents.last?.id {
                            Rectangle().fill(app.palette.rule).frame(height: 1)
                        }
                    }
                }
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 18)
            }
            .padding(.horizontal, 22).padding(.bottom, 40)
        }
        .accessibilityIdentifier("screen.documents")
        .task { await app.loadDocuments() }
    }

    private func row(_ doc: PaymentDocument) -> some View {
        let party = isHost ? (doc.buyer.name ?? app.T("Khách", "Guest")) : (doc.seller.name ?? "")
        // A raw uploaded file (migration 056) has no real totalVnd — showing
        // "0đ" for it was never true. Caption with the event + date instead
        // (from the jsonb snapshot on a legacy structured invoice, or the
        // events(...) join on an uploaded file's row — displayEventCaption
        // picks whichever is actually populated).
        let hasAmount = doc.totalVnd > 0
        let (eventName, eventDate) = doc.displayEventCaption
        let dateLabel = formatShortDate(eventDate, lang: app.lang)
        let caption = [eventName, dateLabel].compactMap { $0 }.joined(separator: " · ")
        return Button { app.openDocument(doc.id) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(doc.event.name ?? party)
                        .font(BanbeTheme.display(15)).foregroundStyle(app.palette.ink)
                        .lineLimit(1)
                    Text("\(doc.number) ▪︎ \(party)")
                        .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.7))
                        .lineLimit(1)
                    if hasAmount {
                        Text(formatVnd(doc.totalVnd))
                            .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(app.palette.ink)
                    } else if !caption.isEmpty {
                        Text(caption)
                            .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text("›").font(.system(size: 15)).foregroundStyle(app.palette.ink)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("document.row")
    }
}

/// The document itself.
///
/// Rendered server-side by api/payment-document.js using the very same
/// module the web app prints from, then shown in a web view — rather than
/// re-laying the whole thing out in SwiftUI. A second renderer would be a
/// second thing to keep in sync, and "the receipt looks different depending
/// on which app produced it" is precisely the discrepancy a document exists
/// to rule out. It also means the share sheet gets a real, printable page.
struct DocumentViewerView: View {
    @EnvironmentObject private var app: AppState
    @State private var loadFailed = false
    @State private var loadFailedDetail = ""
    @State private var printing = false
    @State private var replacing = false
    @State private var pendingFileURL: URL?
    @State private var reason = ""
    @State private var showReplacePicker = false

    private var isHost: Bool { app.documentsRole == "host" }

    var body: some View {
        ZStack {
            app.palette.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                BackLink(label: app.T("Quay lại", "Back")) { app.screen = app.documentBack }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 14)
                    .accessibilityIdentifier("documentView.back")

                if let doc = app.currentDocument {
                    if doc.isUploaded {
                        // The organizer's own file, shown directly via a
                        // signed URL (private bucket, migration 056) — no
                        // Authorization header needed, the token is in the
                        // URL's query string. WKWebView renders a PDF or an
                        // image URL identically well, so one code path
                        // covers both.
                        if let url = app.documentFileURL {
                            DocumentWebView(url: url, authenticated: false, failed: $loadFailed, failedDetail: $loadFailedDetail, printRequested: $printing)
                                .accessibilityIdentifier("document.frame")
                        } else if app.documentFileURLFailed {
                            // 15-organizer-checkin.md follow-up (Bug 1): a
                            // failed/timed-out signed-URL fetch used to leave
                            // this exact spot showing a permanent, silent
                            // ProgressView — no error, no retry, nothing to
                            // do but tap back and assume the app was broken.
                            VStack(spacing: 12) {
                                Text(app.T("Chưa tải được chứng từ. Kiểm tra kết nối rồi thử lại.",
                                           "Couldn't load the document. Check your connection and try again."))
                                    .font(.system(size: 13)).foregroundStyle(app.palette.ink)
                                    .multilineTextAlignment(.center)
                                if !app.documentFileURLErrorDetail.isEmpty {
                                    Text(app.documentFileURLErrorDetail)
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(app.palette.ink.opacity(0.55))
                                        .multilineTextAlignment(.center)
                                        .accessibilityIdentifier("documentView.errorDetail")
                                }
                                Button(app.T("Thử lại", "Try again")) { app.retryDocumentFileURL() }
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(app.palette.paper)
                                    .padding(.horizontal, 18).padding(.vertical, 10)
                                    .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("documentView.retry")
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.horizontal, 22)
                        } else {
                            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else {
                        // Legacy: issued before the switch to uploads —
                        // falls back to the old server-rendered HTML.
                        if let url = app.documentURL(doc.id) {
                            DocumentWebView(url: url, authenticated: true, failed: $loadFailed, failedDetail: $loadFailedDetail, printRequested: $printing)
                                .accessibilityIdentifier("document.frame")
                        }
                    }

                    if loadFailed {
                        VStack(spacing: 2) {
                            Text(app.T("Chưa tải được chứng từ. Kiểm tra kết nối rồi thử lại.",
                                       "Couldn't load the document. Check your connection and try again."))
                                .font(.system(size: 12.5)).foregroundStyle(BanbeTheme.alert)
                            if !loadFailedDetail.isEmpty {
                                Text(loadFailedDetail)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(BanbeTheme.alert.opacity(0.7))
                                    .accessibilityIdentifier("documentView.errorDetail")
                            }
                        }
                        .padding(.horizontal, 22).padding(.vertical, 10)
                    }

                    // Nothing to print from a document that failed to load
                    // at all (no WKWebView is even mounted in that state).
                    if !(doc.isUploaded && app.documentFileURLFailed) {
                        Button { printing = true } label: {
                            Text(app.T("Tải về ▪︎ In", "Download ▪︎ Print"))
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, 18).padding(.bottom, 12)
                                .background(app.palette.ink)
                                .foregroundStyle(app.palette.paper)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("documentView.download")
                    }

                    if isHost {
                        replaceControls(for: doc)
                    }
                } else {
                    Text(app.T("Không tìm thấy chứng từ.", "Couldn't find that document."))
                        .font(.system(size: 13)).foregroundStyle(app.palette.ink)
                        .padding(.horizontal, 22)
                    Spacer()
                }
            }
        }
        .accessibilityIdentifier("screen.documentView")
        .fileImporter(isPresented: $showReplacePicker, allowedContentTypes: [.pdf, .jpeg, .png, .image]) { result in
            if case .success(let url) = result { pendingFileURL = url; replacing = true }
        }
    }

    @ViewBuilder
    private func replaceControls(for doc: PaymentDocument) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !replacing {
                Button(app.T("Thay bằng bản khác", "Replace with a different file")) { showReplacePicker = true }
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(app.palette.rule, lineWidth: 1))
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("document.replaceButton")
            } else {
                Text(pendingFileURL?.lastPathComponent ?? "")
                    .font(.system(size: 12)).foregroundStyle(app.palette.ink.opacity(0.7))
                TextField(app.T("Lý do thay thế (bắt buộc) — khách sẽ thấy lý do này", "Reason for replacing (required) — the guest will see this"), text: $reason, axis: .vertical)
                    .font(.system(size: 12.5))
                    .padding(10)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(app.palette.rule, lineWidth: 1))
                    .accessibilityIdentifier("document.replaceReason")
                if !app.documentUploadError.isEmpty {
                    Text(app.documentUploadError).font(.system(size: 11.5)).foregroundStyle(BanbeTheme.alert)
                        .accessibilityIdentifier("document.replaceError")
                }
                HStack(spacing: 8) {
                    Button(app.T("Huỷ", "Cancel")) { replacing = false; pendingFileURL = nil }
                        .font(.system(size: 12)).foregroundStyle(app.palette.ink.opacity(0.7))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .buttonStyle(.plain)
                    Button(app.documentUploading ? app.T("Đang tải lên…", "Uploading…") : app.T("Xác nhận thay thế", "Confirm replacement")) {
                        Task { await submitReplacement(doc) }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(app.palette.paper)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(app.documentUploading ? app.palette.ink.opacity(0.5) : app.palette.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .buttonStyle(.plain)
                    .disabled(app.documentUploading)
                    .accessibilityIdentifier("document.replaceSubmit")
                }
            }
        }
        .padding(.horizontal, 22).padding(.bottom, 24)
    }

    private func submitReplacement(_ doc: PaymentDocument) async {
        guard let fileURL = pendingFileURL else { return }
        if reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            app.documentUploadError = app.T("Cần nêu lý do khi thay thế chứng từ đã có.", "A reason is required when replacing an existing document.")
            return
        }
        guard fileURL.startAccessingSecurityScopedResource() else { return }
        defer { fileURL.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let ext = fileURL.pathExtension.lowercased()
        let ok = await app.uploadPaymentDocument(bookingID: doc.bookingId, kind: doc.kind, fileData: data, fileExtension: ext.isEmpty ? "jpg" : ext, reason: reason)
        if ok {
            replacing = false
            pendingFileURL = nil
            reason = ""
            app.screen = app.documentBack
        }
    }
}

/// A web view that, for the legacy (`authenticated: true`) case, carries the
/// caller's Supabase access token on its own initial request, so
/// api/payment-document.js can let RLS decide whether this account may see
/// this document. An uploaded file's URL (`authenticated: false`) is a
/// Storage signed URL — the token is already in its query string, and
/// adding an Authorization header on top would be meaningless (and, for a
/// plain image/PDF being fetched directly rather than through PostgREST,
/// harmless either way, but there is no reason to send it).
private struct DocumentWebView: UIViewRepresentable {
    let url: URL
    var authenticated: Bool = true
    @Binding var failed: Bool
    @Binding var failedDetail: String
    @Binding var printRequested: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        context.coordinator.load(into: webView, url: url)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if printRequested {
            // Resetting this binding is itself deferred (SwiftUI forbids
            // mutating state synchronously from inside a view update), which
            // leaves a real window where an unrelated AppState change (e.g.
            // documentFileURLFailed/documentFileURLErrorDetail, both added
            // alongside this document viewer's error handling) re-triggers
            // updateUIView while printRequested is still true — calling
            // present(printFor:) a second time before the first call ever
            // resolved. That double-call on UIPrintInteractionController's
            // single shared instance (see present(printFor:) below — it has
            // no public initializer, so there is no "fresh instance" to
            // hand out instead) is exactly what produced the real-device
            // "cannot add handler to 0 from 0 - dropping" log spam with no
            // print job ever reaching Print Center: the coordinator's own
            // `isPresentingPrint` guard below is synchronous and doesn't
            // depend on this binding's reset timing, so it's the actual
            // re-entrancy guard now — this reset just clears the SwiftUI-level
            // flag so a later, separate tap can set it again.
            DispatchQueue.main.async { printRequested = false }
            context.coordinator.present(printFor: webView)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: DocumentWebView
        // Guards UIPrintInteractionController.shared re-entrancy — see the
        // comment on updateUIView above. Set the instant present() is
        // called, cleared only from the print controller's own completion
        // handler once that specific job has actually resolved (completed,
        // failed, or cancelled), never optimistically.
        private var isPresentingPrint = false
        init(_ parent: DocumentWebView) { self.parent = parent }

        func load(into webView: WKWebView, url: URL) {
            guard parent.authenticated else {
                webView.load(URLRequest(url: url))
                return
            }
            Task { @MainActor in
                var request = URLRequest(url: url)
                if let token = try? await SupabaseService.client.auth.session.accessToken {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                webView.load(request)
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.failed = true
            parent.failedDetail = "navigation error: \(error)"
        }

        // A network-level failure isn't the only way this can go wrong — an
        // expired/invalid signed URL (600s expiry on the storage token) or a
        // storage-side error still comes back as a normal HTTP response, just
        // a non-2xx one. Without this check, `didFinish` below fired
        // unconditionally on any completed navigation, `failed` stayed
        // false, and WKWebView just rendered the error's JSON/HTML body in
        // place of the document — no retry banner, nothing to indicate a
        // failure happened at all.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            if let http = navigationResponse.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                parent.failed = true
                parent.failedDetail = "HTTP \(http.statusCode) from \(http.url?.path ?? "?")"
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.failed = false
            parent.failedDetail = ""
        }

        /// iOS's own print/share pipeline, which is also how a page becomes a
        /// PDF on this platform — the counterpart of the web app handing the
        /// document to window.print().
        @MainActor
        func present(printFor webView: WKWebView) {
            // Apple gives no way to allocate a new UIPrintInteractionController
            // (no public init — only the `shared` class property exists, see
            // UIPrintInteractionController.h), so "fresh instance per attempt"
            // isn't available as a fix here. What actually matters is never
            // calling present() on it again while a previous call hasn't
            // resolved yet — that's what produced "cannot add handler to 0
            // from 0 - dropping" with no job reaching Print Center.
            guard !isPresentingPrint else { return }
            isPresentingPrint = true
            let controller = UIPrintInteractionController.shared
            let info = UIPrintInfo(dictionary: nil)
            info.outputType = .general
            info.jobName = "banbe"
            controller.printInfo = info
            controller.printFormatter = webView.viewPrintFormatter()
            let started = controller.present(animated: true) { [weak self] _, _, _ in
                self?.isPresentingPrint = false
            }
            // present(animated:completionHandler:) returns false when it
            // couldn't even start (e.g. printing unavailable) — in that case
            // the completion handler above never runs, so the guard must be
            // released here instead of staying stuck true forever.
            if !started { isPresentingPrint = false }
        }
    }
}
