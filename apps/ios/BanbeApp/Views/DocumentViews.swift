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
        return Button { app.openDocument(doc.id) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(doc.event.name ?? party)
                        .font(BanbeTheme.display(15)).foregroundStyle(app.palette.ink)
                        .lineLimit(1)
                    Text("\(doc.number) ▪︎ \(party)")
                        .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.7))
                        .lineLimit(1)
                    Text(formatVnd(doc.totalVnd))
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(app.palette.ink)
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
    @State private var printing = false

    var body: some View {
        ZStack {
            app.palette.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                BackLink(label: app.T("Quay lại", "Back")) { app.screen = .documents }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 14)
                    .accessibilityIdentifier("documentView.back")

                if let doc = app.currentDocument, let url = app.documentURL(doc.id) {
                    DocumentWebView(url: url, failed: $loadFailed, printRequested: $printing)
                        .accessibilityIdentifier("document.frame")

                    if loadFailed {
                        Text(app.T("Chưa tải được chứng từ. Kiểm tra kết nối rồi thử lại.",
                                   "Couldn't load the document. Check your connection and try again."))
                            .font(.system(size: 12.5)).foregroundStyle(BanbeTheme.alert)
                            .padding(.horizontal, 22).padding(.vertical, 10)
                    }

                    Button { printing = true } label: {
                        Text(app.T("Tải về ▪︎ In", "Download ▪︎ Print"))
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 18).padding(.bottom, 12)
                            .background(app.palette.ink)
                            .foregroundStyle(app.palette.paper)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("documentView.download")
                } else {
                    Text(app.T("Không tìm thấy chứng từ.", "Couldn't find that document."))
                        .font(.system(size: 13)).foregroundStyle(app.palette.ink)
                        .padding(.horizontal, 22)
                    Spacer()
                }
            }
        }
        .accessibilityIdentifier("screen.documentView")
    }
}

/// A web view that carries the caller's Supabase access token on its own
/// initial request, so api/payment-document.js can let RLS decide whether
/// this account may see this document.
private struct DocumentWebView: UIViewRepresentable {
    let url: URL
    @Binding var failed: Bool
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
            // Reset first: the print controller is presented asynchronously
            // and another updateUIView in the meantime would stack a second
            // sheet on top of the first.
            DispatchQueue.main.async { printRequested = false }
            context.coordinator.present(printFor: webView)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: DocumentWebView
        init(_ parent: DocumentWebView) { self.parent = parent }

        func load(into webView: WKWebView, url: URL) {
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
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.failed = false
        }

        /// iOS's own print/share pipeline, which is also how a page becomes a
        /// PDF on this platform — the counterpart of the web app handing the
        /// document to window.print().
        @MainActor
        func present(printFor webView: WKWebView) {
            let controller = UIPrintInteractionController.shared
            let info = UIPrintInfo(dictionary: nil)
            info.outputType = .general
            info.jobName = "banbe"
            controller.printInfo = info
            controller.printFormatter = webView.viewPrintFormatter()
            controller.present(animated: true, completionHandler: nil)
        }
    }
}
