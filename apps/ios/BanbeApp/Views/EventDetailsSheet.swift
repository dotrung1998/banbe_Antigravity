import SwiftUI

/// "Event details" sheet opened from the ticket (note 78): the event's own facts without leaving the ticket, and one
/// button to the full Event Detail page (whose Back returns to this same ticket). Everything shown comes from the real
/// event; a section with no data is not drawn (no placeholder About, chips or host). The refund line is the app's
/// existing policy paragraph, passed in unchanged. Presentational: ConfirmedView computes and wires everything; the two
/// actions run AFTER the sheet has dismissed (ConfirmedView's onDismiss), so navigation never fights the dismissal.
/// Twin of src/screens/sheets/EventDetailsSheet.jsx.
struct EventDetailsSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    let event: CatalogEvent
    let tiles: [TicketTile]
    let about: EventDetailPresentation.About
    let included: (visible: Bool, items: [String])
    let place: String
    let hostNote: String
    let distance: String?
    let policyNote: String
    let over: Bool
    let onOpenEvent: () -> Void
    let onMessage: () -> Void

    private var shownTiles: [TicketTile] { tiles.filter { !$0.value.isEmpty } }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !event.img.isEmpty {
                        CatalogPhoto(path: event.img, height: 130, cornerRadius: 20)
                            .padding(.bottom, 16)
                            .accessibilityHidden(true)
                            .accessibilityIdentifier("eventDetails.cover")
                    }
                    Text(app.T("Chi tiết sự kiện", "Event details"))
                        .font(.footnote.weight(.semibold)).foregroundStyle(app.palette.clay)
                    Text(event.name).font(BanbeTheme.display(27)).padding(.top, 4)
                        .accessibilityAddTraits(.isHeader)
                    if !shownTiles.isEmpty { tileRow.padding(.top, 14) }

                    if about.visible {
                        sectionLabel(app.T("Giới thiệu", "About"))
                        Text(about.body).font(.body).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("eventDetails.about")
                    }
                    if included.visible {
                        sectionLabel(app.T("Bao gồm", "Included"))
                        FlowLayout(spacing: 8, lineSpacing: 8) {
                            ForEach(included.items, id: \.self) { item in
                                Text(item).font(.footnote.weight(.medium))
                                    .padding(.horizontal, 13).padding(.vertical, 7)
                                    .background(app.palette.block, in: Capsule())
                            }
                        }
                        .accessibilityElement(children: .contain)
            .accessibilityIdentifier("eventDetails.included")
                    }
                    if !event.orgName.isEmpty { host }
                    location
                    if !policyNote.isEmpty {
                        sectionLabel(app.T("Hoàn tiền", "Refunds"))
                        Text(policyNote).font(.subheadline).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("eventDetails.policy")
                    }
                }
                .foregroundStyle(app.palette.ink)
                .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 22)
            }
            Divider().overlay(app.palette.rule)
            Button { onOpenEvent(); dismiss() } label: {
                HStack(spacing: 8) {
                    Text(over ? app.T("Xem trang sự kiện", "View event page") : app.T("Mở trang sự kiện đầy đủ", "Open full event page"))
                        .font(.body.weight(.semibold))
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(app.palette.paper)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(app.palette.ink, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 14)
            .accessibilityIdentifier("eventDetails.open")
        }
        .background(app.palette.paper.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(app.palette.ink)
                    .frame(width: 32, height: 32).background(app.palette.block, in: Circle())
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 8).padding(.trailing, 10)
            .accessibilityLabel(app.T("Đóng", "Close"))
            .accessibilityIdentifier("eventDetails.close")
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("eventDetails.sheet")
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased()).font(.caption2.weight(.semibold)).tracking(0.8)
            .foregroundStyle(app.palette.ink3).padding(.top, 22).padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var tileRow: some View {
        let cells = ForEach(shownTiles) { t in
            VStack(alignment: .leading, spacing: 2) {
                Text(t.label.uppercased()).font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(app.palette.ink3)
                Text(t.value).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(app.palette.block, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("eventDetails.tile.\(t.id)")
        }
        if typeSize.isAccessibilitySize { VStack(spacing: 8) { cells } } else { HStack(alignment: .top, spacing: 8) { cells } }
    }

    private var host: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel(app.T("Chủ nhà", "Host"))
            HStack(spacing: 12) {
                Text(String(event.orgName.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 40).background(app.palette.surface2, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.orgName).font(BanbeTheme.display(17))
                    Text(app.T("Nhắn host nếu cần biết thêm", "Message the host with questions")).font(.footnote).foregroundStyle(app.palette.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button { onMessage(); dismiss() } label: {
                    Image(systemName: "message").font(.system(size: 16, weight: .semibold))
                        .frame(width: 44, height: 44).background(app.palette.blockInset, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(app.T("Nhắn cho ", "Message ") + event.orgName)
                .accessibilityIdentifier("eventDetails.message")
            }
            .padding(12)
            .background(app.palette.block, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("eventDetails.host")
        }
    }

    @ViewBuilder private var location: some View {
        if !place.isEmpty || !hostNote.isEmpty || event.mapsURL != nil {
            sectionLabel(app.T("Địa điểm", "Location"))
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "mappin.and.ellipse").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(app.palette.clay)
                        .frame(width: 34, height: 34).background(app.palette.clayBg, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        if !place.isEmpty {
                            Text(place).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("eventDetails.place")
                        }
                        if let distance {
                            Text(distance).font(.footnote).foregroundStyle(app.palette.ink2)
                                .accessibilityIdentifier("eventDetails.distance")
                        }
                    }
                }
                if !hostNote.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.T("Lời nhắn từ host", "Note from the host")).font(.caption.weight(.semibold)).foregroundStyle(app.palette.ink2)
                        Text(hostNote).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("eventDetails.hostNote")
                }
                if let url = event.mapsURL {
                    Link(destination: url) {
                        Text(app.T("Chỉ đường", "Directions") + " ↗").font(.subheadline.weight(.semibold)).underline()
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("eventDetails.directions")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(app.palette.block, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("eventDetails.location")
        }
    }
}
