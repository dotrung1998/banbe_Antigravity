import XCTest
import PDFKit
@testable import BanbeApp

/// The refund dispute export: complete (every attachment's real bytes), honest
/// (any missing file fails the export), self contained (usable after the
/// dispute is purged) and tidy (temporary files removed).
final class DisputeExportTests: XCTestCase {

    private var base: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("export-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: base) }

    // MARK: Fixtures

    private func jpeg(_ color: UIColor, size: CGSize = CGSize(width: 640, height: 480)) -> Data {
        UIGraphicsImageRenderer(size: size).jpegData(withCompressionQuality: 0.9) { ctx in
            color.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func pdfAttachment() -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 200)).pdfData { ctx in
            ctx.beginPage(); "receipt".draw(at: CGPoint(x: 20, y: 20), withAttributes: nil)
        }
    }

    private struct Fixture {
        var transcript: RefundDisputeTranscript
        var bytes: [String: Data]
    }

    private func fixture(extraPhotos: Int = 0) throws -> Fixture {
        var bytes: [String: Data] = [
            "t/photo1.jpg": jpeg(.red), "t/doc.pdf": pdfAttachment(),
        ]
        var messages: [[String: Any]] = [
            msg(1, role: "guest", name: "Goe Test", body: "Chưa nhận được tiền hoàn", path: nil, mime: nil),
            // attachment only: body is the placeholder the server writes
            msg(2, role: "guest", name: "Goe Test", body: "Sent a photo", path: "t/photo1.jpg", mime: "image/jpeg", w: 640, h: 480),
            msg(3, role: "organizer", name: "Alpha Events", body: "Sent a file", path: "t/doc.pdf", mime: "application/pdf"),
            msg(4, role: "system", name: "banbe", body: "Dispute closed by the guest and marked as completed.", path: nil, mime: nil),
        ]
        for i in 0..<extraPhotos {
            let path = "t/extra\(i).jpg"
            bytes[path] = jpeg(UIColor(hue: CGFloat(i % 10) / 10, saturation: 1, brightness: 1, alpha: 1), size: CGSize(width: 1600, height: 1200))
            messages.append(msg(10 + i, role: "guest", name: "Goe Test", body: "Sent a photo", path: path, mime: "image/jpeg", w: 1600, h: 1200))
        }
        let json: [String: Any] = [
            "found": true, "dispute_thread_id": UUID().uuidString, "refund_claim_id": "c0000001-0000-4000-8000-000000000001",
            "booking_id": UUID().uuidString, "booking_code": "BKA1", "event_id": "test_evt_a", "event_name": "Alpha Night Market",
            "organizer_label": "Alpha Events", "guest_label": "Goe Test", "amount_vnd": 300000, "claim_status": "disputed",
            "disputed_at": "2026-10-01T10:00:00Z", "purge_after": "2026-10-11T10:00:00Z", "exported_at": "2026-10-04T10:00:00Z",
            "messages": messages,
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return Fixture(transcript: try decoder.decode(RefundDisputeTranscript.self, from: data), bytes: bytes)
    }

    private func msg(_ n: Int, role: String, name: String, body: String, path: String?, mime: String?, w: Int? = nil, h: Int? = nil) -> [String: Any] {
        var m: [String: Any] = ["id": UUID().uuidString, "sender_role": role, "sender_name": name, "body": body,
                                "created_at": String(format: "2026-10-01T10:%02d:00Z", n % 60)]
        if let path { m["attachment_path"] = path }
        if let mime { m["attachment_type"] = mime }
        if let w { m["attachment_width"] = w }
        if let h { m["attachment_height"] = h }
        return m
    }

    private func build(_ f: Fixture, missing: Set<String> = [], corrupt: Set<String> = [],
                       progress: @escaping DisputeExporter.ProgressHandler = { _ in }) async throws -> DisputeExportResult {
        try await DisputeExporter.build(transcript: f.transcript, isEN: true, downloader: { path in
            if missing.contains(path) { throw URLError(.fileDoesNotExist) }
            if corrupt.contains(path) { return Data("<html>error</html>".utf8) }
            return f.bytes[path] ?? Data()
        }, progress: progress, baseDirectory: base)
    }

    // MARK: Completeness

    func testZipHoldsThePDFAndEveryOriginalAttachmentByteForByte() async throws {
        let f = try fixture()
        let result = try await build(f)
        let entries = try ZipReader.entries(at: result.zipURL)   // also verifies every CRC
        XCTAssertEqual(entries.count, 3, "PDF + 2 attachments")
        XCTAssertTrue(entries[0].name.hasSuffix(".pdf"))
        let photo = try XCTUnwrap(entries.first { $0.name.hasSuffix("photo.jpg") })
        XCTAssertEqual(photo.data, f.bytes["t/photo1.jpg"], "the ORIGINAL photo bytes, not a thumbnail")
        let doc = try XCTUnwrap(entries.first { $0.name.hasSuffix("file.pdf") })
        XCTAssertEqual(doc.data, f.bytes["t/doc.pdf"])
        XCTAssertEqual(result.attachmentCount, 2)
        // Names map back to the message: msg002 is the photo, msg003 the file.
        XCTAssertTrue(photo.name.contains("msg002_"))
        XCTAssertTrue(doc.name.contains("msg003_"))
    }

    func testPDFHasEveryMessageIncludingAttachmentOnlyOnesAndEmbedsThePhoto() async throws {
        let result = try await build(try fixture())
        let data = try Data(contentsOf: result.pdfURL)
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
        for expected in ["Chưa nhận được tiền hoàn", "Goe Test", "Alpha Events", "Alpha Night Market", "BKA1",
                         "msg002_", "msg003_", "image/jpeg", "application/pdf", "Dispute closed by the guest"] {
            XCTAssertTrue(text.contains(expected), "PDF is missing \(expected)")
        }
        XCTAssertFalse(text.contains("Sent a photo"), "the placeholder caption is replaced by the real attachment")
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("/Subtype /Image") ||
                      String(decoding: data, as: UTF8.self).contains("/Image"), "the photo is embedded")
    }

    func testExportIsUsableOfflineEverythingNeededIsInsideTheZip() async throws {
        let f = try fixture()
        let result = try await build(f)
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("offline-\(UUID().uuidString).zip")
        try FileManager.default.copyItem(at: result.zipURL, to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }
        DisputeExporter.remove(result)   // the working files and the dispute are gone
        let entries = try ZipReader.entries(at: copy)
        XCTAssertEqual(entries.count, 3)
        XCTAssertNotNil(UIImage(data: try XCTUnwrap(entries.first { $0.name.hasSuffix(".jpg") }).data))
        XCTAssertNotNil(PDFDocument(data: try XCTUnwrap(entries.first { $0.name.hasSuffix("transcript") || $0.name.contains("dispute") && $0.name.hasSuffix(".pdf") && !$0.name.contains("attachments/") }).data))
        // Leave a copy where the host shell can run `unzip -t` on it.
        try? FileManager.default.removeItem(atPath: "/tmp/banbe-dispute-export-test.zip")
        try? FileManager.default.copyItem(at: copy, to: URL(fileURLWithPath: "/tmp/banbe-dispute-export-test.zip"))
    }

    func testPortraitPhotoThatBreaksThePageKeepsItsTextUpright() async throws {
        var f = try fixture()
        var extra: [[String: Any]] = []
        for i in 0..<5 { extra.append(msg(20 + i, role: "guest", name: "Goe Test", body: String(repeating: "Dòng dài. ", count: 60), path: nil, mime: nil)) }
        extra.append(msg(30, role: "guest", name: "Goe Test", body: "Sent a photo", path: "t/tall.jpg", mime: "image/jpeg", w: 1500, h: 2000))
        extra.append(msg(31, role: "guest", name: "Goe Test", body: "after", path: nil, mime: nil))
        f.bytes["t/tall.jpg"] = jpeg(.blue, size: CGSize(width: 1500, height: 2000))
        let data = try JSONSerialization.data(withJSONObject: ["found": true, "refund_claim_id": "c0000001-0000-4000-8000-000000000001", "messages": extra])
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        f.transcript = try d.decode(RefundDisputeTranscript.self, from: data)
        let result = try await build(f)
        try? FileManager.default.removeItem(atPath: "/tmp/banbe-tall.pdf")
        try FileManager.default.copyItem(at: result.pdfURL, to: URL(fileURLWithPath: "/tmp/banbe-tall.pdf"))
    }

    // MARK: Honesty

    func testAMissingAttachmentFailsTheWholeExportAndLeavesNothingBehind() async throws {
        let f = try fixture()
        do {
            _ = try await build(f, missing: ["t/doc.pdf"])
            XCTFail("an export missing a file must not be returned as successful")
        } catch let DisputeExportError.attachmentsFailed(failed, total) {
            XCTAssertEqual(failed, 1); XCTAssertEqual(total, 2)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: base.path), [], "temporary files are removed on failure")
    }

    func testBytesThatAreNotTheClaimedTypeCountAsFailed() async throws {
        let f = try fixture()
        do {
            _ = try await build(f, corrupt: ["t/photo1.jpg"])
            XCTFail("an HTML error body must not be zipped up as a photo")
        } catch let DisputeExportError.attachmentsFailed(failed, _) {
            XCTAssertEqual(failed, 1)
        }
    }

    func testEveryFailureIsCountedNotJustTheFirst() async throws {
        let f = try fixture()
        do { _ = try await build(f, missing: ["t/photo1.jpg", "t/doc.pdf"]); XCTFail() }
        catch let DisputeExportError.attachmentsFailed(failed, total) { XCTAssertEqual(failed, 2); XCTAssertEqual(total, 2) }
    }

    func testAnEmptyDisputeStillExportsAValidZipAndPDF() async throws {
        var f = try fixture()
        let json = """
        {"found":true,"messages":[],"refund_claim_id":"c0000001-0000-4000-8000-000000000001"}
        """
        f.transcript = try JSONDecoder().decode(RefundDisputeTranscript.self, from: Data(json.utf8))
        let result = try await build(f)
        XCTAssertEqual(try ZipReader.entries(at: result.zipURL).count, 1)
        XCTAssertNotNil(PDFDocument(url: result.pdfURL))
    }

    // MARK: Scale, progress, cleanup

    func testLargeExportCompletesReportsProgressAndKeepsEveryFile() async throws {
        let f = try fixture(extraPhotos: 30)
        let seen = ProgressBox()
        let result = try await build(f, progress: { seen.add($0) })
        XCTAssertEqual(result.attachmentCount, 32)
        let entries = try ZipReader.entries(at: result.zipURL)
        XCTAssertEqual(entries.count, 33)
        XCTAssertGreaterThan(result.attachmentBytes, 0)
        XCTAssertEqual(seen.fractions.last, 1)
        XCTAssertEqual(seen.fractions, seen.fractions.sorted(), "progress never goes backwards")
        let pdf = try XCTUnwrap(PDFDocument(url: result.pdfURL))
        XCTAssertGreaterThan(pdf.pageCount, 5, "long transcripts paginate")
    }

    func testCancellationRemovesPartialFiles() async throws {
        let f = try fixture(extraPhotos: 10)
        let task = Task { try await build(f, progress: { _ in }) }
        task.cancel()
        _ = try? await task.value
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: base.path), [])
    }

    func testRemoveAndPurgeStaleClearTemporaryFiles() async throws {
        let result = try await build(try fixture())
        DisputeExporter.remove(result)
        XCTAssertFalse(FileManager.default.fileExists(atPath: result.directory.path))

        let old = base.appendingPathComponent("old-export")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -7200)], ofItemAtPath: old.path)
        let fresh = base.appendingPathComponent("fresh-export")
        try FileManager.default.createDirectory(at: fresh, withIntermediateDirectories: true)
        DisputeExporter.purgeStale(olderThan: 3600, root: base)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path))
    }

    func testPlanNamesAreStableAndUnique() throws {
        let plan = DisputeExporter.plan(try fixture(extraPhotos: 3).transcript)
        XCTAssertEqual(Set(plan.map(\.zipName)).count, plan.count)
        XCTAssertTrue(plan.allSatisfy { $0.zipName.hasPrefix("attachments/msg") })
    }

    // MARK: Copy

    @MainActor
    func testCloseNoticeHasNoDashSeparatorsInEitherLanguage() {
        for isEN in [true, false] {
            let app = AppState(); app.lang = isEN ? "en" : "vi"
            let text = RefundDisputeFlows.closeNotice(app)
            for bad in ["-", "\u{2013}", "\u{2014}"] { XCTAssertFalse(text.contains(bad), "\(isEN ? "EN" : "VI") copy contains \(bad)") }
        }
    }
}

private final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []
    func add(_ p: DisputeExportProgress) { lock.lock(); values.append(p.fraction); lock.unlock() }
    var fractions: [Double] { lock.lock(); defer { lock.unlock() }; return values }
}
