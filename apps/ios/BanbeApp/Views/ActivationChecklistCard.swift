import SwiftUI

/// Home's small "get started" card after personalization. Dismissible. Once
/// every item is done it celebrates once ("You're all set!" + confetti +
/// haptic), then folds away. Face ID is offered HERE, in context, rather
/// than during onboarding — still the same device-local setting as
/// Account > Security.
struct ActivationChecklistCard: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var auth: AuthViewModel
    @State private var faceIDMessage = ""
    @State private var faceIDBusy = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var biometricsAvailable: Bool { BiometricAuthService.cachedAvailability.available }
    private var items: [ActivationChecklistItem] { ActivationChecklist.items(biometricsAvailable: biometricsAvailable) }
    private var biometryName: String { BiometricAuthService.cachedAvailability.type == .touchID ? "Touch ID" : "Face ID" }

    private func done(_ item: ActivationChecklistItem) -> Bool {
        ActivationChecklist.isDone(item, state: app.activation, hasSavedEvent: !app.favorites.isEmpty,
                                   faceIDEnabled: auth.faceIDEnabled)
    }

    var body: some View {
        // Cheap exit first: for almost everyone the checklist is off or dismissed, and this body
        // re-runs every second with Home — it must cost nothing then.
        if app.activation.enabled && !app.activation.dismissed,
           ActivationChecklist.isVisible(state: app.activation, items: items,
                                         hasSavedEvent: !app.favorites.isEmpty, faceIDEnabled: auth.faceIDEnabled) {
            let doneCount = items.filter(done).count
            let allDone = doneCount == items.count
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(allDone ? app.T("Bạn đã sẵn sàng! 🎉", "You're all set! 🎉")
                                 : app.T("Bắt đầu với banbe", "Get started with banbe"))
                        .font(.system(.headline, design: .rounded))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("activation.card")
                    Spacer()
                    Text("\(doneCount)/\(items.count)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(app.palette.ink.opacity(0.65))
                        .accessibilityLabel(app.T("Đã xong \(doneCount) trên \(items.count)",
                                                  "\(doneCount) of \(items.count) done"))
                    Button { app.dismissActivationChecklist() } label: {
                        Image(systemName: "xmark").font(.footnote.weight(.semibold))
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(app.T("Ẩn danh sách", "Hide checklist"))
                    .accessibilityIdentifier("activation.dismiss")
                }
                ForEach(items, id: \.self) { item in row(item) }
                if !faceIDMessage.isEmpty {
                    Text(faceIDMessage).font(.footnote).foregroundStyle(BanbeTheme.alert)
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.leading, 16).padding(.trailing, 4).padding(.vertical, 6)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(alignment: .top) { if allDone { ConfettiBurst().padding(.top, 28) } }
            .padding(.horizontal, 20).padding(.top, 10)
            .transition(.asymmetric(insertion: .identity, removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))))
            // Keyed on allDone so it fires once the last item is ticked, whether
            // that happened here (Face ID) or elsewhere (saved on Event Detail).
            .task(id: allDone) {
                guard allDone else { return }
                Haptics.success()
                try? await Task.sleep(nanoseconds: 2_400_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeInOut(duration: 0.35)) {
                    app.markActivationCelebrated()
                }
            }
        }
    }

    private func row(_ item: ActivationChecklistItem) -> some View {
        let isDone = done(item)
        return HStack(spacing: 10) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.body)
                .accessibilityHidden(true)
            Text(title(item))
                .font(.subheadline)
                .strikethrough(isDone, color: app.palette.ink.opacity(0.4))
                .opacity(isDone ? 0.6 : 1)
                .accessibilityValue(isDone ? app.T("Đã xong", "Done") : app.T("Chưa xong", "Not done"))
                .accessibilityIdentifier("activation.\(item.rawValue)")
            Spacer(minLength: 8)
            if item == .faceID && !isDone {
                Button(faceIDBusy ? app.T("Đang bật…", "Turning on…") : app.T("Bật", "Turn on")) {
                    Task { await enableFaceID() }
                }
                .font(.footnote.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .disabled(faceIDBusy)
                .accessibilityIdentifier("activation.faceID")
            }
        }
        .padding(.trailing, 12)
        .frame(minHeight: 36)
    }

    private func title(_ item: ActivationChecklistItem) -> String {
        switch item {
        case .openEvent: return app.T("Mở một sự kiện hợp với bạn", "Open an event that fits you")
        case .saveEvent: return app.T("Lưu một sự kiện bạn thích", "Save an event you like")
        case .faceID: return app.T("Mở khoá nhanh bằng \(biometryName)", "Unlock quickly with \(biometryName)")
        }
    }

    private func enableFaceID() async {
        faceIDBusy = true
        defer { faceIDBusy = false }
        faceIDMessage = ""
        Analytics.track(.permissionPrompted(permission: "faceID"))
        let ok = await auth.setFaceIDEnabled(true, reason: app.T("Xác nhận để bật khoá \(biometryName) cho banbe.",
                                                                 "Confirm to turn on \(biometryName) for banbe."))
        Analytics.track(.permissionResult(permission: "faceID", result: ok ? "granted" : "denied"))
        if ok {
            Haptics.success()
        } else {
            faceIDMessage = app.T("Chưa bật được \(biometryName). Bạn có thể bật sau trong Tài khoản > Bảo mật.",
                                  "Couldn't turn on \(biometryName). You can enable it later in Account > Security.")
        }
    }
}
