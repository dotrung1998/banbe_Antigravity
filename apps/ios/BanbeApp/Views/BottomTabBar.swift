import SwiftUI

/// Floating glass tab bar — the iOS port of src/screens/BottomTabBar.jsx.
/// Deployment target is iOS 17 (apps/ios/project.yml: deploymentTarget.iOS
/// = "17.0"), so the native iOS 26 `.tabBarMinimizeBehavior(.onScrollDown)`
/// isn't available; this hand-rolls the same "shrink on scroll down,
/// restore on scroll up" behavior off AppState.bottomBarCollapsed (see
/// ScreenScaffold's scroll-offset tracking / AppState.noteScaffoldScroll()).
/// Same four destinations as the old header row (Map/Notifications/Inbox/
/// Account), same custom icon vocabulary as the web bar — a ring, a
/// diagonal stroke, small filled dots, echoing public/banbe-mark.png's own
/// bold round-capped strokes rather than the classic IG/FB/Twitter shapes.
struct BottomTabBar: View {
    @EnvironmentObject var app: AppState

    static let visibleScreens: Set<Screen> = [.home, .mapExplore, .notifications, .inbox, .profile]

    private struct Item: Identifiable {
        let id: String
        let icon: (Color) -> AnyView
        let label: String
        let action: () -> Void
        let badge: Int
    }

    private var items: [Item] {
        [
            Item(id: "map", icon: { AnyView(MapGlyph(color: $0)) }, label: app.T("Bản đồ", "Map"), action: { app.goMapExplore() }, badge: 0),
            Item(id: "notifications", icon: { AnyView(NotificationsGlyph(color: $0)) }, label: app.T("Thông báo", "Notifications"), action: { app.goNotifications() }, badge: app.unreadNotifications),
            // No badge here: unlike Notifications, nothing in the schema
            // tracks a per-thread/message read state (no `read_at` on
            // `messages`, confirmed by grep before writing this), so there
            // is no real unread count to show — matching the web bar.
            Item(id: "inbox", icon: { AnyView(InboxGlyph(color: $0)) }, label: app.T("Tin nhắn", "Messages"), action: { app.goInbox() }, badge: 0),
            Item(id: "profile", icon: { AnyView(ProfileGlyph(color: $0)) }, label: app.T("Tài khoản", "Account"), action: { app.goProfile() }, badge: 0),
        ]
    }

    private var barHeight: CGFloat { app.bottomBarCollapsed ? 52 : 60 }
    private var iconSize: CGFloat { app.bottomBarCollapsed ? 19 : 22 }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                Button { item.action() } label: {
                    ZStack(alignment: .topTrailing) {
                        item.icon(app.palette.ink)
                            .frame(width: iconSize, height: iconSize)
                            .frame(width: 40, height: barHeight)
                        if item.badge > 0 {
                            Text(item.badge > 9 ? "9+" : "\(item.badge)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .frame(minWidth: 14, minHeight: 14)
                                .background(BanbeTheme.alert, in: Capsule())
                                .offset(x: -2, y: 8)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tab.\(item.id)")
                .accessibilityLabel(item.label)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: barHeight)
        .frame(maxWidth: 320)
        .background(.thinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(app.palette.ink.opacity(0.06)))
        .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 6)
        .animation(.easeInOut(duration: 0.22), value: app.bottomBarCollapsed)
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
    }
}

private struct MapGlyph: View {
    let color: Color
    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 24
            ZStack {
                Circle().stroke(color, lineWidth: 2.2 * s).frame(width: 6.4 * s, height: 6.4 * s).position(x: 7 * s, y: 16 * s)
                Path { p in p.move(to: CGPoint(x: 9.6 * s, y: 13.6 * s)); p.addLine(to: CGPoint(x: 16 * s, y: 7 * s)) }
                    .stroke(color, style: StrokeStyle(lineWidth: 2.2 * s, lineCap: .round))
                Circle().fill(color).frame(width: 3 * s, height: 3 * s).position(x: 17.3 * s, y: 5.7 * s)
            }
        }
    }
}

private struct NotificationsGlyph: View {
    let color: Color
    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 24
            ZStack {
                Circle().fill(color).frame(width: 3.2 * s, height: 3.2 * s).position(x: 12 * s, y: 16 * s)
                Path { p in p.addArc(center: CGPoint(x: 12 * s, y: 17.5 * s), radius: 5 * s, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false) }
                    .stroke(color, style: StrokeStyle(lineWidth: 2.2 * s, lineCap: .round))
                Path { p in p.addArc(center: CGPoint(x: 12 * s, y: 18.3 * s), radius: 9 * s, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false) }
                    .stroke(color.opacity(0.55), style: StrokeStyle(lineWidth: 2.2 * s, lineCap: .round))
            }
        }
    }
}

private struct InboxGlyph: View {
    let color: Color
    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 24
            ZStack {
                Circle().fill(color).frame(width: 4 * s, height: 4 * s).position(x: 7 * s, y: 9 * s)
                Circle().fill(color).frame(width: 4 * s, height: 4 * s).position(x: 17 * s, y: 15 * s)
                Path { p in
                    p.move(to: CGPoint(x: 9 * s, y: 10.5 * s))
                    p.addQuadCurve(to: CGPoint(x: 15 * s, y: 13.5 * s), control: CGPoint(x: 13 * s, y: 12 * s))
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2.2 * s, lineCap: .round))
            }
        }
    }
}

private struct ProfileGlyph: View {
    let color: Color
    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 24
            ZStack {
                Circle().stroke(color, lineWidth: 2.2 * s).frame(width: 6.8 * s, height: 6.8 * s).position(x: 12 * s, y: 8.5 * s)
                Path { p in
                    p.move(to: CGPoint(x: 5.5 * s, y: 19 * s))
                    p.addCurve(to: CGPoint(x: 18.5 * s, y: 19 * s), control1: CGPoint(x: 6.7 * s, y: 15.4 * s), control2: CGPoint(x: 15.3 * s, y: 15.4 * s))
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2.2 * s, lineCap: .round))
            }
        }
    }
}
