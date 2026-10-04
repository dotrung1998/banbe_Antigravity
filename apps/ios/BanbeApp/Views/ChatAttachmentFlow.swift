import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// ONE attachment flow, shared by every composer in this app.
///
/// Extracted from `ChatView` (MessagingViews.swift), which used to own the
/// whole thing inline: the "+" `Menu`, its two options, the `.fileImporter`
/// and `CameraPicker` presentations, and the security-scoped read / JPEG
/// re-encode that turns whatever the user picked into bytes safe to upload.
/// The temporary REFUND dispute composer (DisputeChatPanel.swift) needed the
/// exact same experience, so the pieces live here instead of being rebuilt —
/// a second, subtly different picker would silently drift on menu wording,
/// accepted file types or the size cap, and the two chats would stop looking
/// like the same product.
///
/// What this deliberately does NOT contain: anything about where the bytes go.
/// `onPick` hands a finished `AttachmentPayload` to its caller, which owns the
/// upload (bucket, message row, error copy, cleanup) — normal chat sends into
/// `messages` + `chat-attachments`, a dispute sends into `dispute_messages` +
/// `dispute-attachments`. Nothing here can send a message on its own.
enum ChatAttachment {
    /// Allowed picker types. Deliberately identical to what ChatView accepted
    /// before this was extracted: photos and PDFs, nothing else. Both storage
    /// buckets allow-list image/jpeg, image/png, image/webp and
    /// application/pdf server-side, so widening this here would only move the
    /// rejection to the upload.
    static let contentTypes: [UTType] = [.image, .pdf]
}

/// A finished, upload-ready attachment: the bytes plus everything the
/// message row needs to render them (MIME type, extension and — for images —
/// the pixel size of the data that actually got re-encoded, so a preview can
/// be built at the source image's own ratio).
struct AttachmentPayload {
    let data: Data
    let contentType: String
    let fileExtension: String
    let width: Int?
    let height: Int?

    var isImage: Bool { contentType.hasPrefix("image/") }
}

/// The "+" attach button and both of its pickers.
///
/// Used verbatim by the booking conversation's composer and by the temporary
/// refund dispute composer, so "attach a photo here" is literally the same
/// view in both places: same two menu rows, same `Menu` presentation (and so
/// the same open/close animation, Liquid Glass appearance, anchoring and
/// outside-tap dismissal as every other menu in this app), same accepted file
/// types, same downscale cap, same disabled-while-uploading affordance.
///
/// - Parameters:
///   - isEnabled: false when this composer can't attach anything right now —
///     ChatView passes "no thread open", the dispute composer adds "this
///     dispute is closed". A dimmed button.
///   - isSending: an upload is already running. The button is inert for the
///     duration (so a double tap can't start a second upload) but stays at
///     full opacity, exactly as ChatView's own button always did.
///   - onPick: receives the finished payload; the caller performs the upload.
///   - onFailure: called with a human-readable reason when a pick produced
///     nothing uploadable (unreadable file, an image too large to re-encode).
///     Normal chat passes nil and keeps its historical silence; the dispute
///     composer surfaces the reason next to its own send errors.
struct ChatAttachButton: View {
    @EnvironmentObject private var app: AppState
    let isEnabled: Bool
    let isSending: Bool
    let onPick: (AttachmentPayload) async -> Void
    var onFailure: ((String) -> Void)? = nil
    /// Same identifier ChatView's own inline button has always exposed, so UI
    /// automation matching "any one of these" lookups keeps resolving.
    var accessibilityIdentifier: String = "chat.attach"

    @State private var fileImporterOpen = false
    @State private var cameraOpen = false

    var body: some View {
        Menu {
            Button {
                fileImporterOpen = true
            } label: {
                Label(app.T("Thêm ảnh hoặc tài liệu", "Add photo or document"), systemImage: "photo.on.rectangle")
            }
            Button {
                cameraOpen = true
            } label: {
                Label(app.T("Máy ảnh", "Camera"), systemImage: "camera")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .medium))
                .frame(width: 40, height: 40)
                .background(app.palette.field, in: Circle())
                .foregroundStyle(app.palette.ink)
        }
        .disabled(!isEnabled || isSending)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityIdentifier(accessibilityIdentifier)
        // Both pickers live here rather than on the caller's screen, so the
        // dock overlay is hidden for exactly as long as either is up —
        // including the edge case where returning from a picker lands on a
        // screen where the dock WOULD show.
        .fileImporter(isPresented: $fileImporterOpen, allowedContentTypes: ChatAttachment.contentTypes) { result in
            switch result {
            case .success(let url):
                Task { await sendPickedFile(url) }
            case .failure:
                onFailure?(app.T("Không mở được tệp đã chọn.", "Couldn't open the file you picked."))
            }
        }
        // Camera's native "Retake"/"Use Photo" review step comes from
        // UIImagePickerController itself (CameraPicker.swift) — no custom
        // preview UI needed to satisfy that requirement.
        .fullScreenCover(isPresented: $cameraOpen) {
            CameraPicker { image in
                cameraOpen = false
                guard let payload = ChatAttachButton.cameraPayload(from: image) else {
                    onFailure?(app.T("Không xử lý được ảnh chụp.", "Couldn't process the photo."))
                    return
                }
                Task { await onPick(payload) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: cameraOpen) { _, _ in BottomTabBarOverlay.shared.setForcedHidden(cameraOpen || fileImporterOpen) }
        .onChange(of: fileImporterOpen) { _, _ in BottomTabBarOverlay.shared.setForcedHidden(cameraOpen || fileImporterOpen) }
        .onDisappear { BottomTabBarOverlay.shared.setForcedHidden(false) }
    }

    /// The camera path's payload: the RE-ENCODED data's own pixel size, not
    /// `image.size` (points, pre-downscale) — decoding what actually got
    /// uploaded is what the bubble needs to match exactly.
    static func cameraPayload(from image: UIImage) -> AttachmentPayload? {
        guard let data = ProofImage.jpegDataUnderLimit(from: image) else { return nil }
        let dims = UIImage(data: data)?.size
        return AttachmentPayload(
            data: data, contentType: "image/jpeg", fileExtension: "jpg",
            width: dims.map { Int($0.width) }, height: dims.map { Int($0.height) }
        )
    }

    private func sendPickedFile(_ url: URL) async {
        guard url.startAccessingSecurityScopedResource() else {
            onFailure?(app.T("Không đọc được tệp đã chọn.", "Couldn't read the file you picked."))
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else {
            onFailure?(app.T("Không đọc được tệp đã chọn.", "Couldn't read the file you picked."))
            return
        }
        if url.pathExtension.lowercased() == "pdf" {
            await onPick(AttachmentPayload(
                data: data, contentType: "application/pdf", fileExtension: "pdf", width: nil, height: nil
            ))
            return
        }
        guard let image = UIImage(data: data), let jpeg = ProofImage.jpegDataUnderLimit(from: image) else {
            onFailure?(app.T("Không xử lý được ảnh đã chọn.", "Couldn't process the photo you picked."))
            return
        }
        let dims = UIImage(data: jpeg)?.size
        await onPick(AttachmentPayload(
            data: jpeg, contentType: "image/jpeg", fileExtension: "jpg",
            width: dims.map { Int($0.width) }, height: dims.map { Int($0.height) }
        ))
    }
}

/// Geometry and rendering shared by attachment bubbles in BOTH chats.
///
/// `boxSize(width:height:)` is `ChatView.attachmentBoxSize` verbatim — a box
/// whose OWN ratio matches the source image's true ratio, clamped inside a
/// sensible chat max/min, so `.scaledToFill()` never has to crop or
/// letterbox (it mirrors web's `attachmentBoxSize()` in Chat.jsx). The
/// original is kept as a forwarder so existing callers and any tests keep
/// working.
enum AttachmentBubble {
    static func boxSize(width: Int?, height: Int?) -> CGSize {
        guard let w = width, let h = height, w > 0, h > 0 else { return CGSize(width: 220, height: 220) }
        let maxW: CGFloat = 240, maxH: CGFloat = 320, minW: CGFloat = 120
        let ratio = CGFloat(w) / CGFloat(h)
        var boxW = min(maxW, CGFloat(w))
        var boxH = boxW / ratio
        if boxH > maxH { boxH = maxH; boxW = boxH * ratio }
        if boxW < minW { boxW = minW; boxH = boxW / ratio }
        return CGSize(width: boxW.rounded(), height: boxH.rounded())
    }
}