import SwiftUI

/// One row in the event feed — name, area, and price, matching what
/// src/screens/Home.jsx's event card shows.
struct EventRow: View {
    let event: Event

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.name)
                .font(.headline)
            Text(event.area.isEmpty ? event.category : event.area)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(priceLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var priceLabel: String {
        if event.priceVnd <= 0 { return "Free" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        let formatted = formatter.string(from: NSNumber(value: event.priceVnd)) ?? "\(event.priceVnd)"
        return "\(formatted)₫"
    }
}
