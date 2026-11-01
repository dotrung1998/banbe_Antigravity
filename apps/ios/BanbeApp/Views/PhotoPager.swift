import SwiftUI

/// Map v6 (note 74): an event's photos you swipe sideways (Airbnb-style), on Map Large cards and Home's discovery
/// cards. Web twin: src/components/PhotoPager.jsx.
///
/// - Horizontal `ScrollView` + `.scrollTargetBehavior(.paging)` (same mechanism as HowBanbeWorksView's deck); pages
///   are lazy (`LazyHStack`), each a `CatalogPhoto` decoded at the card's size (PhotoLoader cache, note 22).
/// - `rootSwipeExclusion("pager.<eventId>.<context>")`: a photo swipe never switches dock tabs
///   (`RootView.tabSwipeGesture`).
/// - Dots + a "2/5" counter; VoiceOver reads "Photo 2 of 5" and pages with swipe up / down (adjustable).
/// - One photo (or none): exactly the plain photo, no dots, no counter, no scrolling.
/// - Reduce Motion: the adjustable action and dot changes jump without animation.
struct PhotoPager: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let eventID: String
    let paths: [String]
    /// Keeps exclusion zones apart when the same event shows twice (e.g. "map", "home").
    var context: String = "card"
    var cornerRadius: CGFloat = 16
    /// Identifier of the photo element itself (Home keeps `card.<key>` there for its UI tests).
    var photoIdentifier: String? = nil
    var placeholder: Color? = nil

    @State private var page: Int? = 0

    private var current: Int { min(max(page ?? 0, 0), max(paths.count - 1, 0)) }

    var body: some View {
        GeometryReader { geo in
            if paths.count <= 1 {
                single(size: geo.size)
            } else {
                pager(size: geo.size)
            }
        }
    }

    @ViewBuilder
    private func single(size: CGSize) -> some View {
        if let path = paths.first, !path.isEmpty {
            CatalogPhoto(path: path, height: size.height, width: size.width, cornerRadius: cornerRadius)
                .accessibilityIdentifier(photoIdentifier ?? "photoPager.photo.\(eventID)")
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(placeholder ?? app.palette.field)
                .overlay { Text(app.T("Chưa có ảnh", "No photo yet")).font(.system(size: 12)).opacity(0.55) }
                .foregroundStyle(app.palette.ink)
                .accessibilityLabel(app.T("Chưa có ảnh", "No photo yet"))
                .accessibilityIdentifier(photoIdentifier ?? "photoPager.photo.\(eventID)")
        }
    }

    private func pager(size: CGSize) -> some View {
        let n = paths.count
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(Array(paths.enumerated()), id: \.offset) { i, path in
                    CatalogPhoto(path: path, height: size.height, width: size.width, cornerRadius: 0)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                        .id(i)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $page)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.T("Ảnh \(current + 1) / \(n)", "Photo \(current + 1) of \(n)"))
        .accessibilityAddTraits(.isImage)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: go(to: current + 1)
            case .decrement: go(to: current - 1)
            @unknown default: break
            }
        }
        .accessibilityIdentifier(photoIdentifier ?? "photoPager.photo.\(eventID)")
        .overlay(alignment: .bottom) {
            HStack(spacing: 5) {
                ForEach(0..<n, id: \.self) { i in
                    Circle()
                        .fill(Color.white.opacity(i == current ? 1 : 0.55))
                        .frame(width: i == current ? 7 : 6, height: i == current ? 7 : 6)
                }
            }
            .padding(.horizontal, 7).padding(.vertical, 5)
            .background(Color.black.opacity(0.28), in: Capsule())
            .padding(.bottom, 10)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .overlay(alignment: .bottomTrailing) {
            Text("\(current + 1)/\(n)")
                .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Color.black.opacity(0.45), in: Capsule())
                .padding(10)
                .allowsHitTesting(false)
                .accessibilityLabel(app.T("Ảnh \(current + 1) / \(n)", "Photo \(current + 1) of \(n)"))
                .accessibilityValue("\(current + 1)/\(n)")
                .accessibilityIdentifier("photoPager.counter.\(eventID)")
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: current)
        .rootSwipeExclusion("pager.\(eventID).\(context)")
        // Home REPLACES `rootGestureExclusionZones` with its preference-reported zones on every change
        // (HomeView `.onPreferenceChange`), so a zone written only by `rootSwipeExclusion` is wiped there and a photo
        // swipe switched Home → Map. Report the zone through the preference as well (Home's story row does the same).
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: RootGestureExclusionZonePreferenceKey.self,
                                       value: ["pager.\(eventID).\(context)": geo.frame(in: .named("rootGesture"))])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("photoPager.\(eventID)")
    }

    private func go(to i: Int) {
        let next = min(max(i, 0), paths.count - 1)
        if reduceMotion { page = next } else { withAnimation(.easeOut(duration: 0.25)) { page = next } }
    }
}
