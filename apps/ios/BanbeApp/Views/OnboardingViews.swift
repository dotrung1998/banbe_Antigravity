import SwiftUI
import PhotosUI

/// Port of src/screens/Splash.jsx — the wordmark, the tagline, and a
/// spinner; tapping (or waiting) moves on to the language picker.
struct SplashView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var auth: AuthViewModel
    @State private var spin = false

    var body: some View {
        ZStack {
            app.palette.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                BanbeLogo(kind: .wordmark, width: 252)
                Text("bạn mới mỗi tuần")
                    .font(.system(size: 14))
                    .foregroundStyle(app.palette.ink)
                    .padding(.top, 16)
                Circle()
                    .trim(from: 0, to: 0.5)
                    .stroke(app.palette.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 28, height: 28)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 1.7).repeatForever(autoreverses: false), value: spin)
                    .padding(.top, 34)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { app.dismissSplash(isSignedIn: auth.isSignedIn) }
        .task {
            spin = true
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if app.screen == .splash { app.dismissSplash(isSignedIn: auth.isSignedIn) }
        }
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

    @State private var galleryItems: [StagedGalleryItem] = []
    @State private var coverItemID: String?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var photoError = ""
    @State private var seededForEventID: String?
    @State private var seededExistingIDs: Set<UUID> = []
    @State private var dateTimeSheetOpen = false

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

    @ViewBuilder
    private func gallerySection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(app.T("Hình ảnh", "Photos")).font(.system(size: 11.5))
                Spacer()
                Text("\(galleryItems.count)/\(maxPhotos)").font(.system(size: 10.5))
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(galleryItems) { item in
                    ZStack(alignment: .topTrailing) {
                        Group {
                            if let image = item.image {
                                Image(uiImage: image).resizable().scaledToFill()
                            } else {
                                AsyncImage(url: item.url) { $0.resizable().scaledToFill() } placeholder: { app.palette.field }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        Button { removeGalleryItem(item) } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(Color.black.opacity(0.55), in: Circle())
                        }
                        .padding(4)

                        VStack {
                            Spacer()
                            Button { coverItemID = item.id } label: {
                                Text(item.id == coverItemID ? app.T("Ảnh bìa", "Cover") : app.T("Đặt làm ảnh bìa", "Set as cover"))
                                    .font(.system(size: 9, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 3)
                                    .background(item.id == coverItemID ? app.palette.ink : app.palette.paper.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                                    .foregroundStyle(item.id == coverItemID ? app.palette.paper : app.palette.ink)
                            }
                            .padding(4)
                        }
                    }
                }
                if galleryItems.count < maxPhotos {
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: maxPhotos - galleryItems.count, matching: .images) {
                        Image(systemName: "plus")
                            .foregroundStyle(app.palette.ink)
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fill)
                            .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(app.palette.ink, style: StrokeStyle(lineWidth: 1, dash: [4])))
                    }
                }
            }
            if !photoError.isEmpty {
                Text(photoError).font(.system(size: 11.5)).foregroundStyle(BanbeTheme.alert)
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
            Text(app.T("Một đoạn giới thiệu dài hơn, hấp dẫn — tách dòng trống giữa các đoạn. Không phải quảng cáo giả, không phải \"Bao gồm\".",
                        "A longer, attractive write-up — leave a blank line between paragraphs. Not fabricated marketing copy, not the same as \"Included\"."))
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
            Text(app.T("Ngày & giờ (giờ Việt Nam)", "Date & time (Vietnam time)")).font(.system(size: 11.5))
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
        }
        .sheet(isPresented: $dateTimeSheetOpen) {
            EventDateTimeSheet(date: $app.createEventDate, time: $app.createEventTime)
                .environmentObject(app)
        }
    }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.hasHosted
                         ? app.T("Trang tổ chức của bạn", "Your host page")
                         : app.T("Trang tổ chức của bạn sẽ trông thế nào", "Preview your organizer page")) {
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
                               placeholder: app.T("Tên sự kiện của bạn", "Your event name"), text: $app.createName)
                    BanbeField(label: app.T("Mô tả", "Description"),
                               placeholder: app.T("Buổi này có gì?", "What happens?"), text: $app.createDesc)
                    introEditor()
                    BanbeField(label: app.T("Địa điểm", "Location"), placeholder: "Bình Thạnh", text: $app.createLoc)
                    dateTimeRow()
                    HStack(spacing: 10) {
                        BanbeField(label: app.T("Giá", "Price"), placeholder: "900.000", text: $app.createPrice,
                                   keyboard: .numberPad)
                        BanbeField(label: app.T("Số chỗ", "Seats"), placeholder: "14", text: $app.createSeats,
                                   keyboard: .numberPad)
                    }

                    Text(app.T("Hạng mục ▪︎ chọn tối đa 2", "Categories ▪︎ up to 2"))
                        .font(.system(size: 11.5))
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
                }

                gallerySection()

                // Excel bulk-create (Stage C) — the SAME bundled .xlsx web
                // downloads, generated by the one shared
                // scripts/generate-template.js. Download-only on iOS this
                // pass: parsing it back (.xlsx/.zip + embedded-image
                // extraction) needs a ZIP/XML capability this project
                // doesn't have yet, unlike web's JSZip dependency — adding
                // one is a real dependency decision, not made here without
                // asking first.
                if let templateURL = Bundle.main.url(forResource: "banbe_event_template", withExtension: "xlsx") {
                    ShareLink(item: templateURL) {
                        Text(app.T("Tải mẫu Excel để tạo hàng loạt", "Download the Excel template for bulk creation"))
                            .font(.system(size: 12.5))
                            .underline()
                            .foregroundStyle(app.palette.ink)
                    }
                    .padding(.top, 18)
                }

                // No SLA is actually monitored server-side — the previous
                // "duyệt sự kiện đầu tiên trong 48 giờ"/"reviews your first
                // event within 48 hours" copy promised a turnaround time
                // nothing enforced. Accurate instead of reassuring.
                InkButton(title: app.createSent
                          ? app.T("Đã gửi, đang chờ Banbe duyệt", "Submitted, waiting for Banbe to review")
                          : (app.loading ? app.T("Đang gửi…", "Submitting…")
                                         : (app.createEditEventId != nil
                                            ? app.T("Gửi lại để duyệt", "Resubmit for review")
                                            : app.T("Gửi để duyệt", "Submit for review"))),
                          enabled: !app.createName.trimmingCharacters(in: .whitespaces).isEmpty
                              && !app.createSent && !app.loading,
                          cornerRadius: 999) {
                    Task {
                        await app.submitCreateEvent(
                            newImages: newImagesInOrder, coverNewIndex: coverNewIndex,
                            removeExistingPhotoIDs: removedExistingIDs, existingCoverPath: existingCoverPath
                        )
                    }
                }
                .padding(.top, 26)

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

    init(date: Binding<Date?>, time: Binding<Date?>) {
        self._date = date
        self._time = time
        let calendar = Self.vnCalendar
        self._draftDate = State(initialValue: date.wrappedValue ?? calendar.startOfDay(for: Date()))
        self._draftTime = State(initialValue: time.wrappedValue ?? Date())
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
                    "", selection: $draftDate, in: Date()...,
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
