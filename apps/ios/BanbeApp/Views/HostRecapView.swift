import SwiftUI

/// L3 host recap (switch `host_recap`, migration 199) — the iOS counterpart of src/screens/HostRecap.jsx. From the
/// host_event_recap notification or Dashboard › Past events. Plain numbers from get_host_event_recap (owner/team only
/// on the server): confirmed seats of capacity, check-ins, new followers since submission, returning guests, photos,
/// and the guests' feedback only once 3 or more answered (counts and notes without names). "Run it again" opens
/// Create Event pre-filled and never submits.
struct HostRecapView: View {
    @EnvironmentObject private var app: AppState
    @State private var recap: CoreLoops.HostRecap?
    @State private var error = ""
    @State private var reload = 0

    private var eventID: String? { app.hostRecapID }
    private var summary: RealEventSummary? { eventID.flatMap { id in app.myOrgEventSummaries.first { $0.id == id } } }

    private func message(_ code: String) -> String {
        switch code {
        case "NOT_AUTHORIZED": return app.T("Chỉ host của sự kiện này xem được tổng kết.", "Only this event’s host can see its recap.")
        case "NOT_AVAILABLE": return app.T("Tính năng này đang tạm tắt.", "This is turned off for now.")
        default: return app.T("Không tải được tổng kết. Thử lại nhé.", "Couldn't load the recap. Try again.")
        }
    }

    private var backLabel: String {
        app.hostRecapBack == .notifications ? app.T("Thông báo", "Notifications") : app.T("Trang tổ chức", "Dashboard")
    }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: backLabel) { app.goBack() }
                    .padding(.top, 8)
                    .accessibilityIdentifier("hostRecap.back")
                Text(app.T("Tổng kết sự kiện", "Event recap"))
                    .font(.system(size: 11.5, weight: .semibold)).opacity(0.7).padding(.top, 14)
                Button { if let eventID { app.goEvent(eventID) } } label: {
                    Text(summary?.name ?? "…").font(BanbeTheme.display(26)).multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("hostRecap.title")
                if let start = summary?.startsAt {
                    Text(app.discoveryWhenLabel(start, timeZone: EventMarket.timeZone(summary?.timeZoneID)))
                        .font(.system(size: 13)).opacity(0.7).padding(.top, 6)
                }

                if !app.hostRecapEnabled {
                    Text(message("NOT_AVAILABLE")).font(.system(size: 13.5)).opacity(0.7).padding(.top, 18)
                        .accessibilityIdentifier("hostRecap.off")
                } else if !error.isEmpty {
                    HStack(spacing: 8) {
                        Text(message(error)).font(.system(size: 12.5)).foregroundStyle(BanbeTheme.alert)
                        if error == "NETWORK" {
                            Button(app.T("Thử lại", "Retry")) { reload += 1 }
                                .font(.system(size: 12.5, weight: .semibold)).buttonStyle(.plain).underline()
                        }
                    }
                    .padding(.top, 18)
                    .accessibilityIdentifier("hostRecap.error")
                } else if let recap {
                    stats(recap).padding(.top, 20)
                    feedback(CoreLoops.hostFeedbackView(recap.feedback)).padding(.top, 26)
                } else {
                    Text(app.T("Đang tải…", "Loading…")).font(.system(size: 13)).opacity(0.7).padding(.top, 18)
                }

                if app.hostRecapEnabled, let summary {
                    InkButton(title: app.T("Tổ chức lại", "Run it again")) { app.runItAgain(summary) }
                        .padding(.top, 28)
                        .accessibilityIdentifier("hostRecap.runAgain")
                    Text(app.T("Mở bản nháp mới từ sự kiện này. Bạn xem lại và gửi khi sẵn sàng.",
                               "Opens a new draft from this event. You review it and submit when ready."))
                        .font(.system(size: 12)).opacity(0.65)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 22)
            .padding(.bottom, 48)
        }
        .task(id: "\(eventID ?? "")|\(reload)") { await load() }
    }

    private func load() async {
        recap = nil
        error = ""
        guard let eventID, app.hostRecapEnabled else { return }
        #if DEBUG
        if UITestFixture.isActive { return } // fixtures never reach the server
        #endif
        let r = await app.fetchHostRecap(eventID: eventID)
        guard eventID == app.hostRecapID else { return }
        if r.success == true { recap = r } else { error = r.error ?? "NETWORK" }
    }

    private func stats(_ r: CoreLoops.HostRecap) -> some View {
        let seats = r.confirmedSeats ?? 0
        let rows: [(String, String, String)] = [
            (app.T("Chỗ đã xác nhận", "Confirmed seats"),
             r.capacity.map { app.T("\(seats)/\($0)", "\(seats) of \($0)") } ?? "\(seats)", "hostRecap.seats"),
            (app.T("Đã check-in", "Checked in"), "\(r.checkedIn ?? 0)", "hostRecap.checkedIn"),
            (app.T("Người theo dõi mới", "New followers"), "\(r.newFollowers ?? 0)", "hostRecap.followers"),
            (app.T("Khách quay lại", "Returning guests"), "\(r.repeatGuests ?? 0)", "hostRecap.repeat"),
            (app.T("Ảnh", "Photos"), "\(r.photos ?? 0)", "hostRecap.photos"),
        ]
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 12) {
                    Text(row.0).font(.system(size: 14))
                    Spacer(minLength: 0)
                    Text(row.1).font(.system(size: 14, weight: .semibold)).monospacedDigit()
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .overlay(alignment: .top) { if index > 0 { Rectangle().fill(app.palette.rule).frame(height: 1) } }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(row.2)
            }
        }
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func feedback(_ fb: CoreLoops.FeedbackView) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(app.T("Cảm nhận của khách", "Guest feedback")).font(BanbeTheme.display(20))
            if fb.hidden {
                Text(app.T(CoreLoops.hostFeedbackHidden.vi, CoreLoops.hostFeedbackHidden.en))
                    .font(.system(size: 13)).opacity(0.75).padding(.top, 8)
                    .accessibilityIdentifier("hostRecap.feedbackHidden")
            } else {
                Text("👍 \(fb.up) · 👎 \(fb.down)").font(.system(size: 15, weight: .semibold)).padding(.top, 8)
                    .accessibilityIdentifier("hostRecap.feedbackCounts")
                if !fb.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(fb.notes.enumerated()), id: \.offset) { index, n in
                            Text(n).font(.system(size: 13.5))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14).padding(.vertical, 11)
                                .overlay(alignment: .top) { if index > 0 { Rectangle().fill(app.palette.rule).frame(height: 1) } }
                                .accessibilityIdentifier("hostRecap.note.\(index)")
                        }
                    }
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.top, 10)
                }
                Text(app.T("Ghi chú không kèm tên, thứ tự ngẫu nhiên.", "Notes are unnamed and in random order."))
                    .font(.system(size: 11.5)).opacity(0.6).padding(.top, 8)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hostRecap.feedback")
    }
}
