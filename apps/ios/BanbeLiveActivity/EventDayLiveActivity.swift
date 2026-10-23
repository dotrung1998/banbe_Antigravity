import ActivityKit
import SwiftUI
import WidgetKit

/// L7 day-of card (docs/impl/phase3-extras.md; switch `live_activity`): the widget extension that draws the
/// event-day Live Activity the app starts locally (BanbeApp/State/LiveActivityController.swift). Data:
/// BanbeApp/Lib/EventDayAttributes.swift, compiled into both targets. Name, start time in the venue's zone, venue and
/// ticket code only: no countdown timers, no urgency text.
@main
struct BanbeLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        EventDayLiveActivity()
    }
}

/// banbe's paper/ink/clay, fixed here because the extension can't read the app's theme.
private enum Tone {
    static let paper = Color(red: 0.976, green: 0.965, blue: 0.945)
    static let ink = Color(red: 0.106, green: 0.098, blue: 0.086)
    static let clay = Color(red: 0.722, green: 0.420, blue: 0.290)
}

struct EventDayLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EventDayAttributes.self) { context in
            EventDayLockScreenView(attributes: context.attributes, phase: context.state.phase)
                .activityBackgroundTint(Tone.paper)
                .activitySystemActionForegroundColor(Tone.ink)
                .widgetURL(context.attributes.ticketURL)
        } dynamicIsland: { context in
            let a = context.attributes
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "ticket.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Tone.clay)
                        .accessibilityHidden(true)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(a.timeText)
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(a.eventName)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.statusText(context.state.phase))
                            .font(.system(size: 13))
                        if !a.venue.isEmpty {
                            Label(a.venue, systemImage: "mappin.and.ellipse")
                                .font(.system(size: 13))
                                .lineLimit(1)
                                .opacity(0.8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "ticket.fill")
                    .foregroundStyle(Tone.clay)
                    .accessibilityLabel(a.eventName)
            } compactTrailing: {
                Text(a.timeText)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "ticket.fill")
                    .foregroundStyle(Tone.clay)
                    .accessibilityLabel(a.eventName)
            }
            .widgetURL(a.ticketURL)
        }
    }
}

/// Lock Screen / banner: the event name, one status line with the start time, the venue and the ticket code.
struct EventDayLockScreenView: View {
    let attributes: EventDayAttributes
    let phase: EventDayAttributes.Phase

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "ticket.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Tone.clay)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(attributes.eventName)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(2)
                Text(attributes.statusText(phase))
                    .font(.system(size: 14))
                if !attributes.venue.isEmpty {
                    Label(attributes.venue, systemImage: "mappin.and.ellipse")
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .opacity(0.75)
                }
            }
            Spacer(minLength: 8)
            if !attributes.ticketCode.isEmpty {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(attributes.text("Mã vé", "Ticket"))
                        .font(.system(size: 11, weight: .semibold))
                        .opacity(0.6)
                    Text(attributes.ticketCode)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                }
            }
        }
        .foregroundStyle(Tone.ink)
        .padding(16)
    }
}
