import XCTest
@testable import BanbeApp

/// Mirrors tests/unit/systemMessageLocale.test.mjs — the two translators must agree.
final class SystemMessageLocaleTests: XCTestCase {
    private func L(_ s: String, _ en: Bool) -> String { SystemMessageLocale.localize(s, isEN: en) }

    func testEnglishWrittenBodiesReadInVietnamese() {
        XCTAssertEqual(L("Booking cancelled. Reason: Nhầm người.", false), "Đặt chỗ đã bị huỷ. Lý do: Nhầm người.")
        XCTAssertEqual(L("Event was cancelled by host. Reason: Cancelled for safety or weather reasons.", false),
                       "Sự kiện đã bị người tổ chức huỷ. Lý do: Sự kiện bị huỷ vì lý do an toàn hoặc thời tiết.")
        XCTAssertEqual(L("Host marked payment received via direct transfer.", false),
                       "Người tổ chức đã xác nhận nhận thanh toán qua chuyển khoản trực tiếp.")
    }

    func testVietnameseWrittenBodiesReadInEnglish() {
        XCTAssertEqual(L("Người tổ chức không nhận yêu cầu đặt chỗ này: Hết chỗ thật sự. Chỗ đã được mở lại cho người khác.", true),
                       "The organizer declined this booking request: Actually out of seats. The spot has been released to others.")
        XCTAssertEqual(L("Người tổ chức chưa tìm thấy khoản chuyển khoản này. Chỗ của bạn vẫn được giữ trong lúc banbe xem xét.", true),
                       "The organizer couldn't find this transfer. Your spot is still held while banbe reviews it.")
        XCTAssertEqual(L("Đã xác nhận thanh toán ▪︎ người tổ chức xác nhận. Biên nhận R-1.", true),
                       "Payment confirmed ▪︎ confirmed by the organizer. Receipt R-1.")
    }

    func testBilingualBodiesShowOnlyTheViewersHalf() {
        let b = "Tranh chấp đã được giải quyết. / Dispute resolved."
        XCTAssertEqual(L(b, false), "Tranh chấp đã được giải quyết.")
        XCTAssertEqual(L(b, true), "Dispute resolved.")
    }

    func testUnknownOrAlreadyLocalTextIsUntouched() {
        XCTAssertEqual(L("Booking cancelled. Reason: X.", true), "Booking cancelled. Reason: X.")
        XCTAssertEqual(L("Xin chào, mình tới trễ 10 phút", true), "Xin chào, mình tới trễ 10 phút")
    }
}
