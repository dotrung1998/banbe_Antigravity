import SwiftUI

/// Refund MVP (product rule B) — Account > "Tài khoản thanh toán & nhận
/// hoàn tiền": the goer's own saved bank accounts, used as refund
/// destinations. Reachable on its own (AccountView), and also opened
/// mid-flow from a refund claim's "Thêm tài khoản mới" (PaymentDetailsView,
/// via `refundAccountsReturnToClaimID`), in which case saving returns
/// straight back to that claim with the new account selected.
struct RefundAccountsView: View {
    @EnvironmentObject private var app: AppState

    @State private var formOpen = false
    @State private var editingID: UUID?
    @State private var label = ""
    @State private var bank = ""
    @State private var account = ""
    @State private var holder = ""
    @State private var note = ""
    @State private var setDefault = false
    @State private var confirmed = false
    @State private var revealedID: UUID?
    @State private var confirmDeleteID: UUID?
    @State private var savedFlash = false

    private var canSave: Bool {
        !bank.trimmingCharacters(in: .whitespaces).isEmpty
            && !account.trimmingCharacters(in: .whitespaces).isEmpty
            && !holder.trimmingCharacters(in: .whitespaces).isEmpty
            && confirmed && !app.refundDestinationBusy
    }

    private func openAddForm() {
        formOpen = true; editingID = nil; label = ""; bank = ""; account = ""; holder = ""; note = ""
        setDefault = app.refundDestinations.isEmpty; confirmed = false
    }
    private func openEditForm(_ d: RefundDestination) {
        formOpen = true; editingID = d.id; label = d.label ?? ""; bank = d.bankName; account = d.accountNumber
        holder = d.accountHolderName; note = d.transferNote ?? ""; setDefault = d.isDefault; confirmed = false
    }

    private func doSave() {
        guard canSave else { return }
        let wasNew = editingID == nil
        Task {
            let newID = await app.saveRefundDestination(
                id: editingID, label: label.trimmingCharacters(in: .whitespaces), bankName: bank.trimmingCharacters(in: .whitespaces),
                accountNumber: account.trimmingCharacters(in: .whitespaces), accountHolderName: holder.trimmingCharacters(in: .whitespaces),
                transferNote: note.trimmingCharacters(in: .whitespaces), setDefault: setDefault, confirmed: confirmed
            )
            guard let newID else { return }
            formOpen = false
            savedFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { savedFlash = false }
            if wasNew, let claimID = app.refundAccountsReturnToClaimID {
                let bookingID = app.refundAccountsReturnToBookingID
                _ = await app.selectRefundDestinationForClaim(claimID: claimID, destinationID: newID)
                if let bookingID {
                    app.paymentBookingID = bookingID
                    app.screen = .paymentDetails
                    app.refundAccountsReturnToClaimID = nil
                    app.refundAccountsReturnToBookingID = nil
                }
            }
        }
    }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.T("Tài khoản", "Account")) { app.backFromRefundAccounts() }

                Text(app.T("Tài khoản thanh toán & nhận hoàn tiền", "Payment & refund accounts"))
                    .font(BanbeTheme.display(24)).padding(.top, 14)
                Text(app.T("Lưu tài khoản ngân hàng để nhận tiền hoàn khi vé bị huỷ.", "Save a bank account to receive refunds when a booking is cancelled."))
                    .font(.system(size: 12.5)).foregroundStyle(app.palette.ink.opacity(0.75)).padding(.top, 8)

                if savedFlash {
                    Text(app.T("Tài khoản nhận hoàn đã được lưu", "Refund account saved"))
                        .font(.system(size: 12.5)).padding(.top, 12)
                }

                if !formOpen {
                    if app.refundDestinations.isEmpty {
                        Text(app.T("Chưa có tài khoản nhận hoàn tiền", "No refund accounts saved yet"))
                            .font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .center)
                            .padding(20).background(app.palette.field, in: RoundedRectangle(cornerRadius: 14)).padding(.top, 16)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(app.refundDestinations) { d in
                                accountRow(d)
                                if d.id != app.refundDestinations.last?.id { Divider().overlay(app.palette.rule) }
                            }
                        }
                        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14)).padding(.top, 16)
                    }
                    Button(app.T("Thêm tài khoản mới", "Add a new account"), action: openAddForm)
                        .font(.system(size: 13)).foregroundStyle(app.palette.ink)
                        .frame(maxWidth: .infinity).padding(13)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(app.palette.rule))
                        .padding(.top, 12)
                        .accessibilityIdentifier("refund.accountAdd")
                } else {
                    formView
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 40)
        }
    }

    @ViewBuilder
    private func accountRow(_ d: RefundDestination) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(d.label ?? app.T("Tài khoản", "Account")).font(BanbeTheme.display(14))
                if d.isDefault {
                    Text(app.T("Mặc định", "Default")).font(.system(size: 10, weight: .semibold)).foregroundStyle(app.palette.ink.opacity(0.6))
                }
            }
            Text("\(d.bankName) ▪︎ \(revealedID == d.id ? d.accountNumber : maskAccountNumber(d.accountNumber)) ▪︎ \(d.accountHolderName)")
                .font(.system(size: 12)).foregroundStyle(app.palette.ink.opacity(0.75))
            HStack(spacing: 14) {
                Button(revealedID == d.id ? app.T("Ẩn", "Hide") : app.T("Hiện số TK", "Reveal")) {
                    revealedID = revealedID == d.id ? nil : d.id
                }
                Button(app.T("Sửa", "Edit")) { openEditForm(d) }
                if !d.isDefault {
                    Button(app.T("Đặt mặc định", "Set default")) { Task { await app.setDefaultRefundDestination(d.id) } }
                }
                Button(app.T("Xoá", "Delete")) { confirmDeleteID = d.id }
                    .foregroundStyle(BanbeTheme.alert)
            }
            .font(.system(size: 11.5))
            if confirmDeleteID == d.id {
                HStack {
                    Text(app.T("Xoá tài khoản này?", "Delete this account?")).font(.system(size: 11.5))
                    Spacer()
                    Button(app.T("Huỷ", "Cancel")) { confirmDeleteID = nil }.font(.system(size: 11.5))
                    Button(app.T("Xoá", "Delete")) { Task { await app.deleteRefundDestination(d.id); confirmDeleteID = nil } }
                        .font(.system(size: 11.5)).foregroundStyle(BanbeTheme.alert)
                }
            }
        }
        .padding(14)
    }

    private var formView: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(app.T("Nhãn (VD: Tài khoản chính)", "Label (e.g. Main account)"), text: $label)
                .font(.system(size: 13)).padding(10).background(app.palette.field, in: RoundedRectangle(cornerRadius: 10))
            TextField(app.T("Tên ngân hàng", "Bank name"), text: $bank)
                .font(.system(size: 13)).padding(10).background(app.palette.field, in: RoundedRectangle(cornerRadius: 10))
            TextField(app.T("Số tài khoản", "Account number"), text: $account)
                .font(.system(size: 13)).padding(10).background(app.palette.field, in: RoundedRectangle(cornerRadius: 10))
                .keyboardType(.numberPad)
            TextField(app.T("Tên chủ tài khoản", "Account holder name"), text: $holder)
                .font(.system(size: 13)).padding(10).background(app.palette.field, in: RoundedRectangle(cornerRadius: 10))
            TextField(app.T("Ghi chú (không bắt buộc)", "Note (optional)"), text: $note)
                .font(.system(size: 13)).padding(10).background(app.palette.field, in: RoundedRectangle(cornerRadius: 10))
            Toggle(isOn: $setDefault) {
                Text(app.T("Đặt làm tài khoản mặc định", "Set as default account")).font(.system(size: 12))
            }
            Toggle(isOn: $confirmed) {
                Text(app.T("Tôi xác nhận thông tin tài khoản trên là chính xác.", "I confirm this account information is correct.")).font(.system(size: 12))
            }
            .accessibilityIdentifier("refund.accountConfirmToggle")
            if !app.refundDestinationError.isEmpty {
                Text(app.refundDestinationError).font(.system(size: 12)).foregroundStyle(BanbeTheme.alert)
            }
            HStack(spacing: 10) {
                Button(app.T("Huỷ", "Cancel")) { formOpen = false }
                    .font(.system(size: 13)).foregroundStyle(app.palette.ink)
                    .frame(maxWidth: .infinity).padding(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(app.palette.rule))
                InkButton(title: app.refundDestinationBusy ? app.T("Đang lưu…", "Saving…") : app.T("Lưu", "Save"), action: doSave)
                    .accessibilityIdentifier("refund.accountSave")
            }
        }
        .padding(.top, 16)
    }
}

private func maskAccountNumber(_ number: String) -> String {
    guard number.count > 4 else { return number }
    return String(repeating: "•", count: number.count - 4) + number.suffix(4)
}
