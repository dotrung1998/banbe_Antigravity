import SwiftUI

/// A bottom sheet with the web app's paper styling — the shape all three
/// of the sheets below share (src/screens/sheets/*.jsx).
struct BottomSheet<Content: View>: View {
    @EnvironmentObject private var app: AppState
    let onDismiss: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
            VStack(alignment: .leading, spacing: 0) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 26)
                .padding(.bottom, 36)
                .background(app.palette.paper)
                .foregroundStyle(app.palette.ink)
        }
        .transition(.opacity)
    }
}

/// Port of AreaSheet.jsx — pick a neighbourhood, with a real event count
/// per area (matching the feed's own filter, invite-only excluded) and a
/// genuine on/off toggle for location sharing.
struct AreaSheetView: View {
    @EnvironmentObject var app: AppState

    private func count(_ area: AreaOption) -> String {
        if area.key == "danang" { return "Sắp có" }
        let n = EventCatalog.all.filter { area.match($0) && $0.isOpen && !$0.inviteOnly }.count
        return "\(n) sự kiện"
    }

    var body: some View {
        BottomSheet(onDismiss: { app.areaAsking = false }) {
            HStack {
                Text("Khu vực").font(.system(size: 11.5, weight: .semibold))
                Spacer()
                Button { app.areaAsking = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(app.palette.ink.opacity(0.6))
                        .padding(4)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("area.close")
            }
            VStack(spacing: 0) {
                ForEach(AreaOption.all) { area in
                    Button { app.pickArea(area.key) } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(area.label)
                                .font(.system(size: 14.5, weight: app.area == area.key ? .semibold : .regular))
                            Spacer()
                            Text(count(area)).font(.system(size: 11))
                        }
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("area.\(area.key)")
                    Divider().overlay(app.palette.rule)
                }
            }
            .padding(.top, 10)

            Button(app.located == true
                   ? "Tắt vị trí ▪︎ đang hiển thị khoảng cách"
                   : "Dùng vị trí của tôi để xem khoảng cách") {
                if app.located == true { app.denyLocation() } else { app.allowLocation() }
            }
            .font(.system(size: 13))
            .frame(maxWidth: .infinity)
            .padding(8)
            .padding(.top, 14)
            .buttonStyle(.plain)
        }
    }
}

/// Port of LocationSheet.jsx — the permission explainer, only shown when
/// someone actually reaches for a distance.
struct LocationSheetView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        BottomSheet(onDismiss: { app.denyLocation() }) {
            Text("Vị trí").font(.system(size: 11.5))
            Text("Cho banbe biết bạn đang ở đâu?")
                .font(BanbeTheme.display(23))
                .padding(.top, 8)
            Text("Chỉ để hiện khoảng cách tới mỗi sự kiện. Không lưu, không chia sẻ với người tổ chức.")
                .font(.system(size: 13.5))
                .lineSpacing(3)
                .padding(.top, 12)
            InkButton(title: "Dùng vị trí của tôi") { app.allowLocation() }
                .padding(.top, 22)
            Button("Để sau") { app.denyLocation() }
                .font(.system(size: 13.5))
                .frame(maxWidth: .infinity)
                .padding(8)
                .padding(.top, 10)
                .buttonStyle(.plain)
        }
    }
}

/// Port of ReasonSheet.jsx — an organizer reversing a check-in, cancelling a
/// paid booking, or rejecting a still-pending one must pick one of a fixed
/// list of reasons (no free text), so the guest's notification always says
/// something concrete. `.confirmCheckin` (14-organizer-checkin.md, Bug 3)
/// has no reason list at all — a plain yes/no before marking a guest
/// arrived.
struct ReasonSheetView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        if let prompt = app.reasonPrompt {
            if prompt.kind == .confirmCheckin {
                BottomSheet(onDismiss: { if !app.reasonPromptBusy { app.closeReasonPrompt() } }) {
                    Text(app.T("Xác nhận điểm danh", "Confirm check-in"))
                        .font(.system(size: 11.5, weight: .semibold))
                    Text(prompt.guestName.isEmpty
                         ? app.T("Bạn có chắc muốn xác nhận khách này đã tới?", "Are you sure this guest has arrived?")
                         : app.T("Bạn có chắc muốn xác nhận \(prompt.guestName) đã tới?", "Are you sure \(prompt.guestName) has arrived?"))
                        .font(.system(size: 13))
                        .lineSpacing(3)
                        .padding(.top, 8)
                    HStack(spacing: 8) {
                        Button(app.T("Xác nhận", "Confirm")) { Task { await app.confirmCheckIn() } }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(app.palette.paper)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .buttonStyle(.plain)
                        Button(app.T("Để sau", "Not now")) { app.closeReasonPrompt() }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(app.palette.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(app.palette.rule))
                            .buttonStyle(.plain)
                    }
                    .padding(.top, 16)
                }
            } else {
                let reasons: [ReasonOption] = prompt.kind == .undoCheckin ? ReasonOption.undoCheckin
                    : prompt.kind == .rejectGuest ? ReasonOption.rejectGuest
                    : ReasonOption.cancelBooking
                let title = prompt.kind == .undoCheckin ? app.T("Huỷ điểm danh", "Undo check-in")
                    : prompt.kind == .rejectGuest ? app.T("Từ chối yêu cầu đặt chỗ", "Reject this request")
                    : app.T("Huỷ vé", "Cancel booking")

                BottomSheet(onDismiss: { if !app.reasonPromptBusy { app.closeReasonPrompt() } }) {
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                    if !prompt.guestName.isEmpty {
                        Text(prompt.kind == .undoCheckin
                             ? app.T("Vì sao bạn muốn chuyển \(prompt.guestName) về \"Chưa đến\"?",
                                     "Why move \(prompt.guestName) back to \"Not yet\"?")
                             : prompt.kind == .rejectGuest
                             ? app.T("Vì sao bạn không nhận yêu cầu của \(prompt.guestName)?",
                                     "Why reject \(prompt.guestName)'s request?")
                             : app.T("Vì sao bạn muốn huỷ vé của \(prompt.guestName)?",
                                     "Why cancel \(prompt.guestName)'s booking?"))
                            .font(.system(size: 13))
                            .lineSpacing(3)
                            .padding(.top, 8)
                    }
                    Text(prompt.kind == .rejectGuest
                         ? app.T("Chỗ sẽ được mở lại ngay và khách sẽ được báo trong ứng dụng.",
                                 "The seat is returned to the pool immediately and the guest is notified in the app.")
                         : app.T("Khách sẽ được báo qua email và trong ứng dụng.",
                                 "The guest will be notified by email and in the app."))
                        .font(.system(size: 12))
                        .foregroundStyle(app.palette.ink.opacity(0.7))
                        .padding(.top, 6)

                    VStack(spacing: 0) {
                        ForEach(reasons) { reason in
                            Button {
                                guard !app.reasonPromptBusy else { return }
                                Task { await app.submitReason(app.T(reason.vi, reason.en)) }
                            } label: {
                                Text(app.T(reason.vi, reason.en))
                                    .font(.system(size: 14.5))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 13)
                                    .opacity(app.reasonPromptBusy ? 0.5 : 1)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider().overlay(app.palette.rule)
                        }
                    }
                    .padding(.top, 14)

                    if !app.reasonPromptError.isEmpty {
                        Text(app.reasonPromptError)
                            .font(.system(size: 12))
                            .foregroundStyle(BanbeTheme.alert)
                            .padding(.top, 12)
                    }

                    Button(app.reasonPromptBusy ? app.T("Đang xử lý…", "Working…") : app.T("Để sau", "Not now")) {
                        if !app.reasonPromptBusy { app.closeReasonPrompt() }
                    }
                    .font(.system(size: 13.5))
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .padding(.top, 14)
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
