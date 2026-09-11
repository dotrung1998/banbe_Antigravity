import SwiftUI

/// Port of src/screens/Attendance.jsx — the real guest list for an event
/// (actual bookings, not a placeholder), tap to check someone in, scan
/// their ticket QR, or cancel a booking. Reversing a check-in always asks
/// for a reason first (ReasonSheet).
struct AttendanceView: View {
    @EnvironmentObject var app: AppState

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
    }

    private func guestRow(_ guest: AttendanceGuest) -> some View {
        Button { app.toggleCheckIn(guest) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(guest.name).font(BanbeTheme.display(15))
                    Text(guest.qty > 1 ? "\(guest.qty)" + app.T(" vé", " tickets") : app.T("1 vé", "1 ticket"))
                        .font(.system(size: 11.5))
                    Button(app.T("Huỷ vé", "Cancel booking")) { app.openCancelBooking(guest) }
                        .font(.system(size: 11))
                        .foregroundStyle(BanbeTheme.alert.opacity(0.8))
                        .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                Text(guest.checkedIn ? app.T("Đã đến ✓", "Here ✓") : app.T("Chưa đến", "Not yet"))
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
