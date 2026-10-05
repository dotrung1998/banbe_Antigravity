import SwiftUI

/// "Tặng vé cho bạn bè" (migration 132) — real gifting, not a shared link.
///
/// Two explicit steps and one result, presented as a `.fullScreenCover` from
/// RootView off `app.giftTicketContext`:
///   1. collect the recipient's full name, email and date of birth,
///   2. review exactly what is about to happen to WHICH seat,
///   3. hand over the PDF (and the .ics) once the server has actually moved it.
///
/// The recipient needs no banbe account to attend — the PDF's QR is the door
/// credential. The account claim is a separate, optional step they take later.
struct GiftTicketView: View {
    @EnvironmentObject var app: AppState

    private var context: GiftTicketContext? { app.giftTicketContext }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch app.giftFormStep {
                    case .form: formStep
                    case .review: reviewStep
                    case .done: doneStep
                    }
                }
                .padding(20)
                .padding(.top, 16)
            }
            .background(app.palette.paper)
            .foregroundStyle(app.palette.ink)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(app.T("Huỷ", "Cancel")) { app.closeGiftForm() }
                        .accessibilityIdentifier("gift.cancel")
                }
            }
        }
    }

    // MARK: - Step 1: who is it for

    @ViewBuilder
    private var formStep: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(app.T("Tặng vé cho bạn bè", "Gift this ticket")).font(BanbeTheme.display(24))
            Text(app.T("Vé sẽ được đổi tên sang người nhận. Bạn vẫn giữ quyền sở hữu vé và mọi khoản hoàn tiền.",
                       "The ticket is reassigned to the recipient. You keep ownership of the booking and of any refund."))
                .font(.system(size: 13)).lineSpacing(3).opacity(0.85)
        }

        if let context {
            VStack(alignment: .leading, spacing: 3) {
                Text(app.T("Sự kiện", "Event")).font(.system(size: 11)).opacity(0.65)
                Text(context.eventName.isEmpty ? app.T("Sự kiện của bạn", "Your event") : context.eventName)
                    .font(.system(size: 15, weight: .semibold))
                Text(context.seats > 1
                     ? app.T("Chuyển đúng 1 chỗ trong \(context.seats) chỗ của bạn.",
                             "Moves exactly 1 of your \(context.seats) seats.")
                     : app.T("Chuyển toàn bộ chỗ của bạn.", "Moves your single seat."))
                    .font(.system(size: 12)).opacity(0.75)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }

        BanbeField(label: app.T("Họ và tên", "Full name"), placeholder: app.T("Nguyễn Thị Bảo Châu", "Alex Nguyen"),
                   text: $app.giftFormName, required: true)
            .accessibilityIdentifier("gift.name")
        BanbeField(label: app.T("Email", "Email"), placeholder: "banbe@example.com",
                   text: $app.giftFormEmail, keyboard: .emailAddress, required: true)
            .accessibilityIdentifier("gift.email")

        VStack(alignment: .leading, spacing: 5) {
            Text(app.T("Ngày sinh", "Date of birth")).font(.system(size: 11.5))
            DatePicker("", selection: $app.giftFormDOB, in: ...Date(), displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .environment(\.locale, Locale(identifier: app.isEN ? "en_US" : "vi_VN"))
                .accessibilityIdentifier("gift.dob")
        }

        Text(app.T("Người nhận dùng email này để nhập vé vào tài khoản banbe nếu họ muốn. Họ vẫn có thể tham dự chỉ với mã QR, không cần tài khoản.",
                   "The recipient uses this email to import the ticket into a banbe account if they want to. They can still attend with the QR alone, no account needed."))
            .font(.system(size: 11.5)).lineSpacing(2.5).opacity(0.7)

        if !app.giftError.isEmpty {
            Text(app.giftError).font(.system(size: 12)).foregroundStyle(BanbeTheme.alert)
                .accessibilityIdentifier("gift.error")
        }

        InkButton(title: app.T("Tiếp tục", "Continue"), enabled: app.giftForm.isValid) {
            app.advanceGiftToReview()
        }
        .accessibilityIdentifier("gift.continue")
    }

    // MARK: - Step 2: review before anything moves

    @ViewBuilder
    private var reviewStep: some View {
        let form = app.giftForm
        Text(app.T("Kiểm tra lại", "Review")).font(BanbeTheme.display(24))

        VStack(spacing: 0) {
            reviewRow(app.T("Người nhận", "Recipient"), form.trimmedName)
            Divider().overlay(app.palette.rule)
            reviewRow(app.T("Email", "Email"), form.trimmedEmail)
            Divider().overlay(app.palette.rule)
            reviewRow(app.T("Ngày sinh", "Date of birth"), Self.dobText(form.dob, isEN: app.isEN))
            if let context {
                Divider().overlay(app.palette.rule)
                reviewRow(app.T("Sự kiện", "Event"),
                          context.eventName.isEmpty ? app.T("Sự kiện của bạn", "Your event") : context.eventName)
                Divider().overlay(app.palette.rule)
                reviewRow(app.T("Phạm vi", "Scope"),
                          context.seats > 1
                            ? app.T("1 trong \(context.seats) chỗ", "1 of \(context.seats) seats")
                            : app.T("Toàn bộ chỗ của bạn", "Your only seat"))
            }
        }
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

        Text(app.T("Xác nhận sẽ làm mất hiệu lực mã QR cũ của bạn và cấp mã mới cho người nhận. Mã cũ không dùng để vào cửa được nữa.",
                   "Confirming invalidates your own QR and issues a new one to the recipient. Your previous QR will no longer admit anyone."))
            .font(.system(size: 12)).lineSpacing(2.5).opacity(0.8)

        if !app.giftError.isEmpty {
            Text(app.giftError).font(.system(size: 12)).foregroundStyle(BanbeTheme.alert)
        }

        InkButton(title: app.giftBusy ? app.T("Đang tặng…", "Gifting…") : app.T("Xác nhận tặng vé", "Confirm gift"),
                  enabled: !app.giftBusy) {
            Task { await app.confirmGift() }
        }
        .opacity(app.giftBusy ? 0.6 : 1)
        .accessibilityIdentifier("gift.confirm")

        Button(app.T("Sửa thông tin", "Edit details")) { app.giftFormStep = .form }
            .font(.system(size: 12.5, weight: .semibold))
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .foregroundStyle(app.palette.ink)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(app.palette.rule))
            .buttonStyle(.plain)
            .disabled(app.giftBusy)
    }

    // MARK: - Step 3: hand it over

    @ViewBuilder
    private var doneStep: some View {
        let result = app.giftResult
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(BanbeTheme.alert)
            Text(app.T("Đã tặng vé", "Ticket gifted")).font(BanbeTheme.display(22))
        }
        .padding(.bottom, 4)

        if let name = result?.recipientName {
            Text(app.T("Vé đã được chuyển cho \(name).", "The ticket now belongs to \(name)."))
                .font(.system(size: 13)).opacity(0.85)
        }
        Text(app.T("Vé này không còn là vé vào cửa của bạn. Bạn vẫn sở hữu giao dịch và mọi quyền hoàn tiền nếu người tổ chức huỷ sự kiện.",
                   "This is no longer your admission ticket. You still own the transaction and any right to a refund if the organizer cancels."))
            .font(.system(size: 12)).lineSpacing(2.5).opacity(0.75)

        if let url = app.giftPDFURL {
            ShareLink(item: url, subject: Text(app.T("Vé banbe của bạn", "Your banbe ticket"))) {
                Label(app.T("Chia sẻ / tải vé PDF", "Share or download the PDF"), systemImage: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(app.palette.paper)
            }
            .accessibilityIdentifier("gift.sharePDF")
        } else {
            Text(app.T("Không tạo được tệp PDF. Hãy thử lại sau.",
                       "The PDF couldn't be generated. Please try again later."))
                .font(.system(size: 12)).foregroundStyle(BanbeTheme.alert)
        }

        if let url = app.giftICSURL {
            ShareLink(item: url, subject: Text(app.T("Thêm vào lịch", "Add to calendar"))) {
                Label(app.T("Chia sẻ tệp lịch .ics", "Share the .ics calendar file"), systemImage: "calendar")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .foregroundStyle(app.palette.ink)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(app.palette.rule))
            }
            .accessibilityIdentifier("gift.shareICS")
        }

        Text(app.T("Gửi kèm vé PDF cho người nhận. Người nhận dùng mã QR để vào cửa, và dùng mã nhận vé (trong tin nhắn của bạn) để nhập vé vào tài khoản banbe nếu họ muốn.",
                   "Send the PDF to the recipient. They use the QR to get in, and the claim code (in your message) to import the ticket into a banbe account if they want to."))
            .font(.system(size: 11.5)).lineSpacing(2.5).opacity(0.7)

        if let code = result?.claimCode {
            VStack(alignment: .leading, spacing: 3) {
                Text(app.T("Mã nhận vé (gửi riêng cho người nhận)", "Claim code (send separately to the recipient)"))
                    .font(.system(size: 11)).opacity(0.65)
                Text(code)
                    .font(.system(size: 15, weight: .semibold)).kerning(1.2)
                    .textSelection(.enabled)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityIdentifier("gift.claimCode")
        }

        Button(app.T("Xong", "Done")) { app.closeGiftForm() }
            .font(.system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity).padding(.vertical, 15)
            .foregroundStyle(app.palette.ink)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(app.palette.rule))
            .buttonStyle(.plain)
            .accessibilityIdentifier("gift.done")
    }

    private func reviewRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title).font(.system(size: 12.5)).opacity(0.65)
            Spacer(minLength: 12)
            Text(value).font(.system(size: 13.5, weight: .semibold)).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    static func dobText(_ date: Date, isEN: Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: isEN ? "en_US" : "vi_VN")
        f.dateFormat = isEN ? "dd/MM/yyyy" : "dd/MM/yyyy"
        f.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")
        return f.string(from: date)
    }
}

/// The recipient's explicit import entry point — a claim code, never the
/// check-in QR value. Presented as a `.fullScreenCover` off
/// `app.giftImportOpen`, from Tickets & Bookings and from the `banbe://gift/claim`
/// link printed on the gift PDF.
///
/// The server is the authority: it compares the signed-in account's VERIFIED
/// email against the address the ticket was sent to. A date of birth is not
/// accepted as proof of ownership, because it is self-asserted.
struct GiftImportView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(app.T("Nhập vé được tặng", "Import a gift ticket"))
                        .font(BanbeTheme.display(24))

                    Text(app.T("Nhập mã nhận vé mà người tặng (hoặc người đặt vé nhóm) gửi cho bạn. Mã này khác với mã QR dùng điểm danh. Nếu bạn nhận được vé PDF, chạm nút \"Mở trong banbe\" trong PDF để mã tự điền.",
                               "Enter the claim code the giver — or whoever booked the group — sent you. It is different from the check-in QR code. If you have the PDF, tap its \"Open in banbe\" button and the code fills itself in."))
                        .font(.system(size: 13)).lineSpacing(3).opacity(0.85)

                    BanbeField(label: app.T("Mã nhận vé", "Claim code"),
                               placeholder: "CLAIM-… / ATT-…",
                               text: $app.giftImportCode)
                        .accessibilityIdentifier("giftImport.code")

                    if app.isSignedIn, let email = app.userEmail, !email.isEmpty {
                        Text(app.T("Đang đăng nhập với \(email). Vé được tặng chỉ nhập được bằng đúng email người nhận; vé nhóm (mã ATT-) chỉ cần mã và email đã xác minh.",
                                   "Signed in as \(email). A gifted ticket needs the recipient's email; a group ticket (ATT- code) needs only the code and a verified email."))
                            .font(.system(size: 11.5)).lineSpacing(2.5).opacity(0.7)
                    } else {
                        Text(app.T("Bạn sẽ được yêu cầu đăng nhập bằng email nhận vé trước khi nhập.",
                                   "You'll be asked to sign in with the recipient email first."))
                            .font(.system(size: 11.5)).lineSpacing(2.5).opacity(0.7)
                    }

                    if !app.giftImportError.isEmpty {
                        Text(app.giftImportError).font(.system(size: 12)).foregroundStyle(BanbeTheme.alert)
                            .accessibilityIdentifier("giftImport.error")
                    }
                    if !app.giftImportNotice.isEmpty {
                        Text(app.giftImportNotice).font(.system(size: 12.5))
                            .accessibilityIdentifier("giftImport.notice")
                    }

                    InkButton(title: app.giftImportBusy ? app.T("Đang nhập…", "Importing…") : app.T("Nhập vé", "Import ticket"),
                              enabled: !app.giftImportBusy) {
                        Task { await app.claimGiftTicket() }
                    }
                    .opacity(app.giftImportBusy ? 0.6 : 1)
                    .accessibilityIdentifier("giftImport.submit")

                    Text(app.T("Bạn không cần tài khoản để tham dự: mã QR trên vé PDF là đủ. Nhập vé chỉ để lưu vé vào tài khoản.",
                               "You don't need an account to attend: the QR on the PDF is enough. Importing only saves the ticket to your account."))
                        .font(.system(size: 11.5)).lineSpacing(2.5).opacity(0.7)
                }
                .padding(20)
                .padding(.top, 16)
            }
            .background(app.palette.paper)
            .foregroundStyle(app.palette.ink)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(app.T("Huỷ", "Cancel")) { app.closeGiftImport() }
                        .accessibilityIdentifier("giftImport.cancel")
                }
            }
        }
    }
}

/// A ticket another account imported into this one (migration 152): the name,
/// entry code and QR the door scans, and a PDF — nothing about the booking's
/// payment, which stays with the buyer.
struct ImportedTicketView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let ticket: ImportedTicket
    @State private var share: PDFShareItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                Button(app.T("Đóng", "Close")) { dismiss() }.font(.system(size: 14))
            }
            Text(ticket.eventName).font(BanbeTheme.display(24))
            Text(ticket.name).font(.system(size: 15, weight: .semibold))
            if let when = ticket.startsAt {
                Text(when.formatted(date: .complete, time: .shortened)).font(.system(size: 12.5)).opacity(0.7)
            }
            if ticket.isVoid {
                Text(app.T("Vé này đã bị huỷ và không còn hiệu lực.", "This ticket was cancelled and is no longer valid."))
                    .font(.system(size: 13)).foregroundStyle(BanbeTheme.alert)
            } else {
                HStack {
                    Spacer()
                    QRCodeImage(value: ticket.admissionToken.uuidString, size: 200)
                    Spacer()
                }
                .padding(.top, 6)
                Text(app.T("Mã vào cửa: ", "Entry code: ") + ticket.ticketCode)
                    .font(.system(size: 13, weight: .semibold)).kerning(1.5)
                    .frame(maxWidth: .infinity)
                if ticket.checkedInAt != nil {
                    Text(app.T("Đã vào cửa", "Checked in"))
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(BanbeTheme.alert)
                        .frame(maxWidth: .infinity)
                }
                Button {
                    if let url = app.exportImportedTicketPDF(ticket) { share = PDFShareItem(url: url) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc")
                        Text(app.T("Tải vé PDF", "Download PDF")).font(.system(size: 13.5, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("importedTicket.download")
            }
            Spacer()
        }
        .foregroundStyle(app.palette.ink)
        .padding(22)
        .background(app.palette.paper.ignoresSafeArea())
        .sheet(item: $share) { item in ActivityShareSheet(url: item.url) }
        .accessibilityIdentifier("importedTicket.sheet")
    }
}
