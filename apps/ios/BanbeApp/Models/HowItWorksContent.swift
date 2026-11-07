import SwiftUI

/// "How banbe works" copy, shared by Version 1 (text pages) and Version 2 (swipeable demo screens), note 63.
/// Web twin: src/data/howItWorks.js. Keep both in sync.
///
/// Each section has a title, an emoji (V1 tile) and:
///   points: V1's three rows (owner, 2026-10-21: "too much text", so short rows, not a paragraph);
///   cards:  V2's demo screens. `kind` picks the mock in HowBanbeWorksView.swift; vi/en is the one-line caption
///           shown under the title while that screen is in the centre.
enum HowItWorksContent {
    enum CardKind: String {
        case quiz, stars, `private`, tickets, hold, pay, qr, organizer, free, direct, step, recipe, live
    }

    struct Card {
        let kind: CardKind
        var step = 0
        let vi: String
        let en: String
    }

    struct Point {
        let emoji: String
        let vi: String
        let en: String
    }

    struct Section {
        let key: String
        let emoji: String
        let vi: String
        let en: String
        let points: [Point]
        let cards: [Card]
    }

    static let sections: [Section] = [
        Section(key: "foryou", emoji: "🌟", vi: "Gợi ý hợp với bạn", en: "Picks that fit you", points: [
            Point(emoji: "✍️", vi: "Trả lời 5 câu ngắn, không bắt buộc", en: "Answer 5 quick, optional questions"),
            Point(emoji: "⭐", vi: "banbe gắn ★ Dành cho bạn lên sự kiện hợp", en: "banbe stars ★ For You on events that fit"),
            Point(emoji: "🔒", vi: "Chỉ mình bạn thấy câu trả lời", en: "Only you see your answers"),
        ], cards: [
            Card(kind: .quiz, vi: "Trả lời 5 câu ngắn, không bắt buộc. Thử chọn vài loại sự kiện.", en: "Answer 5 quick, optional questions. Try picking a few kinds."),
            Card(kind: .stars, vi: "banbe gắn ★ Dành cho bạn lên sự kiện hợp với bạn.", en: "banbe stars ★ For You on the events that fit."),
            Card(kind: .private, vi: "Chỉ mình bạn thấy câu trả lời. Đổi lúc nào cũng được.", en: "Only you see your answers. Change them any time."),
        ]),
        Section(key: "hold", emoji: "🎟️", vi: "Giữ chỗ trong vài chạm", en: "Hold a seat in a few taps", points: [
            Point(emoji: "⏱️", vi: "Giữ chỗ 30 phút để bạn thanh toán", en: "Your seat is held 30 minutes while you pay"),
            Point(emoji: "💸", vi: "Chuyển khoản thẳng cho host", en: "Pay the host directly"),
            Point(emoji: "📲", vi: "Nhận vé QR, kế hoạch hiện trong Lịch", en: "Get a QR ticket, plans land in Schedule"),
        ], cards: [
            Card(kind: .tickets, vi: "Chọn 1, 2 hay 3 vé. Tổng tiền hiện ngay.", en: "Pick 1, 2 or 3 tickets. The total shows right away."),
            Card(kind: .hold, vi: "Chỗ của bạn được giữ 30 phút để thanh toán.", en: "Your seat is held 30 minutes while you pay."),
            Card(kind: .pay, vi: "Chuyển khoản thẳng cho host. banbe không giữ tiền.", en: "Pay the host directly. banbe never holds money."),
            Card(kind: .qr, vi: "Nhận vé QR, kế hoạch hiện ngay trong Lịch.", en: "Get a QR ticket, and the plan lands in Schedule."),
        ]),
        Section(key: "host", emoji: "🎤", vi: "Tự tổ chức sự kiện", en: "Host your own events", points: [
            Point(emoji: "⚙️", vi: "Bật Chế độ tổ chức trong Tài khoản", en: "Turn on Organizer mode in Account"),
            Point(emoji: "🆓", vi: "Miễn phí: không phí đăng, không phí giao dịch", en: "Free: no listing or transaction fees"),
            Point(emoji: "🤝", vi: "Khách trả thẳng cho bạn, banbe không giữ tiền", en: "Guests pay you, banbe never holds money"),
        ], cards: [
            Card(kind: .organizer, vi: "Bật Chế độ tổ chức trong Tài khoản. Thử gạt công tắc.", en: "Turn on Organizer mode in Account. Try the switch."),
            Card(kind: .free, vi: "Miễn phí: không phí đăng, không phí giao dịch.", en: "Free: no listing fee, no transaction fee."),
            Card(kind: .direct, vi: "Khách trả thẳng cho bạn, banbe không giữ tiền.", en: "Guests pay you directly. banbe never holds money."),
        ]),
        Section(key: "create", emoji: "🛠️", vi: "Tạo sự kiện trong 5 bước", en: "Create an event in 5 steps", points: [
            Point(emoji: "📝", vi: "Host → Cơ bản → Thời gian & nơi → Vé → Ảnh", en: "Host → Basics → When & where → Tickets → Photos"),
            Point(emoji: "🧑‍🍳", vi: "Công thức thành công gợi ý cách lấp đầy chỗ", en: "The Recipe for success helps fill seats"),
            Point(emoji: "✅", vi: "banbe duyệt rồi đưa lên sóng, báo cho bạn", en: "banbe reviews it, then it goes live"),
        ], cards: [
            Card(kind: .step, step: 1, vi: "Bước 1: Host. Ai đứng ra tổ chức.", en: "Step 1: Host. Who is putting it on."),
            Card(kind: .step, step: 2, vi: "Bước 2: Cơ bản. Tên và loại sự kiện.", en: "Step 2: Basics. A name and a kind."),
            Card(kind: .step, step: 3, vi: "Bước 3: Thời gian & nơi.", en: "Step 3: When & where."),
            Card(kind: .step, step: 4, vi: "Bước 4: Vé. Giá và số chỗ.", en: "Step 4: Tickets. Price and seats."),
            Card(kind: .step, step: 5, vi: "Bước 5: Ảnh. Cho khách thấy không khí.", en: "Step 5: Photos. Show the feeling."),
            Card(kind: .recipe, vi: "Công thức thành công gợi ý cách lấp đầy chỗ.", en: "The Recipe for success helps fill seats."),
            Card(kind: .live, vi: "banbe duyệt rồi đưa lên sóng, và báo cho bạn.", en: "banbe reviews it, then it goes live and tells you."),
        ]),
    ]

    static var pageCount: Int { sections.count }

    static let stepNames: [(vi: String, en: String)] = [
        ("Host", "Host"), ("Cơ bản", "Basics"), ("Thời gian & nơi", "When & where"), ("Vé", "Tickets"), ("Ảnh", "Photos"),
    ]

    /// One small tip per create step (V2 step screens).
    static let stepTips: [(vi: String, en: String)] = [
        ("Có ảnh đại diện, khách tin bạn hơn.", "A profile photo helps guests trust you."),
        ("Tên ngắn và cụ thể dễ nhớ nhất.", "Short, specific names stick best."),
        ("Tối thứ Sáu, thứ Bảy thường kín chỗ nhanh.", "Friday and Saturday evenings fill fastest."),
        ("Nhóm nhỏ 8–14 chỗ là vừa đẹp.", "Small groups of 8–14 feel just right."),
        ("Ảnh sáng, có người và món ăn.", "Bright photos with people and food."),
    ]
}
