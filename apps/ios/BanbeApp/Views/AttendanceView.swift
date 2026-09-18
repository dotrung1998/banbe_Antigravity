import SwiftUI
import UniformTypeIdentifiers

/// Port of src/screens/Attendance.jsx — the real guest list for an event
/// (actual bookings, not a placeholder), tap to check someone in, scan
/// their ticket QR, or cancel a booking. Reversing a check-in always asks
/// for a reason first (ReasonSheet).
struct AttendanceView: View {
    @EnvironmentObject var app: AppState
    // Which guest's "Upload receipt" is currently driving the file picker —
    // .fileImporter needs one shared presentation per view, not one per row.
    @State private var uploadTarget: UUID?
    @State private var uploadErrorFor: UUID?
    // Replacing an existing live receipt requires a reason
    // (upload_payment_document()'s own REASON_REQUIRED gate, migration
    // 056) — pendingReplace holds the already-read file data until the
    // organizer actually supplies one. Only entered when the guest already
    // hasReceipt; a first upload skips straight to uploadPaymentDocument()
    // with no reason needed, matching the RPC's own condition exactly. Data
    // is copied out of the picked URL immediately (not deferred) since a
    // fileImporter URL's security-scoped access isn't guaranteed to survive
    // across view updates.
    @State private var pendingReplace: PendingReceiptUpload?
    @State private var replaceReason: String = ""

    private struct PendingReceiptUpload {
        let bookingID: UUID
        let data: Data
        let ext: String
    }
    // request_receipt() (migration 061) deep-links here via
    // openNotification() — the guest's own "Xem Receipt" asked for one
    // that doesn't exist yet. Mirrors DisputeChatPanel's chatHighlight
    // scroll/flash pattern: scroll the matching guest row into view, flash
    // it briefly, then clear the request so it doesn't refire.
    @State private var highlightedGuestID: UUID?
    // 15-organizer-checkin.md follow-up: this screen only ever reloaded on
    // appear or right after the organizer's own actions (accept/reject/
    // check-in) — a guest holding a NEW slot or submitting payment while
    // the organizer already has this screen open never showed up until
    // they left and reopened it. Matches this app's own polling convention
    // elsewhere (PaymentViews' 6s poll) — no realtime subscription exists
    // anywhere in this codebase.
    @State private var pollTask: Task<Void, Never>?

    private var event: CatalogEvent? { EventCatalog.find(app.attendanceEventKey) }
    private var checkedCount: Int { app.attendanceGuests.filter(\.checkedIn).count }

    var body: some View {
        ScreenScaffold {
            ScrollViewReader { proxy in
                content(proxy: proxy)
            }
        }
        .onAppear { startPolling() }
        .onChange(of: app.attendanceEventKey) { _, _ in startPolling() }
        .onDisappear { pollTask?.cancel() }
        .fileImporter(
            isPresented: Binding(get: { uploadTarget != nil }, set: { if !$0 { uploadTarget = nil } }),
            allowedContentTypes: [.pdf, .jpeg, .png, .image]
        ) { result in
            guard let bookingID = uploadTarget else { return }
            uploadTarget = nil
            switch result {
            case .success(let url):
                Task { await handlePickedReceipt(bookingID: bookingID, url: url) }
            case .failure(let error):
                print("Attendance receipt picker failed:", error)
            }
        }
    }

    @ViewBuilder
    private func content(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.attendanceBack == .notifications ? app.T("Thông báo", "Notifications") : app.T("Trang của bạn", "Your dashboard")) { app.screen = app.attendanceBack }

                if let event {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(app.T("Điểm danh khách", "Guest check-in"))
                                .font(.system(size: 11.5, weight: .semibold))
                            Text(event.name).font(BanbeTheme.display(24))
                            Text(app.trStatus(event.when)).font(.system(size: 12.5))
                        }
                        Spacer(minLength: 0)
                        Button(app.T("Quét QR", "Scan QR")) { app.scanningQr = true }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(app.palette.paper)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .buttonStyle(.plain)
                    }
                    .padding(.top, 14)

                    HStack {
                        Text(app.T("Đã đến", "Checked in"))
                            .font(.system(size: 12.5))
                            .foregroundStyle(app.palette.paper)
                        Spacer()
                        Text("\(checkedCount) / \(app.attendanceGuests.count)")
                            .font(BanbeTheme.display(24))
                            .foregroundStyle(app.palette.paper)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 16)
                    .background(app.palette.ink)
                    .padding(.top, 18)

                    Text(app.T("Chạm vào tên khách hoặc quét mã QR vé khi họ tới nơi.",
                               "Tap a guest's name, or scan their ticket QR, when they arrive."))
                        .font(.system(size: 11.5))
                        .lineSpacing(2)

                    Text(app.T("Đánh dấu \"Đã thanh toán\" khi bạn thấy tiền vào tài khoản, rồi tải lên hoá đơn/biên nhận thật của bạn cho khách.",
                               "Mark a guest paid once you see the money arrive, then upload your own real invoice/receipt for them."))
                        .font(.system(size: 11.5))
                        .foregroundStyle(app.palette.ink.opacity(0.7))
                        .lineSpacing(2)
                        .padding(.top, 10)

                    VStack(spacing: 0) {
                        if app.attendanceGuests.isEmpty {
                            Text(app.attendanceLoading
                                 ? app.T("Đang tải danh sách khách…", "Loading guest list…")
                                 : app.T("Chưa có ai đặt chỗ cho sự kiện này.", "No one has booked this event yet."))
                                .font(.system(size: 12.5))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                        }
                        ForEach(app.attendanceGuests) { guest in
                            guestRow(guest)
                                .id(guest.id)
                            if guest.id != app.attendanceGuests.last?.id {
                                Divider().overlay(app.palette.rule)
                            }
                        }
                    }
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.top, 14)
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 40)
            // request_receipt() deep-link: scroll the matching guest row
            // into view and flash it, once the guests list has actually
            // loaded (openAttendance sets attendanceGuests = [] first, then
            // loads — this can't scroll to a row that isn't rendered yet).
            .onChange(of: app.attendanceHighlightBookingID) { _, _ in scrollToHighlightIfNeeded(proxy: proxy) }
            .onChange(of: app.attendanceGuests) { _, _ in scrollToHighlightIfNeeded(proxy: proxy) }
    }

    private func startPolling() {
        pollTask?.cancel()
        guard let key = app.attendanceEventKey else { return }
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                if Task.isCancelled { return }
                guard app.attendanceEventKey == key else { return }
                await app.loadAttendanceGuests(key)
            }
        }
    }

    private func scrollToHighlightIfNeeded(proxy: ScrollViewProxy) {
        guard let target = app.attendanceHighlightBookingID,
              app.attendanceGuests.contains(where: { $0.id == target }) else { return }
        withAnimation { proxy.scrollTo(target, anchor: .center) }
        highlightedGuestID = target
        app.attendanceHighlightBookingID = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            if highlightedGuestID == target { highlightedGuestID = nil }
        }
    }

    private func handlePickedReceipt(bookingID: UUID, url: URL) async {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else { return }
        let ext = url.pathExtension.lowercased()
        let fileExt = ext.isEmpty ? "jpg" : ext
        // Matches upload_payment_document()'s own condition exactly: a
        // reason is required only when a live document already exists for
        // this booking+kind (loadAttendanceGuests() populates hasReceipt).
        if app.attendanceGuests.first(where: { $0.id == bookingID })?.hasReceipt == true {
            pendingReplace = PendingReceiptUpload(bookingID: bookingID, data: data, ext: fileExt)
            replaceReason = ""
            return
        }
        await runUpload(bookingID: bookingID, data: data, ext: fileExt, reason: "")
    }

    private func runUpload(bookingID: UUID, data: Data, ext: String, reason: String) async {
        uploadErrorFor = nil
        let ok = await app.uploadPaymentDocument(bookingID: bookingID, kind: "receipt", fileData: data, fileExtension: ext, reason: reason)
        uploadErrorFor = ok ? nil : bookingID
        if ok {
            pendingReplace = nil
            replaceReason = ""
            if let key = app.attendanceEventKey { await app.loadAttendanceGuests(key) }
        }
    }

    private func submitReplace() async {
        guard let pending = pendingReplace else { return }
        let trimmed = replaceReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return } // the button below is disabled in this case too
        await runUpload(bookingID: pending.bookingID, data: pending.data, ext: pending.ext, reason: trimmed)
    }

    private func guestRow(_ guest: AttendanceGuest) -> some View {
        // 14-organizer-checkin.md (Bugs 2a/3): check-in only makes sense once
        // payment is actually confirmed — an unpaid guest's row is no longer
        // tap-to-check-in at all (it used to be, regardless of payment
        // state, which is what made check-in reachable on a guest whose
        // payment hadn't even been reviewed yet).
        Button {
            if guest.paid { app.toggleCheckIn(guest) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(guest.name).font(BanbeTheme.display(15))
                    Text((guest.qty > 1 ? "\(guest.qty)" + app.T(" vé", " tickets") : app.T("1 vé", "1 ticket"))
                         + " ▪︎ " + formatVnd(guest.totalVnd))
                        .font(.system(size: 11.5))

                    if guest.paid {
                        Text(app.T("Đã thanh toán ✓", "Paid ✓"))
                            .font(.system(size: 11))
                            .foregroundStyle(app.palette.ink.opacity(0.7))
                            .accessibilityIdentifier("guest.paid")

                        Button(app.documentUploading && uploadTarget == guest.id
                               ? app.T("Đang tải lên…", "Uploading…")
                               : (guest.hasReceipt ? app.T("Thay biên nhận", "Replace receipt") : app.T("Tải lên biên nhận", "Upload receipt"))) {
                            uploadTarget = guest.id
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(app.palette.ink)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(highlightedGuestID == guest.id ? BanbeTheme.alert : app.palette.rule,
                                        lineWidth: highlightedGuestID == guest.id ? 2 : 1)
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(highlightedGuestID == guest.id ? BanbeTheme.alert.opacity(0.12) : Color.clear)
                        )
                        .animation(.easeInOut(duration: 0.3), value: highlightedGuestID)
                        .buttonStyle(.plain)
                        .disabled(app.documentUploading)
                        .accessibilityIdentifier("guest.uploadReceipt")

                        // Was a bare count with no way to actually open
                        // either file (08-payment-documents.md's
                        // 2026-09-17 follow-up #7 — BUG 1) — now each
                        // version is its own tappable row, opening straight
                        // into DocumentView the same way Documents.jsx's own
                        // rows do. Only shown once there's more than the
                        // trivial single-current-receipt case, keeping the
                        // far more common single-upload row uncluttered.
                        if guest.receiptPendingDelete > 0 {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(app.T("Phiên bản hiện tại (\(guest.receiptVersionCount))", "Current version (\(guest.receiptVersionCount))"))
                                    .font(.system(size: 10)).foregroundStyle(app.palette.ink.opacity(0.5))
                                    .accessibilityIdentifier("guest.receiptVersion")
                                ForEach(guest.receipts) { receipt in
                                    Button(receipt.isLive ? app.T("Bản hiện tại ›", "Current copy ›") : app.T("Bản cũ · xoá sau 24h ›", "Old copy · deletes in 24h ›")) {
                                        Task { await app.openDocumentFromNotification(receipt.id, backTo: .attendance, role: "host") }
                                    }
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(app.palette.ink.opacity(receipt.isLive ? 0.85 : 0.6))
                                    .underline()
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier(receipt.isLive ? "guest.receiptCurrent" : "guest.receiptOld")
                                }
                            }
                            .padding(.top, 1)
                        }

                        if pendingReplace?.bookingID == guest.id {
                            VStack(alignment: .leading, spacing: 6) {
                                TextField(app.T("Vì sao thay thế bản cũ?", "Why are you replacing the old one?"), text: $replaceReason, axis: .vertical)
                                    .font(.system(size: 11.5))
                                    .padding(8)
                                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(app.palette.rule, lineWidth: 1))
                                    .accessibilityIdentifier("guest.replaceReason")
                                HStack(spacing: 6) {
                                    Button(app.T("Huỷ", "Cancel")) { pendingReplace = nil; replaceReason = "" }
                                        .font(.system(size: 11))
                                        .foregroundStyle(app.palette.ink.opacity(0.7))
                                        .buttonStyle(.plain)
                                    Spacer()
                                    let trimmedReason = replaceReason.trimmingCharacters(in: .whitespacesAndNewlines)
                                    Button(app.documentUploading ? app.T("Đang tải lên…", "Uploading…") : app.T("Xác nhận thay thế", "Confirm replacement")) {
                                        Task { await submitReplace() }
                                    }
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(app.palette.paper)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(trimmedReason.isEmpty || app.documentUploading ? app.palette.ink.opacity(0.35) : app.palette.ink, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .buttonStyle(.plain)
                                    .disabled(trimmedReason.isEmpty || app.documentUploading)
                                    .accessibilityIdentifier("guest.replaceSubmit")
                                }
                            }
                            .padding(.top, 2)
                        } else if uploadErrorFor == guest.id {
                            Text(app.documentUploadError.isEmpty
                                 ? app.T("Không tải lên được. Thử lại nhé.", "Couldn't upload. Please try again.")
                                 : app.documentUploadError)
                                .font(.system(size: 10.5))
                                .foregroundStyle(BanbeTheme.alert)
                                .accessibilityIdentifier("guest.uploadError")
                        }
                    } else {
                        Text(app.T("Có nhận khách này không?", "Accept this guest?"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(app.palette.ink.opacity(0.8))

                        HStack(spacing: 6) {
                            // The screenshot the guest already sent is the
                            // strongest signal there is that this is the
                            // right guest to accept.
                            Button(guest.hasProof
                                   ? app.T("Khách đã gửi biên lai ▪︎ Nhận", "Guest sent proof ▪︎ Accept")
                                   : app.T("Nhận", "Accept")) {
                                Task { await app.markGuestPaid(guest.id) }
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(app.palette.ink)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(app.palette.rule, lineWidth: 1))
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("guest.accept")

                            Button(app.T("Từ chối", "Reject")) { app.openRejectGuest(guest) }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(BanbeTheme.alert.opacity(0.8))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(BanbeTheme.alert.opacity(0.2), lineWidth: 1))
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("guest.reject")
                        }

                        // Same muted-alert convention as "Huỷ vé" below —
                        // distinct from "Từ chối" but not a new color.
                        // Only shown once there's something concrete to go
                        // check — a guest who hasn't submitted proof yet has
                        // nothing to review in Verifications.
                        if guest.hasProof {
                            Button(app.T("Kiểm tra thanh toán ›", "Check payment ›")) {
                                app.openVerificationDetail(bookingID: guest.id, eventKey: app.attendanceEventKey)
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(BanbeTheme.alert.opacity(0.8))
                            .buttonStyle(.plain)
                            .padding(.top, 2)
                            .accessibilityIdentifier("guest.checkPayment")
                        }
                    }

                    Button(app.T("Huỷ vé", "Cancel booking")) { app.openCancelBooking(guest) }
                        .font(.system(size: 11))
                        .foregroundStyle(BanbeTheme.alert.opacity(0.8))
                        .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                Text(guest.checkedIn ? app.T("Đã đến ✓", "Here ✓") : guest.paid ? app.T("Chưa đến", "Not yet") : app.T("Chưa thanh toán", "Not paid yet"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(guest.checkedIn ? app.palette.paper : app.palette.ink)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(guest.checkedIn ? app.palette.ink : app.palette.ink.opacity(0.16))
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 16).padding(.vertical, 13)
            .background(guest.checkedIn ? app.palette.ink.opacity(0.08) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
