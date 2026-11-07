import SwiftUI

// MARK: - Shared helpers

/// The tappable "Answer Survey" button drawn over an edited survey story's card,
/// exactly where the card's own (invisible) button sits, so the story looks
/// like the regular survey story but can still carry text and be edited.
struct StorySurveyHotspot: View {
    static let cardSize = CGSize(width: 340, height: 460)
    let label: String
    let urlString: String
    var interactive: Bool
    @EnvironmentObject private var app: AppState
    @Environment(\.openURL) private var openURL

    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / 360                 // canvas is 360x640
            let button = Text(label.isEmpty ? app.T("Trả lời khảo sát", "Answer Survey") : label)
                .font(.system(size: 14 * k, weight: .bold))
                .frame(width: 304 * k, height: 43 * k)
                .foregroundStyle(app.palette.paper)
                .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 12 * k, style: .continuous))
            Group {
                if interactive, let url = URL(string: urlString) {
                    Button { openURL(url) } label: { button }.buttonStyle(.plain)
                        .accessibilityIdentifier("story.viewer.link")
                } else { button }
            }
            // card bottom = 550, 18pt padding, 43pt button -> centre at ~510.5 of 640
            .position(x: geo.size.width / 2, y: geo.size.height * (510.5 / 640))
        }
    }
}

enum StoryLink {
    static func isSurveyAnswer(_ s: String?) -> Bool { s?.hasPrefix("banbe://survey/") == true }

    /// Trims, adds https:// when no scheme was typed, and only accepts
    /// http(s)/banbe — anything else (javascript:, tel:, a bare word) is
    /// rejected so a story link can never be a surprise action.
    static func normalized(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let withScheme = t.contains("://") ? t : "https://" + t
        guard let url = URL(string: withScheme), let scheme = url.scheme?.lowercased(),
              ["http", "https", "banbe"].contains(scheme),
              scheme == "banbe" || (url.host?.contains(".") ?? false),
              withScheme.count <= 500 else { return nil }
        return withScheme
    }
}

private extension Color {
    var isLight: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (0.299 * r + 0.587 * g + 0.114 * b) > 0.6
    }
}

private struct StoryStickerText: View {
    let overlay: StoryOverlay
    let canvasWidth: CGFloat

    var body: some View {
        let color = Color(hex: overlay.colorHex)
        Text(overlay.text)
            .font(.system(size: 24 * overlay.scale * canvasWidth / 360, weight: .bold))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .padding(.horizontal, overlay.background ? 10 : 0).padding(.vertical, overlay.background ? 5 : 0)
            .background(overlay.background ? (color.isLight ? Color.black.opacity(0.6) : Color.white.opacity(0.9)) : .clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(overlay.background ? 0 : 0.45), radius: 3)
            .frame(maxWidth: canvasWidth * 0.9)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Read-only overlay layer; apply as `.overlay` on the fitted media image so
/// it matches the media frame exactly.
struct StoryOverlayLayer: View {
    let overlays: [StoryOverlay]

    var body: some View {
        GeometryReader { geo in
            ForEach(overlays) { o in
                StoryStickerText(overlay: o, canvasWidth: geo.size.width)
                    .position(x: o.x * geo.size.width, y: o.y * geo.size.height)
            }
        }
        .allowsHitTesting(false)
    }
}

/// The tappable link pill shown on a story with a link.
struct StoryLinkPill: View {
    let urlString: String
    let label: String?
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let url = URL(string: urlString) {
            Button { openURL(url) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "link").font(.system(size: 12, weight: .semibold))
                    Text((label?.isEmpty == false ? label! : url.host ?? urlString))
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.white, in: Capsule())
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("story.viewer.link")
        }
    }
}

// MARK: - Editor

private struct EditableSticker: View {
    @Binding var overlay: StoryOverlay
    let canvas: CGSize
    let onTap: () -> Void
    @State private var startScale: Double?

    var body: some View {
        StoryStickerText(overlay: overlay, canvasWidth: canvas.width)
            .contentShape(Rectangle())
            .position(x: overlay.x * canvas.width, y: overlay.y * canvas.height)
            .onTapGesture(perform: onTap)
            .gesture(
                DragGesture(coordinateSpace: .named("storyCanvas"))
                    .onChanged { v in
                        overlay.x = min(1, max(0, v.location.x / canvas.width))
                        overlay.y = min(1, max(0, v.location.y / canvas.height))
                    }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { v in
                        if startScale == nil { startScale = overlay.scale }
                        overlay.scale = min(4, max(0.4, (startScale ?? 1) * v.magnification))
                    }
                    .onEnded { _ in startScale = nil }
            )
            .accessibilityIdentifier("story.editor.sticker")
    }
}

private struct LinkEditSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var url: String
    @State private var label: String
    @State private var invalid = false

    init(url: String, label: String) {
        _url = State(initialValue: url); _label = State(initialValue: label)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(app.T("Thêm liên kết", "Add a link")).font(.system(size: 16, weight: .semibold))
            TextField("https://…", text: $url)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                .padding(12).background(app.palette.field, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("story.editor.linkURL")
            TextField(app.T("Tên nút (tuỳ chọn)", "Button text (optional)"), text: $label)
                .padding(12).background(app.palette.field, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("story.editor.linkLabel")
            if invalid {
                Text(app.T("Liên kết không hợp lệ. Dùng địa chỉ http(s)://…", "That link isn't valid. Use an http(s):// address."))
                    .font(.system(size: 12)).foregroundStyle(BanbeTheme.alert)
            }
            HStack {
                if !app.storyDraftLinkURL.isEmpty {
                    Button(role: .destructive) {
                        app.storyDraftLinkURL = ""; app.storyDraftLinkLabel = ""; dismiss()
                    } label: { Label(app.T("Xóa liên kết", "Remove link"), systemImage: "trash") }
                }
                Spacer()
                Button {
                    if url.trimmingCharacters(in: .whitespaces).isEmpty {
                        app.storyDraftLinkURL = ""; app.storyDraftLinkLabel = ""; dismiss()
                    } else if let ok = StoryLink.normalized(url) {
                        app.storyDraftLinkURL = ok; app.storyDraftLinkLabel = label; dismiss()
                    } else { invalid = true }
                } label: {
                    Text(app.T("Xong", "Done")).font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 22).padding(.vertical, 10)
                        .background(app.palette.ink, in: Capsule()).foregroundStyle(app.palette.paper)
                }
                .accessibilityIdentifier("story.editor.linkDone")
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .foregroundStyle(app.palette.ink)
        .background(app.palette.paper.ignoresSafeArea())
    }
}

/// Full-screen story editor — create (new photo) or edit (posted story).
/// The photo fills the whole screen (aspect-fit, edge to edge); the controls
/// float over it on soft scrims instead of taking their own bars. Text is
/// edited inline on the photo, so it's never hidden behind a sheet.
struct StoryEditorView: View {
    @EnvironmentObject var app: AppState
    @State private var editingID: String?
    @State private var linkSheet = false
    @State private var failed = false
    /// Tracked by hand: this cover doesn't get automatic keyboard avoidance,
    /// which left the colour row underneath the keyboard.
    @State private var keyboardHeight: CGFloat = 0

    private var isEditing: Bool { app.storyEditingID != nil }

    /// Real device insets (the cover doesn't reliably report a safe area).
    private var insets: UIEdgeInsets {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first(where: \.isKeyWindow)?.safeAreaInsets ?? .zero
    }

    private func fitted(_ image: UIImage, in size: CGSize) -> CGSize {
        guard image.size.width > 0, image.size.height > 0 else { return size }
        let s = min(size.width / image.size.width, size.height / image.size.height)
        return CGSize(width: image.size.width * s, height: image.size.height * s)
    }

    /// Looks the overlay up by id on every access, so deleting it while this
    /// binding is still alive can never index out of range.
    private func binding(for id: String) -> Binding<StoryOverlay> {
        Binding(
            get: { app.storyDraftOverlays.first(where: { $0.id == id }) ?? StoryOverlay(id: id, text: "") },
            set: { new in
                if let i = app.storyDraftOverlays.firstIndex(where: { $0.id == id }) { app.storyDraftOverlays[i] = new }
            })
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            canvas.ignoresSafeArea()      // photo ignores the keyboard too — it never rescales

            if editingID == nil {
                VStack(spacing: 0) {
                    topBar
                        .background(LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
                    Spacer()
                    bottomBar
                        .background(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
                }
            }
            if let id = editingID { textEditor(id: id) }
        }
        .ignoresSafeArea()
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
            let screenH = UIScreen.main.bounds.height
            withAnimation(.easeOut(duration: 0.25)) { keyboardHeight = max(0, screenH - end.minY) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.25)) { keyboardHeight = 0 }
        }
        .sheet(isPresented: $linkSheet) {
            LinkEditSheet(url: app.storyDraftLinkURL, label: app.storyDraftLinkLabel)
                .presentationDetents([.height(330)])
        }
        .alert(app.T("Không đăng được story", "Couldn't save the story"), isPresented: $failed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.T("Vui lòng thử lại.", "Please try again."))
        }
    }

    @ViewBuilder private var canvas: some View {
        if let image = app.storyCreatePreviewImage {
            GeometryReader { geo in
                let size = fitted(image, in: geo.size)
                ZStack {
                    Image(uiImage: image).resizable().frame(width: size.width, height: size.height)
                    if StoryLink.isSurveyAnswer(app.storyDraftLinkURL) {
                        StorySurveyHotspot(label: app.storyDraftLinkLabel, urlString: app.storyDraftLinkURL, interactive: false)
                            .frame(width: size.width, height: size.height)
                    }
                    ForEach($app.storyDraftOverlays) { $o in
                        if o.id != editingID {   // the one being edited is drawn by the inline editor
                            EditableSticker(overlay: $o, canvas: size) { editingID = o.id }
                        }
                    }
                }
                .frame(width: size.width, height: size.height)
                .coordinateSpace(name: "storyCanvas")
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
    }

    // MARK: Inline text editing

    private let swatches = ["#FFFFFF", "#000000", "#FFD60A", "#FF453A", "#FF9F0A", "#30D158", "#0A84FF", "#BF5AF2"]

    private func closeTextEditor(_ id: String) {
        if let o = app.storyDraftOverlays.first(where: { $0.id == id }),
           o.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            app.storyDraftOverlays.removeAll { $0.id == id }
        }
        editingID = nil
    }

    private func textEditor(id: String) -> some View {
        let o = binding(for: id)
        return ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { closeTextEditor(id) }
            VStack(spacing: 0) {
                Spacer()
                StoryInlineTextField(overlay: o)
                    .padding(.horizontal, 24)
                Spacer()
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        ForEach(swatches, id: \.self) { hex in
                            Button { o.wrappedValue.colorHex = hex } label: {
                                Circle().fill(Color(hex: hex)).frame(width: 28, height: 28)
                                    .overlay(Circle().stroke(Color.white.opacity(0.5)))
                                    .overlay(Circle().stroke(Color.white, lineWidth: 2).padding(-3)
                                        .opacity(o.wrappedValue.colorHex == hex ? 1 : 0))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack {
                        Button {
                            // Close first, then remove — nothing is left pointing at the row.
                            editingID = nil
                            app.storyDraftOverlays.removeAll { $0.id == id }
                        } label: {
                            Image(systemName: "trash").font(.system(size: 16, weight: .semibold))
                                .frame(width: 46, height: 46).background(Color.white.opacity(0.3), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(app.T("Xóa", "Delete"))
                        .accessibilityIdentifier("story.editor.textDelete")
                        Button { o.wrappedValue.background.toggle() } label: {
                            Text("A").font(.system(size: 17, weight: .bold))
                                .foregroundStyle(o.wrappedValue.background ? .black : .white)
                                .frame(width: 44, height: 44)
                                .background(o.wrappedValue.background ? Color.white : Color.white.opacity(0.18), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(app.T("Nền cho chữ", "Text background"))
                        Spacer()
                        Button { closeTextEditor(id) } label: {
                            Text(app.T("Xong", "Done")).font(.system(size: 14, weight: .semibold))
                                .padding(.horizontal, 22).frame(minHeight: 44)
                                .background(Color.white, in: Capsule()).foregroundStyle(.black)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("story.editor.textDone")
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20).padding(.bottom, (keyboardHeight > 0 ? keyboardHeight : max(insets.bottom, 12)) + 12)
            }
            .padding(.top, max(insets.top, 20))
        }
    }

    // MARK: Bars

    private func editorPill(icon: String, title: String, id: String, highlighted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 16, weight: .bold))
                Text(title).font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(Color.black)
            .padding(.horizontal, 18).frame(minHeight: 46)
            .background(highlighted ? Color(hex: 0xFFD60A) : Color.white, in: Capsule())
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { app.clearStoryDraft() } label: {
                Image(systemName: "xmark").font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 46, height: 46)
                    .background(Color.white, in: Circle())
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(app.T("Hủy", "Cancel"))
            .accessibilityIdentifier("story.editor.cancel")
            Spacer()
            editorPill(icon: "textformat", title: app.T("Chữ", "Text"), id: "story.editor.addText") {
                let o = StoryOverlay(text: "", x: 0.5, y: 0.4)
                app.storyDraftOverlays.append(o)
                editingID = o.id
            }
            editorPill(icon: "link", title: app.storyDraftLinkURL.isEmpty ? app.T("Liên kết", "Link") : app.T("Sửa liên kết", "Edit link"),
                       id: "story.editor.addLink", highlighted: !app.storyDraftLinkURL.isEmpty) { linkSheet = true }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.top, max(insets.top, 20) + 4).padding(.bottom, 16)
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if !app.storyDraftLinkURL.isEmpty && !StoryLink.isSurveyAnswer(app.storyDraftLinkURL) {
                StoryLinkPill(urlString: app.storyDraftLinkURL, label: app.storyDraftLinkLabel).allowsHitTesting(false)
            }
            Text(app.T("Chạm chữ để sửa · kéo để di chuyển · chụm hai ngón để đổi cỡ",
                       "Tap text to edit · drag to move · pinch to resize"))
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.75))
            HStack(spacing: 10) {
                if !isEditing {
                    Button {
                        app.storyCreatePreviewImage = nil
                        app.storyCameraOpen = true
                    } label: {
                        Text(app.T("Chụp lại", "Retake"))
                            .font(.system(size: 15, weight: .bold))
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .foregroundStyle(.white)
                            .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white, lineWidth: 1.5))
                    }
                    .accessibilityIdentifier("story.retake")
                }
                Button {
                    Task { if await !app.publishStory() { failed = true } }
                } label: {
                    Text(app.storyCreateBusy ? app.T("Đang lưu…", "Saving…")
                         : isEditing ? app.T("Lưu thay đổi", "Save changes") : app.T("Đăng story", "Post story"))
                        .font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .foregroundStyle(.black)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                        .opacity(app.storyCreateBusy ? 0.6 : 1)
                }
                .disabled(app.storyCreateBusy)
                .accessibilityIdentifier("story.usePhoto")
            }
        }
        .padding(.horizontal, 22).padding(.top, 24).padding(.bottom, max(insets.bottom, 12) + 6)
    }
}

/// The text being typed, drawn exactly as it will look on the story.
private struct StoryInlineTextField: View {
    @Binding var overlay: StoryOverlay
    @FocusState private var focused: Bool

    var body: some View {
        let color = Color(hex: overlay.colorHex)
        TextField("", text: $overlay.text, prompt: Text("Aa").foregroundColor(.white.opacity(0.5)), axis: .vertical)
            .lineLimit(1...5)
            .font(.system(size: 28 * overlay.scale, weight: .bold))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .padding(.horizontal, overlay.background ? 12 : 0).padding(.vertical, overlay.background ? 6 : 0)
            .background(overlay.background ? (color.isLight ? Color.black.opacity(0.6) : Color.white.opacity(0.9)) : .clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .focused($focused)
            .onAppear { focused = true }
            .accessibilityIdentifier("story.editor.textField")
    }
}

// MARK: - Event → story (edit first)

/// The 9:16 card an event becomes when a host posts it as a story. It is
/// rendered to an image and handed to the normal story editor, so the host
/// can add text/a link before anything is published.
private struct StoryEventCard: View {
    let name: String
    let when: String
    let place: String
    let cover: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color(hex: 0x3A2A1A), Color(hex: 0x14120E)], startPoint: .top, endPoint: .bottom)
            if let cover {
                Image(uiImage: cover).resizable().scaledToFill().frame(width: 360, height: 640).clipped()
            }
            LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.78)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 8) {
                Text(name).font(.system(size: 34, weight: .bold)).lineLimit(3)
                if !when.isEmpty { Text(when).font(.system(size: 16, weight: .semibold)).opacity(0.95) }
                if !place.isEmpty { Text(place).font(.system(size: 14)).opacity(0.85).lineLimit(2) }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24).padding(.bottom, 56)
            VStack { HStack {
                // The Home-screen wordmark, tinted white like the profile share card.
                if let mark = UIImage(named: "banbe-wordmark") {
                    Image(uiImage: mark).renderingMode(.template).resizable().scaledToFit().frame(height: 26)
                } else {
                    Text("banbe").font(.system(size: 20, weight: .heavy))
                }
                Spacer()
            }.padding(.horizontal, 16).padding(.top, 22); Spacer() }
        }
        .frame(width: 360, height: 640)
    }
}

extension AppState {
    /// Turns one of the host's events into a story draft and opens the editor
    /// (nothing is published until the host taps "Post story").
    func beginEventStory(_ ev: CatalogEvent) async {
        var cover: UIImage?
        if let url = ev.imageURL, let (data, _) = try? await URLSession.shared.data(from: url) {
            cover = UIImage(data: data)
        }
        // `where` is a composite ("Area ▪︎ 0,0 km from you ▪︎ date ▪︎ time") —
        // keep only the area; the date already has its own line and the
        // distance is personal to whoever is looking.
        // (Split on the scalar, not the String: "▪︎" is one grapheme with a variation
        // selector, which String.components(separatedBy: "▪") does not match.)
        let area = String(String.UnicodeScalarView(ev.where.unicodeScalars.prefix { $0.value != 0x25AA }))
            .trimmingCharacters(in: .whitespaces)
        let card = StoryEventCard(name: ev.name, when: ev.when, place: area, cover: cover)
        let renderer = await MainActor.run { () -> UIImage? in
            let r = ImageRenderer(content: card)
            r.scale = 3
            return r.uiImage
        }
        guard let image = renderer else { return }
        storyDraftOverlays = []
        storyDraftLinkURL = "banbe://event/\(ev.key)"
        storyDraftLinkLabel = T("Xem sự kiện", "View event")
        storyEditingID = nil
        storyCreatePreviewImage = image
    }
}

// MARK: - Owner "⋯" menu (UIKit button, native menu)

/// A native menu button that reports the moment it's touched. SwiftUI's `Menu`
/// swallows touches, so nothing could pause the story when it opened; a
/// UIButton with a primary-action menu looks and behaves the same but lets us
/// hook the touch-down.
struct StoryOwnerMenuButton: UIViewRepresentable {
    /// Only photo stories have text/link to edit; survey/event shares can only be deleted.
    let canEdit: Bool
    let editTitle: String
    let deleteTitle: String
    let confirmTitle: String
    let onTouchDown: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    final class Coordinator {
        var onTouchDown: () -> Void = {}
        var onEdit: () -> Void = {}
        var onDelete: () -> Void = {}
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIButton {
        let c = context.coordinator
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "ellipsis", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .bold))
        config.baseForegroundColor = .white
        let button = UIButton(configuration: config)
        button.accessibilityIdentifier = "story.viewer.menu"
        button.showsMenuAsPrimaryAction = true
        button.addAction(UIAction { _ in c.onTouchDown() }, for: .touchDown)
        let edit = UIAction(title: editTitle, image: UIImage(systemName: "pencil")) { _ in c.onEdit() }
        let confirm = UIAction(title: confirmTitle, image: UIImage(systemName: "trash"), attributes: .destructive) { _ in c.onDelete() }
        // The confirmation pops out of the "Delete" row as a submenu.
        let delete = UIMenu(title: deleteTitle, image: UIImage(systemName: "trash"), children: [confirm])
        let items: [UIMenuElement] = canEdit ? [edit, delete] : [delete]
        // `touchDown` alone isn't reliably sent for a primary-action menu; the
        // deferred provider below runs every time the menu is about to show.
        let opening = UIDeferredMenuElement.uncached { completion in
            DispatchQueue.main.async { c.onTouchDown() }
            completion(items)
        }
        button.menu = UIMenu(children: [opening])
        button.addAction(UIAction { _ in c.onTouchDown() }, for: .menuActionTriggered)
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {
        let c = context.coordinator
        c.onTouchDown = onTouchDown; c.onEdit = onEdit; c.onDelete = onDelete
    }
}
