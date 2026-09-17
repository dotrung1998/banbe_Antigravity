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

    private var event: CatalogEvent? { EventCatalog.find(app.attendanceEventKey) }
    private var checkedCount: Int { app.attendanceGuests.filter(\.checkedIn).count }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.T("Trang của bạn", "Your dashboard")) { app.goDashboard() }

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
        }
        .fileImporter(
            isPresented: Binding(get: { uploadTarget != nil }, set: { if !$0 { uploadTarget = nil } }),
            allowedContentTypes: [.pdf, .jpeg, .png, .image]
        ) { result in
            guard let bookingID = uploadTarget else { return }
            uploadTarget = nil
            switch result {
            case .success(let url):
                Task { await uploadReceipt(bookingID: bookingID, url: url) }
            case .failure(let error):
                print("Attendance receipt picker failed:", error)
            }
        }
    }

    private func uploadReceipt(bookingID: UUID, url: URL) async {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else { return }
        let ext = url.pathExtension.lowercased()
        let ok = await app.uploadPaymentDocument(bookingID: bookingID, kind: "receipt", fileData: data, fileExtension: ext.isEmpty ? "jpg" : ext)
        uploadErrorFor = ok ? nil : bookingID
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
                               : app.T("Tải lên biên nhận", "Upload receipt")) {
                            uploadTarget = guest.id
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(app.palette.ink)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(app.palette.rule, lineWidth: 1))
                        .buttonStyle(.plain)
                        .disabled(app.documentUploading)
                        .accessibilityIdentifier("guest.uploadReceipt")

                        if uploadErrorFor == guest.id {
                            Text(app.T("Không tải lên được. Thử lại nhé.", "Couldn't upload. Please try again."))
                                .font(.system(size: 10.5))
                                .foregroundStyle(BanbeTheme.alert)
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
