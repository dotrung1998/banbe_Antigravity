import SwiftUI

/// One card in the event feed — mirrors the photo card in
/// src/screens/Home.jsx's feed: a photo (rounded top corners, a soft
/// gradient fading into the page background at the bottom), the event
/// name, a "category ▪︎ area ▪︎ date" meta line, and price/seats at the
/// trailing edge.
struct EventRow: View {
    let event: Event
    /// Position of this event in the feed — used only to deterministically
    /// pick a hero photo (see PhotoCatalog); has no other meaning.
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottom) {
                AsyncImage(url: PhotoCatalog.heroPhotoURL(forIndex: index)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .failure:
                        Color(hex: 0xEEE8DA)
                    default:
                        Color(hex: 0xEEE8DA).overlay(ProgressView())
                    }
                }
                .frame(height: 220)
                .clipped()

                LinearGradient(
                    colors: [BanbeTheme.paper.opacity(0), BanbeTheme.paper.opacity(0.3), BanbeTheme.paper],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 44)
            }
            .clipShape(.rect(topLeadingRadius: 14, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 14))

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.name)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(BanbeTheme.ink)
                    Text(metaLine)
                        .font(.caption)
                        .foregroundStyle(BanbeTheme.ink.opacity(0.7))
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(priceLabel)
                        .font(.caption)
                        .foregroundStyle(BanbeTheme.ink)
                    Text(seatsLabel)
                        .font(.caption2)
                        .foregroundStyle(BanbeTheme.ink.opacity(0.7))
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(BanbeTheme.paper)
        .padding(.horizontal, 20)
    }

    private var metaLine: String {
        [event.category, event.area, dateLabel]
            .filter { !$0.isEmpty }
            .joined(separator: " ▪︎ ")
    }

    private var dateLabel: String {
        guard let startsAt = event.startsAt else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "E, d MMM"
        return formatter.string(from: startsAt)
    }

    private var priceLabel: String {
        if event.priceVnd <= 0 { return "Free" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        let formatted = formatter.string(from: NSNumber(value: event.priceVnd)) ?? "\(event.priceVnd)"
        return "\(formatted)₫"
    }

    private var seatsLabel: String {
        guard let seats = event.seatsRemaining else { return "" }
        return seats > 0 ? "\(seats) left" : "Sold out"
    }
}
