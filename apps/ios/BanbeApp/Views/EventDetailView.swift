import SwiftUI

/// Port of src/screens/EventDetail.jsx — hero photo with back/share pills,
/// the address as a Maps link, details, organizer row, photo strip, and the
/// bottom action bar (which shows your ticket if you already hold one).
struct EventDetailView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.openURL) private var openURL

    private var event: CatalogEvent { app.currentEvent }

    /// Reached from several places, so "back" returns to whichever one you
    /// actually came from, labelled accordingly.
    private var backLabel: String {
        switch app.eventBackScreen {
        case .dashboard: return app.T("Trang của bạn", "Your dashboard")
        case .organizer: return app.T("Trang tổ chức", "Organizer page")
        case .create: return app.T("Tạo sự kiện", "Create event")
        default: return "banbe"
        }
    }

    /// A live booking for this exact event opens the ticket instead of
    /// running the guest through Reserve again.
    private var myBooking: Booking? {
        guard let booking = app.booking,
              booking.eventId == event.key,
              ["pending", "confirmed", "attended"].contains(booking.status)
        else { return nil }
        return booking
    }

    var body: some View {
        ZStack {
            app.palette.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        hero
                        details
                    }
                }
                actionBar
            }
        }
    }

    private var hero: some View {
        ZStack(alignment: .top) {
            CatalogPhoto(path: event.img, height: 400, cornerRadius: 0)
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [app.palette.paper.opacity(0), app.palette.paper],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 78)
                }
            HStack {
                pill("‹ \(backLabel)") { app.backFromEvent() }
                    .accessibilityIdentifier("event.back")
                Spacer()
                pill(app.sharedFlash ? app.T("Đã sao chép link", "Link copied") : app.T("Chia sẻ", "Share")) {
                    share()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
    }

    private func pill(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(app.palette.ink)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(app.palette.paper.opacity(0.85), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            if app.eventBackScreen != .home {
                Button(app.T("▪︎ Về trang chính", "▪︎ Back to home")) { app.goHome() }
                    .font(.system(size: 11.5))
                    .foregroundStyle(app.palette.ink.opacity(0.65))
                    .buttonStyle(.plain)
                    .padding(.bottom, 10)
            }

            HStack(spacing: 8) {
                Text(app.trStatus(event.cat)).font(.system(size: 11.5))
                if event.inviteOnly {
                    Text(app.T("Riêng tư ▪︎ theo lời mời", "Private ▪︎ invite only"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(app.palette.paper)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(app.palette.ink)
                }
            }

            Text(event.name)
                .font(BanbeTheme.display(29))
                .padding(.top, 8)
                .padding(.bottom, 10)

            if let mapsURL = event.mapsURL {
                Button {
                    // Opening directions is the natural moment to also offer
                    // the distance, if that's never been decided.
                    if app.located == nil { app.askLocation() }
                    openURL(mapsURL)
                } label: {
                    Text(app.trStatus(app.stripKm(event.where, event: event)) + " ↗")
                        .font(.system(size: 13))
                        .underline()
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            }

            Text(app.trStatus(event.soldOut ? "Hết chỗ" : event.seatsLong))
                .font(.system(size: 13))
                .padding(.top, 5)

            if event.inviteOnly {
                Text(app.T("Bạn có thể mời thêm 1 người.", "You can bring one +1."))
                    .font(.system(size: 12.5)).padding(.top, 6)
            }

            Text(event.desc)
                .font(.system(size: 14))
                .lineSpacing(4)
                .padding(.top, 20)

            VStack(spacing: 0) {
                Divider().overlay(app.palette.rule)
                detailRow(app.T("Bao gồm", "Included"), value: event.included)
                Button { app.goOrganizer() } label: {
                    detailRow(app.T("Người tổ chức", "Organizer"),
                              value: app.T("Ghé", "Visit") + " \(event.orgName) ›")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("event.organizer")
                if event.orgTrusted {
                    detailRow(app.T("Uy tín", "Track record"), value: app.T(
                        "Tổ chức từ \(event.orgSince) ▪︎ \(event.orgCount) sự kiện",
                        "Hosting since \(event.orgSince) ▪︎ \(event.orgCount) events"
                    ))
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(app.T("Giá", "Price")).font(.system(size: 13))
                    Spacer()
                    Text(app.trStatus(event.price)).font(BanbeTheme.display(23))
                }
                .padding(.top, 16)
            }
            .padding(.top, 22)

            if event.isOpen && !event.isFree {
                Text(app.T(
                    "Nếu sự kiện bị hủy, bạn được hoàn tiền tự động 100%.",
                    "If the event is cancelled, you are automatically refunded in full."
                ))
                .font(.system(size: 11.5))
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
            }

            Text(app.T("Hình ảnh", "Photos"))
                .font(.system(size: 11.5))
                .padding(.top, 28)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(Array(event.gallery.enumerated()), id: \.offset) { _, path in
                        CatalogPhoto(path: path, height: 186, width: 148)
                    }
                }
            }
            .padding(.top, 12)
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 22)
        .padding(.bottom, 30)
    }

    private func detailRow(_ label: String, value: String) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                Text(label).font(.system(size: 13))
                Spacer(minLength: 0)
                Text(value).font(.system(size: 13)).multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 12)
            .foregroundStyle(app.palette.ink)
            Divider().overlay(app.palette.rule)
        }
        // Without this the gap between the label and the value isn't part
        // of the button at all — tapping the middle of the row did nothing.
        .contentShape(Rectangle())
    }

    // A completed event has nothing left to reserve — showing "Reserve"
    // (or even the sold-out waitlist prompt) on something that already
    // happened reads as broken, not just unnecessary.
    private var ended: Bool { event.endedHoursAgo != nil }

    private var actionBar: some View {
        Group {
            if let booking = myBooking {
                InkButton(title: app.T("Xem vé của bạn ▪︎ mã \(booking.code ?? "")",
                                       "View your ticket ▪︎ code \(booking.code ?? "")")) {
                    app.openHeld()
                }
            } else if ended {
                Text(app.T("Sự kiện đã kết thúc", "Event has ended"))
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(app.palette.ink)
            } else if event.soldOut {
                Button { app.goChat() } label: {
                    Text(app.T("Hết chỗ ▪︎ nhắn để vào danh sách chờ", "Sold out ▪︎ message for waitlist"))
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .foregroundStyle(app.palette.ink)
                }
                .buttonStyle(.plain)
            } else {
                InkButton(title: app.T("Giữ chỗ ▪︎ ", "Reserve ▪︎ ") + app.trStatus(event.price)) {
                    app.goReserve()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .accessibilityIdentifier("event.actionBar")
    }

    /// The web app copies a share link; iOS has a real share sheet.
    private func share() {
        guard let url = URL(string: "https://banbe.app/\(event.key)") else { return }
        let activity = UIActivityViewController(activityItems: [event.name, url], applicationActivities: nil)
        UIApplication.shared.topViewController?.present(activity, animated: true)
    }
}

extension UIApplication {
    /// Topmost view controller — needed to present UIKit's share sheet from
    /// SwiftUI without threading a presenter through every screen.
    var topViewController: UIViewController? {
        let scene = connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
