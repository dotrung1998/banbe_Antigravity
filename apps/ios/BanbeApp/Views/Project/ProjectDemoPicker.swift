import SwiftUI

/// Admin "Project hub demo" (migration 216): who to view the sample as, and whether the clock sits on the event day
/// (Day-of live mode and the now line). Opens the hub on the sample data; nothing reaches the server.
struct ProjectDemoPicker: View {
    @EnvironmentObject private var app: AppState
    @State private var role: ProjectDemo.Role = .host
    @State private var eventDay = false
    let open: (ProjectDemo.Role, Bool) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.T("Bản demo dự án sự kiện", "Project hub demo"))
                        .font(.title3.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("projectDemo.title")
                    Text(app.T("Dữ liệu mẫu trên máy này. Không tạo dự án, không gửi gì cho ai.",
                               "Sample data on this device. No project is created and nothing is sent to anyone."))
                        .font(.subheadline).foregroundStyle(app.palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(app.T("Xem với vai trò", "View as")).font(.footnote.weight(.semibold)).foregroundStyle(app.palette.ink2)
                VStack(spacing: 0) {
                    ForEach(Array(ProjectDemo.Role.allCases.enumerated()), id: \.element) { i, r in
                        if i > 0 { Rectangle().fill(app.palette.divider).frame(height: 1) }
                        Button { role = r } label: {
                            HStack {
                                Text(app.T(r.vi, r.en)).font(.body)
                                Spacer()
                                Image(systemName: role == r ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(role == r ? app.palette.ink : app.palette.ink3)
                                    .accessibilityHidden(true)
                            }
                            .padding(.horizontal, 16).frame(minHeight: 48)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(role == r ? .isSelected : [])
                        .accessibilityIdentifier("projectDemo.as.\(r.rawValue)")
                    }
                }
                .background(app.palette.block, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Toggle(isOn: $eventDay) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.T("Ngày diễn ra", "Event day")).font(.body)
                        Text(app.T("Đặt đồng hồ demo vào ngày sự kiện để thấy chế độ trực tiếp.",
                                   "Puts the demo clock on the event day to show live mode."))
                            .font(.footnote).foregroundStyle(app.palette.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(app.palette.block, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityIdentifier("projectDemo.eventDay")

                InkButton(title: app.T("Mở bản demo", "Open demo"), font: .body.weight(.bold)) { open(role, eventDay) }
                    .accessibilityIdentifier("projectDemo.open")
            }
            .padding(20)
        }
        .foregroundStyle(app.palette.ink)
        .background(app.palette.paper.ignoresSafeArea())
        .accessibilityIdentifier("projectDemo.picker")
    }
}
