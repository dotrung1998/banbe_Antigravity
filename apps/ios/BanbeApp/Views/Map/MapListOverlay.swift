import SwiftUI
import UIKit

// Map E+ (plan step 0, note 79): the list that slides up to just under the shared search/chip row, and the pull-down
// that returns to the map. An in-hierarchy layer, NOT a system `.sheet` (a custom drag on the system sheet failed on a
// real device and was reverted, note 06). The pull never uses a SwiftUI `DragGesture`: like `SheetBottomLift` it adds a
// target to the list's OWN `UIScrollView` pan recognizer, so scrolling, taps and the pull never fight.

/// Reports a downward pull of the enclosing list, only when the finger went down while the list was already at its
/// top. While pulling, the list is held at its top (no rubber band) and `onChange` carries the pull distance.
/// Place it as the `.background` of the list's FIRST row: at scroll-top that row is always alive.
struct ListTopPullProbe: UIViewRepresentable {
    var isEnabled = true
    var onBegin: () -> Void = {}
    let onChange: (CGFloat) -> Void
    let onEnd: (Bool) -> Void      // true = the pull closes the list

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> Hook {
        let v = Hook(); v.coordinator = context.coordinator; v.isUserInteractionEnabled = false; return v
    }
    func updateUIView(_ uiView: Hook, context: Context) {
        let c = context.coordinator
        c.isEnabled = isEnabled; c.onBegin = onBegin; c.onChange = onChange; c.onEnd = onEnd
    }
    static func dismantleUIView(_ uiView: Hook, coordinator: Coordinator) { coordinator.detach() }

    final class Hook: UIView {
        weak var coordinator: Coordinator?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.coordinator?.attach(from: self) }
        }
    }

    @MainActor final class Coordinator: NSObject {
        var isEnabled = true
        var onBegin: () -> Void = {}
        var onChange: (CGFloat) -> Void = { _ in }
        var onEnd: (Bool) -> Void = { _ in }
        private weak var scrollView: UIScrollView?
        private var qualified = false   // the finger went down with the list already at its top
        private var pulling = false
        private var dy: CGFloat = 0

        func attach(from view: UIView?) {
            var v = view?.superview
            while let cur = v, !(cur is UIScrollView) { v = cur.superview }
            guard let sv = v as? UIScrollView, sv !== scrollView else { return }
            detach()
            scrollView = sv
            sv.panGestureRecognizer.addTarget(self, action: #selector(pan(_:)))
        }

        func detach() {
            scrollView?.panGestureRecognizer.removeTarget(self, action: #selector(pan(_:)))
            scrollView = nil
        }

        private func top(_ sv: UIScrollView) -> CGFloat { -sv.adjustedContentInset.top }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            guard let sv = scrollView else { return }
            let ty = g.translation(in: sv.window).y
            switch g.state {
            case .began:
                qualified = isEnabled && sv.contentOffset.y <= top(sv) + 0.5
                pulling = false; dy = 0
            case .changed:
                guard qualified else { return }
                if !pulling {
                    guard ty > MapListPull.slopPx, sv.contentOffset.y <= top(sv) + 0.5 else { return }
                    pulling = true
                    onBegin()
                }
                if ty <= 0 {
                    // The finger went back above where it started: an ordinary scroll again.
                    pulling = false; dy = 0
                    onChange(0)
                    return
                }
                dy = max(0, ty - MapListPull.slopPx)
                sv.contentOffset.y = top(sv)   // held at the top: the list rides with the sheet, no bounce
                onChange(dy)
            case .ended, .cancelled, .failed:
                guard pulling else { return }
                pulling = false
                let v = g.velocity(in: sv.window).y / 1000
                let closes = g.state == .ended && MapListPull.closes(dy: dy, velocity: v)
                sv.setContentOffset(CGPoint(x: sv.contentOffset.x, y: top(sv)), animated: false)
                onEnd(closes)
                dy = 0
            default: break
            }
        }
    }
}

/// The list layer: a paper-coloured veil over the strip above it, the list below, a floating "Map" button.
/// `top` is the measured bottom of the shared controls; the caller draws those controls ABOVE this view in z-order
/// (the veil sits behind them, covering the map). Pulling moves the list and fades the veil with the finger.
struct MapListOverlay<Content: View>: View {
    @Binding var isOpen: Bool
    let top: CGFloat
    let background: Color
    let closeTitle: String
    var bottomInset: CGFloat = 100
    @ViewBuilder let content: (ListTopPullProbe) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dy: CGFloat = 0

    private var spring: Animation? { reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.88) }

    private func close() { withAnimation(spring) { isOpen = false; dy = 0 } }

    private var probe: ListTopPullProbe {
        ListTopPullProbe(
            isEnabled: isOpen,
            onChange: { v in
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { dy = v }
            },
            onEnd: { closes in
                withAnimation(spring) {
                    if closes { isOpen = false }
                    dy = 0
                }
            })
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                background
                    .frame(height: top + 2)
                    .opacity(isOpen ? MapListPull.veilOpacity(dy: dy) : 0)
                    .allowsHitTesting(isOpen)
                    .accessibilityHidden(true)
                    .frame(maxHeight: .infinity, alignment: .top)

                VStack(spacing: 0) {
                    content(probe)
                }
                .frame(height: max(0, geo.size.height - top))
                .background(background)
                .offset(y: isOpen ? dy : geo.size.height)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(isOpen)
                .accessibilityHidden(!isOpen)
                .accessibilityAction(.escape) { close() }

                if isOpen {
                    Button(action: close) {
                        Label(closeTitle, systemImage: "map")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 16).frame(height: 40)
                            .background(Capsule().fill(.ultraThinMaterial))
                    }
                    .buttonStyle(.plain)
                    .opacity(MapListPull.veilOpacity(dy: dy))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, bottomInset)
                    .accessibilityIdentifier("map.list.mapButton")
                    .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }
}
