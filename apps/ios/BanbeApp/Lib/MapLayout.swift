import CoreGraphics

// Map E+ (note 79): dimming, the list pull and the dock. Web twin: the "Map E+" section at the bottom of
// src/lib/mapLayout.js; shared cases in tests/fixtures/map-discovery.json (dim, pullOutcome, veilOpacity, dockVisible).

/// How the time window dims what is outside it. Opacity / scale are 0 to 1.
enum MapDim {
    static let pinOpacity: CGFloat = 0.3
    static let pinScale: CGFloat = 0.88
    static let rowOpacity: CGFloat = 0.42
    static let chipOpacity: CGFloat = 0.5
    static let zeroBubble: CGFloat = 0.5
    static let rangeOff: CGFloat = 0.32
}

/// Pulling the list down to return to the map. Distances in px, speed in px per millisecond.
enum MapListPull {
    static let closePx: CGFloat = 110      // a pull past this closes
    static let flickPxPerMs: CGFloat = 0.6 // …or a faster flick
    static let flickMinPx: CGFloat = 50    // …after at least this far
    static let veilPx: CGFloat = 130       // the veil is fully gone at this pull
    static let slopPx: CGFloat = 6         // finger travel before a pull starts

    enum Outcome: String { case close, back }

    /// `velocity` in px per millisecond, positive = downward.
    static func closes(dy: CGFloat, velocity: CGFloat) -> Bool {
        dy > closePx || (velocity > flickPxPerMs && dy > flickMinPx)
    }
    static func outcome(dy: CGFloat, velocity: CGFloat = 0) -> Outcome { closes(dy: dy, velocity: velocity) ? .close : .back }
    /// Opacity of the veil over the strip above the list while it is pulled `dy` px: 1 at rest, 0 at `veilPx`.
    static func veilOpacity(dy: CGFloat) -> CGFloat { max(0, 1 - dy / veilPx) }
}

enum MapLayout {
    /// The dock shows except while the area panel is open (the list and the map keep a bottom clearance for it).
    static func dockVisible(panelOpen: Bool) -> Bool { !panelOpen }
}
