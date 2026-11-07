import EventKit
import EventKitUI
import SwiftUI

// "Add to Apple Calendar" — ONE event, exported through the system event
// editor (EKEventEditViewController). Since iOS 17 the editor runs out of
// process and saves on the person's behalf, so banbe requests NO calendar
// access (neither full nor write-only) and never writes silently: the person
// reviews, picks a calendar, edits, saves or cancels in system UI.
// This is an export, not sync. Note 44.

/// Everything the editor is pre-filled with — pure, unit-tested.
struct CalendarEventDraft: Equatable {
    let title: String
    let start: Date
    let end: Date
    let location: String?
    let url: URL?
    let notes: String
    /// True when banbe had no end time and used the default duration.
    let endIsEstimated: Bool
}

enum CalendarExport {
    /// Events carry no end time (note 38); the editor shows this default and
    /// the note tells the person to adjust it. Same 2h the existing export used.
    static let defaultDuration: TimeInterval = 2 * 3600

    enum Result: String, Equatable {
        case saved, cancelled, deleted, unavailable
    }

    static func draft(title: String, start: Date?, end: Date?, location: String, eventKey: String,
                      origin: String, T: (String, String) -> String) -> CalendarEventDraft? {
        guard let start else { return nil }
        let realEnd = end.flatMap { $0 > start ? $0 : nil }
        let link = eventKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            .flatMap { URL(string: "\(origin)/api/photo-share?eid=\($0)") }
        var notes = [T("Sự kiện trên banbe.", "A banbe event.")]
        if realEnd == nil {
            notes.append(T("Host chưa ghi giờ kết thúc. banbe tạm đặt 2 giờ, bạn có thể sửa.",
                           "The host didn't list an end time. banbe filled in 2 hours, edit it if needed."))
        }
        if let link { notes.append(link.absoluteString) }
        let loc = location.trimmingCharacters(in: .whitespacesAndNewlines)
        return CalendarEventDraft(title: title, start: start, end: realEnd ?? start.addingTimeInterval(defaultDuration),
                                  location: loc.isEmpty ? nil : loc, url: link, notes: notes.joined(separator: "\n"),
                                  endIsEstimated: realEnd == nil)
    }

    static func result(for action: EKEventEditViewAction) -> Result {
        switch action {
        case .saved: return .saved
        case .deleted: return .deleted
        default: return .cancelled
        }
    }
}

/// Item for `.sheet(item:)`.
struct CalendarExportRequest: Identifiable {
    let id = UUID()
    let draft: CalendarEventDraft
}

/// SwiftUI wrapper around the pre-filled system editor. No access request.
struct SystemEventEditor: UIViewControllerRepresentable {
    let draft: CalendarEventDraft
    let onFinish: (CalendarExport.Result) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = draft.title
        event.startDate = draft.start
        event.endDate = draft.end
        event.location = draft.location
        event.url = draft.url
        event.notes = draft.notes
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onFinish: (CalendarExport.Result) -> Void
        private var finished = false
        init(onFinish: @escaping (CalendarExport.Result) -> Void) { self.onFinish = onFinish }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            guard !finished else { return }
            finished = true
            onFinish(CalendarExport.result(for: action))
        }
    }
}
