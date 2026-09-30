import SwiftUI
import PhotosUI
import UIKit

/// Port of src/screens/Splash.jsx — the logomotion animation and the
/// tagline; tapping (or waiting) moves on to the language picker.
///
/// Completion-gating fix (2026-09-30) — the AUTOMATIC advance (and,
/// through it, the FaceID lock prompt/login/home destination
/// `dismissSplash` routes to) now waits for BOTH the logomotion animation
/// to report one real completed cycle (`animationComplete`, via
/// `LogomotionView`'s new `onComplete`) AND session/bootstrap readiness
/// (`auth.sessionChecked` — see that property's own doc comment for the
/// real race this closes). A bounded fallback timer (`fallbackFired`)
/// covers a WebView load failure/missing asset so a broken animation can
/// never hang the splash forever — it proceeds exactly as if completion
/// had fired normally. Reduce Motion skips waiting on the animation
/// signal entirely (the html/js itself also skips playing it — see
/// `logomotion2309.html`'s `prefersReducedMotion()` — this is belt-and-
/// suspenders for the native side of the same rule).
/// Tap-to-dismiss is deliberately NOT gated on any of this — it's an
/// explicit user action, and this app's existing product behavior already
/// lets an impatient tap skip the whole splash instantly; only the
/// unattended/automatic path and whatever it gates (FaceID, in
/// `RootView.swift`) must wait for real completion.
/// Cold-launch only by construction, not something this fix needs to
/// re-derive: `AppState.init()` sets `screen = .splash` exactly once, at
/// app launch, and nothing else ever re-assigns `.splash` — returning from
/// background never remounts this view or replays the animation.
///
/// 1.0s completed-motion dwell (2026-09-30, second pass) — on the NORMAL
/// (non-Reduce-Motion) path only, once the real `animationComplete` signal
/// fires, a single cancellable `Task.sleep` dwell timer starts at that
/// exact moment (not view mount, not session readiness). The animation's
/// own completed final frame is already held on screen by the prior fix
/// (the JS ticker removes itself), so nothing else is needed to avoid a
/// blank screen during the dwell. Automatic advance then requires the
/// dwell AND session readiness both — whichever finishes later gates the
/// transition (`readyToAdvance` below composes them with `&&`, same as it
/// already composed `sessionChecked`). The bounded `fallbackFired` path
/// (broken WebView/iframe load) intentionally skips the dwell — it is not
/// a real completion, waiting an extra second on top of an already-broken
/// load serves nobody. Reduce Motion skips the dwell entirely, matching
/// its existing "complete immediately" behavior; the dwell Task is never
/// started for that path even though the shared HTML/JS may still fire
/// `animationComplete` immediately under Reduce Motion too (belt-and-
/// suspenders, same reasoning as the native `reduceMotion` OR below).
struct SplashView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var auth: AuthViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var animationComplete = false
    @State private var fallbackFired = false
    @State private var dismissed = false
    @State private var dwellElapsed = false
    @State private var dwellTask: Task<Void, Never>? = nil

    private static let logomotionAspect: CGFloat = 800.0 / 1288.0
    // A few seconds past the real ~ (totalFrames / 24fps) authored
    // duration (a handful of seconds at 24fps per `lib.properties.fps` /
    // `exportRoot.totalFrames`, logomotion2309.js) — long enough that a
    // healthy load/play never hits it, short enough that a genuinely
    // broken WebView load doesn't strand the user on the splash screen.
    private static let fallbackTimeout: UInt64 = 6_000_000_000
    // Hold the completed launch motion on screen for one extra second
    // before advancing, normal (non-Reduce-Motion) path only.
    private static let dwellDuration: UInt64 = 1_000_000_000

    /// Both real signals this screen waits on for the AUTOMATIC path.
    /// Reduce Motion and the bounded fallback both count as "ready"
    /// immediately (no dwell); real completion additionally needs the
    /// 1s dwell to have elapsed. Session bootstrap readiness always gates
    /// on top, same as before this pass.
    private var readyToAdvance: Bool {
        let motionReady = reduceMotion || fallbackFired || dwellElapsed
        return motionReady && auth.sessionChecked
    }

    var body: some View {
        ZStack {
            app.palette.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                LogomotionView(onComplete: { animationComplete = true })
                    .frame(width: 280, height: 280 * Self.logomotionAspect)
                Text("bạn mới mỗi tuần")
                    .font(.system(size: 14))
                    .foregroundStyle(app.palette.ink)
                    .padding(.top, 16)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { advance(force: true) }
        .onChange(of: animationComplete) { _, newValue in
            if newValue && !reduceMotion { startDwellTimer() }
            advance(force: false)
        }
        .onChange(of: auth.sessionChecked) { _, _ in advance(force: false) }
        .task {
            try? await Task.sleep(nanoseconds: Self.fallbackTimeout)
            fallbackFired = true
            advance(force: false)
        }
        .onDisappear { dwellTask?.cancel() }
    }

    /// Starts the single named 1.0s dwell timer, cancelling any prior one
    /// first (defensive — `animationComplete` only ever flips false->true
    /// once per `LogomotionView`'s own guarded bridge, but this keeps the
    /// invariant explicit rather than assumed).
    private func startDwellTimer() {
        dwellTask?.cancel()
        dwellTask = Task {
            try? await Task.sleep(nanoseconds: Self.dwellDuration)
            guard !Task.isCancelled else { return }
            dwellElapsed = true
            advance(force: false)
        }
    }

    /// `force: true` is the explicit-tap path (always dismisses, no
    /// gating — unchanged relationship to the completion/dwell gate). It
    /// also cancels an in-flight dwell timer since the screen is going
    /// away. `force: false` is every automatic call site — only actually
    /// advances once `readyToAdvance` is true; harmless to call
    /// speculatively (from either `onChange`) before that.
    private func advance(force: Bool) {
        guard app.screen == .splash, !dismissed else { return }
        guard force || readyToAdvance else { return }
        dismissed = true
        dwellTask?.cancel()
        app.dismissSplash(isSignedIn: auth.isSignedIn)
    }
}

/// Port of src/screens/LangPick.jsx.
struct LangPickView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                // Same mark, at the same 44pt, as src/screens/LangPick.jsx.
                BanbeLogo(kind: .mark, width: 44, height: 44)
                    .padding(.bottom, 26)

                Text("Chọn ngôn ngữ")
                    .font(BanbeTheme.display(27))
                Text("Choose your language")
                    .font(.system(size: 19))
                    .opacity(0.52)
                    .padding(.top, 5)

                VStack(spacing: 10) {
                    choice(title: "Tiếng Việt", subtitle: "Mặc định", active: app.lang == "vi") {
                        app.pickLang("vi")
                    }
                    .accessibilityIdentifier("lang.vi")
                    choice(title: "English", subtitle: "Switch anytime", active: app.lang == "en") {
                        app.pickLang("en")
                    }
                    .accessibilityIdentifier("lang.en")
                }
                .padding(.top, 28)
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 30)
            .padding(.top, 80)
        }
    }

    private func choice(title: String, subtitle: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(BanbeTheme.display(19))
                    Text(subtitle).font(.system(size: 11.5))
                }
                Spacer()
                Text("›").font(.system(size: 15))
            }
            .foregroundStyle(app.palette.ink)
            .padding(18)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(active ? app.palette.ink : app.palette.rule, lineWidth: active ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }
}

/// Port of src/screens/ThemePick.jsx — the light/dark choice, previewed
/// live, then "Continue" into the feed.
struct ThemePickView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var auth: AuthViewModel

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                Text(app.T("Hiển thị", "Appearance")).font(.system(size: 11.5))
                Text(app.T("Bạn thích nền sáng hay tối?", "Light or dark?"))
                    .font(BanbeTheme.display(27))
                    .padding(.top, 8)
                Text(app.T("Bạn có thể đổi lại bất cứ lúc nào trong Tài khoản.",
                           "You can change this anytime in your account."))
                    .font(.system(size: 13.5))
                    .padding(.top, 10)

                VStack(spacing: 10) {
                    choice(title: app.T("Sáng", "Light"), subtitle: app.T("Nền giấy ấm", "Warm paper"),
                           active: app.theme == "light") { app.pickTheme("light") }
                        .accessibilityIdentifier("theme.light")
                    choice(title: app.T("Tối", "Dark"), subtitle: app.T("Nền mực dịu mắt", "Soft ink background"),
                           active: app.theme == "dark") { app.pickTheme("dark") }
                        .accessibilityIdentifier("theme.dark")
                }
                .padding(.top, 28)

                InkButton(title: app.T("Tiếp tục", "Continue")) { app.finishOnboarding(isSignedIn: auth.isSignedIn) }
                    .accessibilityIdentifier("onboarding.continue")
                    .padding(.top, 26)
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 30)
            .padding(.top, 80)
        }
    }

    private func choice(title: String, subtitle: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(BanbeTheme.display(19))
                    Text(subtitle).font(.system(size: 11.5))
                }
                Spacer()
                Text(active ? "✓" : "›").font(.system(size: 15))
            }
            .foregroundStyle(app.palette.ink)
            .padding(18)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(active ? app.palette.ink : app.palette.rule, lineWidth: active ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }
}

/// Port of src/screens/CreateEvent.jsx — the organizer profile fields, the
/// event fields, category pickers and the submit that calls
/// create_event_draft.
/// A single staged gallery tile — either one of the event's ALREADY-
/// uploaded `event_photos` rows (when editing an owned event) or a
/// freshly-picked local image, unified so remove/reorder/cover-pick work
/// the same way on both (mirrors web's CreateEvent.jsx `items` list).
private struct StagedGalleryItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case existing(photoID: UUID, storagePath: String)
        case new(image: UIImage)
        static func == (a: Kind, b: Kind) -> Bool {
            switch (a, b) {
            case (.existing(let x, _), .existing(let y, _)): return x == y
            case (.new(let x), .new(let y)): return x === y
            default: return false
            }
        }
    }
    let id: String
    var kind: Kind
    var url: URL? // only for .existing, resolved once at seed time

    var image: UIImage? { if case .new(let img) = kind { return img }; return nil }
}

/// Port of src/screens/CreateEvent.jsx — the organizer profile fields, the
/// event fields, category pickers and the submit that calls
/// create_event_draft.
struct CreateEventView: View {
    @EnvironmentObject var app: AppState

    private let categories: [(key: String, vi: String, en: String)] = [
        ("supper", "Supper club", "Supper club"),
        ("fashion", "Thời trang", "Fashion"),
        ("gallery", "Phòng tranh", "Gallery"),
        ("music", "Nhạc", "Music"),
        ("popup", "Pop-up", "Pop-up"),
    ]
    private let maxPhotos = 8
    private let minPhotos = 3

    @State private var galleryItems: [StagedGalleryItem] = []
    @State private var coverItemID: String?
    @State private var pickerItems: [PhotosPickerItem] = []
    /// Address-autocomplete fix pass (2026-09-28) — debounce for the
    /// location search box, same 500ms/4-char-minimum convention web's
    /// own `createLocType` (GocContext.jsx) uses. Cancelling the previous
    /// `Task` on every keystroke is this view's equivalent of web's
    /// `clearTimeout` — `Task.sleep` throws `CancellationError` when
    /// cancelled, which the `try?` below simply treats as "never fired."
    @State private var createAddressSearchTask: Task<Void, Never>?
    @State private var photoError = ""
    @State private var seededForEventID: String?
    @State private var seededExistingIDs: Set<UUID> = []
    @State private var dateTimeSheetOpen = false
    // "Review before submitting" step (task 1) — a plain local bool, same
    // reasoning as web's `reviewOpen` (CreateEvent.jsx): every field it
    // shows already lives in `app.create*`/this view's own `galleryItems`/
    // `coverItemID` state, so dismissing it loses nothing.
    @State private var reviewOpen = false
    // TASK 3 (event creation validation pass) — the post-submission
    // chooser; opened only by a real submitCreateEvent() success (see the
    // review sheet's own onConfirm above), never merely because the
    // request finished. `successChoiceMade` distinguishes an explicit
    // button tap from a swipe-to-dismiss/backdrop-tap on the native
    // `.confirmationDialog` — both must land on the SAME "unambiguous
    // success" default (pending events) per this ticket's own instruction.
    @State private var successChooserOpen = false
    @State private var successChoiceMade = false

    private var removedExistingIDs: [UUID] {
        let kept = Set(galleryItems.compactMap { if case .existing(let id, _) = $0.kind { return id }; return nil })
        return seededExistingIDs.filter { !kept.contains($0) }
    }
    private var newImagesInOrder: [UIImage] { galleryItems.compactMap(\.image) }
    private var coverNewIndex: Int? {
        guard let coverItemID, let item = galleryItems.first(where: { $0.id == coverItemID }),
              case .new(let image) = item.kind else { return nil }
        return newImagesInOrder.firstIndex(where: { $0 === image })
    }
    private var existingCoverPath: String? {
        guard let coverItemID, let item = galleryItems.first(where: { $0.id == coverItemID }),
              case .existing(_, let path) = item.kind else { return nil }
        return path
    }

    // TASK 3 (event creation validation pass) — these five are genuinely
    // required (not decorative asterisks): each blocks the "Xem lại"/
    // "Review" button below via `enabled:`, mirroring the SAME "hint text
    // always visible while invalid" convention this screen's own
    // `!app.createLocConfirmed` hint already uses (not a tap-triggered
    // banner — `InkButton(enabled: false)` is a real disabled button, a
    // tap on it does nothing to react to). `galleryItems` already excludes
    // removed items (removeGalleryItem splices them out) and only ever
    // holds locally-staged/already-uploaded ones — nothing "failed/
    // in-progress" to separately exclude before a real upload attempt.
    private var descValid: Bool { !app.createDesc.trimmingCharacters(in: .whitespaces).isEmpty }
    private var dateTimeValid: Bool { app.createEventDate != nil && app.createEventTime != nil }
    private var seatsValid: Bool { Int(app.createSeats) ?? 0 > 0 }
    private var catsValid: Bool { !app.createCats.isEmpty }
    private var includedValid: Bool { app.createIncludedItems.contains { !$0.label.trimmingCharacters(in: .whitespaces).isEmpty } }
    private var photosValid: Bool { galleryItems.count >= minPhotos && galleryItems.count <= maxPhotos }
    private var hasCreateFieldErrors: Bool { !descValid || !dateTimeValid || !seatsValid || !catsValid || !includedValid || !photosValid }

    private func seedGalleryIfNeeded() {
        guard let editID = app.createEditEventId else {
            if seededForEventID != nil { galleryItems = []; coverItemID = nil; seededExistingIDs = [] }
            seededForEventID = nil
            return
        }
        guard seededForEventID != editID, !app.eventPhotosLoading else { return }
        seededForEventID = editID
        let cover = app.myOrgEventSummaries.first(where: { $0.id == editID })?.coverImage
        let seeded: [StagedGalleryItem] = app.eventPhotos.map { photo in
            let relative = photo.storagePath.hasPrefix("event-photos/")
                ? String(photo.storagePath.dropFirst("event-photos/".count)) : photo.storagePath
            let url = try? SupabaseService.client.storage.from("event-photos").getPublicURL(path: relative)
            return StagedGalleryItem(id: photo.id.uuidString, kind: .existing(photoID: photo.id, storagePath: photo.storagePath), url: url)
        }
        galleryItems = seeded
        seededExistingIDs = Set(app.eventPhotos.map(\.id))
        let coverItem = seeded.first { if case .existing(_, let path) = $0.kind { return path == cover }; return false }
        coverItemID = (coverItem ?? seeded.first)?.id
    }

    private func removeGalleryItem(_ item: StagedGalleryItem) {
        galleryItems.removeAll { $0.id == item.id }
        if coverItemID == item.id { coverItemID = galleryItems.first?.id }
    }

    /// Photo-management cleanup (task 1, screenshot 1 follow-up) — a clean
    /// vertical list, one row per photo, replacing the old 4-column
    /// `LazyVGrid` where remove/cover controls were tiny overlapping
    /// buttons stacked on the thumbnail itself (matches web's identical
    /// redesign, CreateEvent.jsx). Same underlying actions as before
    /// (remove, set-cover, and now up/down reorder using the SAME array-
    /// swap `galleryItems` already supported nothing new is invented here)
    /// — just laid out so nothing overlaps the photo or another control.
    @ViewBuilder
    private func gallerySection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 4) {
                    Text(app.T("Hình ảnh", "Photos")).font(.system(size: 11.5))
                    Text("*").font(.system(size: 11.5)).foregroundStyle(BanbeTheme.alert)
                }
                Spacer()
                Text("\(galleryItems.count)/\(maxPhotos) (\(app.T("tối thiểu \(minPhotos)", "min \(minPhotos)")))").font(.system(size: 10.5))
            }
            VStack(spacing: 8) {
                ForEach(Array(galleryItems.enumerated()), id: \.element.id) { index, item in
                    let isCover = item.id == coverItemID
                    HStack(spacing: 10) {
                        Group {
                            if let image = item.image {
                                Image(uiImage: image).resizable().scaledToFill()
                            } else {
                                AsyncImage(url: item.url) { $0.resizable().scaledToFill() } placeholder: { app.palette.field }
                            }
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(alignment: .bottom) {
                            if isCover {
                                Text(app.T("Ảnh bìa", "Cover"))
                                    .font(.system(size: 8.5, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 2)
                                    .background(app.palette.ink)
                                    .foregroundStyle(app.palette.paper)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(app.T("Ảnh \(index + 1)", "Photo \(index + 1)"))
                                .font(.system(size: 11.5)).opacity(0.65)
                            Button { coverItemID = item.id } label: {
                                Text(isCover ? app.T("Đang là ảnh bìa", "Currently the cover") : app.T("Đặt làm ảnh bìa", "Set as cover"))
                                    .font(.system(size: 11, weight: .semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(isCover ? app.palette.ink : .clear, in: Capsule())
                                    .overlay(Capsule().stroke(isCover ? .clear : app.palette.rule, lineWidth: 1))
                                    .foregroundStyle(isCover ? app.palette.paper : app.palette.ink)
                            }
                            .buttonStyle(.plain)
                            .disabled(isCover)
                        }
                        Spacer(minLength: 0)

                        VStack(spacing: 4) {
                            Button {
                                guard index > 0 else { return }
                                galleryItems.swapAt(index - 1, index)
                            } label: {
                                Image(systemName: "chevron.up").font(.system(size: 11, weight: .semibold))
                                    .frame(width: 26, height: 26)
                                    .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(app.palette.rule))
                            }
                            .buttonStyle(.plain)
                            .opacity(index == 0 ? 0.3 : 1)
                            .disabled(index == 0)

                            Button {
                                guard index < galleryItems.count - 1 else { return }
                                galleryItems.swapAt(index, index + 1)
                            } label: {
                                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                                    .frame(width: 26, height: 26)
                                    .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(app.palette.rule))
                            }
                            .buttonStyle(.plain)
                            .opacity(index == galleryItems.count - 1 ? 0.3 : 1)
                            .disabled(index == galleryItems.count - 1)
                        }
                        .foregroundStyle(app.palette.ink)

                        Button { removeGalleryItem(item) } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(BanbeTheme.alert)
                                .frame(width: 26, height: 26)
                                .background(BanbeTheme.alert.opacity(0.08), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                if galleryItems.count < maxPhotos {
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: maxPhotos - galleryItems.count, matching: .images) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                            Text(app.T("Thêm ảnh", "Add photo")).font(.system(size: 12.5, weight: .semibold))
                        }
                        .foregroundStyle(app.palette.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(app.palette.ink, style: StrokeStyle(lineWidth: 1, dash: [4])))
                    }
                }
            }
            if !photoError.isEmpty {
                Text(photoError).font(.system(size: 11.5)).foregroundStyle(BanbeTheme.alert)
            } else if !photosValid && !app.createSent {
                Text(app.T("Cần tối thiểu \(minPhotos) và tối đa \(maxPhotos) ảnh khả dụng.", "Minimum \(minPhotos), maximum \(maxPhotos) available photos."))
                    .font(.system(size: 11.5)).foregroundStyle(BanbeTheme.alert)
            }
        }
        .padding(.top, 22)
        .onChange(of: pickerItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                var accepted: [StagedGalleryItem] = []
                for pickerItem in newItems {
                    guard let data = try? await pickerItem.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                        await MainActor.run { photoError = app.T("Không thể đọc một trong các ảnh đã chọn.", "Couldn't read one of the selected photos.") }
                        continue
                    }
                    if data.count > 50 * 1024 * 1024 {
                        await MainActor.run { photoError = app.T("Mỗi ảnh tối đa 50MB.", "Each photo must be under 50MB.") }
                        continue
                    }
                    accepted.append(StagedGalleryItem(id: UUID().uuidString, kind: .new(image: image), url: nil))
                }
                await MainActor.run {
                    if !accepted.isEmpty {
                        photoError = ""
                        galleryItems.append(contentsOf: accepted)
                        if coverItemID == nil { coverItemID = galleryItems.first?.id }
                    }
                    pickerItems = []
                }
            }
        }
    }

    @ViewBuilder
    private func introEditor() -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(app.T("Giới thiệu sự kiện", "Event introduction")).font(.system(size: 11.5))
                Spacer()
                Text("\(app.createIntro.count)/4000").font(.system(size: 10.5))
            }
            Text(app.T("Một đoạn giới thiệu dài hơn, hấp dẫn. Tách dòng trống giữa các đoạn. Không phải quảng cáo giả, không phải \"Bao gồm\".",
                        "A longer, attractive write-up. Leave a blank line between paragraphs. Not fabricated marketing copy, not the same as \"Included\"."))
                .font(.system(size: 11)).opacity(0.75)
            TextEditor(text: $app.createIntro)
                .font(.system(size: 14))
                .frame(minHeight: 110)
                .padding(8)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onChange(of: app.createIntro) { _, newValue in
                    if newValue.count > 4000 { app.createIntro = String(newValue.prefix(4000)) }
                }
        }
        .foregroundStyle(app.palette.ink)
    }

    // "Bao gồm" item-editing parity fix (2026-09-29) — iOS's CreateEventView
    // previously had no editing UI for this field at all, unlike web's
    // CreateEvent.jsx (`addCreateIncludedItem`/`removeCreateIncludedItem`/
    // `setCreateIncludedItem`) — a real, reported gap: a host filling this
    // in on iOS had nowhere to put it, and the review screen correctly
    // showed nothing because there was genuinely nothing to show. Up to 3
    // items, same as the server-side cap (migration 087).
    @ViewBuilder
    private func includedItemsEditor() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Text(app.T("Bao gồm", "Included")).font(.system(size: 11.5))
                Text("*").font(.system(size: 11.5)).foregroundStyle(BanbeTheme.alert)
            }
            ForEach(Array(app.createIncludedItems.enumerated()), id: \.offset) { index, item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField(
                            app.T("Tên (vd. 5 món)", "Label (e.g. 5 courses)"),
                            text: Binding(
                                get: { item.label },
                                set: { app.setCreateIncludedItemLabel(index, $0) }
                            )
                        )
                        .font(.system(size: 13.5))
                        Button {
                            app.removeCreateIncludedItem(at: index)
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 11)).opacity(0.6)
                        }
                        .buttonStyle(.plain)
                    }
                    TextField(
                        app.T("Mô tả (không bắt buộc)", "Detail (optional)"),
                        text: Binding(
                            get: { item.detail },
                            set: { app.setCreateIncludedItemDetail(index, $0) }
                        )
                    )
                    .font(.system(size: 12.5))
                    .opacity(0.8)
                }
                .padding(10)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if app.createIncludedItems.count < 3 {
                Button { app.addCreateIncludedItem() } label: {
                    Text(app.T("+ Thêm mục", "+ Add item")).font(.system(size: 12.5, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
            if !includedValid && !app.createSent {
                Text(app.T("Hãy thêm ít nhất một mục Bao gồm.", "Please add at least one Included item."))
                    .font(.system(size: 11)).foregroundStyle(BanbeTheme.alert)
            }
        }
        .foregroundStyle(app.palette.ink)
    }

    // Address-autocomplete fix pass (2026-09-28) — replaces the old
    // single-shot "type free text, tap Confirm, get ONE geocode result"
    // flow (mirrors web's identical GocContext.jsx/CreateEvent.jsx
    // change, same pass). Publishing now REQUIRES a real, selected
    // address — there is no more "Skip".
    @ViewBuilder
    private func locationConfirmSection() -> some View {
        if app.createAddressSearching {
            Text(app.T("Đang tìm địa chỉ…", "Searching addresses…"))
                .font(.system(size: 11)).opacity(0.6).foregroundStyle(app.palette.ink)
        }
        if !app.createAddressSearchError.isEmpty {
            HStack(spacing: 8) {
                Text(app.createAddressSearchError).font(.system(size: 11)).foregroundStyle(BanbeTheme.alert)
                Spacer(minLength: 0)
                Button(app.T("Thử lại", "Retry")) { Task { await app.retryCreateAddressSearch() } }
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(app.palette.ink)
            }
        }
        if !app.createAddressSuggestions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(app.createAddressSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                    Button {
                        app.selectCreateAddressSuggestion(suggestion)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.addressLine + (suggestion.isVenue ? " " + app.T("(địa điểm)", "(venue)") : ""))
                                .font(.system(size: 13, weight: .semibold))
                            Text([suggestion.district, suggestion.city, suggestion.postalCode].filter { !$0.isEmpty }.joined(separator: ", "))
                                .font(.system(size: 11.5)).opacity(0.7)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(app.palette.ink)
                    if index < app.createAddressSuggestions.count - 1 {
                        Divider().overlay(app.palette.rule)
                    }
                }
                // Nominatim/MapKit attribution — MKLocalSearch results are
                // Apple's own MapKit data, but this list uses the same
                // visual convention regardless of provider for consistency
                // between platforms.
                Text("© OpenStreetMap contributors")
                    .font(.system(size: 9.5)).opacity(0.45)
                    .padding(.horizontal, 10).padding(.vertical, 6)
            }
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        if app.createLocConfirmed {
            VStack(alignment: .leading, spacing: 6) {
                Text("✓ " + app.createLocLabel).font(.system(size: 11.5)).opacity(0.85)
                Text(app.T("Sẽ hiện ghim trên bản đồ tại toạ độ này.", "Will show a map pin at this exact point."))
                    .font(.system(size: 10.5)).opacity(0.6)
                Button(app.T("Đổi địa chỉ", "Change address")) { app.clearCreateAddressSelection() }
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(app.palette.ink.opacity(0.75))
            }
            .padding(10)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(app.palette.ink)
        } else {
            Text(app.T("Chọn một địa chỉ gợi ý ở trên (cần thiết để đăng sự kiện).", "Pick a suggested address above (required to publish)."))
                .font(.system(size: 11)).opacity(0.6).foregroundStyle(app.palette.ink)
        }
    }

    private static let vnDateLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = AppState.vietnamTimeZone
        f.dateFormat = "dd.MM.yyyy"
        return f
    }()
    private static let vnTimeLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = AppState.vietnamTimeZone
        f.dateFormat = "HH:mm"
        return f
    }()

    @ViewBuilder
    private func dateTimeRow() -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(app.T("Ngày & giờ (giờ Việt Nam)", "Date & time (Vietnam time)")).font(.system(size: 11.5))
                Text("*").font(.system(size: 11.5)).foregroundStyle(BanbeTheme.alert)
            }
            Button {
                dateTimeSheetOpen = true
            } label: {
                HStack {
                    if let date = app.createEventDate, let time = app.createEventTime {
                        Text("\(Self.vnDateLabelFormatter.string(from: date)) ▪︎ \(Self.vnTimeLabelFormatter.string(from: time))")
                    } else {
                        Text(app.T("Chọn ngày & giờ", "Pick date & time")).opacity(0.6)
                    }
                    Spacer()
                    Image(systemName: "calendar")
                }
                .font(.system(size: 14))
                .foregroundStyle(app.palette.ink)
                .padding(13)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            if !dateTimeValid && !app.createSent {
                Text(app.T("Hãy chọn ngày và giờ diễn ra.", "Please pick a date and time."))
                    .font(.system(size: 11)).foregroundStyle(BanbeTheme.alert)
            }
        }
        .sheet(isPresented: $dateTimeSheetOpen) {
            EventDateTimeSheet(date: $app.createEventDate, time: $app.createEventTime)
                .environmentObject(app)
        }
    }

    var body: some View {
        // Swipe-to-back "blank white space" fix (2026-09-29) — this used
        // to present CreateEventReviewSheet via `.fullScreenCover`, which
        // replaces the ENTIRE window content: nothing from this screen
        // exists behind it to reveal while dragging, only whatever blank
        // color the system shows there. Now an ordinary ZStack overlay
        // instead — CreateEventView's own form (below) stays mounted and
        // live underneath at all times, exactly like web's identical
        // `{reviewOpen && <ReviewStep/>}` sibling-overlay pattern
        // (CreateEvent.jsx) — so dragging the review sheet to the right
        // reveals the REAL, live create-event form underneath, not a
        // placeholder.
        ZStack(alignment: .leading) {
            createFormBody
            if reviewOpen {
                CreateEventReviewSheet(
                    categories: categories,
                    galleryItems: galleryItems,
                    coverItemID: coverItemID,
                    dateLabel: {
                        if let date = app.createEventDate, let time = app.createEventTime {
                            return "\(Self.vnDateLabelFormatter.string(from: date)) ▪︎ \(Self.vnTimeLabelFormatter.string(from: time))"
                        }
                        return app.T("Chưa chọn", "Not set")
                    }(),
                    onBack: { withAnimation(.easeInOut(duration: 0.25)) { reviewOpen = false } },
                    onConfirm: {
                        // TASK 3 (event creation validation pass) —
                        // defense-in-depth: this sheet's own fields are
                        // read-only display, but re-check here too rather
                        // than trust nothing changed since Review opened.
                        guard !app.createName.trimmingCharacters(in: .whitespaces).isEmpty,
                              app.createLocConfirmed, !hasCreateFieldErrors else {
                            withAnimation(.easeInOut(duration: 0.25)) { reviewOpen = false }
                            return
                        }
                        // Keyword-search fix (migration 108) — same
                        // default-to-category-label(s) fallback web's
                        // identical `createCatLabel` provides, computed
                        // here (not duplicated in AppState) since
                        // `categories` already lives on this view.
                        let picked = app.createCats.isEmpty ? ["supper"] : app.createCats
                        let defaultKeywordsLabel = picked.compactMap { key in categories.first(where: { $0.key == key }).map { app.T($0.vi, $0.en) } }.joined(separator: " ▪︎ ")
                        // TASK 3 (event creation validation pass) — only a
                        // REAL RPC-confirmed success opens the post-
                        // submission chooser; a failure leaves Review open
                        // with data intact and app.createError already
                        // showing, never the chooser.
                        let ok = await app.submitCreateEvent(
                            newImages: newImagesInOrder, coverNewIndex: coverNewIndex,
                            removeExistingPhotoIDs: removedExistingIDs, existingCoverPath: existingCoverPath,
                            defaultKeywordsLabel: defaultKeywordsLabel
                        )
                        if ok {
                            withAnimation(.easeInOut(duration: 0.25)) { reviewOpen = false }
                            successChoiceMade = false
                            successChooserOpen = true
                        }
                    }
                )
                .environmentObject(app)
                .transition(.move(edge: .trailing))
                .zIndex(1)
            }
        }
        .onChange(of: reviewOpen) { _, open in app.isCreateReviewOpen = open }
        .onDisappear { app.isCreateReviewOpen = false }
        // TASK 3 (event creation validation pass) — a native
        // `.confirmationDialog` (UIAlertController style .actionSheet under
        // the hood), this ticket's own "supported platform API" instruction
        // — not an imitation of Apple's password-provider UI.
        .confirmationDialog(
            app.T("Đã gửi sự kiện!", "Event submitted!"),
            isPresented: $successChooserOpen,
            titleVisibility: .visible
        ) {
            Button(app.T("Tạo sự kiện khác", "Create another event")) {
                successChoiceMade = true
                galleryItems = []
                coverItemID = nil
                photoError = ""
                seededForEventID = nil
                seededExistingIDs = []
                app.goCreate()
            }
            Button(app.T("Xem sự kiện đang chờ duyệt", "View pending events")) {
                successChoiceMade = true
                app.goDashboard()
            }
            Button(app.T("Về Trang chủ", "Go to Home")) {
                successChoiceMade = true
                app.goHome()
            }
            Button(app.T("Về Tài khoản", "Go to Account")) {
                successChoiceMade = true
                app.goProfile()
            }
            // Explicit Cancel row — SwiftUI would otherwise supply its own
            // no-op Cancel, which doesn't match this ticket's own "default
            // to the pending-events destination" instruction.
            Button(app.T("Đóng", "Dismiss"), role: .cancel) {
                successChoiceMade = true
                app.goDashboard()
            }
        }
        // Swipe-to-dismiss/backdrop-tap on the sheet flips this binding to
        // false WITHOUT any button firing — same "unambiguous success"
        // pending-events default as the explicit Cancel row above.
        .onChange(of: successChooserOpen) { _, open in
            if !open && !successChoiceMade { app.goDashboard() }
        }
    }

    private var createFormBody: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                // Stage 1 fix — this used to name a fixed destination,
                // which stopped being true once createBack started
                // returning to the REAL originating tab (see
                // createOriginScreen's own comment) instead of always
                // landing on Dashboard/HostIntro.
                BackLink(label: app.T("Quay lại", "Back")) {
                    app.createBack()
                }

                Text(app.T("Dành cho người tổ chức", "For organizers"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.top, 14)
                Text(app.createEditEventId != nil
                     ? app.T("Chỉnh sửa và gửi lại", "Correct and resubmit")
                     : app.T("Tạo sự kiện, hoàn toàn miễn phí", "Create an event, completely free"))
                    .font(BanbeTheme.display(26))
                    .padding(.top, 8)
                if let editID = app.createEditEventId,
                   let reason = app.myOrgEventSummaries.first(where: { $0.id == editID })?.rejectionReason,
                   !reason.isEmpty {
                    Text(app.T("Bị từ chối: ", "Rejected: ") + reason)
                        .font(.system(size: 12))
                        .foregroundStyle(BanbeTheme.alert)
                        .padding(10)
                        .background(BanbeTheme.alert.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(.top, 10)
                }

                group(app.T("Hồ sơ người tổ chức", "Organizer profile")) {
                    BanbeField(label: app.T("Tên", "Name"), placeholder: "Bếp Nhỏ", text: $app.orgRegName)
                    BanbeField(label: "Instagram", placeholder: "@bepnho.saigon", text: $app.orgRegIg)
                    BanbeField(label: app.T("Giới thiệu", "About"),
                               placeholder: app.T("Mình nấu cho người lạ từ 2021…", "I cook for strangers since 2021…"),
                               text: $app.orgRegDesc)
                }

                group(app.T("Sự kiện", "Event")) {
                    BanbeField(label: app.T("Tên sự kiện", "Event name"),
                               placeholder: app.T("Tên sự kiện của bạn", "Your event name"), text: $app.createName,
                               required: true)
                    BanbeField(label: app.T("Mô tả", "Description"),
                               placeholder: app.T("Buổi này có gì?", "What happens?"), text: $app.createDesc,
                               required: true)
                    if !descValid && !app.createSent {
                        Text(app.T("Hãy nhập mô tả.", "Please enter a description."))
                            .font(.system(size: 11)).foregroundStyle(BanbeTheme.alert)
                    }
                    introEditor()
                    BanbeField(
                        label: app.T("Địa điểm", "Location"),
                        placeholder: app.T("12 Nguyễn Văn Đậu, hoặc tên địa điểm…", "12 Nguyễn Văn Đậu, or a venue name…"),
                        text: $app.createLoc,
                        required: true
                    )
                    .onChange(of: app.createLoc) { _, newValue in
                        createAddressSearchTask?.cancel()
                        // A stale confirmation/point for a since-edited
                        // address is worse than none — see
                        // createLocConfirmed's own doc comment.
                        app.createLat = nil
                        app.createLng = nil
                        app.createLocLabel = ""
                        app.createAddressLine = ""
                        app.createDistrict = ""
                        app.createCity = ""
                        app.createPostalCode = ""
                        app.createLocConfirmed = false
                        app.createAddressSuggestions = []
                        app.createAddressSearchError = ""
                        let query = newValue.trimmingCharacters(in: .whitespaces)
                        guard query.count >= 4 else { app.createAddressSearching = false; return }
                        createAddressSearchTask = Task {
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            guard !Task.isCancelled else { return }
                            await app.searchCreateAddress(query)
                        }
                    }
                    Text(app.T(
                        "Gõ số nhà + tên đường (hoặc tên địa điểm nếu không có số nhà) rồi chọn một gợi ý — cần thiết để đăng sự kiện.",
                        "Type a house number + street (or a venue name if there is no house number), then pick a suggestion — required to publish."
                    ))
                    .font(.system(size: 11)).opacity(0.75).foregroundStyle(app.palette.ink)
                    locationConfirmSection()
                    dateTimeRow()
                    HStack(spacing: 10) {
                        BanbeField(label: app.T("Giá", "Price"), placeholder: "900.000", text: $app.createPrice,
                                   keyboard: .numberPad)
                        BanbeField(label: app.T("Số chỗ", "Seats"), placeholder: "14", text: $app.createSeats,
                                   keyboard: .numberPad, required: true)
                    }
                    if !seatsValid && !app.createSent {
                        Text(app.T("Hãy nhập số chỗ lớn hơn 0.", "Please enter a number of seats greater than 0."))
                            .font(.system(size: 11)).foregroundStyle(BanbeTheme.alert)
                    }

                    HStack(spacing: 4) {
                        Text(app.T("Hạng mục ▪︎ chọn tối đa 2", "Categories ▪︎ up to 2"))
                            .font(.system(size: 11.5))
                        Text("*").font(.system(size: 11.5)).foregroundStyle(BanbeTheme.alert)
                    }
                    FlowRow(spacing: 8) {
                        ForEach(categories, id: \.key) { category in
                            let active = app.createCats.contains(category.key)
                            Button { app.pickCreateCategory(category.key) } label: {
                                Text(app.T(category.vi, category.en))
                                    .font(.system(size: 12.5, weight: active ? .semibold : .regular))
                                    .foregroundStyle(active ? app.palette.paper : app.palette.ink)
                                    .padding(.horizontal, 14).padding(.vertical, 9)
                                    .background(active ? app.palette.ink : .clear, in: Capsule())
                                    .overlay(Capsule().stroke(active ? .clear : app.palette.rule, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if !catsValid && !app.createSent {
                        Text(app.T("Hãy chọn ít nhất một danh mục.", "Please pick at least one category."))
                            .font(.system(size: 11)).foregroundStyle(BanbeTheme.alert)
                    }

                    // Keyword-search fix (migration 108) — so this event
                    // actually surfaces in Map's search box for terms
                    // beyond its literal name/district. Left blank,
                    // submission defaults it to the category label(s)
                    // picked just above (never silently empty).
                    VStack(alignment: .leading, spacing: 5) {
                        Text(app.T("Từ khoá tìm kiếm", "Search keywords")).font(.system(size: 11.5))
                        TextField(
                            app.T("vd. tiệc tối, rượu vang, ẩm thực Việt", "e.g. supper club, wine, Vietnamese food"),
                            text: $app.createKeywords
                        )
                        .font(.system(size: 14))
                        Text(app.T(
                            "Cách nhau bằng dấu phẩy — để trống sẽ tự dùng danh mục đã chọn ở trên.",
                            "Comma-separated — left blank, the category picked above is used instead."
                        ))
                        .font(.system(size: 11)).opacity(0.75)
                    }
                    .foregroundStyle(app.palette.ink)

                    includedItemsEditor()
                }

                gallerySection()

                // TASK 3 (event creation validation pass) — the "Download
                // the Excel template" entry (a `ShareLink` to the bundled
                // .xlsx, generated by scripts/generate-template.js) is
                // removed per this ticket's own instruction. iOS never had
                // an upload/parse side to this feature at all (see this
                // block's own prior doc comment: no ZIP/XML capability),
                // so there is no "unrelated import functionality" left
                // here to preserve — the whole feature is gone on iOS,
                // matching what actually remains once the entry point is
                // removed (web keeps its own upload/parse path, unaffected).

                // No SLA is actually monitored server-side — the previous
                // "duyệt sự kiện đầu tiên trong 48 giờ"/"reviews your first
                // event within 48 hours" copy promised a turnaround time
                // nothing enforced. Accurate instead of reassuring.
                // "Review before submitting" step (task 1) — this button now
                // only OPENS the review sheet; only that sheet's own
                // "Xác nhận và gửi" ever actually calls submitCreateEvent.
                InkButton(title: app.createSent
                          ? app.T("Đã gửi, đang chờ Banbe duyệt", "Submitted, waiting for Banbe to review")
                          : app.T("Xem lại trước khi gửi", "Review before submitting"),
                          enabled: !app.createName.trimmingCharacters(in: .whitespaces).isEmpty
                              && app.createLocConfirmed && !hasCreateFieldErrors && !app.createSent && !app.loading,
                          cornerRadius: 999) {
                    // Keyboard-stays-up fix (2026-09-29) — opening the review
                    // used to rely on `.fullScreenCover` implicitly resigning
                    // first responder (a new modal context takes it away for
                    // free); now that it's a plain overlay in the SAME view
                    // hierarchy (see `body`'s own doc comment), nothing does
                    // that automatically, so any focused text field stayed
                    // focused — and the keyboard visible — underneath it.
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    withAnimation(.easeInOut(duration: 0.25)) { reviewOpen = true }
                }
                .padding(.top, 26)

                if !app.createLocConfirmed && !app.createSent {
                    Text(app.T("Chọn một địa chỉ gợi ý ở trên trước khi đăng.", "Pick a suggested address above before publishing."))
                        .font(.system(size: 11.5)).opacity(0.7)
                        .foregroundStyle(app.palette.ink)
                        .padding(.top, 8)
                }

                if !app.createError.isEmpty {
                    Text(app.createError)
                        .font(.system(size: 12))
                        .foregroundStyle(BanbeTheme.alert)
                        .padding(.top, 12)
                }
                if !app.createMediaError.isEmpty {
                    Text(app.createMediaError)
                        .font(.system(size: 12))
                        .foregroundStyle(BanbeTheme.alert)
                        .padding(.top, 12)
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .task(id: app.createEditEventId) {
            guard let editID = app.createEditEventId else { seedGalleryIfNeeded(); return }
            await app.loadEventPhotos(eventID: editID)
        }
        .onChange(of: app.eventPhotos) { _, _ in seedGalleryIfNeeded() }
        .onAppear { seedGalleryIfNeeded() }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 11.5, weight: .semibold))
            content()
        }
        .padding(16)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.top, 22)
    }
}

/// "Review before submitting" step (task 1) — TWO tabs (2026-09-29
/// follow-up, matching web's identical CreateEvent.jsx `ReviewStep`
/// change): "Nội bộ" (private/host) shows EXACTLY the fields that will be
/// sent (title, gallery order + cover marker, description/intro, full
/// resolved address, date/time, capacity, price, category, included
/// items) — the original content of this screen; "Xem trước công khai"
/// (public preview) renders the SAME draft data shaped the way a normal
/// viewer would see it on the real Event Detail page (`EventDetailView`)
/// once approved — same "district ▪︎ live km ▪︎ long date ▪︎ time"
/// where-line format (via the shared `app.stripKm`/`app.trStatus`), same
/// price-or-"Miễn phí" rule, same cover/gallery. Both tabs share one
/// back/confirm footer; only the explicit "Xác nhận và gửi" tap (available
/// from either tab) calls `submitCreateEvent`. A `.fullScreenCover`, not a
/// second screen in the nav stack — there is no back-stack state to
/// reconcile.
private struct CreateEventReviewSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.openURL) private var openURL
    let categories: [(key: String, vi: String, en: String)]
    let galleryItems: [StagedGalleryItem]
    let coverItemID: String?
    let dateLabel: String
    // Swipe-to-back "blank white space" fix (2026-09-29) — this sheet is no
    // longer a `.fullScreenCover` (see `CreateEventView.body`'s own doc
    // comment), so there's no system presentation left to call
    // `@Environment(\.dismiss)` on; the parent instead owns `reviewOpen`
    // and hands down this closure, exactly like web's `ReviewStep(onBack)`.
    let onBack: () -> Void
    let onConfirm: () async -> Void
    @State private var confirmBusy = false
    private enum Tab { case privateTab, publicTab }
    @State private var tab: Tab = .privateTab
    // `swipeAxisLocked` is decided once per gesture, the first time its
    // translation is unambiguous either way, and never re-decided mid-
    // gesture — a genuine up/down swipe is locked out entirely (offset
    // stays exactly 0, no diagonal drift) rather than only mostly ignored,
    // which is what "steady" means here: one axis moves, or none does.
    @State private var swipeBackOffset: CGFloat = 0
    @State private var swipeAxisLocked: Bool?
    // Vertical-scroll lock fix (2026-09-29 follow-up) — once a drag is
    // confirmed horizontal, the ScrollView below is disabled for the rest
    // of that gesture, so moving a finger up/down mid-swipe can no longer
    // also scroll the content underneath at the same time (the two
    // gestures fighting each other was the reported "issues").
    @State private var scrollLockedForSwipe = false
    // Real-device follow-up — this preview used to have exactly ONE
    // tappable thing (the Google Maps link); Included/Organizer/photos
    // were static. None of these can navigate to the REAL Included/
    // organizer-profile/photo-viewer screens (this is an unsaved draft —
    // no real event id/organizer id exists in the database yet), so each
    // opens its own small, self-contained sheet/full-screen cover showing
    // the same draft data, instead of a dead tap.
    @State private var includedSheetOpen = false
    @State private var organizerSheetOpen = false
    @State private var viewerIndex: Int?

    // Same "cover first, then the rest" order the public tab already
    // displays photos in (coverItem, then restPhotos) — the pager below
    // must match exactly, or a tapped thumbnail would open on the wrong
    // photo.
    private func orderedGalleryForViewer() -> [StagedGalleryItem] {
        let coverItem = galleryItems.first(where: { $0.id == coverItemID }) ?? galleryItems.first
        guard let coverItem else { return galleryItems }
        return [coverItem] + galleryItems.filter { $0.id != coverItem.id }
    }

    private var categoryLabel: String {
        let picked = app.createCats.isEmpty ? ["supper"] : app.createCats
        return picked.compactMap { key in categories.first(where: { $0.key == key }).map { app.T($0.vi, $0.en) } }.joined(separator: " ▪︎ ")
    }
    private var addressLabel: String {
        if !app.createLocLabel.isEmpty { return app.createLocLabel }
        let parts = [app.createAddressLine, app.createDistrict, app.createCity].filter { !$0.isEmpty }
        return parts.isEmpty ? app.T("Chưa xác nhận địa chỉ", "Address not confirmed") : parts.joined(separator: ", ")
    }
    // "Bao gồm" review parity fix (2026-09-29) — CreateEventView now has a
    // real editing UI for this (`includedItemsEditor()`), so the review
    // step shows exactly what was entered, same trimmed/non-empty-label
    // filter `submitCreateEvent`'s own validation applies.
    private var reviewIncludedItems: [IncludedItem] {
        app.createIncludedItems
            .map { IncludedItem(label: $0.label.trimmingCharacters(in: .whitespaces), detail: $0.detail.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.label.isEmpty }
    }

    private var publicPriceVnd: Int { Int(app.createPrice.filter { $0.isNumber }) ?? 0 }
    private var publicPriceLabel: String { publicPriceVnd > 0 ? EventLabels.vnd(publicPriceVnd) : app.T("Miễn phí", "Free") }
    private var publicSeatsLabel: String {
        let seats = app.createSeats.trimmingCharacters(in: .whitespaces)
        return seats.isEmpty ? "" : app.T("Còn \(seats) chỗ", "\(seats) seats left")
    }
    // Merges the two VN-timezone-picked Date/time values into ONE Date
    // whose components read back correctly under the DEVICE's own local
    // calendar, so `Countdown.formatVnEventDate` (which reads `.current`)
    // shows the same wall-clock digits the host actually picked in
    // EventDateTimeSheet, regardless of the device's own timezone setting.
    private var mergedStartsAt: Date? {
        guard let d = app.createEventDate, let t = app.createEventTime else { return nil }
        var vnCal = Calendar(identifier: .gregorian); vnCal.timeZone = AppState.vietnamTimeZone
        let dc = vnCal.dateComponents([.year, .month, .day], from: d)
        let tc = vnCal.dateComponents([.hour, .minute], from: t)
        var comps = DateComponents()
        comps.year = dc.year; comps.month = dc.month; comps.day = dc.day
        comps.hour = tc.hour; comps.minute = tc.minute
        return Calendar(identifier: .gregorian).date(from: comps)
    }
    // Same shape `CatalogEvent.fromReal`'s `whereLabel` builds for a real
    // event — district ▪︎ live-km placeholder ▪︎ long date ▪︎ time — so the
    // preview matches the actual Event Detail page exactly.
    private var publicWhereLabel: String {
        let startsAt = mergedStartsAt
        let d = startsAt.map(Countdown.formatVnEventDate)
        let kmSegment = startsAt != nil ? "0,0 km từ bạn" : nil
        let raw = [app.createDistrict, kmSegment, d?.dayLong, d?.time].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ▪︎ ")
        let previewCoords: Coordinates? = (app.createLat != nil && app.createLng != nil) ? Coordinates(lat: app.createLat!, lng: app.createLng!) : nil
        let stripped = raw.replacingOccurrences(of: #" ▪︎ \d+[.,]\d+ km(?: từ bạn| away)?"#, with: "", options: .regularExpression)
        guard app.located == true, let previewCoords, let km = haversineKm(from: app.userCoords, toCoords: previewCoords) else { return app.trStatus(stripped) }
        let kmStr = String(format: "%.1f", km).replacingOccurrences(of: ".", with: ",")
        return app.trStatus(raw.replacingOccurrences(of: #"\d+[.,]\d+(?= km)"#, with: kmStr, options: .regularExpression))
    }
    private var publicMapsURL: URL? {
        guard let lat = app.createLat, let lng = app.createLng else { return nil }
        return URL(string: "https://www.google.com/maps/search/?api=1&query=\(lat),\(lng)")
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 10.5)).opacity(0.6)
            Text(value).font(.system(size: 13.5)).lineLimit(nil)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Divider().overlay(app.palette.rule) }
    }

    // Same visual shape as `EventDetailView`'s own `detailRow`/`includedRow`
    // (label left, value right, divider below, optional chevron) — the
    // public preview tab must look like the real page, not invent its own.
    @ViewBuilder
    private func previewDetailRow(_ label: String, _ value: String, chevron: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                Text(label).font(.system(size: 13))
                Spacer(minLength: 0)
                Text(value).font(.system(size: 13)).multilineTextAlignment(.trailing)
                if chevron {
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium)).opacity(0.45)
                }
            }
            .padding(.vertical, 12)
            .foregroundStyle(app.palette.ink)
            Divider().overlay(app.palette.rule)
        }
    }

    @ViewBuilder
    private func tabButton(_ target: Tab, _ label: String) -> some View {
        Button { tab = target } label: {
            Text(label)
                .font(.system(size: 12.5, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(tab == target ? app.palette.ink : Color.clear, in: RoundedRectangle(cornerRadius: 999, style: .continuous))
                .foregroundStyle(tab == target ? app.palette.paper : app.palette.ink)
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        // Real-device follow-up — this outer ZStack (added so Included/
        // Organizer/photo-viewer overlays could sit above the main
        // content) has NO explicit size of its own; without it, a ZStack
        // sizes itself to the UNION of its children and centers each one
        // within that — since organizerPreviewScreen's OWN inner content
        // doesn't force full width the same way the main VStack below
        // does, the whole thing could resolve narrower than the screen
        // and get center-placed instead of pinned left, reading as
        // "shifted right" (the real-device report). An explicit
        // full-bleed frame removes the ambiguity entirely.
        ZStack {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.T("Quay lại chỉnh sửa", "Back to edit")) { onBack() }
                    .padding(.top, 16)

                Text(app.T("Xem lại trước khi gửi", "Review before submitting"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.top, 14)

                HStack(spacing: 6) {
                    tabButton(.privateTab, app.T("Nội bộ (Host)", "Private (Host)"))
                    tabButton(.publicTab, app.T("Xem trước công khai", "Public preview"))
                }
                .padding(3)
                .background(app.palette.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 999, style: .continuous))
                .padding(.top, 14)
            }
            .padding(.horizontal, 22)
            .foregroundStyle(app.palette.ink)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if tab == .privateTab {
                        Text(app.createName.trimmingCharacters(in: .whitespaces).isEmpty ? app.T("(Chưa đặt tên)", "(Untitled)") : app.createName)
                            .font(BanbeTheme.display(24))
                            .padding(.top, 4)

                        VStack(alignment: .leading, spacing: 0) {
                            row(app.T("Danh mục", "Category"), categoryLabel)
                            row(app.T("Ngày & giờ", "Date & time"), dateLabel)
                            row(app.T("Địa chỉ", "Address"), addressLabel)
                            row(app.T("Số chỗ", "Capacity"), app.createSeats.isEmpty ? app.T("Chưa nhập", "Not set") : app.createSeats)
                            row(app.T("Giá vé", "Price"), app.createPrice.isEmpty ? app.T("Miễn phí", "Free") : app.createPrice)
                            if !app.createDesc.trimmingCharacters(in: .whitespaces).isEmpty {
                                row(app.T("Mô tả", "Description"), app.createDesc.trimmingCharacters(in: .whitespaces))
                            }
                            if !app.createIntro.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                row(app.T("Giới thiệu sự kiện", "Event introduction"), app.createIntro.trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                        if !reviewIncludedItems.isEmpty {
                            Text(app.T("Bao gồm", "Included")).font(.system(size: 11.5)).padding(.top, 22)
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(reviewIncludedItems.enumerated()), id: \.offset) { index, item in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.label).font(.system(size: 13.5, weight: .semibold))
                                        if !item.detail.isEmpty {
                                            Text(item.detail).font(.system(size: 12.5)).opacity(0.8)
                                        }
                                    }
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .overlay(alignment: .bottom) {
                                        if index < reviewIncludedItems.count - 1 { Divider().overlay(app.palette.rule) }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        if !galleryItems.isEmpty {
                            Text(app.T("Thứ tự ảnh", "Photo order")).font(.system(size: 11.5)).padding(.top, 22)
                            VStack(spacing: 8) {
                                ForEach(Array(galleryItems.enumerated()), id: \.element.id) { index, item in
                                    HStack(spacing: 10) {
                                        Group {
                                            if let image = item.image {
                                                Image(uiImage: image).resizable().scaledToFill()
                                            } else {
                                                AsyncImage(url: item.url) { $0.resizable().scaledToFill() } placeholder: { app.palette.field }
                                            }
                                        }
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        Text(item.id == coverItemID ? app.T("Ảnh bìa", "Cover photo") : app.T("Ảnh \(index + 1)", "Photo \(index + 1)"))
                                            .font(.system(size: 12.5))
                                        Spacer(minLength: 0)
                                    }
                                    .padding(8)
                                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                            .padding(.top, 10)
                        }
                    } else {
                        let coverItem = galleryItems.first(where: { $0.id == coverItemID }) ?? galleryItems.first
                        if let coverItem {
                            // Real-device follow-up — TWO problems in one:
                            // (1) `.aspectRatio(1, contentMode: .fill)`
                            // with no explicit height, inside a
                            // `ScrollView` (an unconstrained vertical
                            // axis), is a known SwiftUI trap — it resolves
                            // against an effectively-infinite proposed
                            // height and blows up to a huge, uncontrolled
                            // size instead of a real square (the "giant
                            // photo with all the text overlaid on top of
                            // it" report). (2) even fixed, a rounded,
                            // padded square never matched the REAL
                            // EventDetailView's own cover photo anyway —
                            // that's `CatalogPhoto(path: event.img, height:
                            // 400, cornerRadius: 0)`, i.e. full-BLEED
                            // (edge to edge, no rounding), not an inset
                            // card. Matches that exactly now, including
                            // breaking out of this content's own 22pt
                            // horizontal padding (applied once, at the
                            // bottom of this whole VStack) via a negating
                            // `.padding(.horizontal, -22)`.
                            Button { viewerIndex = 0 } label: {
                                Group {
                                    if let image = coverItem.image {
                                        Image(uiImage: image).resizable().scaledToFill()
                                    } else {
                                        AsyncImage(url: coverItem.url) { $0.resizable().scaledToFill() } placeholder: { app.palette.field }
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 400)
                                .clipped()
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, -22)
                            .accessibilityIdentifier("createEvent.preview.coverPhoto")
                        }

                        Text(categoryLabel).font(.system(size: 12)).opacity(0.7).padding(.top, 14)
                        Text(app.createName.trimmingCharacters(in: .whitespaces).isEmpty ? app.T("(Chưa đặt tên)", "(Untitled)") : app.createName)
                            .font(BanbeTheme.display(26))
                            .padding(.top, 4)

                        if let publicMapsURL {
                            Button { openURL(publicMapsURL) } label: {
                                Text(publicWhereLabel + " ↗").font(.system(size: 13)).underline()
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 6)
                        } else {
                            Text(publicWhereLabel.isEmpty ? app.T("Chưa xác nhận địa chỉ", "Address not confirmed") : publicWhereLabel)
                                .font(.system(size: 13))
                                .padding(.top, 6)
                        }
                        if !publicSeatsLabel.isEmpty {
                            Text(publicSeatsLabel).font(.system(size: 13)).padding(.top, 4)
                        }

                        // Standard-layout fix (2026-09-29) — matches the
                        // REAL `EventDetailView`'s exact field order
                        // (category/name/where/seats/description, THEN a
                        // divider-topped block of Included → Organizer →
                        // Track record → Price), which this preview had
                        // drifted from (price/Included were both above the
                        // description, and there was no Organizer row at
                        // all). Description here is `createDesc` ("Mô tả"),
                        // the same field the real event's own `ev.desc`
                        // comes from — never `createIntro` ("Giới thiệu sự
                        // kiện"), a separate field the real page doesn't
                        // show on the main body either.
                        if !app.createDesc.trimmingCharacters(in: .whitespaces).isEmpty {
                            Text(app.createDesc.trimmingCharacters(in: .whitespaces))
                                .font(.system(size: 14)).lineSpacing(4).padding(.top, 20)
                        }

                        VStack(spacing: 0) {
                            Divider().overlay(app.palette.rule)
                            // Real-device follow-up — "Bao gồm"/"Người tổ
                            // chức" used to be static text (the ONLY
                            // tappable thing on this tab was the Google
                            // Maps link) — now real Buttons opening a
                            // self-contained detail sheet, same "click on
                            // it like a real event" ask this preview
                            // exists for. Neither can navigate to the
                            // REAL Included/organizer-profile screens
                            // (this is an unsaved draft — no real event id/
                            // organizer id exists yet), so each opens its
                            // own small sheet showing the same draft data.
                            if !reviewIncludedItems.isEmpty {
                                Button { includedSheetOpen = true } label: {
                                    previewDetailRow(
                                        app.T("Bao gồm", "Included"),
                                        reviewIncludedItems.map(\.label).joined(separator: " ▪︎ "),
                                        chevron: true
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("createEvent.preview.included")
                            }
                            Button { organizerSheetOpen = true } label: {
                                previewDetailRow(
                                    app.T("Người tổ chức", "Organizer"),
                                    // Real-device follow-up — `chevron:
                                    // true` already draws a real chevron
                                    // glyph; this string had its OWN " ›"
                                    // appended too, so the row showed two
                                    // (circled in the real-device report).
                                    app.T("Ghé", "Visit") + " " + (app.orgRegName.trimmingCharacters(in: .whitespaces).isEmpty ? "Organizer" : app.orgRegName.trimmingCharacters(in: .whitespaces)),
                                    chevron: true
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("createEvent.preview.organizer")
                            // No "Track record" row: that only ever shows
                            // for an ALREADY-established organizer (20+ past
                            // events, `orgTrusted`) — a brand-new draft
                            // never has one yet, same as the real page.
                            HStack(alignment: .firstTextBaseline) {
                                Text(app.T("Giá", "Price")).font(.system(size: 13))
                                Spacer()
                                Text(publicPriceLabel).font(BanbeTheme.display(23))
                            }
                            .padding(.top, 16)
                        }
                        .padding(.top, 22)

                        let restPhotos = galleryItems.filter { $0.id != coverItem?.id }
                        if !restPhotos.isEmpty {
                            Text(app.T("Hình ảnh", "Photos")).font(.system(size: 11.5)).padding(.top, 18)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(Array(restPhotos.enumerated()), id: \.element.id) { offset, item in
                                        Button { viewerIndex = offset + 1 } label: {
                                            Group {
                                                if let image = item.image {
                                                    Image(uiImage: image).resizable().scaledToFill()
                                                } else {
                                                    AsyncImage(url: item.url) { $0.resizable().scaledToFill() } placeholder: { app.palette.field }
                                                }
                                            }
                                            .frame(width: 96, height: 96)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("createEvent.preview.photo.\(offset + 1)")
                                    }
                                }
                            }
                            .padding(.top, 10)
                        }
                    }
                }
                .foregroundStyle(app.palette.ink)
                .padding(.horizontal, 22)
                .padding(.bottom, 16)
            }
            .scrollDisabled(scrollLockedForSwipe)

            // Confirm — the ONLY call site that actually submits, available
            // from either tab. Local `confirmBusy` disables the button for
            // this ONE tap on top of `AppState.submitCreateEventInFlight`'s
            // own synchronous guard.
            VStack(alignment: .leading, spacing: 0) {
                InkButton(
                    title: app.createSent
                        ? app.T("Đã gửi, đang chờ Banbe duyệt", "Submitted, waiting for Banbe to review")
                        : (confirmBusy ? app.T("Đang gửi…", "Submitting…") : app.T("Xác nhận và gửi", "Confirm & submit")),
                    enabled: !confirmBusy && !app.createSent,
                    cornerRadius: 999
                ) {
                    Task { confirmBusy = true; await onConfirm(); confirmBusy = false }
                }

                if !app.createError.isEmpty {
                    Text(app.createError).font(.system(size: 12)).foregroundStyle(BanbeTheme.alert).padding(.top, 12)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 40)
            .padding(.top, 10)
        }
        .background(app.palette.paper.ignoresSafeArea())
        .offset(x: swipeBackOffset)
        // `.simultaneousGesture` so the ScrollView above can still start a
        // vertical scroll on an ambiguous/actually-vertical drag — once
        // THIS gesture locks onto horizontal, `scrollLockedForSwipe`
        // disables that ScrollView outright for the rest of the gesture,
        // so a wobble up/down mid-swipe can no longer also scroll the
        // content underneath at the same time.
        .simultaneousGesture(
            DragGesture(minimumDistance: 12, coordinateSpace: .local)
                .onChanged { value in
                    if swipeAxisLocked == nil {
                        swipeAxisLocked = abs(value.translation.width) > abs(value.translation.height)
                        if swipeAxisLocked == true { scrollLockedForSwipe = true }
                    }
                    guard swipeAxisLocked == true else { return }
                    swipeBackOffset = max(0, value.translation.width)
                }
                .onEnded { value in
                    let wasHorizontal = swipeAxisLocked == true
                    swipeAxisLocked = nil
                    scrollLockedForSwipe = false
                    guard wasHorizontal else { return }
                    if swipeBackOffset > 110 || value.predictedEndTranslation.width > 280 {
                        // Hand off to the parent's own `.move(edge: .trailing)`
                        // removal transition (identical motion to a plain
                        // BackLink tap) rather than compositing that
                        // transition's animated offset on top of whatever
                        // manual `swipeBackOffset` the drag left behind.
                        swipeBackOffset = 0
                        onBack()
                    } else {
                        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.86)) { swipeBackOffset = 0 }
                    }
                }
        )

        // Real-device follow-up — a plain `.sheet` (system card, sparse
        // content) didn't match "click on it like a real event": the REAL
        // EventDetailView opens Included in a `BottomSheet` (this exact
        // component, Sheets.swift — a dimmed backdrop + bottom panel in
        // the SAME view hierarchy, not a system modal) showing "Giới
        // thiệu & Bao gồm"/"About & Included" TOGETHER (intro paragraphs
        // AND every included item's label+detail), never just Included
        // alone. Reused verbatim, not reinvented.
        if includedSheetOpen {
            BottomSheet(onDismiss: { includedSheetOpen = false }) { includedSheetContent }
        }

        // Real-device follow-up — the REAL EventDetailView doesn't open a
        // small popup for Organizer at all: it navigates to a full,
        // dedicated OrganizerView screen. This can't literally navigate
        // there (no real organizer id exists until the event is actually
        // submitted), so it's a full-screen panel styled the same way —
        // "Người tổ chức" label, large name, Instagram, About paragraph —
        // not a follow button/track record/other-events grid, since none
        // of those exist yet for a brand-new draft either (matching the
        // real page's own `orgTrusted`-gated behavior for a new host).
        if organizerSheetOpen {
            organizerPreviewScreen
        }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fullScreenCover(isPresented: Binding(get: { viewerIndex != nil }, set: { if !$0 { viewerIndex = nil } })) {
            photoViewer
        }
    }

    // Real-device follow-up — matches the REAL EventDetailView's own
    // `introIncludedSheetContent` (About + Included combined), not just a
    // bare list of included items.
    private var includedSheetContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(app.T("Giới thiệu & Bao gồm", "About & Included")).font(BanbeTheme.display(18))
                Spacer()
                Button { includedSheetOpen = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("createEvent.preview.includedSheet.close")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    let intro = app.createIntro.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !intro.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(app.T("Giới thiệu sự kiện", "About this event"))
                                .font(.system(size: 11.5, weight: .semibold))
                            ForEach(Array(intro.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                                Text(paragraph.trimmingCharacters(in: .whitespacesAndNewlines))
                                    .font(.system(size: 13.5))
                                    .lineSpacing(5)
                            }
                        }
                    }
                    if !reviewIncludedItems.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(app.T("Bao gồm", "Included"))
                                .font(.system(size: 11.5, weight: .semibold))
                            ForEach(Array(reviewIncludedItems.enumerated()), id: \.offset) { _, item in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.label).font(.system(size: 13.5, weight: .medium))
                                    if !item.detail.isEmpty {
                                        Text(item.detail).font(.system(size: 12.5)).opacity(0.7)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .foregroundStyle(app.palette.ink)
        .accessibilityIdentifier("createEvent.preview.includedSheet")
    }

    // Real-device follow-up — styled like OrganizerView's own header
    // (name, Instagram, about), full screen, not a small system sheet —
    // no follow button/track record/other-events grid, since none of
    // those exist yet for a brand-new draft (same as the real page's own
    // behavior for a first-time host).
    private var organizerPreviewScreen: some View {
        ZStack(alignment: .top) {
            app.palette.paper.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.createName.trimmingCharacters(in: .whitespaces).isEmpty ? app.T("(Chưa đặt tên)", "(Untitled)") : app.createName) {
                    organizerSheetOpen = false
                }
                .padding(.top, 16)

                Text(app.T("Người tổ chức", "Organizer")).font(.system(size: 11.5)).padding(.top, 22)

                Text(app.orgRegName.trimmingCharacters(in: .whitespaces).isEmpty ? "Organizer" : app.orgRegName.trimmingCharacters(in: .whitespaces))
                    .font(BanbeTheme.display(29))
                    .padding(.top, 8)

                if !app.orgRegIg.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(app.orgRegIg.trimmingCharacters(in: .whitespaces))
                        .font(.system(size: 13))
                        .padding(.top, 10)
                }

                if !app.orgRegDesc.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(app.orgRegDesc.trimmingCharacters(in: .whitespaces))
                        .font(.system(size: 14))
                        .lineSpacing(4)
                        .padding(.top, 18)
                }

                Text(app.T("Xem trước: chưa đăng công khai", "Preview: not published yet"))
                    .font(.system(size: 11)).opacity(0.6)
                    .padding(.top, 22)

                Spacer()
            }
            // Real-device follow-up — the actual "shifting right" bug:
            // this VStack(alignment: .leading) only ever asks for its
            // CONTENT's own natural width (`.leading` only controls how
            // children align WITHIN it, it doesn't make the VStack itself
            // full-width) — so the surrounding `ZStack(alignment: .top)`
            // (defaulting to horizontally CENTERED) centered this whole
            // narrower-than-screen block instead of pinning it to the
            // left edge, reading as randomly shifted depending on the
            // widest line's own natural width. An explicit full-width
            // frame fixes it the same way the main content already does.
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("createEvent.preview.organizerScreen")
    }

    @ViewBuilder
    private func viewerImage(_ item: StagedGalleryItem, contentMode: ContentMode) -> some View {
        if let image = item.image {
            Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
        } else {
            AsyncImage(url: item.url) { $0.resizable().aspectRatio(contentMode: contentMode) } placeholder: { Color.black }
        }
    }

    // Real-device follow-up — this used to be a plain edge-to-edge
    // `TabView` pager, which read as generic/inconsistent with the rest of
    // the app ("not like a real event does"). Now visually matches the
    // REAL, already-published-event photo viewer (`PhotoViewerView.swift`)
    // as closely as a LOCAL, not-yet-uploaded draft photo can: same
    // blurred-backdrop-of-itself + centered framed photo (14pt corner,
    // middle third of the screen) + credit line layout. Can't literally
    // reuse `PhotoViewerView` itself — that view is keyed to a real,
    // persisted `event_photos.id` for like/share/save engagement, which
    // has no meaning for a draft that hasn't been submitted (no id exists
    // yet) — so this is a preview-only sibling with no engagement row,
    // captioned as a preview rather than silently showing fake zeros.
    private var photoViewer: some View {
        let photos = orderedGalleryForViewer()
        let index = min(max(viewerIndex ?? 0, 0), max(photos.count - 1, 0))
        let organizerName = app.orgRegName.trimmingCharacters(in: .whitespaces).isEmpty ? "Organizer" : app.orgRegName.trimmingCharacters(in: .whitespaces)
        return GeometryReader { proxy in
            let photoWidth = proxy.size.width - 40
            ZStack {
                if let current = photos[safe: index] {
                    viewerImage(current, contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(1.24)
                        .blur(radius: 34)
                        .overlay(Color.black.opacity(0.38))
                        .allowsHitTesting(false)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(app.T("Ảnh của", "Photo by") + " " + organizerName)
                        .font(.system(size: 10.5)).kerning(0.4)
                        .foregroundStyle(.white.opacity(0.72))
                        .shadow(color: .black.opacity(0.55), radius: 3, y: 1)

                    if let current = photos[safe: index] {
                        viewerImage(current, contentMode: .fit)
                            .frame(width: photoWidth, height: proxy.size.height / 3)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(color: .black.opacity(0.4), radius: 22, y: 10)
                            .id(index)
                            .contentShape(Rectangle())
                            .highPriorityGesture(
                                DragGesture(minimumDistance: 0)
                                    .onEnded { value in
                                        let dx = value.translation.width
                                        if abs(dx) > 44 {
                                            viewerIndex = dx < 0 ? min(index + 1, photos.count - 1) : max(index - 1, 0)
                                        } else if value.location.x >= photoWidth / 2 {
                                            viewerIndex = min(index + 1, photos.count - 1)
                                        } else if photoWidth > 0 {
                                            viewerIndex = max(index - 1, 0)
                                        }
                                    }
                            )
                            .accessibilityIdentifier("createEvent.preview.photoViewer.photo")
                    }

                    // No like/share/save row — this photo isn't real yet
                    // (no `event_photos.id` exists until submission), so
                    // this stays an honest "preview" caption instead of
                    // faking engagement the real viewer would show.
                    Text(app.T("Xem trước: chưa đăng công khai", "Preview: not published yet"))
                        .font(.system(size: 10.5)).kerning(0.4)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack {
                    HStack {
                        Spacer()
                        Button { viewerIndex = nil } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(.black.opacity(0.4), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("createEvent.preview.photoViewer.close")
                    }
                    Spacer()
                }
                .padding(.top, 50)
                .padding(.trailing, 20)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .onTapGesture { viewerIndex = nil }
        }
        .background(Color.black.ignoresSafeArea())
        .ignoresSafeArea()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// Date/time picker fix (Stage B, 2026-09-26) — ONE sheet, a graphical
/// native calendar directly above a native wheel time picker, both forced
/// to Asia/Ho_Chi_Minh via `.environment(\.timeZone, ...)` so the digits
/// shown always match Vietnam wall-clock time regardless of the device's
/// own timezone. Nothing is written back to the parent's bindings until
/// "Xong" — dismissing via "Hủy" (or a swipe) leaves the previously
/// confirmed selection untouched, which is what "reopen retains draft
/// selection" means in practice: there's no separate, discardable draft
/// state to lose, only ever the last CONFIRMED one.
struct EventDateTimeSheet: View {
    @Binding var date: Date?
    @Binding var time: Date?
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var draftDate: Date
    @State private var draftTime: Date
    // Month-navigation snap-back fix (2026-09-29) — the graphical
    // DatePicker below used to take `in: Date()...` directly, which calls
    // `Date()` fresh on every `body` re-evaluation (e.g. every tick while
    // scrubbing the wheel time picker below it). SwiftUI treats that as the
    // picker's valid range genuinely changing each render, which resets its
    // internal displayed-month scroll position back to today — exactly the
    // "jumps back to the current month" bug. Frozen once at init instead,
    // so the range argument is stable for the sheet's whole lifetime.
    private let minSelectableDate: Date

    init(date: Binding<Date?>, time: Binding<Date?>) {
        self._date = date
        self._time = time
        let calendar = Self.vnCalendar
        let today = calendar.startOfDay(for: Date())
        self._draftDate = State(initialValue: date.wrappedValue ?? today)
        self._draftTime = State(initialValue: time.wrappedValue ?? Date())
        self.minSelectableDate = today
    }

    private static var vnCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = AppState.vietnamTimeZone
        return cal
    }()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DatePicker(
                    "", selection: $draftDate, in: minSelectableDate...,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .environment(\.timeZone, AppState.vietnamTimeZone)
                .padding(.horizontal, 12)

                DatePicker(
                    "", selection: $draftTime,
                    displayedComponents: [.hourAndMinute]
                )
                .datePickerStyle(.wheel)
                .environment(\.timeZone, AppState.vietnamTimeZone)
                .labelsHidden()
                .padding(.horizontal, 12)

                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .background(app.palette.paper)
            .navigationTitle(app.T("Ngày & giờ", "Date & time"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(app.T("Hủy", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(app.T("Xong", "Done")) {
                        date = draftDate
                        time = draftTime
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Minimal wrapping row — SwiftUI has no stock flow layout before iOS 16's
/// Layout protocol, and the category chips need to wrap.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
