import SwiftUI

// Note 99 (E): every heart toggle by a signed-in user says what it did to the Schedule ("Saved · added to banbe
// Schedule" / "Removed · taken off banbe Schedule") with Undo for a few seconds. Always on (not behind a switch):
// Saved feeds the Schedule now. Web twin: the save toast in BanBeContext.jsx.

struct SaveToast: Identifiable, Equatable {
    let id = UUID()
    let key: String
    let saved: Bool
    /// "T7 22/11 · 16:00 · Event name" (empty when the event is not resolvable).
    let detail: String
    static let duration: Double = 4.5
}

extension AppState {
    func showSaveToast(key: String, saved: Bool) {
        var detail = ""
        if let e = resolvedEvent(for: key) {
            let when = discoveryDateBadge(discoveryStart(for: e), timeZone: e.eventTimeZone)
            detail = [when, e.name].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        let toast = SaveToast(key: key, saved: saved, detail: detail)
        withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .spring(response: 0.34, dampingFraction: 0.86)) {
            saveToast = toast
        }
        let title = saved ? T("Đã lưu, thêm vào Lịch banbe", "Saved, added to banbe Schedule")
                          : T("Đã bỏ lưu, gỡ khỏi Lịch banbe", "Removed, taken off banbe Schedule")
        UIAccessibility.post(notification: .announcement, argument: detail.isEmpty ? title : "\(title). \(detail)")
    }

    /// Undo: flips the same heart back (one more toggle, no new toast). Waits for the first write to settle so the
    /// in-flight guard never swallows it.
    func undoSaveToast(_ id: UUID) {
        guard let toast = saveToast, toast.id == id else { return }
        withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .easeOut(duration: 0.2)) { saveToast = nil }
        Task { @MainActor in
            for _ in 0..<30 where favoriteToggleInFlight.contains(toast.key) {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            // Only if the heart still shows what the toast announced.
            guard favorites.contains(toast.key) == toast.saved else { return }
            toggleFavorite(toast.key, showsToast: false)
            UIAccessibility.post(notification: .announcement, argument: T("Đã hoàn tác", "Undone"))
        }
    }

    func expireSaveToast(_ id: UUID) {
        guard saveToast?.id == id else { return }
        withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .easeOut(duration: 0.2)) { saveToast = nil }
    }
}

/// The bottom toast itself (RootView, above the dock).
struct SaveToastView: View {
    let toast: SaveToast
    @EnvironmentObject private var app: AppState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.saved ? "heart.fill" : "heart.slash")
                .font(.app(size: 15, weight: .semibold))
                .foregroundStyle(toast.saved ? app.palette.clay : app.palette.ink2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.saved ? app.T("Đã lưu · thêm vào Lịch banbe", "Saved · added to banbe Schedule")
                                 : app.T("Đã bỏ lưu · gỡ khỏi Lịch banbe", "Removed · taken off banbe Schedule"))
                    .font(.app(.subheadline).weight(.semibold))
                    .lineLimit(2)
                if !toast.detail.isEmpty {
                    Text(toast.detail).font(.app(size: 12.5)).foregroundStyle(app.palette.ink2).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button { app.undoSaveToast(toast.id) } label: {
                Text(app.T("Hoàn tác", "Undo"))
                    .font(.app(.subheadline).weight(.bold))
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("saveToast.undo")
        }
        .foregroundStyle(app.palette.ink)
        .padding(.leading, 16).padding(.trailing, 6).padding(.vertical, 8)
        .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(app.palette.rule, lineWidth: 1))
        .shadow(color: .black.opacity(0.16), radius: 16, y: 6)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("saveToast")
        .task(id: toast.id) {
            try? await Task.sleep(nanoseconds: UInt64(SaveToast.duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            app.expireSaveToast(toast.id)
        }
    }
}
