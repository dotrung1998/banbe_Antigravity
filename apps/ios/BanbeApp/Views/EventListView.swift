import SwiftUI

/// Port of src/screens/EventList.jsx — opened from the "Going"/"Saved"
/// cards on Account. Its own view rather than redirecting to Home, so a
/// single tap back returns to Account.
struct EventListView: View {
    @EnvironmentObject var app: AppState

    private var title: String {
        app.eventListMode == .going ? app.T("Đang tham gia", "Going") : app.T("Đã lưu", "Saved")
    }
    private var emptyMessage: String {
        app.eventListMode == .going
            ? app.T("Bạn chưa tham gia sự kiện nào.", "You're not going to any events yet.")
            : app.T("Bạn chưa lưu sự kiện nào.", "You haven't saved any events yet.")
    }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Button { app.backFromEventList() } label: {
                        Text("‹").font(.system(size: 15))
                    }
                    .buttonStyle(.plain)
                    Text(title).font(BanbeTheme.display(24))
                }

                let events = app.eventListEvents
                if events.isEmpty {
                    Text(emptyMessage)
                        .font(.system(size: 13))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(events.enumerated()), id: \.element.key) { index, event in
                            Button { app.goEvent(event.key) } label: {
                                HStack(spacing: 12) {
                                    CatalogPhoto(path: event.img, height: 52, width: 52, cornerRadius: 10)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(event.name).font(BanbeTheme.display(15)).lineLimit(1)
                                        Text(app.trStatus(app.stripKm(event.meta, event: event)))
                                            .font(.system(size: 11.5)).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    Text("›").font(.system(size: 15))
                                }
                                .foregroundStyle(app.palette.ink)
                                .padding(.vertical, 13).padding(.horizontal, 16)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if index < events.count - 1 { Divider().overlay(app.palette.rule) }
                        }
                    }
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.top, 20)
                }

                Spacer(minLength: 0)
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }
}
