import SwiftUI

/// v2.3 Event Detail look (note 81, switch `home_v23`), twin of web `src/components/event/v23Style.js`: the serif
/// display face, the Liquid-Glass material for the nav and the floating reserve bar, the glass hairline and the stub
/// shadow. Colours are the app's own tokens.
enum V23Style {
    /// The prototype's serif: Iowan Old Style ships with iOS (the face the web asks for first). Note 83: with Be Vietnam
    /// Pro chosen, the accents follow it too (web `--bb-font-accent`), so the app stays one typeface.
    static func serif(_ size: CGFloat) -> Font {
        .custom(AppFontPref.choice == .beVietnam ? "Be Vietnam Pro" : "Iowan Old Style", size: size)
    }
    static let spring = Animation.spring(response: 0.34, dampingFraction: 0.78)
    static let out = Animation.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.42)
    /// The glass hairline: bright in light, faint in dark.
    static func line(_ scheme: ColorScheme) -> Color { scheme == .dark ? .white.opacity(0.09) : .white.opacity(0.62) }
}

/// Liquid glass: a blur with the page colour over it (opaque with Reduce Transparency), the hairline and a soft shadow.
struct V23Glass<S: Shape>: ViewModifier {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: S
    var shadow = true

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    if reduceTransparency {
                        shape.fill(app.palette.paper)
                    } else {
                        shape.fill(.ultraThinMaterial)
                        shape.fill(app.palette.paper.opacity(0.84))
                    }
                }
                .shadow(color: .black.opacity(shadow ? (scheme == .dark ? 0.55 : 0.16) : 0), radius: 22, y: 18)
            }
            .overlay(shape.stroke(V23Style.line(scheme), lineWidth: 1))
    }
}

// MARK: - Ticket stub

/// v2.3 ticket stub (web `TicketStubV23.jsx`): a paper ticket riding up over the hero. Top: a calendar page (serif
/// month, numeral, weekday behind one hairline), the time, the countdown and the place with Directions. Perforation,
/// the price band (tear-off strip; the seat pill, or the Held / Confirmed stamp, on the right), perforation, then one
/// slim "Save the date" row with the two calendar chips. Real data only.
struct TicketStubV23: View {
    struct Seat { let text: String; let kind: EventDetailPresentation.SeatKind }
    struct StampModel: Equatable { let confirmed: Bool; let text: String }

    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    let block: EventDetailPresentation.DateBlock?
    let time: String?
    let countdown: String?
    let placeLine: String
    let mapsURL: URL?
    var onDirections: () -> Void = {}
    let price: String?
    let perTicket: String?
    let seat: Seat?
    var stamp: StampModel? = nil
    /// Each increase slams the stamp in (Reduce Motion: a fade); a confirmation sends one sheen across the strip.
    var stampPlay = 0
    var calendar: AnyView? = nil
    var inert = false

    @State private var stampScale: CGFloat = 1
    @State private var stampAngle: Double = -6
    @State private var stampOpacity: Double = 1
    @State private var press: CGFloat = 0
    @State private var sheen: CGFloat = -1.2

    var body: some View {
        VStack(spacing: 0) {
            top
            Perforation()
            priceStrip
            if let calendar {
                Perforation()
                HStack(spacing: 10) {
                    Label {
                        Text(app.T("Lưu ngày", "Save the date")).font(.app(size: 12, weight: .semibold)).foregroundStyle(app.palette.ink2)
                    } icon: {
                        Image(systemName: "calendar.badge.plus").font(.app(size: 13)).foregroundStyle(app.palette.clay)
                    }
                    .fixedSize()
                    Spacer(minLength: 0)
                    calendar.allowsHitTesting(!inert)
                }
                .padding(.leading, 18).padding(.trailing, 12).padding(.vertical, 4)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("event.stubLip")
            }
        }
        .foregroundStyle(app.palette.ink)
        .background(app.palette.surface1, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(V23Style.line(scheme), lineWidth: 1))
        .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.22), radius: 34, y: 30)
        .shadow(color: .black.opacity(scheme == .dark ? 0.3 : 0.08), radius: 6, y: 3)
        .offset(y: press * 2)
        .scaleEffect(1 - press * 0.006)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("event.ticketStub")
        .onChange(of: stampPlay) { _, _ in playStamp() }
    }

    private var top: some View {
        HStack(alignment: .center, spacing: 18) {
            if let b = block {
                VStack(spacing: 0) {
                    Text(b.month).font(V23Style.serif(10.5).weight(.semibold)).tracking(1.8).foregroundStyle(app.palette.clay)
                    Text(b.day).font(V23Style.serif(38)).tracking(-1.3).padding(.top, 5).padding(.bottom, 6)
                    Text(b.weekday).font(.app(size: 10, weight: .semibold)).tracking(1.6).foregroundStyle(app.palette.ink3)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(width: 56)
                .padding(.trailing, 16)
                .overlay(alignment: .trailing) { Rectangle().fill(app.palette.rule).frame(width: 1) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(b.weekday) \(b.day) \(b.month)")
                .accessibilityIdentifier("event.fact.when")
            }
            VStack(alignment: .leading, spacing: 4) {
                if let time {
                    Text(time).font(.app(size: 16, weight: .semibold)).tracking(-0.16)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("event.fact.time")
                }
                if let countdown {
                    HStack(spacing: 5) {
                        Circle().frame(width: 5, height: 5)
                        Text(countdown).font(.app(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(app.palette.honey)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("event.countdown")
                }
                HStack(spacing: 10) {
                    Text(placeLine).font(.app(size: 13)).foregroundStyle(app.palette.ink2).lineLimit(1)
                        .accessibilityIdentifier("event.fact.where")
                    Spacer(minLength: 0)
                    if let mapsURL {
                        Button {
                            onDirections()
                            openURL(mapsURL)
                        } label: {
                            Label(app.T("Chỉ đường", "Directions"), systemImage: "arrow.up")
                                .font(.app(size: 12, weight: .bold))
                                .foregroundStyle(app.palette.paper)
                                .padding(.horizontal, 11)
                                .frame(height: 30)
                                .background(app.palette.ink, in: Capsule())
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableButtonStyle())
                        .allowsHitTesting(!inert)
                        .accessibilityIdentifier("event.address")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
    }

    private var priceStrip: some View {
        let confirmed = stamp?.confirmed == true
        return HStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let price { Text(price).font(V23Style.serif(24)).tracking(-0.5).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7) }
                if let perTicket { Text(perTicket).font(.app(size: 12)).foregroundStyle(app.palette.ink3).lineLimit(1) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("event.price")
            Spacer(minLength: 0)
            Group {
                if let stamp { stampView(stamp) } else if let seat { seatPill(seat) }
            }
            .accessibilityIdentifier("event.fact.seats")
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background {
            ZStack {
                (confirmed ? app.palette.update.opacity(0.14) : Color.clear).background(app.palette.surface2)
                // One sheen across the strip on a confirmation.
                LinearGradient(stops: [.init(color: .clear, location: 0.28), .init(color: .white.opacity(0.55), location: 0.47),
                                       .init(color: .clear, location: 0.64)], startPoint: .leading, endPoint: .trailing)
                    .offset(x: sheen * 400)
                    .opacity(abs(sheen) < 1.1 ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: calendar == nil ? 25 : 0, bottomTrailingRadius: calendar == nil ? 25 : 0,
                                              style: .continuous))
            .animation(V23Style.out, value: confirmed)
        }
        .accessibilityIdentifier("event.priceStrip")
    }

    private func seatPill(_ s: Seat) -> some View {
        let few = s.kind == .few, going = s.kind == .going
        let tone: Color = few ? app.palette.honey : going ? app.palette.clay : app.palette.ink
        return HStack(spacing: 5) {
            Circle().frame(width: 5, height: 5)
            Text(s.text).font(.app(size: 12, weight: .semibold)).lineLimit(1)
        }
        .fixedSize()
        .foregroundStyle(tone)
        .padding(.horizontal, 11).frame(height: 28)
        .background((few || going) ? tone.opacity(0.10) : .clear, in: Capsule())
        .overlay(Capsule().stroke((few || going) ? tone.opacity(0.34) : app.palette.rule, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("event.seatStatus")
    }

    private func stampView(_ s: StampModel) -> some View {
        let tone = s.confirmed ? app.palette.update : app.palette.honey
        return HStack(spacing: 5) {
            Image(systemName: s.confirmed ? "checkmark" : "clock").font(.app(size: 10, weight: .heavy))
            Text(s.text.uppercased()).font(.app(size: 10.5, weight: .heavy)).tracking(1.7).lineLimit(1)
        }
        .fixedSize()
        .foregroundStyle(tone)
        .padding(.horizontal, 10).frame(height: 28)
        .background(app.palette.surface1, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(tone, lineWidth: 1.5))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(tone.opacity(0.45), lineWidth: 1).padding(2))
        .rotationEffect(.degrees(stampAngle))
        .scaleEffect(stampScale)
        .opacity(stampOpacity)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("event.stubStamp")
    }

    private func playStamp() {
        var t = Transaction(); t.disablesAnimations = true
        if reduceMotion {
            withTransaction(t) { stampOpacity = 0 }
            withAnimation(.easeOut(duration: 0.22)) { stampOpacity = 1 }
            return
        }
        withTransaction(t) { stampOpacity = 0; stampScale = 1.9; stampAngle = -16; sheen = -1.2 }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.55)) { stampOpacity = 1; stampScale = 1; stampAngle = -6 }
        Haptics.light()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            withAnimation(.easeOut(duration: 0.12)) { press = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { withAnimation(.easeOut(duration: 0.12)) { press = 0 } }
        }
        if stamp?.confirmed == true {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 1)) { sheen = 1.2 }
            }
        }
    }
}

/// A dashed perforation across the stub with a pressed half-circle bite at each edge (paper pressed in: a touch
/// darker than the page, a soft shade from the top, the glass line on its lower lip).
private struct Perforation: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            notch(leading: true)
            DashLine().stroke(app.palette.rule, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .frame(height: 1.5).padding(.horizontal, 7)
            notch(leading: false)
        }
        .frame(height: 16)
        .padding(.vertical, -8)
        .zIndex(2)
        .accessibilityHidden(true)
    }

    private func notch(leading: Bool) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: leading ? 0 : 8, bottomLeadingRadius: leading ? 0 : 8,
                                           bottomTrailingRadius: leading ? 8 : 0, topTrailingRadius: leading ? 8 : 0)
        return shape
            .fill(app.palette.paper)
            .overlay(shape.fill(Color.black.opacity(0.07)))
            .overlay(shape.fill(LinearGradient(colors: [.black.opacity(0.22), .clear], startPoint: .top, endPoint: .center)))
            .overlay(alignment: .bottom) { Rectangle().fill(V23Style.line(scheme)).frame(height: 1) }
            .clipShape(shape)
            .frame(width: 9, height: 16)
            .offset(x: leading ? -1 : 1)
    }
}

private struct DashLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

/// The same two "Save the date" chips, inert, for the create-event preview (a draft is not a real event yet).
struct PlanChipsPreview: View {
    @EnvironmentObject private var app: AppState
    var body: some View {
        HStack(spacing: 6) {
            PlanChipFace(label: "banbe", systemImage: "bell", added: false)
            PlanChipFace(label: app.T("Lịch", "Calendar"), systemImage: "calendar", added: false)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Reserve bar

/// v2.3 reserve bar (web `ReserveBarV23.jsx`): compact on arrival (1 · 2 · 3 · 4+ and a plain Reserve), the full card
/// past ~40 pt of scroll (chips, guest dots, total with what it multiplies, Reserve, trust line). One sliding ink under
/// the chosen chip; 4+ turns its own slot into a − N + stepper up to 6 per person or the seats left. Once the viewer
/// holds seats (`booked` > 0) the same bar opens their booking or adds tickets as a second booking.
struct ReserveBarV23View: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var inkSpace

    let compact: Bool
    let qty: Int
    let remaining: Int?
    let setQty: (Int) -> Void
    let totalFor: (Int) -> String
    let unitText: String
    let free: Bool
    let onReserve: () -> Void
    let trustLine: String?
    var booked = 0
    var confirmed = false
    var phase: String? = nil
    var onHeld: () -> Void = {}
    var onAdd: (Int) -> Void = { _ in }

    @State private var refusal: ViEn?
    @State private var refusalGen = 0
    @State private var shake: CGFloat = 0
    @State private var totalBob: CGFloat = 0

    private var en: Bool { app.isEN }
    private var held: Bool { booked > 0 }
    private var add: ReserveBarV23.AddControl? { held ? ReserveBarV23.addControl(qty, remaining: remaining, booked: booked) : nil }
    private var plain: ReserveBarV23.Control { ReserveBarV23.control(qty, remaining: remaining) }
    private var stepper: Bool { add?.stepper ?? plain.stepper }
    private var maxQ: Int { add?.max ?? plain.max }
    private var minQ: Int { add?.min ?? 1 }
    private var moreEnabled: Bool { add?.moreEnabled ?? plain.moreEnabled }
    private var canMinus: Bool { add?.canMinus ?? plain.canMinus }
    private var canPlus: Bool { add?.canPlus ?? plain.canPlus }
    private var heldCopy: ReserveBarV23.HeldCopy? {
        add.map { ReserveBarV23.heldCopy(booked: booked, extra: $0.extra, confirmed: confirmed, phase: phase) }
    }
    private enum BarState: String { case reserve, adding, ticket, held }
    private var barState: BarState { !held ? .reserve : (add?.adding == true) ? .adding : confirmed ? .ticket : .held }
    private var fold: Bool { compact && stepper }

    var body: some View {
        Group {
            if compact {
                HStack(spacing: 10) { chips; reserveButton }
            } else {
                VStack(spacing: 0) {
                    chips
                    if stepper { guestLine.padding(.top, 8) }
                    HStack(spacing: 12) { totalBlock; reserveButton }.padding(.top, 10)
                    if let trust = trustText { trustRow(trust).padding(.top, 8) }
                }
            }
        }
        .overlay(alignment: .top) {
            if let refusal {
                Text(refusal.t(en))
                    .font(.app(size: 12.5, weight: .semibold))
                    .foregroundStyle(app.palette.paper)
                    .lineLimit(1)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(app.palette.ink, in: Capsule())
                    .shadow(color: .black.opacity(0.28), radius: 15, y: 14)
                    .offset(y: compact ? -74 : -80)
                    .transition(.opacity.combined(with: .offset(y: 10)))
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("event.qtyRefusal")
            }
        }
        .animation(reduceMotion ? nil : V23Style.spring, value: compact)
        .animation(reduceMotion ? nil : V23Style.spring, value: stepper)
        .onChange(of: qty) { _, _ in
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.13)) { totalBob = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) { withAnimation(.easeOut(duration: 0.13)) { totalBob = 0 } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(compact ? "event.barV23.compact" : "event.barV23.full")
    }

    // MARK: chips

    private var chips: some View {
        HStack(spacing: fold ? 0 : compact ? 2 : 4) {
            ForEach([1, 2, 3], id: \.self) { n in chip(n) }
            slot
        }
        .padding(compact ? 3 : 4)
        .background(app.palette.surface2, in: Capsule())
        .fixedSize(horizontal: compact, vertical: false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(app.T("Chọn số vé", "Choose tickets"))
        .accessibilityIdentifier("event.qtyPresets")
    }

    private func chip(_ n: Int) -> some View {
        let on = !stepper && qty == n
        let enabled = n <= maxQ && n >= minQ
        return Button { pick(n) } label: {
            Text(compact ? "\(n)" : app.T("\(n) vé", n == 1 ? "1 ticket" : "\(n) tickets"))
                .font(.app(size: compact ? 12.5 : 13, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(on ? app.palette.paper : app.palette.ink2)
                .frame(width: fold ? 0 : compact ? 44 : nil, height: 44)
                .frame(maxWidth: compact ? nil : .infinity)
                .background {
                    if on { Capsule().fill(app.palette.ink).matchedGeometryEffect(id: "ink", in: inkSpace) }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!enabled || fold)
        .opacity(fold ? 0 : enabled ? 1 : 0.32)
        .accessibilityHidden(fold)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("event.qty.\(n)")
    }

    @ViewBuilder private var slot: some View {
        if stepper {
            HStack(spacing: 0) {
                stepButton(minus: true)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(qty)").font(.app(size: 15, weight: .heavy)).monospacedDigit()
                        .contentTransition(.numericText(value: Double(qty)))
                    if !en { Text("vé").font(.app(size: 10.5, weight: .semibold)).opacity(0.75) }
                }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("event.qty.value")
                stepButton(minus: false)
            }
            .foregroundStyle(app.palette.paper)
            .frame(width: compact ? 132 : 140, height: 44)
            .background(app.palette.ink, in: Capsule())
            .transition(.scale(scale: 0.86).combined(with: .opacity))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(app.T("Số vé", "Tickets"))
            .accessibilityValue("\(qty)")
            .accessibilityAdjustableAction { d in
                switch d {
                case .increment: if canPlus { setQty(qty + 1) }
                case .decrement: if canMinus { setQty(qty - 1) }
                @unknown default: break
                }
            }
            .accessibilityIdentifier("event.qtyStepper")
        } else {
            Button { pickMore() } label: {
                Text(compact ? "4+" : app.T("4+ vé", "4+"))
                    .font(.app(size: compact ? 12.5 : 13, weight: .semibold))
                    .foregroundStyle(app.palette.ink2)
                    .frame(width: compact ? 44 : nil, height: 44)
                    .frame(maxWidth: compact ? nil : .infinity)
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .opacity(moreEnabled ? 1 : 0.4)
            .modifier(ShakeEffect(travel: shake))
            .accessibilityLabel(app.T("4 đến 6 vé", "4 to 6 tickets"))
            .accessibilityIdentifier("event.qty.more")
        }
    }

    private func stepButton(minus: Bool) -> some View {
        let enabled = minus ? canMinus : canPlus
        return Button { setQty(qty + (minus ? -1 : 1)); Haptics.light() } label: {
            Image(systemName: minus ? "minus" : "plus").font(.app(size: 11, weight: .bold))
                .frame(width: 26, height: 26)
                .background(app.palette.paper.opacity(0.18), in: Circle())
                .frame(width: 42, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(minus ? app.T("Bớt một vé", "One ticket fewer") : app.T("Thêm một vé", "One more ticket"))
        .accessibilityIdentifier(minus ? "event.qty.minus" : "event.qty.plus")
    }

    private func pick(_ n: Int) {
        withAnimation(.easeOut(duration: 0.2)) { refusal = nil }
        withAnimation(reduceMotion ? nil : V23Style.spring) { setQty(n) }
        Haptics.light()
    }

    private func pickMore() {
        guard moreEnabled else {
            let text = held ? ViEn("Tối đa \(maxQ) vé cho bạn ở sự kiện này", "Up to \(maxQ) tickets for you on this one")
                            : ReserveBarV23.moreRefusal(remaining ?? 0)
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) { refusal = text }
            if !reduceMotion { withAnimation(.linear(duration: 0.26)) { shake += 1 } }
            Haptics.error()
            refusalGen += 1
            let gen = refusalGen
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                if refusalGen == gen { withAnimation(.easeOut(duration: 0.2)) { refusal = nil } }
            }
            return
        }
        pick(max(ReserveBarV23.moreAt, minQ))
    }

    // MARK: full card parts

    private var guestLine: some View {
        let line: ViEn = held
            ? (ReserveBarV23.addGuestLine(qty, booked: booked, max: maxQ) ?? ViEn("\(booked) vé của bạn · tối đa \(maxQ)", "\(booked) yours · up to \(maxQ)"))
            : ReserveBarV23.guestLine(qty, remaining: remaining)
        return HStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(Array(ReserveBarV23.seatDots(qty).enumerated()), id: \.offset) { _, d in
                    let c: Color = d == .me ? app.palette.ink : d == .guest ? app.palette.clay : app.palette.ink3
                    Circle().strokeBorder(c, lineWidth: 1.5).background(Circle().fill(d == .empty ? .clear : c)).frame(width: 7, height: 7)
                }
            }
            .accessibilityHidden(true)
            Text(line.t(en)).font(.app(size: 12)).foregroundStyle(app.palette.ink2)
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("event.guestLine")
    }

    private var totalText: String {
        if !held { return totalFor(qty) }
        if free { return totalFor(qty) }
        if let a = add, a.adding { return "+" + totalFor(a.extra) }
        return totalFor(booked)
    }

    private var totalBlock: some View {
        let sub = heldCopy?.sub ?? ReserveBarV23.totalSub(qty, unitText: unitText, free: free)
        return VStack(alignment: .leading, spacing: 2) {
            Text(totalText).font(V23Style.serif(26)).tracking(-0.65).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                .offset(y: -5 * totalBob).opacity(1 - 0.45 * totalBob)
                .accessibilityIdentifier("event.barTotal")
            Text(sub.t(en)).font(.app(size: 11.5)).monospacedDigit()
                .foregroundStyle(barState == .adding ? app.palette.honey : app.palette.ink2).lineLimit(1)
                .accessibilityIdentifier("event.barTotalSub")
        }
        .frame(minWidth: 112, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var reserveButton: some View {
        Button {
            switch barState {
            case .reserve: onReserve()
            case .adding: onAdd(add?.extra ?? 0)
            case .held, .ticket: onHeld()
            }
        } label: {
            HStack(spacing: 8) {
                if barState == .held { Image(systemName: "checkmark").font(.app(size: 15, weight: .semibold)) }
                Text(heldCopy.map { $0.button.t(en) } ?? app.T("Giữ chỗ", "Reserve")).lineLimit(1).minimumScaleFactor(0.8)
            }
            .font(.app(size: compact ? 14 : 15, weight: .bold))
            .foregroundStyle(app.palette.paper)
            .frame(maxWidth: .infinity, minHeight: compact ? 46 : 54)
            .background(app.palette.ink, in: Capsule())
            .shadow(color: .black.opacity(0.24), radius: 16, y: 14)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityIdentifier("event.actionBar")
        .accessibilityValue(barState.rawValue)
    }

    private var trustText: String? { heldCopy.map { $0.trust.t(en) } ?? trustLine }

    private func trustRow(_ text: String) -> some View {
        let color: Color = barState == .adding ? app.palette.honey : barState == .ticket ? app.palette.update : app.palette.ink2
        return Label {
            Text(text).font(.app(size: 12)).multilineTextAlignment(.center)
        } icon: {
            Image(systemName: "checkmark.shield").font(.app(size: 12)).foregroundStyle(held ? color : app.palette.clay)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.28), value: barState)
        .accessibilityIdentifier("event.trustLine")
    }
}

/// A short side-to-side shake (the 4+ refusal).
private struct ShakeEffect: GeometryEffect {
    var travel: CGFloat
    var animatableData: CGFloat { get { travel } set { travel = newValue } }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 3 * sin(travel * .pi * 3), y: 0))
    }
}

// MARK: - Editorial body pieces

/// Section heading: small spaced caps.
struct V23SectionHeading: View {
    @EnvironmentObject private var app: AppState
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.app(size: 11, weight: .bold)).tracking(1.76)
            .foregroundStyle(app.palette.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 14)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One body section: a hairline under all but the last, revealed (rise + fade) once it scrolls into view.
struct V23Section<Content: View>: View {
    @EnvironmentObject private var app: AppState
    let shown: Bool
    let last: Bool
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, last ? 0 : 30)
            .overlay(alignment: .bottom) { if !last { Rectangle().fill(app.palette.divider).frame(height: 1) } }
            .padding(.bottom, last ? 0 : 30)
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
    }
}
