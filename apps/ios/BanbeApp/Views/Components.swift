import SwiftUI
import CoreImage.CIFilterBuiltins

/// A photo from the catalogue, loaded remotely from the deployed web app's
/// static assets (see PhotoCatalog / CatalogEvent.photoURL).
struct CatalogPhoto: View {
    let path: String
    var height: CGFloat?
    var width: CGFloat?
    var cornerRadius: CGFloat = 14

    @EnvironmentObject private var app: AppState

    var body: some View {
        // The frame comes from the placeholder rectangle, and the photo is
        // drawn as an overlay on top of it: an overlay can never change its
        // parent's size, whereas a loaded AsyncImage sized directly would
        // report its full pixel width and stretch the whole scroll view
        // sideways once it finished downloading.
        Rectangle()
            .fill(app.palette.field)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .overlay {
                AsyncImage(url: CatalogEvent.photoURL(path)) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    }
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// The on-photo state chip — "Saved", "Going", "Cancelled" and friends.
struct PhotoChip: View {
    let text: String
    var background: Color = BanbeTheme.Chip.saved
    var foreground: Color = .white

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.4)
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.5), lineWidth: 1)
            )
    }
}

/// The primary ink-filled action button used across the web screens.
struct InkButton: View {
    let title: String
    var enabled = true
    var cornerRadius: CGFloat = 18
    let action: () -> Void

    @EnvironmentObject private var app: AppState

    var body: some View {
        Button(action: { if enabled { action() } }) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    enabled ? app.palette.ink : app.palette.ink.opacity(0.16),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .foregroundStyle(enabled ? app.palette.paper : app.palette.ink)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// A labelled text field styled like the web app's glass fields.
struct BanbeField: View {
    let label: String?
    let placeholder: String
    @Binding var text: String
    var secure = false
    var keyboard: UIKeyboardType = .default

    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let label {
                Text(label).font(.system(size: 11.5)).foregroundStyle(app.palette.ink)
            }
            Group {
                if secure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(.system(size: 14))
            .keyboardType(keyboard)
            .autocorrectionDisabled()
            .textInputAutocapitalization(keyboard == .emailAddress ? .never : .sentences)
            .foregroundStyle(app.palette.ink)
            .padding(13)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

/// A back link ("‹ somewhere"), the web app's standard way back.
struct BackLink: View {
    let label: String
    let action: () -> Void
    @EnvironmentObject private var app: AppState

    var body: some View {
        Button(action: action) {
            Text("‹ \(label)")
                .font(.system(size: 12))
                .foregroundStyle(app.palette.ink)
        }
        .buttonStyle(.plain)
    }
}

/// A real, scannable QR of the booking id — the same value
/// check_in_guest() accepts, so the organizer's scanner reads it directly.
/// Fixed black-on-white whatever the theme: a phone camera doesn't know
/// about the app's palette.
struct QRCodeImage: View {
    let value: String
    var size: CGFloat = 76

    var body: some View {
        ZStack {
            Color.white
            if let image = Self.generate(value) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            }
        }
        .frame(width: size, height: size)
    }

    private static func generate(_ value: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        guard let output = filter.outputImage?.transformedBy(.init(scaleX: 10, y: 10)),
              let cgImage = context.createCGImage(output, from: output.extent)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

private extension CIImage {
    func transformedBy(_ transform: CGAffineTransform) -> CIImage { transformed(by: transform) }
}

/// Screen scaffold: paper background, the app's own top inset, and a
/// scrolling body — the shape nearly every web screen has.
struct ScreenScaffold<Content: View>: View {
    @EnvironmentObject private var app: AppState
    var scroll = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            app.palette.paper.ignoresSafeArea()
            if scroll {
                ScrollView {
                    // maxWidth pins the content to the viewport — without it
                    // any wide child (a photo, a long meta line) makes the
                    // whole page pan sideways.
                    content().frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                content().frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
