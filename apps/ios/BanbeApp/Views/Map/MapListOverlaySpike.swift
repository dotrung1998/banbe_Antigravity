#if DEBUG
import SwiftUI
import MapKit

// Map E+ plan step 0: a stand-alone screen to prove `MapListOverlay` + `ListTopPullProbe` on a real iPhone BEFORE the
// Map is rebuilt around them. Launch with `-uiFixture spike.mapList`. Nothing here touches MapExploreView.
//
// Check on the device (note 79): a long pull from scroll-top closes; a short pull springs back; scrolling the list
// never moves it; tapping a row still counts. The readout under the status bar shows the live numbers.
struct MapListOverlaySpike: View {
    @EnvironmentObject private var app: AppState
    @State private var open = false
    @State private var taps = 0
    @State private var opens = 0
    @State private var closes = 0
    private let rows = Array(1...40)
    private let top: CGFloat = 150   // stands in for the measured bottom of search + chips

    var body: some View {
        let p = app.palette
        ZStack(alignment: .top) {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 10.7769, longitude: 106.7009),
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08))))
                .ignoresSafeArea()

            MapListOverlay(isOpen: $open, top: top, background: p.paper, closeTitle: app.T("Bản đồ", "Map")) { probe in
                List {
                    Color.clear.frame(height: 1)
                        .background(probe)
                        .listRowSeparator(.hidden).listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    ForEach(rows, id: \.self) { n in
                        Button { taps += 1 } label: {
                            HStack {
                                RoundedRectangle(cornerRadius: 12).fill(p.field).frame(width: 68, height: 68)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Sự kiện số \(n)").font(.system(size: 15, weight: .bold)).foregroundStyle(p.ink)
                                    Text("Hôm nay 19:00 · Quận 1").font(.system(size: 12.5)).foregroundStyle(p.ink2)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("spike.row.\(n)")
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(.bottom, 160, for: .scrollContent)
                .accessibilityIdentifier("spike.list")
            }

            // The shared controls stand-in: drawn ABOVE the overlay so the veil sits behind them.
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text(app.T("Tìm sự kiện, khu vực", "Search events, areas"))
                        .foregroundStyle(p.ink3).padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .background(Capsule().fill(.ultraThinMaterial))
                    Circle().fill(.ultraThinMaterial).frame(width: 44, height: 44)
                }
                .padding(.horizontal, 16)
                Text("dy readout below")
                    .font(.system(size: 11)).foregroundStyle(p.ink3)
                    .accessibilityHidden(true)
                Text("opens \(opens) · closes \(closes) · taps \(taps) · \(open ? "list open" : "map")")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(p.ink)
                    .accessibilityIdentifier("spike.readout")
            }
            .padding(.top, 62)

            if !open {
                Button { open = true; opens += 1 } label: {
                    Label(app.T("Danh sách · 40", "List · 40"), systemImage: "list.bullet")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(p.paper)
                        .padding(.horizontal, 16).frame(height: 40)
                        .background(Capsule().fill(p.ink))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 16).padding(.bottom, 130)
                .accessibilityIdentifier("spike.listButton")
            }
        }
        .onChange(of: open) { old, new in if old && !new { closes += 1 } }
    }
}
#endif
