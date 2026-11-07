import UIKit
import ImageIO
import CoreText
import Foundation

// MARK: - Refund dispute export
//
// Builds the COMPLETE record of one refund dispute as two real files:
//
//   * a readable PDF transcript, photos embedded, every file referenced by its
//     name inside the ZIP;
//   * a ZIP holding that PDF and the ORIGINAL bytes of every attachment.
//
// The bytes come from the private `dispute-attachments` bucket through an
// injected `Downloader` (production: the signed-in user's own storage download,
// authorized by the bucket's participant policy). A signed URL or a storage
// path is never put in the export: the files are deleted with the temporary
// chat, so an offline copy has to carry the bytes themselves.
//
// An export is only ever returned when EVERY attachment was fetched and
// verified. If any file is missing or fails, `build` throws
// `DisputeExportError.attachmentsFailed` and writes nothing the caller could
// mistake for a finished export.

enum DisputeExportError: Error, Equatable {
    /// Number of attachments that could not be fetched, and how many there were.
    case attachmentsFailed(failed: Int, total: Int)
    case writeFailed(String)
}

struct DisputeExportProgress: Equatable {
    enum Phase: Equatable { case downloading, renderingPDF, buildingZIP }
    var phase: Phase
    /// Files fetched so far / total files (only meaningful while downloading).
    var done: Int
    var total: Int
    /// 0...1 across the whole export.
    var fraction: Double
}

struct DisputeExportResult: Equatable {
    let directory: URL
    let pdfURL: URL
    let zipURL: URL
    let attachmentCount: Int
    let attachmentBytes: Int
    /// Entry names inside the ZIP (PDF first, then attachments), as written.
    let zipEntryNames: [String]
}

enum DisputeExporter {
    typealias Downloader = @Sendable (String) async throws -> Data
    typealias ProgressHandler = @Sendable (DisputeExportProgress) -> Void

    /// Where exports live. A folder of their own so cleanup can never touch
    /// anything else in the temporary directory.
    static var exportsRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("dispute-exports", isDirectory: true)
    }

    // MARK: Planning

    /// One attachment of the transcript, with the name it gets inside the ZIP.
    struct PlannedFile: Equatable {
        let messageNumber: Int          // 1 based position in the transcript
        let messageID: UUID
        let storagePath: String
        let mime: String
        let zipName: String             // "attachments/..."
        let width: Int?
        let height: Int?
    }

    static func plan(_ transcript: RefundDisputeTranscript) -> [PlannedFile] {
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")
        stamp.dateFormat = "yyyyMMdd'T'HHmmss"
        var out: [PlannedFile] = []
        for (index, m) in transcript.messages.enumerated() where m.hasAttachment {
            let mime = (m.attachmentType ?? "").lowercased()
            let kind = mime.hasPrefix("image/") ? "photo" : "file"
            let name = String(format: "attachments/msg%03d_%@_%@_%@.%@",
                              index + 1, stamp.string(from: m.createdAt),
                              sanitize(m.senderRole), kind,
                              fileExtension(mime: mime, path: m.attachmentPath ?? ""))
            out.append(PlannedFile(messageNumber: index + 1, messageID: m.id,
                                   storagePath: m.attachmentPath ?? "", mime: mime,
                                   zipName: name, width: m.attachmentWidth, height: m.attachmentHeight))
        }
        return out
    }

    static func fileExtension(mime: String, path: String) -> String {
        switch mime {
        case "image/jpeg": return "jpg"
        case "image/png": return "png"
        case "image/webp": return "webp"
        case "application/pdf": return "pdf"
        default:
            let ext = (path as NSString).pathExtension.lowercased()
            return ext.isEmpty ? "bin" : sanitize(ext)
        }
    }

    private static func sanitize(_ s: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        let cleaned = String(s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "x" })
        return cleaned.isEmpty ? "x" : cleaned
    }

    /// The downloaded bytes must actually be the type the message claims. A
    /// storage error body, an empty object or an HTML page would otherwise be
    /// zipped up as a "photo" and reported as a successful export.
    static func bytesLookValid(_ data: Data, mime: String) -> Bool {
        guard !data.isEmpty else { return false }
        let head = [UInt8](data.prefix(12))
        switch mime {
        case "image/jpeg": return head.count >= 3 && head[0] == 0xFF && head[1] == 0xD8
        case "image/png": return head.count >= 4 && head[0] == 0x89 && head[1] == 0x50 && head[2] == 0x4E && head[3] == 0x47
        case "image/webp": return head.count >= 12 && head[0] == 0x52 && head[1] == 0x49 && head[8] == 0x57 && head[9] == 0x45
        case "application/pdf": return head.count >= 4 && head[0] == 0x25 && head[1] == 0x50 && head[2] == 0x44 && head[3] == 0x46
        default: return true
        }
    }

    // MARK: Build

    /// Fetches every attachment, renders the PDF, writes the ZIP and verifies
    /// the ZIP's own table of contents against the plan. Heavy work runs off
    /// the main actor. Cancelling the surrounding Task stops it between steps
    /// and removes everything written so far.
    static func build(
        transcript: RefundDisputeTranscript,
        isEN: Bool,
        downloader: @escaping Downloader,
        progress: @escaping ProgressHandler = { _ in },
        baseDirectory: URL = DisputeExporter.exportsRoot
    ) async throws -> DisputeExportResult {
        let claimTag = (transcript.refundClaimId?.uuidString ?? "dispute").lowercased().prefix(8)
        let dir = baseDirectory.appendingPathComponent("\(claimTag)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        let attachmentsDir = dir.appendingPathComponent("attachments", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)
            let planned = plan(transcript)
            let total = planned.count
            progress(.init(phase: .downloading, done: 0, total: total, fraction: 0))

            // 1. Bytes. One at a time so memory stays at one attachment, and
            //    each is written straight to disk.
            var failed = 0
            var bytes = 0
            for (i, file) in planned.enumerated() {
                try Task.checkCancellation()
                do {
                    let data = try await downloader(file.storagePath)
                    guard bytesLookValid(data, mime: file.mime) else { throw DisputeExportError.writeFailed("invalid bytes") }
                    let url = dir.appendingPathComponent(file.zipName)
                    try data.write(to: url, options: .atomic)
                    bytes += data.count
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    failed += 1
                }
                progress(.init(phase: .downloading, done: i + 1, total: total,
                               fraction: total == 0 ? 0.6 : 0.6 * Double(i + 1) / Double(total)))
            }
            if failed > 0 { throw DisputeExportError.attachmentsFailed(failed: failed, total: total) }

            // 2. PDF, off the main actor.
            try Task.checkCancellation()
            progress(.init(phase: .renderingPDF, done: total, total: total, fraction: 0.65))
            let pdfName = "banbe-refund-dispute-\(claimTag).pdf"
            let pdfURL = dir.appendingPathComponent(pdfName)
            let pdfData = await Task.detached(priority: .userInitiated) {
                DisputePDFRenderer.render(transcript: transcript, files: planned, directory: dir, isEN: isEN)
            }.value
            try pdfData.write(to: pdfURL, options: .atomic)

            // 3. ZIP, then verify it by reading its own central directory.
            try Task.checkCancellation()
            progress(.init(phase: .buildingZIP, done: total, total: total, fraction: 0.85))
            let zipURL = dir.appendingPathComponent("banbe-refund-dispute-\(claimTag).zip")
            var entries: [(name: String, url: URL)] = [(pdfName, pdfURL)]
            entries += planned.map { ($0.zipName, dir.appendingPathComponent($0.zipName)) }
            try await Task.detached(priority: .userInitiated) {
                try ZipWriter.write(entries: entries, to: zipURL)
            }.value
            let written = try ZipReader.entries(at: zipURL)
            guard written.map(\.name) == entries.map(\.name) else {
                throw DisputeExportError.writeFailed("zip verification failed")
            }
            progress(.init(phase: .buildingZIP, done: total, total: total, fraction: 1))
            return DisputeExportResult(directory: dir, pdfURL: pdfURL, zipURL: zipURL,
                                       attachmentCount: total, attachmentBytes: bytes,
                                       zipEntryNames: entries.map(\.name))
        } catch {
            try? FileManager.default.removeItem(at: dir)
            throw error
        }
    }

    // MARK: Cleanup

    static func remove(_ result: DisputeExportResult?) {
        guard let result else { return }
        try? FileManager.default.removeItem(at: result.directory)
    }

    /// Removes exports older than `age` seconds, so a crash or force quit
    /// mid-export cannot leave a dispute's contents in temporary storage.
    static func purgeStale(olderThan age: TimeInterval = 3600, root: URL = DisputeExporter.exportsRoot) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for url in items {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if Date().timeIntervalSince(modified) > age { try? fm.removeItem(at: url) }
        }
    }
}

// MARK: - ZIP (stored, no compression)

/// Minimal streaming ZIP writer. Entries are STORED: the payloads are JPEG,
/// PNG, WebP and PDF, which are already compressed, so deflating them would
/// cost CPU and gain nothing. Each file is read twice in 1 MB chunks (CRC, then
/// copy), so memory never holds more than a chunk.
enum ZipWriter {
    private static let chunk = 1 << 20

    static func write(entries: [(name: String, url: URL)], to destination: URL) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: destination)
        guard fm.createFile(atPath: destination.path, contents: nil),
              let out = try? FileHandle(forWritingTo: destination) else {
            throw DisputeExportError.writeFailed("cannot create zip")
        }
        defer { try? out.close() }

        struct Central { let name: Data; let crc: UInt32; let size: UInt32; let offset: UInt32 }
        var central: [Central] = []
        var offset: UInt64 = 0
        let (dosTime, dosDate) = dosStamp(Date())

        for entry in entries {
            let nameData = Data(entry.name.utf8)
            let (crc, size) = try crc32AndSize(of: entry.url)
            guard size <= UInt64(UInt32.max), offset <= UInt64(UInt32.max) else {
                throw DisputeExportError.writeFailed("zip too large")
            }
            var header = Data()
            header.le32(0x04034b50)
            header.le16(20)           // version needed
            header.le16(0x0800)       // UTF-8 names
            header.le16(0)            // stored
            header.le16(dosTime); header.le16(dosDate)
            header.le32(crc)
            header.le32(UInt32(size)); header.le32(UInt32(size))
            header.le16(UInt16(nameData.count)); header.le16(0)
            header.append(nameData)
            try out.write(contentsOf: header)
            let entryOffset = UInt32(offset)
            offset += UInt64(header.count)

            let input = try FileHandle(forReadingFrom: entry.url)
            defer { try? input.close() }
            while let part = try input.read(upToCount: chunk), !part.isEmpty {
                try out.write(contentsOf: part)
                offset += UInt64(part.count)
            }
            central.append(Central(name: nameData, crc: crc, size: UInt32(size), offset: entryOffset))
        }

        let centralStart = offset
        var dir = Data()
        for c in central {
            dir.le32(0x02014b50)
            dir.le16(20); dir.le16(20)
            dir.le16(0x0800); dir.le16(0)
            dir.le16(dosTime); dir.le16(dosDate)
            dir.le32(c.crc); dir.le32(c.size); dir.le32(c.size)
            dir.le16(UInt16(c.name.count)); dir.le16(0); dir.le16(0)
            dir.le16(0); dir.le16(0); dir.le32(0)
            dir.le32(c.offset)
            dir.append(c.name)
        }
        var end = Data()
        end.le32(0x06054b50)
        end.le16(0); end.le16(0)
        end.le16(UInt16(central.count)); end.le16(UInt16(central.count))
        end.le32(UInt32(dir.count)); end.le32(UInt32(centralStart))
        end.le16(0)
        try out.write(contentsOf: dir)
        try out.write(contentsOf: end)
    }

    private static func crc32AndSize(of url: URL) throws -> (UInt32, UInt64) {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var crc: UInt32 = 0xFFFF_FFFF
        var size: UInt64 = 0
        while let part = try input.read(upToCount: chunk), !part.isEmpty {
            size += UInt64(part.count)
            part.withUnsafeBytes { raw in
                for byte in raw.bindMemory(to: UInt8.self) {
                    crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
                }
            }
        }
        return (~crc, size)
    }

    static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return ~crc
    }

    private static func dosStamp(_ date: Date) -> (UInt16, UInt16) {
        let c = Calendar(identifier: .gregorian).dateComponents(in: .current, from: date)
        let year = max(1980, c.year ?? 1980)
        let time = UInt16(((c.hour ?? 0) << 11) | ((c.minute ?? 0) << 5) | ((c.second ?? 0) / 2))
        let day = UInt16(((year - 1980) << 9) | ((c.month ?? 1) << 5) | (c.day ?? 1))
        return (time, day)
    }
}

/// Reads a ZIP's central directory. Used to verify what was just written and
/// by the unit tests; it also checks each entry's stored CRC against its bytes.
enum ZipReader {
    struct Entry: Equatable { let name: String; let size: Int; let crc: UInt32; let data: Data }

    static func entries(at url: URL) throws -> [Entry] {
        let zip = try Data(contentsOf: url, options: .mappedIfSafe)
        guard zip.count >= 22 else { throw DisputeExportError.writeFailed("zip too short") }
        // End of central directory is the last 22 bytes (no comment is written).
        let eocd = zip.count - 22
        guard zip.u32(eocd) == 0x06054b50 else { throw DisputeExportError.writeFailed("no end record") }
        let count = Int(zip.u16(eocd + 10))
        var p = Int(zip.u32(eocd + 16))
        var out: [Entry] = []
        for _ in 0..<count {
            guard zip.u32(p) == 0x02014b50 else { throw DisputeExportError.writeFailed("bad central entry") }
            let crc = zip.u32(p + 16)
            let size = Int(zip.u32(p + 24))
            let nameLen = Int(zip.u16(p + 28))
            let extraLen = Int(zip.u16(p + 30)), commentLen = Int(zip.u16(p + 32))
            let local = Int(zip.u32(p + 42))
            let name = String(decoding: zip[(p + 46)..<(p + 46 + nameLen)], as: UTF8.self)
            guard zip.u32(local) == 0x04034b50 else { throw DisputeExportError.writeFailed("bad local header") }
            let localName = Int(zip.u16(local + 26)), localExtra = Int(zip.u16(local + 28))
            let start = local + 30 + localName + localExtra
            guard start + size <= zip.count else { throw DisputeExportError.writeFailed("entry past end") }
            let data = Data(zip[start..<(start + size)])
            guard ZipWriter.crc32(data) == crc else { throw DisputeExportError.writeFailed("crc mismatch for \(name)") }
            out.append(Entry(name: name, size: size, crc: crc, data: data))
            p += 46 + nameLen + extraLen + commentLen
        }
        return out
    }
}

private extension Data {
    mutating func le16(_ v: UInt16) { append(UInt8(v & 0xFF)); append(UInt8(v >> 8)) }
    mutating func le32(_ v: UInt32) { le16(UInt16(v & 0xFFFF)); le16(UInt16(v >> 16)) }
    func u16(_ i: Int) -> UInt16 { UInt16(self[startIndex + i]) | UInt16(self[startIndex + i + 1]) << 8 }
    func u32(_ i: Int) -> UInt32 { UInt32(u16(i)) | UInt32(u16(i + 2)) << 16 }
}

// MARK: - PDF

/// Renders the transcript as an A4 PDF. Text is real text (selectable and
/// searchable), long messages continue across pages, photos are embedded at a
/// reduced size, and every attachment names its file inside the ZIP.
enum DisputePDFRenderer {
    private static let pageW: CGFloat = 595
    private static let pageH: CGFloat = 842
    private static let margin: CGFloat = 46

    static func render(transcript: RefundDisputeTranscript, files: [DisputeExporter.PlannedFile],
                       directory: URL, isEN: Bool) -> Data {
        func L(_ vi: String, _ en: String) -> String { isEN ? en : vi }
        let ink = UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        let muted = UIColor(red: 0.45, green: 0.45, blue: 0.48, alpha: 1)
        let rule = UIColor(red: 0.87, green: 0.87, blue: 0.89, alpha: 1)
        let contentW = pageW - margin * 2
        let bottom = pageH - margin - 18

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")
        df.dateFormat = "yyyy/MM/dd HH:mm"
        func when(_ d: Date?) -> String { d.map { df.string(from: $0) + " GMT+7" } ?? L("Không có", "Not set") }

        let byMessage = Dictionary(uniqueKeysWithValues: files.map { ($0.messageID, $0) })
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageW, height: pageH))

        return renderer.pdfData { ctx in
            var y = margin
            var page = 0

            func footer() {
                let text = L("Trang \(page)", "Page \(page)")
                text.draw(at: CGPoint(x: margin, y: pageH - margin + 4), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 8.5), .foregroundColor: muted])
            }
            func newPage() {
                if page > 0 { footer() }
                ctx.beginPage()
                page += 1
                y = margin
            }
            func attr(_ s: String, size: CGFloat, weight: UIFont.Weight = .regular, color: UIColor? = nil, italic: Bool = false) -> NSAttributedString {
                var font = UIFont.systemFont(ofSize: size, weight: weight)
                if italic, let d = font.fontDescriptor.withSymbolicTraits(.traitItalic) { font = UIFont(descriptor: d, size: size) }
                let style = NSMutableParagraphStyle()
                style.lineSpacing = 2
                return NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color ?? ink, .paragraphStyle: style])
            }
            /// Draws text across as many pages as it needs.
            func paragraph(_ s: NSAttributedString, gapAfter: CGFloat = 4) {
                guard s.length > 0 else { return }
                let fs = CTFramesetterCreateWithAttributedString(s)
                var loc = 0
                while loc < s.length {
                    let avail = bottom - y
                    var fit = CFRange()
                    let size = CTFramesetterSuggestFrameSizeWithConstraints(
                        fs, CFRange(location: loc, length: 0), nil, CGSize(width: contentW, height: max(avail, 0)), &fit)
                    if fit.length == 0 {
                        if y <= margin + 1 { fit.length = s.length - loc } else { newPage(); continue }
                    }
                    let height = max(size.height, 12)
                    let cg = ctx.cgContext
                    cg.saveGState()
                    // UIKit's own text drawing (the page footer) leaves a flipped
                    // text matrix behind, which Core Text would apply to every
                    // paragraph on the NEXT page and draw it mirrored.
                    cg.textMatrix = .identity
                    cg.translateBy(x: margin, y: y + height)
                    cg.scaleBy(x: 1, y: -1)
                    let path = CGPath(rect: CGRect(x: 0, y: 0, width: contentW, height: height), transform: nil)
                    let frame = CTFramesetterCreateFrame(fs, CFRange(location: loc, length: fit.length), path, nil)
                    CTFrameDraw(frame, cg)
                    cg.restoreGState()
                    y += height
                    loc += fit.length
                    if loc < s.length { newPage() }
                }
                y += gapAfter
            }
            func divider() {
                let cg = ctx.cgContext
                cg.setStrokeColor(rule.cgColor); cg.setLineWidth(0.6)
                cg.move(to: CGPoint(x: margin, y: y)); cg.addLine(to: CGPoint(x: pageW - margin, y: y)); cg.strokePath()
                y += 8
            }
            func ensure(_ h: CGFloat) { if y + h > bottom { newPage() } }

            newPage()
            paragraph(attr("banbe", size: 20, weight: .bold), gapAfter: 2)
            paragraph(attr(L("Bản ghi tranh chấp hoàn tiền", "Refund dispute transcript"), size: 14, weight: .semibold), gapAfter: 8)

            let facts: [(String, String)] = [
                (L("Sự kiện", "Event"), "\(transcript.eventName ?? L("Không có", "Not set")) (\(transcript.eventId ?? ""))"),
                (L("Người tổ chức", "Organizer"), transcript.organizerLabel ?? L("Không có", "Not set")),
                (L("Khách", "Guest"), transcript.guestLabel ?? L("Không có", "Not set")),
                (L("Mã đặt chỗ", "Booking code"), transcript.bookingCode ?? L("Không có", "Not set")),
                (L("Mã đặt chỗ nội bộ", "Booking reference"), transcript.bookingId?.uuidString ?? L("Không có", "Not set")),
                (L("Mã yêu cầu hoàn tiền", "Refund claim"), transcript.refundClaimId?.uuidString ?? L("Không có", "Not set")),
                (L("Số tiền", "Amount"), transcript.amountVnd.map { String(format: "%d VND", $0) } ?? L("Không có", "Not set")),
                (L("Trạng thái hoàn tiền", "Refund status"), transcript.claimStatus ?? L("Không có", "Not set")),
                (L("Lý do", "Reason"), transcript.claimReason ?? L("Không có", "Not set")),
                (L("Mở tranh chấp lúc", "Dispute opened"), when(transcript.disputedAt)),
                (L("Đóng lúc", "Closed"), when(transcript.disputeClosedAt ?? transcript.resolvedAt)),
                (L("Bị xoá lúc", "Scheduled deletion"), when(transcript.purgeAfter)),
                (L("Xuất lúc", "Exported"), when(transcript.exportedAt)),
            ]
            for (k, v) in facts {
                let line = NSMutableAttributedString(attributedString: attr(k + ": ", size: 10, weight: .semibold, color: muted))
                line.append(attr(v, size: 10))
                paragraph(line, gapAfter: 1)
            }
            if let note = transcript.claimNote, !note.isEmpty {
                paragraph(attr(L("Ghi chú của yêu cầu: ", "Claim note: ") + note, size: 10), gapAfter: 2)
            }
            y += 6
            divider()
            paragraph(attr(L("Tin nhắn (\(transcript.messages.count))", "Messages (\(transcript.messages.count))"), size: 12, weight: .bold), gapAfter: 2)
            paragraph(attr(L("Tệp đính kèm: \(files.count). Mọi tệp gốc nằm trong gói ZIP đi kèm.",
                             "Attachments: \(files.count). Every original file is in the ZIP that comes with this PDF."),
                           size: 9.5, color: muted), gapAfter: 8)

            let placeholders: Set<String> = ["Sent a photo", "Sent a file", "Đã gửi một ảnh", "Đã gửi một tệp"]
            for (i, m) in transcript.messages.enumerated() {
                ensure(60)
                let who = m.senderName ?? m.senderRole
                let head = "#\(i + 1)  \(who) (\(m.senderRole))  \(when(m.createdAt))"
                paragraph(attr(head, size: 9.5, weight: .semibold, color: muted), gapAfter: 2)
                let isSystem = m.senderRole == "system"
                let attachedOnly = m.hasAttachment && placeholders.contains(m.body)
                if !attachedOnly, !m.body.isEmpty {
                    paragraph(attr(m.body, size: 11, color: isSystem ? muted : ink, italic: isSystem), gapAfter: 4)
                }
                if let f = byMessage[m.id] {
                    var detail = f.mime
                    if let w = f.width, let h = f.height, w > 0, h > 0 { detail += ", \(w)x\(h)" }
                    if let size = (try? FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(f.zipName).path)[.size]) as? Int {
                        detail += ", " + ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
                    }
                    if f.mime.hasPrefix("image/"), let img = thumbnail(directory.appendingPathComponent(f.zipName)) {
                        let maxW = min(contentW, 320), maxH: CGFloat = 340
                        let scale = min(maxW / img.size.width, maxH / img.size.height, 1)
                        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
                        ensure(size.height + 28)
                        img.draw(in: CGRect(x: margin, y: y, width: size.width, height: size.height))
                        y += size.height + 4
                    } else if f.mime.hasPrefix("image/") {
                        paragraph(attr(L("Không hiển thị được bản xem trước. Xem tệp gốc trong gói ZIP.",
                                         "Preview could not be drawn. See the original file in the ZIP."), size: 9.5, color: muted), gapAfter: 2)
                    }
                    paragraph(attr(L("Tệp đính kèm: ", "Attachment: ") + f.zipName + " (" + detail + ")", size: 9.5, color: muted), gapAfter: 2)
                }
                y += 6
            }
            if transcript.messages.isEmpty {
                paragraph(attr(L("Chưa có tin nhắn nào.", "No messages."), size: 11, color: muted))
            }
            footer()
        }
    }

    /// Embedded photos are downsampled: the PDF is for reading, the ZIP keeps
    /// the originals.
    private static func thumbnail(_ url: URL) -> UIImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1400,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cg)
        if let jpeg = image.jpegData(compressionQuality: 0.82), let compact = UIImage(data: jpeg) { return compact }
        return image
    }
}
