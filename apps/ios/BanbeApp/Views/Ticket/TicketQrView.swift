import SwiftUI

/// One QR slot with the ticket's mode (note 78, Lib/TicketStatus.swift). `.ok` / `.in` draw the real admission token;
/// `.lock`, `.void` and `.past` NEVER receive it: they draw a fixed decorative pattern (the same for everyone, blurred,
/// not a valid code) with a status label, so a cancelled, ended or unconfirmed ticket can never be scanned or
/// screenshotted as valid. `.in` keeps the real code but dimmed under a check. Display only: nothing here touches
/// check-in, gifting or polling. Twin of src/components/ticket/TicketQr.jsx.
struct TicketQrView: View {
    @EnvironmentObject private var app: AppState
    let mode: TicketStatus.QR
    let value: String
    var size: CGFloat = 220
    var padding: CGFloat = 10
    var label: String = ""

    private var real: Bool { TicketStatus.qrShowsToken(mode) }
    private var small: Bool { size < 120 }

    var body: some View {
        ZStack {
            if real {
                QRCodeImage(value: value, size: size, padding: padding)
                    .opacity(mode == .in ? 0.35 : 1)
                    .accessibilityIdentifier("ticket.qr.real")
            } else {
                ZStack {
                    Color.white
                    TicketQrPattern().fill(Color(red: 17 / 255, green: 17 / 255, blue: 17 / 255))
                        .padding(padding)
                        .blur(radius: 6)
                        .opacity(0.35)
                }
                .frame(width: size, height: size)
                .clipped()
                .accessibilityIdentifier("ticket.qr.placeholder")
            }
            if mode == .in {
                Image(systemName: "checkmark")
                    .font(.system(size: small ? 14 : 28, weight: .bold))
                    .foregroundStyle(app.palette.paper)
                    .frame(width: small ? 30 : 56, height: small ? 30 : 56)
                    .background(app.palette.update, in: Circle())
            } else if !real, !small, !label.isEmpty {
                // Fixed colours: the box behind is always the white QR card, in both themes.
                Text(label)
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(red: 27 / 255, green: 25 / 255, blue: 22 / 255))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(14)
                    .accessibilityIdentifier("ticket.qr.label")
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
        .accessibilityIdentifier("ticket.qr")
    }
}

/// A fixed pseudo-random 25x25 pattern (the same LCG and seed as the web twin). Not derived from any booking data.
private struct TicketQrPattern: Shape {
    static let cells: [(Int, Int)] = {
        let n = 25
        var x: UInt32 = 20_261_105
        var out: [(Int, Int)] = []
        for r in 0..<n {
            for c in 0..<n {
                x = x &* 1_664_525 &+ 1_013_904_223
                if (x >> 16) & 1 == 1 { out.append((c, r)) }
            }
        }
        return out
    }()

    func path(in rect: CGRect) -> Path {
        let n: CGFloat = 25
        let cell = min(rect.width, rect.height) / n
        var p = Path()
        for (c, r) in Self.cells {
            p.addRect(CGRect(x: rect.minX + CGFloat(c) * cell, y: rect.minY + CGFloat(r) * cell, width: cell, height: cell))
        }
        return p
    }
}
