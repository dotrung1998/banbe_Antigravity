import SwiftUI

/// The paper ticket (note 78, Ticket A): the event's name and three tiles on top, a perforation in the middle (two
/// notches in the page colour and a dashed rule), and the stub underneath, which is the `stub` slot (the QR and the 3-3
/// entry code, or the per-attendee pager). `strip` is the What's next strip, shown above the name. Tiles stack in a
/// column at accessibility text sizes; long Vietnamese strings wrap. Twin of src/components/ticket/PaperTicket.jsx.
/// A labelled value tile (Date / Time / Area on the ticket, Date / Time / Place in the Event details sheet).
struct TicketTile: Identifiable { let id: String; let label: String; let value: String }

struct PaperTicketView<Strip: View, Stub: View>: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dynamicTypeSize) private var typeSize
    let holderLabel: String
    let title: String
    let tiles: [TicketTile]
    var viewLabel: String = ""
    var onOpenDetails: (() -> Void)?
    @ViewBuilder var strip: () -> Strip
    @ViewBuilder var stub: () -> Stub

    private var shown: [TicketTile] { tiles.filter { !$0.value.isEmpty } }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                strip()
                header.padding(.horizontal, 8).padding(.top, 4)
                if !shown.isEmpty { tileGrid }
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(app.palette.block, in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous))

            perforation

            stub()
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 22)
                .frame(maxWidth: .infinity)
                .background(app.palette.block, in: UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24, style: .continuous))
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 8)
        // A container must be its own element BEFORE it is identified, or the id would mask its children's ids.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("confirmed.ticket")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Label and pill share a row; at accessibility text sizes the pill drops under the label so neither wraps badly.
            let labelView = Text(holderLabel.uppercased())
                .font(.caption2.weight(.semibold)).tracking(0.8)
                .foregroundStyle(app.palette.ink3)
                .frame(maxWidth: .infinity, alignment: .leading)
            // The name and this pill both open the Event details sheet.
            let pill = Group {
                if let onOpenDetails {
                    Button(action: onOpenDetails) {
                        HStack(spacing: 8) {
                            Text(viewLabel).font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold)).foregroundStyle(app.palette.paper)
                                .frame(width: 20, height: 20).background(app.palette.ink, in: Circle())
                        }
                        .foregroundStyle(app.palette.ink)
                        .padding(.leading, 12).padding(.trailing, 6).padding(.vertical, 6)
                        .background(app.palette.blockInset, in: Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(app.T("Mở chi tiết sự kiện", "Opens the event details"))
                    .accessibilityIdentifier("confirmed.viewEvent")
                }
            }
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) { labelView; pill }
            } else {
                HStack(alignment: .center, spacing: 8) { labelView; pill }
            }
            if let onOpenDetails {
                Button(action: onOpenDetails) {
                    Text(title).font(BanbeTheme.display(27)).multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("confirmed.openDetails")
            } else {
                Text(title).font(BanbeTheme.display(27))
            }
        }
    }

    @ViewBuilder
    private var tileGrid: some View {
        let cells = ForEach(shown) { t in
            VStack(alignment: .leading, spacing: 2) {
                Text(t.label.uppercased()).font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(app.palette.ink3)
                Text(t.value).font(.subheadline.weight(.semibold)).foregroundStyle(app.palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(app.palette.blockInset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("confirmed.tile.\(t.id)")
        }
        if typeSize.isAccessibilitySize {
            VStack(spacing: 8) { cells }
        } else {
            HStack(alignment: .top, spacing: 8) { cells }
        }
    }

    /// A dashed rule on the ticket fill, with a notch cut out of each edge in the page colour.
    private var perforation: some View {
        ZStack {
            app.palette.block
            Rectangle().stroke(app.palette.rule, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                .frame(height: 0).padding(.horizontal, 16)
            HStack {
                Circle().fill(app.palette.paper).frame(width: 22, height: 22).offset(x: -11)
                Spacer()
                Circle().fill(app.palette.paper).frame(width: 22, height: 22).offset(x: 11)
            }
        }
        .frame(height: 1)
        .accessibilityHidden(true)
    }
}
