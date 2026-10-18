import Foundation

/// Pure helpers for the Home Pulse ticker (note 51). Web twin: src/lib/pulseTicker.js — keep both and their tests
/// in sync. The view only renders what these return.
enum PulseTicker {
    struct Item: Equatable, Identifiable {
        let id: String
        let rank: Int
        let name: String
    }

    static let maxItems = 5
    private static let secondsPerChar = 0.26 // a fixed reading-speed feel: longer lists scroll for longer, never faster
    private static let minSeconds = 14.0
    private static let extraCharsPerItem = 4  // the rank number and the gap between items

    /// The top events to show: skips rows without a name, keeps the server's order, numbers them 1...N.
    static func items(from pulse: [PulseItem]) -> [Item] {
        var out: [Item] = []
        for p in pulse {
            let name = p.eventName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            out.append(Item(id: p.eventId, rank: out.count + 1, name: name))
            if out.count == maxItems { break }
        }
        return out
    }

    /// Seconds for one full pass of the strip (the view turns this into a points-per-second speed).
    static func seconds(for items: [Item]) -> Double {
        let chars = items.reduce(0) { $0 + $1.name.count + extraCharsPerItem }
        return max(minSeconds, (Double(chars) * secondsPerChar).rounded())
    }
}
