import SwiftUI
import PhotosUI
import PassKit

/// "Add to Apple Wallet": pick how the card looks, then hand it to Wallet.
/// Wallet draws the layout itself, so the choices are the colours and an
/// optional banner image behind the event name.
struct WalletPassDesignView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let bookingID: UUID
    let eventName: String
    let venue: String

    @State private var style = WalletPassStyle.load()
    @State private var bannerItem: PhotosPickerItem?
    @State private var busy = false
    @State private var error = ""

    private var bg: Color { Color(hex: style.backgroundHex) }
    private var fg: Color { Color(hex: style.foregroundHex) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    preview

                    Text(app.T("Màu nền có sẵn", "Colour presets")).font(.system(size: 11.5, weight: .semibold))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(WalletPassStyle.presets, id: \.nameEN) { preset in
                                Button {
                                    style.backgroundHex = preset.style.backgroundHex
                                    style.foregroundHex = preset.style.foregroundHex
                                } label: {
                                    VStack(spacing: 5) {
                                        Circle().fill(Color(hex: preset.style.backgroundHex))
                                            .frame(width: 38, height: 38)
                                            .overlay(Circle().stroke(app.palette.rule))
                                            .overlay(Circle().stroke(app.palette.ink, lineWidth: 2.5).padding(-3)
                                                .opacity(style.backgroundHex == preset.style.backgroundHex ? 1 : 0))
                                        Text(app.T(preset.name, preset.nameEN)).font(.system(size: 10.5))
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("wallet.preset.\(preset.nameEN)")
                            }
                        }
                        .padding(.vertical, 4).padding(.horizontal, 4)
                    }

                    ColorPicker(app.T("Màu nền tự chọn", "Custom background"),
                                selection: Binding(get: { bg }, set: { style.backgroundHex = $0.hexString }),
                                supportsOpacity: false)
                        .font(.system(size: 13))
                    ColorPicker(app.T("Màu chữ", "Text colour"),
                                selection: Binding(get: { fg }, set: { style.foregroundHex = $0.hexString }),
                                supportsOpacity: false)
                        .font(.system(size: 13))

                    Text(app.T("Ảnh banner", "Banner image")).font(.system(size: 11.5, weight: .semibold)).padding(.top, 4)
                    HStack(spacing: 10) {
                        PhotosPicker(selection: $bannerItem, matching: .images) {
                            Label(style.bannerPNG == nil ? app.T("Chọn ảnh", "Choose a photo") : app.T("Đổi ảnh", "Change photo"),
                                  systemImage: "photo")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .overlay(Capsule().stroke(app.palette.rule))
                        }
                        .accessibilityIdentifier("wallet.pickBanner")
                        if style.bannerPNG != nil {
                            Button(app.T("Bỏ ảnh", "Remove")) { style.bannerPNG = nil; bannerItem = nil }
                                .font(.system(size: 13))
                        }
                    }
                    Text(app.T("Ảnh được cắt giữa theo khung ngang của thẻ. Mã QR luôn hiển thị rõ ở dưới.",
                               "The photo is centre-cropped to the card's wide banner. The QR code always stays plain and scannable below it."))
                        .font(.system(size: 10.5)).opacity(0.65)

                    if !error.isEmpty {
                        Text(error).font(.system(size: 12)).foregroundStyle(BanbeTheme.alert)
                    }

                    Button { Task { await add() } } label: {
                        HStack {
                            if busy { ProgressView().tint(app.palette.paper) }
                            Text(app.T("Thêm vào Apple Wallet", "Add to Apple Wallet"))
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .foregroundStyle(app.palette.paper)
                    }
                    .disabled(busy)
                    .accessibilityIdentifier("wallet.add")
                }
                .padding(20)
                .foregroundStyle(app.palette.ink)
            }
            .background(app.palette.paper.ignoresSafeArea())
            .navigationTitle(app.T("Thiết kế thẻ Wallet", "Design your Wallet card"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(app.T("Đóng", "Close")) { dismiss() } } }
        }
        .onChange(of: bannerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data),
                   let png = WalletPassService.bannerPNG(from: image) {
                    style.bannerPNG = png
                }
            }
        }
    }

    /// Approximation of what Wallet will draw; Wallet's own rendering is final.
    private var preview: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                // The same wordmark as the Home header, tinted like Wallet will.
                if let mark = UIImage(named: "banbe-wordmark") {
                    Image(uiImage: mark).renderingMode(.template).resizable().scaledToFit()
                        .frame(height: 26).accessibilityLabel("banbe")
                } else {
                    Text("banbe").font(.system(size: 14, weight: .bold))
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 14)
            if let png = style.bannerPNG, let image = UIImage(data: png) {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(height: 96).clipped().padding(.top, 10)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(app.T("SỰ KIỆN", "EVENT")).font(.system(size: 9, weight: .semibold)).opacity(0.7)
                Text(eventName).font(.system(size: 20, weight: .semibold)).lineLimit(2)
                if !venue.isEmpty {
                    Text(venue).font(.system(size: 12)).opacity(0.85).padding(.top, 2)
                }
            }
            .padding(16)
            HStack { Spacer()
                Image(systemName: "qrcode").font(.system(size: 54))
                    .padding(8).background(.white, in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(.black)
                Spacer()
            }
            .padding(.bottom, 16)
        }
        .foregroundStyle(fg)
        .background(bg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .accessibilityIdentifier("wallet.preview")
    }

    private func add() async {
        busy = true
        error = ""
        defer { busy = false }
        do {
            style.save()
            let pass = try await WalletPassService.fetchPass(bookingID: bookingID, style: style)
            guard let controller = PKAddPassesViewController(pass: pass) else {
                error = WalletPassError.notAvailable.message(isEN: app.isEN)
                return
            }
            UIApplication.shared.topViewController?.present(controller, animated: true)
        } catch let e as WalletPassError {
            error = e.message(isEN: app.isEN)
        } catch {
            self.error = WalletPassError.server("").message(isEN: app.isEN)
        }
    }
}
