import SwiftUI
import PhotosUI

/// How the shareable profile card looks. Since the published-card pass the
/// design lives on the server (get_published_share_card/publish_share_card,
/// migration 155) — the owner edits a local draft and explicitly saves it.
struct ShareCardStyle: Equatable {
    var topHex: String
    var bottomHex: String
    var textHex: String
    /// Optional background photo (JPEG, already downscaled). Drawn under a
    /// dark scrim so text and avatar stay readable on any picture.
    var photoJPEG: Data?

    static let presets: [(name: String, nameEN: String, style: ShareCardStyle)] = [
        ("Hoàng hôn", "Sunset", .init(topHex: "#FF7E5F", bottomHex: "#C2185B", textHex: "#FFFFFF", photoJPEG: nil)),
        ("Đại dương", "Ocean", .init(topHex: "#2B86C5", bottomHex: "#1B2A6B", textHex: "#FFFFFF", photoJPEG: nil)),
        ("Rừng", "Forest", .init(topHex: "#56AB91", bottomHex: "#1F4D3F", textHex: "#FFFFFF", photoJPEG: nil)),
        ("Tím mộng", "Violet", .init(topHex: "#8E54E9", bottomHex: "#3B1F7A", textHex: "#FFFFFF", photoJPEG: nil)),
        ("Mực", "Ink", .init(topHex: "#3A3A3C", bottomHex: "#0E0E10", textHex: "#FFFFFF", photoJPEG: nil)),
        ("Giấy", "Paper", .init(topHex: "#FBF8F1", bottomHex: "#E9E2D2", textHex: "#1C1C1E", photoJPEG: nil)),
    ]
    static let `default` = presets[0].style

    /// Whole `data:` URL must stay under the server's 400000-char cap.
    static let maxPhotoBytes = 280_000

    /// Downscale + recompress so the base64 data URL fits the server cap.
    static func compressedJPEG(from img: UIImage) -> Data? {
        var size = CGSize(width: 680, height: 1040)
        for _ in 0..<4 {
            let fmt = UIGraphicsImageRendererFormat.default(); fmt.scale = 1
            let scaled = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
                let s = max(size.width / img.size.width, size.height / img.size.height)
                let w = img.size.width * s, h = img.size.height * s
                img.draw(in: CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h))
            }
            for q in [0.8, 0.65, 0.5, 0.4, 0.3] as [CGFloat] {
                if let d = scaled.jpegData(compressionQuality: q), d.count <= maxPhotoBytes { return d }
            }
            size = CGSize(width: size.width * 0.75, height: size.height * 0.75)
        }
        return nil
    }
}

/// Wire shape shared with web: { topHex, bottomHex, textHex, photo? } with
/// '#RRGGBB' uppercase hex and photo as a `data:image/...;base64,` URL.
struct PublishedShareCard: Codable {
    var topHex: String
    var bottomHex: String
    var textHex: String
    var photo: String?

    init(_ style: ShareCardStyle) {
        topHex = style.topHex.uppercased(); bottomHex = style.bottomHex.uppercased(); textHex = style.textHex.uppercased()
        photo = style.photoJPEG.map { "data:image/jpeg;base64," + $0.base64EncodedString() }
    }
    var style: ShareCardStyle {
        var data: Data?
        if let photo, photo.hasPrefix("data:"), let comma = photo.firstIndex(of: ",") {
            data = Data(base64Encoded: String(photo[photo.index(after: comma)...]))
        }
        return ShareCardStyle(topHex: topHex, bottomHex: bottomHex, textHex: textHex, photoJPEG: data)
    }
}

enum ShareCardService {
    /// nil on "nothing published" or on any failure (callers fall back to the default preset).
    static func fetch(kind: String, id: String) async -> ShareCardStyle? {
        struct Params: Encodable { let p_kind: String; let p_id: String }
        guard !id.isEmpty else { return nil }
        do {
            let card: PublishedShareCard? = try await SupabaseService.client
                .rpc("get_published_share_card", params: Params(p_kind: kind, p_id: id))
                .execute().value
            return card?.style
        } catch {
            print("get_published_share_card failed:", error)
            return nil
        }
    }

    /// Returns nil on success, otherwise an error code/message.
    static func publish(kind: String, id: String, style: ShareCardStyle) async -> String? {
        struct Params: Encodable { let p_kind: String; let p_id: String; let p_style: PublishedShareCard }
        struct Result: Decodable { let success: Bool?; let error: String? }
        do {
            let r: Result = try await SupabaseService.client
                .rpc("publish_share_card", params: Params(p_kind: kind, p_id: id, p_style: PublishedShareCard(style)))
                .execute().value
            return r.success == true ? nil : (r.error ?? "error")
        } catch {
            print("publish_share_card failed:", error)
            return error.localizedDescription
        }
    }
}

/// The card itself — one view used both for the on-screen preview and for the
/// image that actually gets shared (via ImageRenderer), so they can't drift.
struct ProfileShareCard: View {
    let style: ShareCardStyle
    let kindLabel: String
    let name: String
    let subtitle: String
    let detail: String
    let avatar: UIImage?
    let roundAvatar: Bool
    let link: URL
    let footnote: String

    static let size = CGSize(width: 340, height: 520)

    private var fg: Color { Color(hex: style.textHex) }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: style.topHex), Color(hex: style.bottomHex)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if let data = style.photoJPEG, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: Self.size.width, height: Self.size.height).clipped()
                LinearGradient(colors: [.black.opacity(0.25), .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
            }
            // Soft decorative glows — purely visual.
            Circle().fill(.white.opacity(0.14)).frame(width: 220).blur(radius: 40).offset(x: -110, y: -190)
            Circle().fill(.black.opacity(0.14)).frame(width: 240).blur(radius: 44).offset(x: 130, y: 220)

            VStack(spacing: 0) {
                HStack {
                    if let mark = UIImage(named: "banbe-wordmark") {
                        Image(uiImage: mark).renderingMode(.template).resizable().scaledToFit().frame(height: 24)
                    } else {
                        Text("banbe").font(.system(size: 16, weight: .bold))
                    }
                    Spacer()
                    Text(kindLabel.uppercased())
                        .font(.system(size: 10, weight: .semibold)).tracking(1.2)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .overlay(Capsule().stroke(fg.opacity(0.55)))
                }
                .padding(.top, 22)

                Spacer(minLength: 10)

                Group {
                    if let avatar {
                        Image(uiImage: avatar).resizable().scaledToFill()
                    } else {
                        ZStack {
                            fg.opacity(0.18)
                            Text(String(name.prefix(1)).uppercased()).font(.system(size: 38, weight: .semibold))
                        }
                    }
                }
                .frame(width: 92, height: 92)
                .clipShape(RoundedRectangle(cornerRadius: roundAvatar ? 46 : 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: roundAvatar ? 46 : 24, style: .continuous).stroke(fg.opacity(0.8), lineWidth: 3))
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)

                Text(name).font(.system(size: 26, weight: .bold)).lineLimit(2).multilineTextAlignment(.center).padding(.top, 14)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 14, weight: .medium)).opacity(0.85).lineLimit(1).padding(.top, 2)
                }
                if !detail.isEmpty {
                    Text(detail).font(.system(size: 12.5)).opacity(0.8).lineLimit(2).multilineTextAlignment(.center).padding(.top, 6)
                }

                Spacer(minLength: 14)

                QRCodeImage(value: link.absoluteString, size: 132)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                Text(footnote).font(.system(size: 11, weight: .medium)).opacity(0.85)
                    .multilineTextAlignment(.center).padding(.top, 10).padding(.bottom, 22)
            }
            .padding(.horizontal, 24)
            .foregroundStyle(fg)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

/// "Share profile": preview the card, restyle it, share it as an image.
struct ProfileShareSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let kindLabel: String
    let name: String
    let subtitle: String
    let detail: String
    let avatarURL: URL?
    let roundAvatar: Bool
    let link: URL
    let idPrefix: String
    /// "member" (cardID = profile handle) or "host" (cardID = organizer id).
    let cardKind: String
    let cardID: String
    /// Only the owner gets the editor; everyone else sees the published card read-only.
    let isOwner: Bool

    @State private var style = ShareCardStyle.default
    @State private var published = ShareCardStyle.default
    @State private var loaded = false
    @State private var saving = false
    @State private var saveError: String?
    @State private var avatar: UIImage?
    @State private var photoItem: PhotosPickerItem?

    private var footnote: String {
        app.T("Quét mã QR bằng camera điện thoại để mở trong ứng dụng banbe", "Scan with your phone camera to open this in the banbe app")
    }

    private var card: ProfileShareCard {
        ProfileShareCard(style: style, kindLabel: kindLabel, name: name, subtitle: subtitle, detail: detail,
                         avatar: avatar, roundAvatar: roundAvatar, link: link, footnote: footnote)
    }

    var body: some View {
        sheetBody
            // Hides the dock while the card is up, like Pulse does.
            .onAppear { BottomTabBarOverlay.shared.setShareCardOpen(true) }
            .onDisappear { BottomTabBarOverlay.shared.setShareCardOpen(false) }
    }

    private var sheetBody: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack { Spacer()
                        card
                            .scaleEffect(0.92)
                            .frame(width: ProfileShareCard.size.width * 0.92, height: ProfileShareCard.size.height * 0.92)
                            .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                            .contentShape(RoundedRectangle(cornerRadius: 28))
                            .onLongPressGesture(minimumDuration: 0.5) {
                                Haptics.light()
                                dismiss()
                                app.handleDeepLink(link)
                            }
                            .accessibilityIdentifier("\(idPrefix).shareCard")
                            .accessibilityHint(app.T("Nhấn giữ để mở trong ứng dụng", "Press and hold to open in the app"))
                        Spacer() }
                    Text(app.T("Nhấn giữ thẻ để mở ngay trong ứng dụng. Người nhận quét mã QR bằng camera điện thoại để mở trong ứng dụng banbe (cần cài sẵn ứng dụng).",
                               "Press and hold the card to open it in the app. Recipients scan the QR with their phone camera to open it in the banbe app (the app must be installed)."))
                        .font(.system(size: 11)).opacity(0.65)

                    if isOwner { Group {
                        Text(app.T("Phong cách", "Style")).font(.system(size: 11.5, weight: .semibold))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(ShareCardStyle.presets, id: \.nameEN) { p in
                                    Button {
                                        style.topHex = p.style.topHex; style.bottomHex = p.style.bottomHex
                                        style.textHex = p.style.textHex; style.photoJPEG = nil; photoItem = nil
                                    } label: {
                                        VStack(spacing: 5) {
                                            Circle().fill(LinearGradient(colors: [Color(hex: p.style.topHex), Color(hex: p.style.bottomHex)],
                                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                                                .frame(width: 38, height: 38)
                                                .overlay(Circle().stroke(app.palette.rule))
                                                .overlay(Circle().stroke(app.palette.ink, lineWidth: 2.5).padding(-3)
                                                    .opacity(style.photoJPEG == nil && style.topHex == p.style.topHex && style.bottomHex == p.style.bottomHex ? 1 : 0))
                                            Text(app.T(p.name, p.nameEN)).font(.system(size: 10.5))
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("\(idPrefix).preset.\(p.nameEN)")
                                }
                            }
                            .padding(.vertical, 4).padding(.horizontal, 4)
                        }

                        ColorPicker(app.T("Màu nền phía trên", "Background top"),
                                    selection: Binding(get: { Color(hex: style.topHex) }, set: { style.topHex = $0.hexString }),
                                    supportsOpacity: false).font(.system(size: 13))
                        ColorPicker(app.T("Màu nền phía dưới", "Background bottom"),
                                    selection: Binding(get: { Color(hex: style.bottomHex) }, set: { style.bottomHex = $0.hexString }),
                                    supportsOpacity: false).font(.system(size: 13))
                        ColorPicker(app.T("Màu chữ", "Text colour"),
                                    selection: Binding(get: { Color(hex: style.textHex) }, set: { style.textHex = $0.hexString }),
                                    supportsOpacity: false).font(.system(size: 13))

                        HStack(spacing: 10) {
                            let bgTitle = style.photoJPEG == nil ? app.T("Ảnh nền", "Background photo") : app.T("Đổi ảnh nền", "Change photo")
                            let ruleColor = app.palette.rule
                            PhotosPicker(selection: $photoItem, matching: .images) {
                                Label(bgTitle, systemImage: "photo")
                                    .font(.system(size: 13, weight: .semibold))
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .overlay(Capsule().stroke(ruleColor))
                            }
                            .accessibilityIdentifier("\(idPrefix).pickPhoto")
                            if style.photoJPEG != nil {
                                Button(app.T("Bỏ ảnh", "Remove")) { style.photoJPEG = nil; photoItem = nil }.font(.system(size: 13))
                            }
                        }

                    }.disabled(!loaded) }

                    if isOwner && loaded && style != published {
                        Button { Task { await saveCard() } } label: {
                            Text(saving ? app.T("Đang lưu…", "Saving…") : app.T("Lưu thẻ", "Save Card"))
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, 15)
                                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(app.palette.ink, lineWidth: 1.5))
                                .foregroundStyle(app.palette.ink)
                        }
                        .disabled(saving)
                        .accessibilityIdentifier("\(idPrefix).saveCard")
                    }
                    if let saveError {
                        Text(saveError).font(.system(size: 11.5)).foregroundStyle(BanbeTheme.alert)
                    }

                    Button { shareImage() } label: {
                        Text(app.T("Chia sẻ thẻ", "Share card"))
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .foregroundStyle(app.palette.paper)
                    }
                    .accessibilityIdentifier("\(idPrefix).shareCardSend")
                }
                .padding(20)
                .foregroundStyle(app.palette.ink)
            }
            .background(app.palette.paper.ignoresSafeArea())
            .navigationTitle(app.T("Thẻ chia sẻ", "Share card"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                if #available(iOS 26.0, *) {
                    Button(role: .close) { dismiss() }.accessibilityIdentifier("\(idPrefix).shareCardClose")
                } else {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(app.palette.ink)
                            .frame(width: 30, height: 30)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel(app.T("Đóng", "Close"))
                    .accessibilityIdentifier("\(idPrefix).shareCardClose")
                }
            } }
        }
        .presentationDragIndicator(.visible)
        .task {
            let fetched = await ShareCardService.fetch(kind: cardKind, id: cardID) ?? .default
            published = fetched; style = fetched; loaded = true
        }
        .task {
            guard let avatarURL, avatar == nil,
                  let (data, _) = try? await URLSession.shared.data(from: avatarURL) else { return }
            avatar = UIImage(data: data)
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else { return }
                style.photoJPEG = ShareCardStyle.compressedJPEG(from: img)
            }
        }
    }

    private func saveCard() async {
        saving = true; saveError = nil
        let toSave = style
        if let err = await ShareCardService.publish(kind: cardKind, id: cardID, style: toSave) {
            saveError = app.T("Không lưu được thẻ (\(err)).", "Couldn't save the card (\(err)).")
        } else {
            published = toSave
        }
        saving = false
    }

    private func shareImage() {
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let image = renderer.uiImage else { return }
        let vc = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        UIApplication.shared.topViewController?.present(vc, animated: true)
    }
}
