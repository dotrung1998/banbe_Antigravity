import SwiftUI

/// Port of src/screens/Reserve.jsx — name/email, a ticket stepper (1–6),
/// the "banbe doesn't collect money" note, and the hold button that calls
/// the claim_seats RPC.
struct ReserveView: View {
    @EnvironmentObject var app: AppState

    private var event: CatalogEvent { app.currentEvent }
    private var formOK: Bool {
        !app.formName.trimmingCharacters(in: .whitespaces).isEmpty
            && app.formEmail.contains("@") && app.formEmail.contains(".")
    }
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
                    BanbeField(label: app.T("Tên", "Name"),
                               placeholder: app.T("Tên của bạn", "Your name"),
                               text: $app.formName)
                    BanbeField(label: "Email", placeholder: "ban@email.com",
                               text: $app.formEmail, keyboard: .emailAddress)
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
                    "banbe không thu tiền. Bạn giữ chỗ 30 phút, sau đó chuyển khoản trực tiếp cho người tổ chức theo hướng dẫn trong tin nhắn. Nếu họ hủy, họ có trách nhiệm hoàn tiền cho bạn.",
                    "banbe does not collect money. Your spot is held for 30 minutes, then you pay the organizer directly using the instructions in chat. If they cancel, they are responsible for your refund."
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
