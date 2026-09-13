import SwiftUI
import PhotosUI

/// Where a guest is told how to pay, and how they say they have.
///
/// Deliberately does not look like a checkout. banbe is not in the middle of
/// this transfer, and a guest who believes the app took their money will
/// bring the problem to the app when something goes wrong.
struct PaymentDetailsView: View {
    @EnvironmentObject private var app: AppState
    @State private var photoItem: PhotosPickerItem?

    private var booking: PayableBooking? {
        app.paymentBookings.first { $0.id == app.paymentBookingID }
    }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.T("Quay lại", "Back")) { app.screen = app.paymentBack }
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
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let id = app.paymentBookingID {
                    await app.uploadPaymentProof(bookingID: id, imageData: data)
                }
                photoItem = nil
            }
        }
    }

    @ViewBuilder
    private func content(_ booking: PayableBooking) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(booking.isPaid ? app.T("Đã thanh toán", "Paid") : app.T("Thanh toán", "Payment"))
                .font(BanbeTheme.display(24)).foregroundStyle(app.palette.ink)
                .padding(.top, 14)
            Text(booking.eventName)
                .font(.system(size: 12.5)).foregroundStyle(app.palette.ink.opacity(0.75))
                .padding(.top, 6)

            // Amount
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
            .padding(.top, 18)

            if booking.isPaid {
                paidBlock
            } else if !booking.hasAnyPayRail {
                noticeCard(app.T(
                    "Người tổ chức chưa thêm thông tin nhận tiền. Nhắn cho họ trong phần Tin nhắn để hỏi cách chuyển khoản.",
                    "The organizer hasn't added payment details yet. Message them to ask how to transfer."))
                    .accessibilityIdentifier("payment.noDetails")
            } else {
                transferBlock(booking)
                referenceBlock(booking)
                if !booking.payNote.isEmpty {
                    Text(booking.payNote)
                        .font(.system(size: 12.5)).foregroundStyle(app.palette.ink)
                        .padding(.top, 16)
                }
                afterTransferBlock(booking)
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
            .buttonStyle(.plain)
            .padding(.top, 20)
            .accessibilityIdentifier("payment.billingLink")

            Text(app.T(
                "banbe không thu tiền và không giữ tiền. Bạn chuyển trực tiếp cho người tổ chức; nếu họ hủy, họ có trách nhiệm hoàn tiền cho bạn.",
                "banbe does not collect or hold money. You pay the organizer directly; if they cancel, they are responsible for refunding you."))
                .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.65))
                .padding(.top, 20)
        }
        .padding(.horizontal, 22)
    }

    private var paidBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(app.T("Người tổ chức đã xác nhận nhận được tiền. Biên nhận của bạn đã sẵn sàng.",
                       "The organizer confirmed the money arrived. Your receipt is ready."))
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

    private func transferBlock(_ booking: PayableBooking) -> some View {
        var rows: [(String, String, String)] = []
        if booking.hasBank {
            rows.append((app.T("Ngân hàng", "Bank"), booking.bankName, "bank_name"))
            rows.append((app.T("Số tài khoản", "Account number"), booking.bankAccountNo, "bank_no"))
            rows.append((app.T("Chủ tài khoản", "Account name"), booking.bankAccountName, "bank_holder"))
        }
        if booking.hasMomo {
            rows.append(("MoMo", booking.momoPhone, "momo"))
        }
        return VStack(alignment: .leading, spacing: 10) {
            Text(app.T("Chuyển khoản tới", "Transfer to"))
                .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(app.palette.ink)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.2) { index, row in
                    copyRow(label: row.0, value: row.1, key: row.2)
                    if index < rows.count - 1 {
                        Rectangle().fill(app.palette.rule).frame(height: 1)
                    }
                }
            }
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.top, 20)
    }

    private func copyRow(label: String, value: String, key: String) -> some View {
        Button { app.copyPayField(key, value) } label: {
            HStack(alignment: .center, spacing: 12) {
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
        VStack(alignment: .leading, spacing: 10) {
            Text(app.T("Nội dung chuyển khoản", "Transfer reference"))
                .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(app.palette.ink)
            Button { app.copyPayField("reference", booking.code) } label: {
                HStack {
                    Text(booking.code)
                        .font(BanbeTheme.display(20)).tracking(2.5)
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

            // In Vietnam this is how an organizer matches an incoming
            // transfer to a person at all, so it gets the same weight as the
            // amount rather than being a footnote.
            Text(app.T("Ghi đúng mã này khi chuyển khoản — người tổ chức dựa vào nó để biết ai đã trả.",
                       "Use this exact reference — it is how the organizer knows the transfer is yours."))
                .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.7))
        }
        .padding(.top, 16)
    }

    private func afterTransferBlock(_ booking: PayableBooking) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(app.T("Sau khi chuyển", "After you transfer"))
                .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(app.palette.ink)
            VStack(alignment: .leading, spacing: 12) {
                Text(booking.proofUploadedAt != nil
                     ? app.T("Đã gửi xác nhận. Người tổ chức sẽ kiểm tra và đánh dấu đã thanh toán.",
                             "Confirmation sent. The organizer will check and mark it paid.")
                     : app.T("Gửi ảnh chụp biên lai để người tổ chức xác nhận nhanh hơn.",
                             "Send a screenshot of your transfer so the organizer can confirm faster."))
                    .font(.system(size: 13)).foregroundStyle(app.palette.ink)

                PhotosPicker(selection: $photoItem, matching: .images) {
                    Text(app.paymentProofUploading
                         ? app.T("Đang gửi…", "Sending…")
                         : booking.proofUploadedAt != nil
                            ? app.T("Gửi ảnh khác", "Send another")
                            : app.T("Tôi đã chuyển khoản", "I've transferred"))
                        .font(.system(size: 13.5, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(app.palette.paper)
                }
                .disabled(app.paymentProofUploading)
                .accessibilityIdentifier("payment.proofUpload")

                if !app.paymentProofError.isEmpty {
                    Text(app.paymentProofError)
                        .font(.system(size: 12)).foregroundStyle(BanbeTheme.alert)
                }
            }
            .padding(16)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.top, 22)
    }

    private func noticeCard(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13)).foregroundStyle(app.palette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.top, 14)
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
