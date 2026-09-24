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
    @State private var openMenuID: UUID?

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
            // TASK A point 7 — save -> pop back to the EXACT claim that sent
            // us here (never a blank/root screen): reuses the same
            // backFromRefundAccounts() the swipe gesture and the in-view
            // BackLink both use, so this exit path can't drift out of sync
            // with those either.
            if wasNew, let claimID = app.refundAccountsReturnToClaimID {
                let bookingID = app.refundAccountsReturnToBookingID
                _ = await app.selectRefundDestinationForClaim(claimID: claimID, destinationID: newID)
                if let bookingID { app.paymentBookingID = bookingID }
                app.backFromRefundAccounts()
            }
        }
    }

    // TASK C — root cause of the dragged row overlaying/cutting off the
    // next row: the list used to be a native `List` (with its own native
    // drag-reorder lift/preview animation) placed INSIDE ScreenScaffold's
    // own `ScrollView` (`scroll` defaults to true), with `.scrollDisabled
    // (true)` and a hand-computed `.frame(height:)` (a flat `44pt * row
    // count` sum) bolted on to make it behave like a plain non-scrolling
    // block. That fixed-height clipping frame doesn't account for the
    // native drag lift/preview's real (taller, elevated) row metrics, so
    // during an active drag the container clipped whatever didn't fit
    // inside its hand-computed height — exactly the cut-off/overlap in the
    // report. Fixed: `ScreenScaffold(scroll: false)` (no outer ScrollView
    // to compete with), and this screen's own `List` now owns scrolling and
    // sizes itself natively — no `.scrollDisabled`, no manual row-height
    // sum, so its native drag animation has the space it actually needs.
    var body: some View {
        ScreenScaffold(scroll: false) {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.T("Tài khoản", "Account")) { app.backFromRefundAccounts() }

                Text(app.T("Tài khoản nhận hoàn tiền", "Refund accounts"))
                    .font(BanbeTheme.display(24)).padding(.top, 14)
                if app.refundDestinations.count > 1 {
                    Text(app.T("Kéo để sắp xếp", "Drag to reorder"))
                        .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.6)).padding(.top, 6)
                }

                if savedFlash {
                    Text(app.T("Tài khoản nhận hoàn đã được lưu", "Refund account saved"))
                        .font(.system(size: 12.5)).padding(.top, 12)
                }
                if !formOpen && app.refundDestinationsReordering {
                    Text(app.T("Đang lưu thứ tự…", "Saving order…"))
                        .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.6)).padding(.top, 12)
                }
                if !formOpen && !app.refundDestinationsReordering && !app.refundDestinationError.isEmpty {
                    Text(app.refundDestinationError)
                        .font(.system(size: 12.5)).foregroundStyle(BanbeTheme.alert).padding(.top, 12)
                }

                if formOpen {
                    ScrollView { formView.padding(.top, 4) }
                } else if app.refundDestinations.isEmpty {
                    Text(app.T("Chưa có tài khoản nhận hoàn tiền", "No refund accounts saved yet"))
                        .font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .center)
                        .padding(20).background(app.palette.field, in: RoundedRectangle(cornerRadius: 14)).padding(.top, 16)
                    Button(app.T("+ Thêm tài khoản", "+ Add account"), action: openAddForm)
                        .font(.system(size: 13)).foregroundStyle(app.palette.ink)
                        .frame(maxWidth: .infinity).padding(13)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(app.palette.rule))
                        .padding(.top, 12)
                        .accessibilityIdentifier("refund.accountAdd")
                } else {
                    accountsList
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 40)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    /// TASK B — compact iOS Settings-style grouped list: a native `List`
    /// with `.onMove` gives long-press-and-drag reordering by its own
    /// leading three-line handle for free (shown because editMode is
    /// pinned `.active`; `.deleteDisabled` on every row suppresses the red
    /// delete control that edit mode would otherwise also show, leaving
    /// only the reorder handle visible). One thin row per account — no
    /// card padding/shadow — main label + secondary bank/masked-number
    /// line, trailing "Mặc định" tag or chevron. Edit/Delete live behind a
    /// tap on the row instead of always-visible buttons. The "+ Thêm tài
    /// khoản" row is its OWN List row (not a sibling outside the List) so
    /// there is exactly one scroll container on this whole screen (TASK C1)
    /// — never a List competing with an outer ScrollView, never a second
    /// scrollable region.
    private var accountsList: some View {
        List {
            Section {
                ForEach(app.refundDestinations) { d in
                    VStack(spacing: 0) {
                        accountRow(d)
                        if openMenuID == d.id { accountRowMenu(d) }
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(app.palette.field)
                    .listRowSeparatorTint(app.palette.rule)
                }
                .onMove { indices, newOffset in
                    var ids = app.refundDestinations.map(\.id)
                    ids.move(fromOffsets: indices, toOffset: newOffset)
                    Task { await app.reorderRefundDestinations(ids) }
                }
                .deleteDisabled(true)
            }
            Section {
                Button(app.T("+ Thêm tài khoản", "+ Add account"), action: openAddForm)
                    .font(.system(size: 13)).foregroundStyle(app.palette.ink)
                    .frame(maxWidth: .infinity).padding(13)
                    .accessibilityIdentifier("refund.accountAdd")
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .moveDisabled(true)
                    .deleteDisabled(true)
            }
        }
        .environment(\.editMode, .constant(.active))
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14))
        .padding(.top, 16)
    }

    @ViewBuilder
    private func accountRow(_ d: RefundDestination) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(d.label ?? app.T("Tài khoản", "Account")).font(BanbeTheme.display(14))
                Text("\(d.bankName) ▪︎ \(maskAccountNumber(d.accountNumber))")
                    .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.6))
            }
            Spacer(minLength: 8)
            if d.isDefault {
                Text(app.T("Mặc định", "Default")).font(.system(size: 11, weight: .semibold)).foregroundStyle(app.palette.ink.opacity(0.55))
            } else {
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(app.palette.ink.opacity(0.35))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { openMenuID = openMenuID == d.id ? nil : d.id }
        .frame(height: 44)
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private func accountRowMenu(_ d: RefundDestination) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(revealedID == d.id ? d.accountNumber : maskAccountNumber(d.accountNumber)) ▪︎ \(d.accountHolderName)")
                .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.7))
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
        .padding(.horizontal, 14).padding(.bottom, 10)
        .frame(height: 92, alignment: .top)
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
