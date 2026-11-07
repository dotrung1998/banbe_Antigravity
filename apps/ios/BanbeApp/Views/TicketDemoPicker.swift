import SwiftUI

/// Admin "Ticket demo" (migration 217): which ticket status to show (Hold, Pay, Review, ticket, ended, cancelled, expired),
/// and for a paid ticket 1 ticket / 3 named tickets / a gifted one. Opens the real ticket screen on sample data; nothing
/// reaches the server. Web twin: src/components/project/TicketDemoPicker.jsx.
struct TicketDemoPicker: View {
    @EnvironmentObject private var app: AppState
    @State private var key = "upcoming"
    @State private var variant: TicketDemo.Variant = .single
    let open: (String, TicketDemo.Variant) -> Void

    private func variantTitle(_ v: TicketDemo.Variant) -> String {
        switch v {
        case .single: return app.T("1 vé", "1 ticket")
        case .named: return app.T("3 vé có tên", "3 named tickets")
        case .gifted: return app.T("Vé đã tặng", "Gifted ticket")
        }
    }

    private func group<T: Hashable>(_ items: [(T, String)], selected: T, id: String, pick: @escaping (T) -> Void) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                if i > 0 { Rectangle().fill(app.palette.divider).frame(height: 1) }
                Button { pick(item.0) } label: {
                    HStack {
                        Text(item.1).font(.body)
                        Spacer()
                        Image(systemName: selected == item.0 ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected == item.0 ? app.palette.ink : app.palette.ink3).accessibilityHidden(true)
                    }
                    .padding(.horizontal, 16).frame(minHeight: 48).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected == item.0 ? .isSelected : [])
                .accessibilityIdentifier("\(id).\(i)")
            }
        }
        .background(app.palette.block, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(app.T("Bản demo vé", "Ticket demo")).font(.title3.weight(.bold)).accessibilityAddTraits(.isHeader)
                Text(app.T("Dữ liệu mẫu trên máy này. Các nút ghi dữ liệu hoặc rời màn hình hiện \"Không có trong bản demo\".",
                           "Sample data on this device. Buttons that write data or leave the screen say \"Not available in the demo\"."))
                    .font(.subheadline).foregroundStyle(app.palette.ink2).fixedSize(horizontal: false, vertical: true)
                Text(app.T("Trạng thái vé", "Ticket status")).font(.footnote.weight(.semibold)).foregroundStyle(app.palette.ink2)
                group(TicketDemo.specs.map { ($0.key, app.T($0.vi, $0.en)) }, selected: key, id: "ticketDemo.case") { key = $0 }
                if TicketDemo.hasVariants(key) {
                    Text(app.T("Loại vé", "Ticket type")).font(.footnote.weight(.semibold)).foregroundStyle(app.palette.ink2)
                    group(TicketDemo.Variant.allCases.map { ($0, variantTitle($0)) }, selected: variant, id: "ticketDemo.variant") { variant = $0 }
                }
                InkButton(title: app.T("Mở bản demo", "Open demo"), font: .body.weight(.bold)) { open(key, variant) }
                    .accessibilityIdentifier("ticketDemo.open")
            }
            .padding(20)
        }
        .background(app.palette.paper.ignoresSafeArea())
    }
}
