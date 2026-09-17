import SwiftUI

/// Port of src/screens/Reserve.jsx — name/email, a ticket stepper (1–6),
/// the "banbe doesn't collect money" note, and the hold button that calls
/// the hold_seats RPC.
struct ReserveView: View {
    @EnvironmentObject var app: AppState

    private var event: CatalogEvent { app.currentEvent }
    // 01-hold-payment.md's 2026-09-17 follow-up #6: Name/Email used to be
    // free-typed fields that never persisted anywhere (bookings has no such
    // columns) — every organizer-facing view of a guest's name is meant to
    // be a live join to profiles.display_name (6c6b932), and the
    // registered email already exists on the session (userEmail). A guest
    // with a real display_name gets it read-only; one without gets a real
    // input that writes via setNameAtHold() (rename_display_name(), same
    // RPC Account's "Đổi tên" uses) instead of a value that goes nowhere.
    private var hasName: Bool { !(app.user?.displayName ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
    private var formOK: Bool { hasName }
    private var totalLabel: String {
        event.isFree ? "Miễn phí" : EventLabels.vnd(event.priceVnd * app.qty)
    }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.T("Quay lại", "Back")) { app.backToEvent() }

                Text(app.T("Gần xong rồi.", "Almost there."))
                    .font(BanbeTheme.display(24))
                    .padding(.top, 16)

                HStack(spacing: 14) {
                    CatalogPhoto(path: event.img, height: 52, width: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.name).font(BanbeTheme.display(15))
                        Text("\(event.when) ▪︎ \(app.qty) " + app.T("chỗ", "seats") + " ▪︎ \(app.trStatus(totalLabel))")
                            .font(.system(size: 11.5))
                    }
                    Spacer(minLength: 0)
                }
                .padding(13)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 18)

                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(app.T("Tên", "Name")).font(.system(size: 11.5))
                            Spacer()
                            if hasName {
                                Button(app.T("Đổi trong Tài khoản", "Change in Account")) { app.goEditName() }
                                    .font(.system(size: 11))
                                    .foregroundStyle(app.palette.ink.opacity(0.6))
                                    .buttonStyle(.plain)
                            }
                        }
                        if hasName {
                            Text(app.user?.displayName ?? "")
                                .font(.system(size: 14))
                                .foregroundStyle(app.palette.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(13)
                                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .accessibilityIdentifier("reserve.nameReadonly")
                        } else {
                            BanbeField(label: nil, placeholder: app.T("Tên của bạn", "Your name"), text: $app.formName)
                                .accessibilityIdentifier("reserve.nameInput")
                            Button(app.reserveNameSaving ? app.T("Đang lưu…", "Saving…") : app.T("Lưu tên", "Save name")) {
                                Task { await app.setNameAtHold(app.formName) }
                            }
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(app.palette.ink)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(app.palette.rule, lineWidth: 1))
                            .buttonStyle(.plain)
                            .disabled(app.reserveNameSaving)
                            .accessibilityIdentifier("reserve.nameSave")
                            if !app.reserveNameError.isEmpty {
                                Text(app.reserveNameError).font(.system(size: 11)).foregroundStyle(BanbeTheme.alert)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Email").font(.system(size: 11.5))
                        Text(app.userEmail ?? "")
                            .font(.system(size: 14))
                            .foregroundStyle(app.palette.ink.opacity(0.75))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(13)
                            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .accessibilityIdentifier("reserve.emailReadonly")
                    }
                }
                .padding(.top, 20)

                Text(app.T("Số vé", "Tickets"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.top, 22)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(app.qty) " + app.T("vé", "tickets"))
                            .font(.system(size: 14, weight: .semibold))
                        Text(app.qty > 1 ? app.T("Tổng ", "Total ") + app.trStatus(totalLabel)
                                         : app.trStatus(event.price))
                            .font(.system(size: 11.5))
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        stepper("−", enabled: app.qty > 1) { app.qtyMinus() }
                        Text("\(app.qty)").font(BanbeTheme.display(18)).frame(minWidth: 20)
                        stepper("+", enabled: app.qty < 6) { app.qtyPlus() }
                    }
                }
                .foregroundStyle(app.palette.ink)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 12)

                Text(app.T(
                    "banbe không thu tiền. Bạn giữ chỗ 30 phút để chuyển khoản trực tiếp cho người tổ chức. Bấm \"Tôi đã chuyển khoản\" là đồng hồ dừng và chỗ được khoá cho tới khi người tổ chức xác nhận.",
                    "banbe does not collect money. Your seat is held for 30 minutes while you transfer to the organizer directly. Tapping \"I have transferred\" stops the clock and locks your seat until they confirm."
                ))
                .font(.system(size: 12))
                .lineSpacing(3)
                .padding(.top, 22)

                InkButton(title: app.loading
                          ? app.T("Đang giữ chỗ…", "Holding…")
                          : app.T("Giữ chỗ ▪︎ 30 phút", "Hold ▪︎ 30 minutes"),
                          enabled: formOK && !app.loading,
                          cornerRadius: 999) {
                    Task { await app.submitReserve() }
                }
                .padding(.top, 18)

                if !app.reserveError.isEmpty {
                    Text(app.reserveError)
                        .font(.system(size: 12))
                        .foregroundStyle(BanbeTheme.alert)
                        .padding(.top, 12)
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
    }

    private func stepper(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { if enabled { action() } }) {
            Text(symbol)
                .font(.system(size: 18))
                .frame(width: 32, height: 32)
                .foregroundStyle(enabled ? app.palette.ink : app.palette.ink.opacity(0.3))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(app.palette.rule, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
