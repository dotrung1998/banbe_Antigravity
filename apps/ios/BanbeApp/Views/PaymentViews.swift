import SwiftUI
import PhotosUI

/// The buyer's side of the two-phase payment machine.
///
/// PHASE 1 ('holding')              — running countdown, scannable VietQR
///                                    with amount and reference baked in,
///                                    and the "I have transferred" form.
/// PHASE 2 ('pendingVerification')  — NO countdown at all. The single most
///                                    important thing this screen says is
///                                    that the clock has stopped and the
///                                    seat is safe; a buyer who still sees a
///                                    timer after paying assumes they are
///                                    about to lose what they just paid for.
struct PaymentDetailsView: View {
    @EnvironmentObject private var app: AppState
    @State private var photoItem: PhotosPickerItem?
    @State private var pickedImage: Data?
    @State private var pickedPreview: UIImage?
    @State private var pickedName = ""
    @State private var pickError = ""
    @State private var tick = Date()
    @State private var pollTask: Task<Void, Never>?

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var booking: PayableBooking? {
        app.paymentBookings.first { $0.id == app.paymentBookingID }
    }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                // A rejected/cancelled booking is over — going back to
                // whatever screen sent the guest here (often still
                // mid-transition off a now-dead timer UI) is exactly the
                // "lingering countdown before actually leaving" this was
                // fixed for. Straight to Home instead, every time.
                BackLink(label: app.T("Quay lại", "Back")) {
                    app.screen = (booking?.paymentState == .cancelled) ? .home : app.paymentBack
                }
                    .padding(.top, 8).padding(.horizontal, 22)
                    .accessibilityIdentifier("payment.back")

                if let booking {
                    content(booking)
                } else {
                    Text(app.paymentsLoading
                         ? app.T("Đang tải…", "Loading…")
                         : app.T("Không tìm thấy khoản thanh toán này.", "Couldn't find that payment."))
                        .font(.system(size: 13))
                        .foregroundStyle(app.palette.ink)
                        .padding(.horizontal, 22).padding(.top, 18)
                }
            }
            .padding(.bottom, 40)
        }
        .accessibilityIdentifier("screen.paymentDetails")
        .task { await app.loadPaymentBookings() }
        // PHASE 1 drives the "seat held for" clock. PHASE 2 (14-organizer-
        // checkin.md follow-up) now ALSO ticks — not a second "your seat is
        // at risk" countdown, but a separate, informational read-only one
        // for the ORGANIZER's own confirm-window deadline (`verifyDueAt`).
        .onReceive(ticker) { now in
            guard let booking, booking.paymentState.isCountingDown || booking.isFrozen else { return }
            tick = now
            // The moment this screen's own clock notices the hold has
            // lapsed, forfeit it immediately — self-guards against firing
            // twice, since the local patch flips paymentState to .expired
            // on the very next tick, and isCountingDown follows straight
            // from that.
            if booking.paymentState.isCountingDown, let deadline = booking.holdExpiresAt,
               Countdown.secondsUntil(deadline, now: now) == 0 {
                app.forfeitExpiredHold(booking)
            }
        }
        .onAppear { startPollingIfNeeded() }
        .onChange(of: booking?.paymentState) { _, _ in startPollingIfNeeded() }
        .onDisappear { pollTask?.cancel() }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                pickError = ""
                if let data = try? await item.loadTransferable(type: Data.self), let uiImage = UIImage(data: data) {
                    // Re-encode to JPEG regardless of the source format —
                    // PhotosPicker commonly hands back HEIC straight off the
                    // camera roll, which the 'pay-proof' bucket's allowlist
                    // (image/jpeg, image/png, image/webp, application/pdf;
                    // supabase/migrations/20260913000024_…) does not accept.
                    // Decoding through UIImage also gives the preview below
                    // for free, and guarantees the bytes actually match
                    // whatever content-type submitPaymentProof declares
                    // (previously hardcoded to "image/jpeg" over whatever
                    // the raw picked bytes really were).
                    //
                    // ProofImage downscales/re-compresses as needed to land
                    // under the bucket's 5 MB cap — a plain
                    // `jpegData(compressionQuality: 0.9)` on a full-resolution
                    // camera photo (commonly 6-12 MB) blew straight past that
                    // limit and was silently rejected by Storage, independent
                    // of format, which is exactly what was still failing here.
                    pickedImage = ProofImage.jpegDataUnderLimit(from: uiImage)
                    pickedPreview = uiImage
                    pickedName = app.T("Đã chọn ảnh biên lai", "Receipt image selected")
                } else {
                    pickedImage = nil
                    pickedPreview = nil
                    pickError = app.T("Không đọc được ảnh này. Thử một ảnh khác.", "Couldn't read that photo. Try a different one.")
                }
                photoItem = nil
            }
        }
    }

    @ViewBuilder
    private func content(_ booking: PayableBooking) -> some View {
        let phase = booking.paymentState
        VStack(alignment: .leading, spacing: 0) {
            Text({
                switch phase {
                case .confirmed: return app.T("Đã thanh toán", "Paid")
                case .pendingVerification: return app.T("Đang chờ xác nhận", "Awaiting confirmation")
                case .disputed: return app.T("Đang được xem xét", "Under review")
                case .expired: return app.T("Đã hết hạn giữ chỗ", "Hold expired")
                case .cancelled: return app.T("Đã bị từ chối", "Booking declined")
                default: return app.T("Thanh toán", "Payment")
                }
            }())
                .font(BanbeTheme.display(24)).foregroundStyle(app.palette.ink)
                .padding(.top, 14)
            Text(booking.eventName)
                .font(.system(size: 12.5)).foregroundStyle(app.palette.ink.opacity(0.75))
                .padding(.top, 6)

            if phase == .holding, let deadline = booking.holdExpiresAt {
                countdownCard(deadline)
            }
            if phase == .pendingVerification { frozenCard(booking) }
            // reject_payment ("Can't find it") flags this without disputing
            // it — paymentState stays .pendingVerification, so this is a
            // sibling of frozenCard above, not the .disputed branch below.
            if phase == .pendingVerification, let reason = booking.disputeReason, !reason.isEmpty {
                needsInfoCard(booking, reason: reason)
            }
            if phase == .disputed { disputedCard(booking) }
            // reject_pending_guest() (migration 059) — a dedicated terminal
            // view, not the generic "no payment details" notice below,
            // which is meant for an unconfigured-payment-info case, not a
            // declined booking.
            if phase == .cancelled { rejectedCard(booking) }

            amountCard(booking)

            if phase == .confirmed {
                paidBlock
            } else if phase == .holding || phase == .pendingVerification {
                if let payload = VietQR.payload(for: booking) { qrCard(payload) }
                if booking.hasAnyPayRail { transferBlock(booking) }
                referenceBlock(booking)
                if !booking.payNote.isEmpty {
                    Text(booking.payNote).font(.system(size: 12.5)).padding(.top, 16)
                }
                if phase == .holding { transferredForm(booking) }
            } else if phase != .cancelled && !booking.hasAnyPayRail {
                noticeCard(app.T("Người tổ chức chưa thêm thông tin nhận tiền. Nhắn cho họ để hỏi cách chuyển khoản.",
                                 "The organizer hasn't added payment details yet. Message them to ask how to transfer."))
                    .accessibilityIdentifier("payment.noDetails")
            }

            Button { app.openBilling() } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.T("Thông tin xuất hoá đơn", "Billing details"))
                            .font(.system(size: 14)).foregroundStyle(app.palette.ink)
                        Text(app.T("Tên và địa chỉ in trên hoá đơn, biên nhận.",
                                   "The name and address printed on your documents."))
                            .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.7))
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Text("›").font(.system(size: 15)).foregroundStyle(app.palette.ink)
                }
                .padding(16)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain).padding(.top, 20)
            .accessibilityIdentifier("payment.billingLink")

            Text(app.T("banbe không thu tiền và không giữ tiền. Bạn chuyển trực tiếp cho người tổ chức; nếu họ hủy, họ có trách nhiệm hoàn tiền cho bạn.",
                       "banbe does not collect or hold money. You pay the organizer directly; if they cancel, they are responsible for refunding you."))
                .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.65))
                .padding(.top, 20)
        }
        .padding(.horizontal, 22)
    }

    private func countdownCard(_ deadline: Date) -> some View {
        let remaining = max(0, Int(deadline.timeIntervalSince(tick)))
        return HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(app.T("Giữ chỗ còn", "Seat held for"))
                    .font(.system(size: 11.5, weight: .semibold))
                Text(app.T("Chuyển khoản rồi bấm \"Tôi đã chuyển khoản\" trước khi hết giờ.",
                           "Transfer, then tap \"I have transferred\" before this runs out."))
                    .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.7))
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            Text(String(format: "%02d:%02d", remaining / 60, remaining % 60))
                .font(BanbeTheme.display(30)).monospacedDigit()
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 18).padding(.vertical, 16)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.top, 16)
        .accessibilityIdentifier("payment.countdown")
    }

    private func frozenCard(_ booking: PayableBooking) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(app.T("Chỗ của bạn đã được khoá ▪︎ không còn đếm ngược",
                       "Your seat is locked ▪︎ the countdown has stopped"))
                .font(.system(size: 13.5, weight: .semibold))
            Text(app.T("Người tổ chức đang đối chiếu khoản chuyển khoản của bạn. Chỗ sẽ không bị huỷ trong lúc chờ.",
                       "The organizer is checking your transfer against their statement. The seat will not be released while you wait."))
                .font(.system(size: 12.5)).foregroundStyle(app.palette.ink.opacity(0.75))
            if !booking.transactionId.isEmpty {
                Text(app.T("Mã giao dịch đã gửi: ", "Transaction ID submitted: ") + booking.transactionId)
                    .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.7))
            }
            // 14-organizer-checkin.md follow-up: read-only — this is the
            // organizer's own confirm-window clock, not a second "your seat
            // is at risk" countdown.
            if let deadline = booking.verifyDueAt {
                HStack {
                    Text(app.T("Người tổ chức xác nhận trong", "Organizer confirms within"))
                        .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.7))
                    Spacer()
                    Text(Countdown.format(Countdown.secondsUntil(deadline, now: tick)))
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                }
                .padding(.top, 4)
                .accessibilityIdentifier("payment.organizerCountdown")
            }
            // The ONE actionable control on this screen — everything else
            // here is read-only status. Disables itself (not just visually
            // — nudgeOrganizer() itself refuses past 2, server-side) once
            // nudgeCount reaches the RPC's own limit.
            Button {
                Task { await app.nudgeOrganizer(bookingID: booking.id) }
            } label: {
                Text(app.nudgeSending
                     ? app.T("Đang gửi…", "Sending…")
                     : booking.nudgeCount >= 2
                     ? app.T("Đã nhắc tối đa 2 lần", "Nudged the max 2 times")
                     : app.T("Nhắc người tổ chức xác nhận", "Remind the organizer to confirm"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(app.palette.rule))
            }
            .buttonStyle(.plain)
            .foregroundStyle(app.palette.ink)
            .opacity(booking.nudgeCount >= 2 || app.nudgeSending ? 0.4 : 1)
            .disabled(booking.nudgeCount >= 2 || app.nudgeSending)
            .padding(.top, 4)
            .accessibilityIdentifier("payment.nudgeOrganizer")
            // Warn BEFORE the limit is spent, not just disable silently
            // after — a guest should get to choose when their 2 nudges are
            // worth using, not discover the cap only once it's too late.
            if booking.nudgeCount < 2 {
                Text(app.T("Bạn chỉ có thể nhắc tối đa 2 lần — hãy chọn thời điểm phù hợp.",
                           "You can only nudge up to 2 times — choose the right moment."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(app.palette.ink.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
                    .accessibilityIdentifier("payment.nudgeLimitNote")
            }
            if !app.nudgeError.isEmpty {
                Text(app.nudgeError).font(.system(size: 11.5)).foregroundStyle(BanbeTheme.alert)
            }
        }
        .foregroundStyle(app.palette.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.top, 16)
        .accessibilityIdentifier("payment.frozen")
    }

    private func disputedCard(_ booking: PayableBooking) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(app.T("banbe đang xem xét", "banbe is reviewing this"))
                    .font(.system(size: 13.5, weight: .semibold))
                Text(app.T("Người tổ chức chưa đối chiếu được khoản này. Chỗ của bạn vẫn được giữ trong lúc banbe xem xét.",
                           "The organizer couldn't match this against their statement. Your seat stays held while banbe reviews it."))
                    .font(.system(size: 12.5)).foregroundStyle(app.palette.ink.opacity(0.75))
            }
            .foregroundStyle(app.palette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityIdentifier("payment.disputed")

            DisputeChatPanel(bookingID: booking.id)
        }
        .padding(.top, 16)
    }

    private func needsInfoCard(_ booking: PayableBooking, reason: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(app.T("Người tổ chức cần thêm thông tin", "The organizer needs more information"))
                    .font(.system(size: 13.5, weight: .semibold))
                Text(reason)
                    .font(.system(size: 12.5)).foregroundStyle(app.palette.ink.opacity(0.75))
            }
            .foregroundStyle(app.palette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityIdentifier("payment.needsInfo")

            DisputeChatPanel(bookingID: booking.id)
        }
        .padding(.top, 16)
    }

    /// reject_pending_guest() (migration 059) — this booking is over: the
    /// seat already went back to the pool and every timer already stopped
    /// server-side. Shows the organizer's own stated reason rather than the
    /// generic "no payment details" notice this used to fall through to.
    private func rejectedCard(_ booking: PayableBooking) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(app.T("Người tổ chức đã từ chối yêu cầu này", "The organizer declined this booking"))
                .font(.system(size: 13.5, weight: .semibold))
            Text((booking.cancelReason?.isEmpty == false ? booking.cancelReason! : nil)
                 ?? app.T("Không có lý do cụ thể được nêu.", "No specific reason was given."))
                .font(.system(size: 12.5)).foregroundStyle(app.palette.ink.opacity(0.75))
            Text(app.T("Chỗ đã được trả lại. Bạn có thể tìm sự kiện khác hoặc nhắn cho người tổ chức nếu có thắc mắc.",
                       "The seat has been released. You can look for another event, or message the organizer if you have questions."))
                .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.6))
                .padding(.top, 2)
        }
        .foregroundStyle(app.palette.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.top, 16)
        .accessibilityIdentifier("payment.rejected")
    }

    private func amountCard(_ booking: PayableBooking) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(app.T("Số tiền", "Amount"))
                .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.7))
            Text(formatVnd(booking.totalVnd))
                .font(BanbeTheme.display(30)).foregroundStyle(app.palette.ink)
                .accessibilityIdentifier("payment.amount")
            Text("\(booking.qty) " + app.T("vé", booking.qty == 1 ? "ticket" : "tickets"))
                .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.vertical, 18)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.top, 14)
    }

    private func qrCard(_ payload: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(app.T("Quét để chuyển khoản", "Scan to pay"))
                .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(app.palette.ink)
            VStack(spacing: 10) {
                // Fixed black-on-white, like the ticket QR: a banking app's
                // camera does not know about the app's palette.
                QRCodeImage(value: payload)
                    .frame(width: 210, height: 210)
                    .accessibilityIdentifier("payment.vietqr")
                Text(app.T("Mở app ngân hàng, quét mã — số tiền và nội dung đã được điền sẵn.",
                           "Open your banking app and scan — the amount and reference are filled in already."))
                    .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(18)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.top, 20)
    }

    private func transferBlock(_ booking: PayableBooking) -> some View {
        var rows: [(String, String, String)] = []
        if booking.hasBank {
            rows.append((app.T("Ngân hàng", "Bank"), booking.bankName, "bank_name"))
            rows.append((app.T("Số tài khoản", "Account number"), booking.bankAccountNo, "bank_no"))
            rows.append((app.T("Chủ tài khoản", "Account name"), booking.bankAccountName, "holder"))
        }
        if booking.hasMomo { rows.append(("MoMo", booking.momoPhone, "momo")) }
        return VStack(alignment: .leading, spacing: 10) {
            Text(app.T("Hoặc chuyển thủ công", "Or transfer manually"))
                .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(app.palette.ink)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.2) { index, row in
                    copyRow(label: row.0, value: row.1, key: row.2)
                    if index < rows.count - 1 { Rectangle().fill(app.palette.rule).frame(height: 1) }
                }
            }
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.top, 20)
    }

    private func copyRow(label: String, value: String, key: String) -> some View {
        Button { app.copyPayField(key, value) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.system(size: 11)).foregroundStyle(app.palette.ink.opacity(0.65))
                    Text(value).font(.system(size: 14, weight: .semibold)).foregroundStyle(app.palette.ink)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Text(app.paymentCopied == key ? app.T("Đã chép", "Copied") : app.T("Chép", "Copy"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(app.palette.ink.opacity(0.75))
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }

    private func referenceBlock(_ booking: PayableBooking) -> some View {
        let reference = booking.paymentRef.isEmpty ? booking.code : booking.paymentRef
        return VStack(alignment: .leading, spacing: 10) {
            Text(app.T("Nội dung chuyển khoản", "Transfer reference"))
                .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(app.palette.ink)
            Button { app.copyPayField("reference", reference) } label: {
                HStack {
                    Text(reference).font(BanbeTheme.display(20)).tracking(2.5)
                        .foregroundStyle(app.palette.ink)
                    Spacer()
                    Text(app.paymentCopied == "reference" ? app.T("Đã chép", "Copied") : app.T("Chép", "Copy"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(app.palette.ink.opacity(0.75))
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("payment.reference")

            Text(app.T("Ghi đúng mã này — hệ thống đối soát tự động dựa vào nó để xác nhận ngay khi tiền tới.",
                       "Use this exact reference — automatic reconciliation uses it to confirm you the moment the money lands."))
                .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.7))
        }
        .padding(.top, 16)
    }

    /// The PHASE 1 -> PHASE 2 form. Both a transaction id and an image are
    /// required: a receipt with no transaction id is not reconcilable.
    private func transferredForm(_ booking: PayableBooking) -> some View {
        let canSubmit = pickedImage != nil
            && !app.paymentTxnId.trimmingCharacters(in: .whitespaces).isEmpty
            && !app.paymentProofUploading

        return VStack(alignment: .leading, spacing: 10) {
            Text(app.T("Sau khi chuyển", "After you transfer"))
                .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(app.palette.ink)
            VStack(alignment: .leading, spacing: 12) {
                BanbeField(label: app.T("Mã giao dịch", "Transaction ID"),
                           placeholder: app.T("Ví dụ FT24123456789", "e.g. FT24123456789"),
                           text: $app.paymentTxnId)
                    .accessibilityIdentifier("payment.txnId")
                Text(app.T("Tìm trong biên lai của app ngân hàng.", "Find it on the receipt in your banking app."))
                    .font(.system(size: 11)).foregroundStyle(app.palette.ink.opacity(0.65))

                // A thumbnail of whatever was just picked — this row used
                // to only ever show a static "Receipt image selected"
                // label, so there was no way to notice a wrong photo before
                // submitting it.
                if let pickedPreview {
                    Image(uiImage: pickedPreview)
                        .resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 220)
                        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityIdentifier("payment.proofPreview")
                }
                if !pickError.isEmpty {
                    Text(pickError).font(.system(size: 12)).foregroundStyle(Color(red: 0.60, green: 0.24, blue: 0.18))
                }

                PhotosPicker(selection: $photoItem, matching: .images) {
                    HStack {
                        Text(pickedImage == nil
                             ? app.T("Chọn ảnh biên lai", "Choose a receipt image")
                             : pickedName)
                            .font(.system(size: 13.5)).foregroundStyle(app.palette.ink)
                        Spacer()
                        Text(pickedImage == nil ? app.T("Chọn", "Choose") : app.T("Đổi", "Change"))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(app.palette.ink.opacity(0.75))
                    }
                    .padding(13)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .accessibilityIdentifier("payment.proofPick")

                Button {
                    guard let data = pickedImage else { return }
                    Task {
                        await app.submitPaymentProof(bookingID: booking.id, imageData: data,
                                                     transactionID: app.paymentTxnId)
                    }
                } label: {
                    Text(app.paymentProofUploading
                         ? app.T("Đang gửi…", "Sending…")
                         : app.T("Tôi đã chuyển khoản", "I have transferred"))
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(canSubmit ? app.palette.ink : app.palette.ink.opacity(0.35),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(app.palette.paper)
                }
                .buttonStyle(.plain).disabled(!canSubmit)
                .accessibilityIdentifier("payment.submitProof")

                Text(app.T("Bấm nút này sẽ dừng đồng hồ và khoá chỗ của bạn cho tới khi người tổ chức xác nhận.",
                           "Tapping this stops the clock and locks your seat until the organizer confirms."))
                    .font(.system(size: 11)).foregroundStyle(app.palette.ink.opacity(0.65))

                if !app.paymentProofError.isEmpty {
                    Text(app.paymentProofError)
                        .font(.system(size: 12)).foregroundStyle(BanbeTheme.alert)
                        .accessibilityIdentifier("payment.submitError")
                }
            }
            .padding(16)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.top, 22)
    }

    private var paidBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(app.T("Đã xác nhận. Vé và biên nhận của bạn đã sẵn sàng.",
                       "Confirmed. Your ticket and receipt are ready."))
                .font(.system(size: 13)).foregroundStyle(app.palette.ink)
            InkButton(title: app.T("Xem biên nhận", "View receipt"), cornerRadius: 14) {
                app.openDocuments(kind: "receipt", role: "guest")
            }
        }
        .padding(16)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.top, 14)
        .accessibilityIdentifier("payment.paidNote")
    }

    private func noticeCard(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13)).foregroundStyle(app.palette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.top, 14)
    }

    /// Bug 1 (01-hold-payment.md follow-up): this screen used to fetch
    /// `paymentBookings` once per appearance (the `.task` above) and never
    /// again while it stayed mounted — a real phase change while the guest
    /// stayed on this exact screen (tapping "Tôi đã chuyển khoản" itself,
    /// or the organizer acting from elsewhere) never patched `app.paymentBookings`,
    /// so swiping back to it later could still show a frozen countdown
    /// instead of the correct pending_verification state. Mirrors
    /// `ConfirmedView`'s own `startPollingIfNeeded()` for the identical
    /// reason.
    private func startPollingIfNeeded() {
        pollTask?.cancel()
        guard let bookingID = booking?.id, let phaseAtStart = booking?.paymentState,
              phaseAtStart != .confirmed, phaseAtStart != .expired, phaseAtStart != .cancelled
        else { return }
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                if Task.isCancelled { break }
                guard booking?.id == bookingID, booking?.paymentState == phaseAtStart else { return }
                guard let fresh: Booking = try? await SupabaseService.client
                    .from("bookings").select().eq("id", value: bookingID.uuidString)
                    .single().execute().value
                else { continue }
                guard let idx = app.paymentBookings.firstIndex(where: { $0.id == bookingID }) else { return }
                if fresh.paymentState != phaseAtStart {
                    app.paymentBookings[idx].status = fresh.status
                    app.paymentBookings[idx].paymentState = fresh.paymentState
                    app.paymentBookings[idx].paymentRef = fresh.paymentRef ?? app.paymentBookings[idx].paymentRef
                    app.paymentBookings[idx].holdExpiresAt = fresh.holdExpiresAt
                    app.paymentBookings[idx].transactionId = fresh.transactionId ?? app.paymentBookings[idx].transactionId
                    app.paymentBookings[idx].verifyDueAt = fresh.verifyDueAt
                    app.paymentBookings[idx].paidMarkedAt = fresh.paidMarkedAt
                    app.paymentBookings[idx].cancelReason = fresh.cancelReason
                    return
                }
            }
        }
    }
}

/// The buyer block on every invoice and receipt this account is ever issued.
/// Kept apart from "Rename" on purpose: what you are called in the app and
/// what belongs on a document are frequently not the same thing.
struct BillingView: View {
    @EnvironmentObject private var app: AppState

    // An address is what a document actually needs and the field a person is
    // most likely to skip, so it — not the name — gates saving.
    private var canSave: Bool {
        !app.billingName.trimmingCharacters(in: .whitespaces).isEmpty
        && !app.billingAddress.trimmingCharacters(in: .whitespaces).isEmpty
        && !app.billingSaving
    }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.T("Quay lại", "Back")) { app.screen = .paymentDetails }
                    .padding(.top, 8)

                Text(app.T("Thông tin xuất hoá đơn", "Billing details"))
                    .font(BanbeTheme.display(24)).foregroundStyle(app.palette.ink)
                    .padding(.top, 14)
                Text(app.T("Được in vào phần \"Bên mua\" trên hoá đơn và biên nhận của bạn.",
                           "Printed in the \"Buyer\" block of your invoices and receipts."))
                    .font(.system(size: 12.5)).foregroundStyle(app.palette.ink.opacity(0.75))
                    .padding(.top, 8)

                VStack(spacing: 12) {
                    BanbeField(label: app.T("Tên người mua", "Buyer name"),
                               placeholder: app.T("Cá nhân hoặc công ty", "Person or company"),
                               text: $app.billingName)
                        .accessibilityIdentifier("billing.name")
                    BanbeField(label: app.T("Địa chỉ", "Address"),
                               placeholder: app.T("Số nhà, đường, phường, quận, thành phố",
                                                  "Street, ward, district, city"),
                               text: $app.billingAddress)
                        .accessibilityIdentifier("billing.address")
                    BanbeField(label: app.T("Điện thoại", "Phone"), placeholder: "09xx xxx xxx",
                               text: $app.billingPhone, keyboard: .phonePad)
                        .accessibilityIdentifier("billing.phone")
                    BanbeField(label: app.T("Mã số thuế (nếu có)", "Tax code (optional)"),
                               placeholder: app.T("Dành cho công ty", "For companies"),
                               text: $app.billingTaxCode, keyboard: .numberPad)
                        .accessibilityIdentifier("billing.tax")
                }
                .padding(.top, 20)

                InkButton(title: app.billingSaving ? app.T("Đang lưu…", "Saving…") : app.T("Lưu", "Save"),
                          enabled: canSave) {
                    Task { await app.saveBillingDetails() }
                }
                .padding(.top, 20)
                .accessibilityIdentifier("billing.save")

                if app.billingSaved {
                    Text(app.T("Đã lưu.", "Saved."))
                        .font(.system(size: 12.5)).foregroundStyle(app.palette.ink.opacity(0.75))
                        .padding(.top, 12)
                        .accessibilityIdentifier("billing.saved")
                }
                if !app.billingError.isEmpty {
                    Text(app.billingError).font(.system(size: 12))
                        .foregroundStyle(BanbeTheme.alert).padding(.top, 12)
                }

                Text(app.T("Thay đổi ở đây chỉ áp dụng cho chứng từ phát hành sau đó. Hoá đơn đã thanh toán giữ nguyên thông tin lúc phát hành.",
                           "Changes apply to documents issued afterwards. Anything already paid keeps the details it was issued with."))
                    .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.65))
                    .padding(.top, 20)
            }
            .padding(.horizontal, 22).padding(.bottom, 40)
        }
        .accessibilityIdentifier("screen.billing")
    }
}

/// Where the organizer says how they want to be paid. Without this filled in
/// a guest's payment screen has nothing to show, so it is the one hosting
/// setting that actually blocks money moving.
struct PayoutView: View {
    @EnvironmentObject private var app: AppState

    // Either rail is enough. save_organizer_payment() derives pay_methods
    // from whichever fields are non-empty, so a half-filled bank block can
    // never advertise itself to a guest.
    private var canSave: Bool {
        (!app.payoutAccountNo.trimmingCharacters(in: .whitespaces).isEmpty
         || !app.payoutMomo.trimmingCharacters(in: .whitespaces).isEmpty)
        && !app.payoutSaving
    }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.T("Tài khoản", "Account")) { app.screen = .profile }
                    .padding(.top, 8)

                Text(app.T("Nhận thanh toán", "Getting paid"))
                    .font(BanbeTheme.display(24)).foregroundStyle(app.palette.ink)
                    .padding(.top, 14)
                Text(app.T("Khách chuyển khoản thẳng cho bạn. banbe không giữ tiền và không thu phí.",
                           "Guests transfer straight to you. banbe never holds the money and takes no cut."))
                    .font(.system(size: 12.5)).foregroundStyle(app.palette.ink.opacity(0.75))
                    .padding(.top, 8)

                section(app.T("Ngân hàng", "Bank")) {
                    BanbeField(label: app.T("Tên ngân hàng", "Bank name"), placeholder: "Vietcombank",
                               text: $app.payoutBankName).accessibilityIdentifier("payout.bank")
                    BanbeField(label: app.T("Số tài khoản", "Account number"), placeholder: "0071000…",
                               text: $app.payoutAccountNo, keyboard: .numberPad)
                        .accessibilityIdentifier("payout.accountNo")
                    BanbeField(label: app.T("Chủ tài khoản", "Account name"), placeholder: "NGUYEN VAN A",
                               text: $app.payoutAccountName).accessibilityIdentifier("payout.accountName")
                }

                section(app.T("Ví MoMo", "MoMo wallet")) {
                    BanbeField(label: app.T("Số điện thoại MoMo", "MoMo phone"), placeholder: "09xx xxx xxx",
                               text: $app.payoutMomo, keyboard: .phonePad)
                        .accessibilityIdentifier("payout.momo")
                }

                section(app.T("Trên chứng từ", "On your documents")) {
                    BanbeField(label: app.T("Địa chỉ", "Address"),
                               placeholder: app.T("Số nhà, đường, phường, quận, thành phố",
                                                  "Street, ward, district, city"),
                               text: $app.payoutAddress).accessibilityIdentifier("payout.address")
                    BanbeField(label: app.T("Mã số thuế (nếu có)", "Tax code (optional)"),
                               placeholder: app.T("Dành cho hộ kinh doanh, công ty", "For registered businesses"),
                               text: $app.payoutTaxCode, keyboard: .numberPad)
                        .accessibilityIdentifier("payout.tax")
                    BanbeField(label: app.T("Ghi chú cho khách", "Note to guests"),
                               placeholder: app.T("Ví dụ: chuyển trước 24h để giữ chỗ",
                                                  "e.g. transfer 24h ahead to keep your seat"),
                               text: $app.payoutNote).accessibilityIdentifier("payout.note")
                }

                InkButton(title: app.payoutSaving ? app.T("Đang lưu…", "Saving…") : app.T("Lưu", "Save"),
                          enabled: canSave) {
                    Task { await app.savePayoutDetails() }
                }
                .padding(.top, 20)
                .accessibilityIdentifier("payout.save")

                if app.payoutSaved {
                    Text(app.T("Đã lưu. Khách sẽ thấy thông tin này khi thanh toán.",
                               "Saved. Guests will see this when they pay."))
                        .font(.system(size: 12.5)).foregroundStyle(app.palette.ink.opacity(0.75))
                        .padding(.top, 12)
                        .accessibilityIdentifier("payout.saved")
                }
                if !app.payoutError.isEmpty {
                    Text(app.payoutError).font(.system(size: 12))
                        .foregroundStyle(BanbeTheme.alert).padding(.top, 12)
                }
            }
            .padding(.horizontal, 22).padding(.bottom, 40)
        }
        .accessibilityIdentifier("screen.payout")
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(app.palette.ink)
            VStack(spacing: 12) { content() }
        }
        .padding(.top, 20)
    }
}
