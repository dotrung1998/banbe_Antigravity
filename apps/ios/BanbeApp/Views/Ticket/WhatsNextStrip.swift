import SwiftUI

/// Slim "What's next" strip at the top of the paper ticket (note 78). One line (heading + optional tail); tapping it
/// expands the explanation and the one existing action that fits. The tone paints the disc, the tint and the status dot
/// ONLY: every text here is ink (tone-coloured text fails 4.5:1 on its own tint in light, DesignTokensTests).
/// `solid` (checked in) fills with the tone and reads paper on it. Twin of src/components/ticket/WhatsNextStrip.jsx.
struct WhatsNextStrip: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let key: TicketStatus.Key
    let tone: Color
    var solid = false
    let heading: String
    var sub: String?
    var tail: String?
    var tailID: String?
    var detail: String?
    var linkLabel: String?
    var linkURL: URL?
    var onLink: () -> Void = {}
    @State private var open = false

    private var expandable: Bool { detail != nil || linkLabel != nil }
    private var fg: Color { solid ? app.palette.paper : app.palette.ink }
    private var fg2: Color { solid ? app.palette.paper : app.palette.ink2 }
    private var fill: Color { solid ? tone : tone.opacity(0.13) }

    private var icon: String {
        switch key {
        case .cancelled: return "xmark"
        case .expired, .holding: return "hourglass"
        case .review: return "info"
        case .awaiting: return "creditcard"
        case .ended: return "flag"
        case .checkedIn: return "checkmark"
        case .today: return "clock"
        case .upcoming: return "calendar"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if expandable {
                Button { toggle() } label: { row }
                    .buttonStyle(.plain)
                    .accessibilityValue(open ? app.T("Đang mở", "Expanded") : app.T("Đang thu gọn", "Collapsed"))
                    .accessibilityHint(app.T("Chạm để xem thêm", "Tap for more"))
                    .accessibilityIdentifier("confirmed.strip.toggle")
            } else {
                row
            }
            if expandable, open {
                VStack(alignment: .leading, spacing: 8) {
                    if let detail {
                        Text(detail).font(.footnote).foregroundStyle(fg2)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("confirmed.strip.detail")
                    }
                    if let linkLabel {
                        if let linkURL {
                            Link(destination: linkURL) { linkText(linkLabel) }
                                .accessibilityIdentifier("confirmed.strip.link")
                        } else {
                            Button(action: onLink) { linkText(linkLabel) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("confirmed.strip.link")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 48).padding(.trailing, 12).padding(.bottom, 12)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("confirmed.strip")
    }

    private func toggle() {
        if reduceMotion { open.toggle() } else { withAnimation(.easeOut(duration: 0.25)) { open.toggle() } }
    }

    private func linkText(_ label: String) -> some View {
        Text(label + " ›")
            .font(.footnote.weight(.semibold)).foregroundStyle(fg)
            .underline()
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
    }

    private var row: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(solid ? tone : app.palette.paper)
                .frame(width: 26, height: 26)
                .background(solid ? app.palette.paper : tone, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(heading).font(.footnote.weight(.semibold)).foregroundStyle(fg)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("confirmed.strip.heading")
                if let sub {
                    Text(sub).font(.caption).foregroundStyle(fg2).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let tail {
                Text(tail).font(.footnote.weight(.semibold)).monospacedDigit().foregroundStyle(fg)
                    .accessibilityIdentifier(tailID ?? "confirmed.strip.tail")
            }
            if expandable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(fg)
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
