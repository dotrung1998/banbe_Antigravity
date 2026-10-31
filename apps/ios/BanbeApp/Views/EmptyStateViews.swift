import SwiftUI

// Note 48 — motivating empty states. Instead of a bare "nothing here" line,
// a small scene built from the app's own keychain charm art
// (Resources/Keychains, note 35) gently sways on a soft backdrop, followed by
// a warm line and ONE clear next step.

/// Which little scene to show.
enum CharmScene {
    /// Home feed empty: bear + ticket + star — "let's find a plan".
    case findPlans
    /// My schedule empty: cat + coffee + moon — "your day is free".
    case freeDay
    /// Discover empty: compass + plane + cloud — "look a little further".
    case explore

    var charms: [String] {
        switch self {
        case .findPlans: return ["trip-ticket", "pals-bear", "sky-star"]
        case .freeDay: return ["cafe-cup", "pals-cat", "sky-moon"]
        case .explore: return ["sky-cloud", "trip-compass", "trip-plane"]
        }
    }
}

/// Bundled charm PNG by file name (subfolder first, then flattened bundle).
private enum CharmArt {
    private static let cache = NSCache<NSString, UIImage>()
    static func image(_ name: String) -> UIImage? {
        if let hit = cache.object(forKey: name as NSString) { return hit }
        let b = Bundle.main
        guard let url = b.url(forResource: name, withExtension: "png", subdirectory: "Keychains")
                ?? b.url(forResource: name, withExtension: "png"),
              let img = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(img, forKey: name as NSString)
        return img
    }
}

/// Three charms hanging from a little rail, the middle one larger, each
/// swaying on its own rhythm (still under Reduce Motion).
struct CharmSceneView: View {
    let scene: CharmScene
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var swing = false

    var body: some View {
        ZStack(alignment: .top) {
            // Soft blob backdrop.
            Ellipse()
                .fill(RadialGradient(colors: [app.palette.ink.opacity(0.07), app.palette.ink.opacity(0.0)],
                                     center: .center, startRadius: 2, endRadius: 85))
                .frame(width: 200, height: 70)
                .offset(y: 118)
            // The rail the charms hang from.
            Capsule()
                .fill(app.palette.ink.opacity(0.18))
                .frame(width: 150, height: 4)
            HStack(alignment: .top, spacing: 6) {
                charm(scene.charms[0], width: 58, angle: 7, delay: 0.0)
                charm(scene.charms[1], width: 84, angle: 4, delay: 0.35)
                charm(scene.charms[2], width: 58, angle: 8, delay: 0.7)
            }
            .padding(.top, -6)
        }
        .frame(height: 170)
        .accessibilityHidden(true)
        .onAppear { if !reduceMotion { swing = true } }
    }

    @ViewBuilder
    private func charm(_ name: String, width: CGFloat, angle: Double, delay: Double) -> some View {
        if let ui = CharmArt.image(name) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFit()
                .frame(width: width)
                .rotationEffect(.degrees(swing ? angle : -angle), anchor: .top)
                .animation(reduceMotion ? nil
                           : .easeInOut(duration: 1.6 + delay).repeatForever(autoreverses: true).delay(delay),
                           value: swing)
        }
    }
}

/// Illustration + headline + message + one primary action (+ optional link).
struct MotivatingEmptyState: View {
    let scene: CharmScene
    let title: String
    let message: String
    let actionTitle: String
    var actionIcon: String = "sparkles"
    var actionID: String? = nil
    let action: () -> Void
    var secondaryTitle: String? = nil
    var secondaryID: String? = nil
    var secondaryAction: (() -> Void)? = nil
    var identifier: String? = nil

    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(spacing: 12) {
            CharmSceneView(scene: scene)
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(app.palette.ink.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifier ?? "")
            Button(action: action) {
                Label(actionTitle, systemImage: actionIcon)
                    .font(.headline)
                    .padding(.horizontal, 22)
                    .frame(minHeight: 48)
                    .foregroundStyle(app.palette.paper)
                    .background(app.palette.ink, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            .accessibilityIdentifier(actionID ?? "")
            if let secondaryTitle, let secondaryAction {
                Button(action: secondaryAction) {
                    Text(secondaryTitle)
                        .font(.subheadline.weight(.semibold))
                        .underline()
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(secondaryID ?? "")
            }
        }
        .foregroundStyle(app.palette.ink)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}

/// Calm Pass guided empty state for ONE section (not a whole screen): a dashed outline, so it can never be mistaken
/// for real content, one bold line, one sentence and one action. The action is passed in (a Button or a ShareLink);
/// wrap its label in `InlineEmptyState.actionLabel` so every action looks the same. Web twin:
/// src/components/ui/InlineEmpty.jsx.
struct InlineEmptyState<Action: View>: View {
    let title: String
    let message: String
    var identifier: String? = nil
    @ViewBuilder let action: () -> Action

    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(.footnote)
                .foregroundStyle(app.palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
            action().padding(.top, 8)
        }
        .foregroundStyle(app.palette.ink)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: BanbeTheme.Radius.card, style: .continuous)
            .strokeBorder(app.palette.ink.opacity(0.3), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
            .accessibilityHidden(true))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier ?? "")
    }

    /// The shared look of the one action: a `block` capsule, 44pt tall, ink text.
    static func actionLabel(_ title: String, systemImage: String, palette: Palette) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .foregroundStyle(palette.ink)
            .background(palette.block, in: Capsule())
            .contentShape(Capsule())
    }
}
