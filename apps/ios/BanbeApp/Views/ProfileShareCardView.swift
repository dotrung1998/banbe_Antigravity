import SwiftUI
import PhotosUI

/// How the shareable profile card looks — chosen by the person sharing, kept
/// on this device so the next share opens with the same look.
struct ShareCardStyle: Codable, Equatable {
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

    private static let key = "shareCardStyle.v1"
    static func load() -> ShareCardStyle {
        guard let d = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(ShareCardStyle.self, from: d) else { return .default }
        return s
    }
    func save() {
        if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Self.key) }
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

    @State private var style = ShareCardStyle.load()
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
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button(app.T("Đóng", "Close")) { dismiss() }.accessibilityIdentifier("\(idPrefix).shareCardClose")
            } }
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
                let target = CGSize(width: 680, height: 1040)
                let fmt = UIGraphicsImageRendererFormat.default(); fmt.scale = 1
                let scaled = UIGraphicsImageRenderer(size: target, format: fmt).image { _ in
                    let s = max(target.width / img.size.width, target.height / img.size.height)
                    let w = img.size.width * s, h = img.size.height * s
                    img.draw(in: CGRect(x: (target.width - w) / 2, y: (target.height - h) / 2, width: w, height: h))
                }
                style.photoJPEG = scaled.jpegData(compressionQuality: 0.8)
            }
        }
        .onChange(of: style) { _, s in s.save() }
    }

    private func shareImage() {
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let image = renderer.uiImage else { return }
        style.save()
        let vc = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        UIApplication.shared.topViewController?.present(vc, animated: true)
    }
}
