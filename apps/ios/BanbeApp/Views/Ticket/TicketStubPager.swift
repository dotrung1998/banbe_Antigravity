import SwiftUI

/// One stub per named attendee (migration 151), paged sideways with dots (note 78). Each stub has its own QR, 3-3 code,
/// name and a Checked-in badge. When a ticket is scanned WHILE this screen is open, that stub tears off (it stays, torn
/// and dimmed) and the pager moves on to the next ticket still to be scanned. Nothing replays on load: a stub that was
/// already checked in simply renders torn. Reduced Motion: no tilt or slide, an opacity change, and an instant move.
/// Display only: the check-in RPC, the 6s door poll and the QR values are untouched.
/// Twin of src/components/ticket/TicketStubPager.jsx.
struct TicketStubPager: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let attendees: [BookingAttendee]
    let qrMode: TicketStatus.QR
    let qrLabel: String
    @Binding var activeIndex: Int

    @State private var activeID: UUID?
    @State private var tearingID: UUID?
    /// 0 = still whole, 1 = dropped and tilted, 2 = settled torn.
    @State private var tearPhase = 0
    @State private var seen: [UUID: Bool]?
    @State private var pending: [Task<Void, Never>] = []

    private var live: Bool { qrMode == .ok || qrMode == .in }
    /// Re-evaluated only when somebody's checked-in state changes.
    private var signature: String { attendees.map { "\($0.id.uuidString):\($0.checkedInAt != nil ? 1 : 0)" }.joined(separator: ",") }
    private var many: Bool { attendees.count > 1 }

    var body: some View {
        VStack(spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(attendees) { att in
                        stub(att)
                            .containerRelativeFrame(.horizontal)
                            .id(att.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $activeID)
            .scrollDisabled(!many)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("confirmed.stubPager")

            if many { dots }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("confirmed.attendeeTickets")
        .onAppear {
            if seen == nil { seen = Self.state(attendees) }
            if activeID == nil { activeID = attendees.first?.id }
        }
        .onChange(of: activeID) { _, id in
            if let id, let i = attendees.firstIndex(where: { $0.id == id }) { activeIndex = i }
        }
        .onChange(of: signature) { _, _ in handleChange() }
        .onDisappear { pending.forEach { $0.cancel() }; pending = [] }
    }

    private static func state(_ list: [BookingAttendee]) -> [UUID: Bool] {
        list.reduce(into: [:]) { $0[$1.id] = $1.checkedInAt != nil }
    }

    // MARK: stub

    private func stub(_ att: BookingAttendee) -> some View {
        let checked = live && att.checkedInAt != nil
        let tearing = tearingID == att.id && !reduceMotion
        // While tearing, the phase drives the pose; otherwise a checked-in stub rests in the settled pose.
        let phase = tearing ? tearPhase : (checked ? 2 : 0)
        let pose: (angle: Double, drop: CGFloat, opacity: Double) = {
            if reduceMotion { return (0, 0, checked ? 0.6 : 1) }
            switch phase {
            case 1: return (-3.5, 12, 0.9)
            case 2: return (-1.5, 6, 0.6)
            default: return (0, 0, 1)
            }
        }()
        let mode: TicketStatus.QR = live ? (checked ? .in : .ok) : qrMode
        return VStack(spacing: 0) {
            if checked { TicketZigzag().stroke(app.palette.rule, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round)).frame(height: 8).padding(.bottom, 10) }
            TicketQrView(mode: mode, value: att.admissionToken.uuidString, size: 220, padding: 10, label: qrLabel)
            Text(att.name).font(BanbeTheme.display(17)).multilineTextAlignment(.center)
                .padding(.top, 14)
                .accessibilityIdentifier("confirmed.stub.name.\(att.seatNo)")
            Text(app.T("Mã vào cửa", "Entry code").uppercased())
                .font(.caption2.weight(.semibold)).tracking(0.8).foregroundStyle(app.palette.ink3)
                .padding(.top, 10)
            Text(live ? TicketStatus.formatEntryCode(att.ticketCode) : "••• •••")
                .font(.system(.title, design: .monospaced).weight(.semibold)).tracking(3)
                .lineLimit(1).minimumScaleFactor(0.6)
                .opacity(live ? 1 : 0.35)
                .padding(.top, 4)
            if checked {
                Text("✓ " + app.T("Đã vào cửa", "Checked in")).font(.footnote.weight(.semibold))
                    .padding(.top, 8)
                    .accessibilityIdentifier("confirmed.stub.badge.\(att.seatNo)")
            }
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(app.palette.ink)
        .rotationEffect(.degrees(pose.angle), anchor: .topLeading)
        .offset(y: pose.drop)
        .opacity(pose.opacity)
        .animation(reduceMotion ? .easeOut(duration: 0.3) : nil, value: checked)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(app.T("Vé \(att.seatNo) trên \(attendees.count): \(att.name)", "Ticket \(att.seatNo) of \(attendees.count): \(att.name)"))
        .accessibilityValue(checked ? app.T("Đã vào cửa", "Checked in") : "")
        .accessibilityIdentifier("confirmed.stub.\(att.seatNo)")
    }

    private var dots: some View {
        HStack(spacing: 0) {
            ForEach(attendees) { att in
                let isActive = att.id == activeID
                Button {
                    if reduceMotion { activeID = att.id } else { withAnimation(.easeInOut(duration: 0.3)) { activeID = att.id } }
                } label: {
                    Capsule().fill(isActive ? app.palette.ink : app.palette.ink3)
                        .frame(width: isActive ? 18 : 8, height: 8)
                        .opacity(isActive ? 1 : 0.55)
                        .frame(width: 28, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(app.T("Vé \(att.seatNo): \(att.name)", "Ticket \(att.seatNo): \(att.name)"))
                .accessibilityAddTraits(isActive ? .isSelected : [])
                .accessibilityIdentifier("confirmed.stub.dot.\(att.seatNo)")
            }
            Text("\((attendees.firstIndex { $0.id == activeID } ?? 0) + 1)/\(attendees.count)")
                .font(.footnote).foregroundStyle(app.palette.ink2).padding(.leading, 6)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, -14)
    }

    // MARK: tear

    private func handleChange() {
        let before = seen ?? [:]
        seen = Self.state(attendees)
        // A tear is a not-scanned -> scanned change of a ticket we already knew as open, seen while mounted.
        guard live, let idx = attendees.firstIndex(where: { $0.checkedInAt != nil && before[$0.id] == false }) else { return }
        let att = attendees[idx]
        activeID = att.id
        tearingID = att.id
        tearPhase = 0
        Haptics.success()
        UIAccessibility.post(notification: .announcement, argument: app.T("\(att.name) đã vào cửa", "\(att.name) checked in"))
        pending.forEach { $0.cancel() }
        if reduceMotion {
            tearPhase = 2
        } else {
            pending = [Task { @MainActor in
                withAnimation(.easeOut(duration: 0.16)) { tearPhase = 1 }
                try? await Task.sleep(nanoseconds: 160_000_000)
                if Task.isCancelled { return }
                withAnimation(.easeInOut(duration: 0.29)) { tearPhase = 2 }
            }]
        }
        let id = att.id
        pending.append(Task { @MainActor in
            try? await Task.sleep(nanoseconds: reduceMotion ? 300_000_000 : 450_000_000)
            if Task.isCancelled { return }
            if tearingID == id { tearingID = nil; tearPhase = 0 }
            try? await Task.sleep(nanoseconds: reduceMotion ? 0 : 150_000_000)
            if Task.isCancelled { return }
            // On to the next ticket that is still to be scanned (wrapping round).
            let n = attendees.count
            let next = (1...max(1, n)).map { (idx + $0) % n }.first { attendees[$0].checkedInAt == nil }
            guard let next else { return }
            if reduceMotion { activeID = attendees[next].id } else { withAnimation(.easeInOut(duration: 0.35)) { activeID = attendees[next].id } }
        })
    }
}

/// The torn top edge of a stub: a zigzag across the width.
private struct TicketZigzag: Shape {
    func path(in rect: CGRect) -> Path {
        let teeth = 28
        var p = Path()
        for i in 0...(teeth * 2) {
            let x = rect.minX + rect.width * CGFloat(i) / CGFloat(teeth * 2)
            let y = i % 2 == 1 ? rect.minY : rect.maxY - 2
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        return p
    }
}
