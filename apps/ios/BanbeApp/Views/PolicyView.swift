import SwiftUI

/// Port of src/screens/Policy.jsx — banbe_User_Policy.md v1.1, rendered in
/// full (bilingual, Vietnamese paragraph followed by its English
/// counterpart, matching the source document's own alternating structure),
/// not a paraphrase or summary. Where the source and English differ, the
/// Vietnamese text prevails (A1).
struct PolicyView: View {
    @EnvironmentObject var app: AppState

    static let version = "2026-10-06" // keep in sync with src/lib/policy.js's POLICY_VERSION

    /// Set only for a brand-new OAuth (Google/Facebook) profile that
    /// reached a session with no policyAcceptedAt yet
    /// (AppState+Data.swift's applySession(), note 10's OAuth consent
    /// fix) — no back-out (there's nowhere legitimate to go; the account
    /// already exists) and a mandatory "I agree" bar instead of the
    /// ordinary read-only view. A returning user, or anyone who signed up
    /// via email/password (already gated by LoginView's own checkbox),
    /// never sees this mode at all.
    private var gateActive: Bool { app.policyGateActive }

    /// Hidden once tapped (the gate's "Jump to end" shortcut, below).
    @State private var jumped = false

    var body: some View {
        ScrollViewReader { proxy in
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        if gateActive {
                            Text("Đọc và đồng ý để tiếp tục / Read and agree to continue")
                                .font(.system(size: 12)).opacity(0.7)
                        } else {
                            Button("‹ Quay lại / Back") { app.screen = app.policyBackScreen }
                                .font(.system(size: 12)).buttonStyle(.plain)
                        }
                        Spacer()
                        Text("Phiên bản / Version \(Self.version)")
                            .font(.system(size: 11)).opacity(0.5)
                    }
                    .padding(.top, 8)

                    Text("Điều khoản và quyền riêng tư · v1.1 · Terms and privacy")
                        .font(.system(size: 11)).opacity(0.55).textCase(.uppercase)
                        .padding(.top, 14)
                    Text("Điều khoản sử dụng và Thông báo quyền riêng tư banbe")
                        .font(BanbeTheme.display(22))
                        .padding(.top, 6)
                    Text("banbe Terms of Use and Privacy Notice")
                        .font(BanbeTheme.display(18)).opacity(0.75)
                        .padding(.top, 2).padding(.bottom, 14)

                    bi("Bản tóm tắt bên dưới là màn hình bạn thấy khi đăng ký. Mọi điều trong đó được nêu đầy đủ ở Phần A (Điều khoản) và Phần B (Quyền riêng tư). Tài liệu được lập bằng tiếng Việt và tiếng Anh; nếu có khác biệt, bản tiếng Việt được ưu tiên áp dụng. Hiệu lực từ [effective date].",
                       "The summary below is the screen you see at sign-up. Everything in it is set out in full in Part A (Terms) and Part B (Privacy). This document is written in Vietnamese and English; where they differ, the Vietnamese text prevails. Effective [effective date].")

                    Text("Tóm tắt: bạn đang đồng ý điều gì")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.top, 18)
                    Text("In short: what you are agreeing to")
                        .font(.system(size: 13, weight: .semibold)).opacity(0.7)
                        .padding(.top, 1).padding(.bottom, 10)

                    summaryList

                    consentBox

                    partHeading("Phần A. Điều khoản sử dụng", "Part A. Terms of Use")
                    partA

                    partHeading("Phần B. Thông báo quyền riêng tư", "Part B. Privacy Notice")
                    partB

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Liên hệ. CÔNG TY TNHH CÓMPANY · [registered address] · Mã số doanh nghiệp [enterprise code] · [contact email]. Bản này có hiệu lực từ [effective date]; các bản trước được lưu và cung cấp khi bạn yêu cầu.")
                        Text("Contact. CÓMPANY CO., LTD · [registered address] · Enterprise code [enterprise code] · [contact email]. This version is effective from [effective date]; earlier versions are kept and provided on request.")
                    }
                    .font(.system(size: 12)).lineSpacing(4).opacity(0.7)
                    .padding(.top, 18)
                    .overlay(alignment: .top) { Rectangle().fill(app.palette.rule).frame(height: 1) }
                    .padding(.top, 20)

                    Color.clear.frame(height: 1).id("policyEnd")
                }
                .foregroundStyle(app.palette.ink)
                .padding(.horizontal, 22)
                .padding(.bottom, 40)
            }
        .safeAreaInset(edge: .bottom) {
            policyGateBar
        }
        .overlay(alignment: .bottomTrailing) {
            if gateActive && !jumped {
                Button {
                    withAnimation(.easeInOut(duration: 0.45)) { proxy.scrollTo("policyEnd", anchor: .bottom) }
                    jumped = true
                } label: {
                    Text("↓ Xuống cuối / Jump to end")
                        .font(.system(size: 12.5, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(app.palette.ink, in: Capsule())
                        .foregroundStyle(app.palette.paper)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 16).padding(.bottom, 84)
                .accessibilityIdentifier("policy.gate.jump")
            }
        }
        }
    }

    @ViewBuilder
    private var policyGateBar: some View {
            if gateActive {
                HStack(spacing: 10) {
                    Button {
                        app.policyGateActive = false
                        Task { await app.signOut() }
                    } label: {
                        Text("Từ chối / Decline")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .overlay(Rectangle().stroke(app.palette.ink, lineWidth: 1))
                            .foregroundStyle(app.palette.ink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("policy.gate.decline")
                    Button {
                        app.acceptPolicyGate()
                    } label: {
                        Text("Tôi đồng ý ▪︎ Tiếp tục / I agree ▪︎ Continue")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(app.palette.ink)
                            .foregroundStyle(app.palette.paper)
                    }
                    .buttonStyle(.plain)
                    .layoutPriority(1)
                    .accessibilityIdentifier("policy.gate.accept")
                }
                .padding(.horizontal, 22).padding(.vertical, 10)
                .background(app.palette.paper)
                .overlay(alignment: .top) { Rectangle().fill(app.palette.rule).frame(height: 1) }
            }
        }

    // MARK: - Summary

    private var summaryList: some View {
        VStack(alignment: .leading, spacing: 10) {
            summaryItem("banbe là trung gian kết nối bạn với người tổ chức (host). Host tạo sự kiện; bạn giữ chỗ trên banbe. banbe không giữ hay chuyển tiền: nếu sự kiện có thu tiền, bạn chuyển tiền trực tiếp cho host, ngoài banbe; banbe chỉ hiển thị thông tin nhận tiền do host cung cấp và ghi nhận trạng thái thanh toán để hai bên đối chiếu.",
                        "banbe is an intermediary connecting you with hosts. Hosts run the events; you hold a seat on banbe. banbe does not hold or transfer money: if an event charges, you pay the host directly, outside banbe; banbe only shows the payment details the host provides and records payment status so both sides can reconcile.")
            summaryItem("Vì banbe không giữ tiền của ai, chúng tôi không thể hoàn tiền hay đòi tiền giúp bạn; banbe chỉ ghi nhận trạng thái thanh toán và hoàn tiền do bạn và host xác nhận, và admin có thể xem xét tranh chấp. Giá và điều kiện hoàn tiền do host công bố trên trang sự kiện; hãy đọc trước khi trả tiền cho ai.",
                        "Because banbe holds no one's money, we cannot refund you or recover money for you; banbe only records payment and refund status confirmed by you and the host, and an admin can review disputes. Price and refund terms are published by the host on the event page; read them before you pay anyone.")
            summaryItem("Bạn phải từ 16 tuổi, dùng số điện thoại thật đã xác minh và một địa chỉ email để nhận vé. Để tổ chức sự kiện, bạn phải từ 18 tuổi.",
                        "You must be 16 or older, with a verified phone number and an email address for your tickets. To host events you must be 18 or older.")
            summaryItem("Giữ chỗ sự kiện miễn phí là nhận vé ngay; với sự kiện thu tiền, chỗ được giữ 30 phút để bạn chuyển tiền cho host và gửi bằng chứng, và vé chỉ được cấp khi host xác nhận đã nhận tiền. Vé có mã đặt chỗ sáu ký tự và mã QR; xuất trình tại cửa. Nếu không đi được, hãy huỷ để host mở lại chỗ cho người khác.",
                        "Holding a seat at a free event gives you your ticket at once; at a paid event the seat is held for 30 minutes while you pay the host and submit proof, and the ticket is issued once the host confirms receipt. A ticket carries a six-character booking code and a QR code; show it at the door. If you cannot come, cancel so the host can release the seat.")
            summaryItem("Chúng tôi ghi nhận số điện thoại, email, tên, các lần đặt chỗ và tin nhắn của bạn với host. Host thấy tên, mã đặt chỗ và số điện thoại của bạn; khi vào cửa, host còn thấy tên và ngày sinh của người tham dự ghi trên vé.",
                        "We store your phone number, email, name, bookings and your chats with hosts. Hosts see your name, booking code and phone number; at check-in a host also sees the name and date of birth of the attendee on each ticket.")
            summaryItem("Huy hiệu “host thường xuyên” cho biết host đã tổ chức nhiều lần trước đó. Chúng tôi không kiểm tra giấy tờ tuỳ thân, giấy phép hay lý lịch của host. Bạn sẽ gặp người mới ở ngoài đời: hãy đọc kỹ thông tin sự kiện, cho bạn bè biết bạn đi đâu, và rời đi nếu thấy không thoải mái. Thấy có gì không ổn, báo cho chúng tôi qua [contact email]; khẩn cấp gọi 113 hoặc 115.",
                        "The regular host badge means a host has run events before. We do not check hosts' identity documents, permits or background. You will be meeting new people in person: read the event details, tell a friend where you are going, and leave if you are not comfortable. If something feels off, report it to us at [contact email]; in an emergency call 113 or 115.")
            summaryItem("Bạn xem, sửa và xoá tài khoản bất kỳ lúc nào trong Tuỳ chọn; muốn lấy bản sao dữ liệu thì gửi yêu cầu theo Điều B8. (Việc tự động xoá tài khoản không hoạt động lâu ngày, nêu ở Điều A3, chưa được triển khai — hiện tại xoá tài khoản luôn là hành động chủ động của bạn.)",
                        "You can view, correct and delete your account at any time in Preferences; for a copy of your data, request it under Section B8. (Automatic deletion for long inactivity, described in Section A3, is not yet implemented — today, deleting an account is always something you do yourself.)")
            summaryItem("Chúng tôi không bán dữ liệu và không chạy quảng cáo. Tin nhắn từ chính banbe chỉ gồm mã OTP đăng nhập và thông báo về sự kiện bạn đã đặt hoặc tổ chức; host chỉ được nhắn quảng bá cho bạn nếu bạn đã bật đồng ý riêng, và đó là tin của host, không phải của banbe. Mọi tin nhắn khác tự xưng là banbe, nhất là tin xin tiền hoặc thông tin tài khoản, đều là giả mạo.",
                        "We do not sell data and do not run ads. A text from banbe itself only ever carries a sign-in OTP or a notice about an event you booked or are hosting; a host may send you promotional messages only if you have opted in separately, and those are the host's, not banbe's. Any other message claiming to be banbe, especially one asking for money or account details, is fake.")
        }
    }

    private var consentBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tôi đồng ý với Điều khoản sử dụng (Phần A) và để CÔNG TY TNHH CÓMPANY xử lý dữ liệu cá nhân của tôi theo Thông báo quyền riêng tư (Phần B), gồm việc host của sự kiện tôi đặt nhận được số điện thoại của tôi, và việc lưu trữ ngoài Việt Nam.\n\nI agree to the Terms of Use (Part A) and consent to CÓMPANY CO., LTD processing my personal data under the Privacy Notice (Part B), including hosts of events I book receiving my phone number, and storage outside Vietnam.")
                .font(.system(size: 12.5)).lineSpacing(4)
            Text("Ô đánh dấu không được chọn sẵn. Mỗi điểm trong tóm tắt mở tới điều tương ứng bên dưới.\nThe box is never pre-ticked. Each point in the summary opens the matching section below.")
                .font(.system(size: 11)).opacity(0.6)
        }
        .padding(14)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(app.palette.rule, lineWidth: 1))
        .padding(.top, 16)
    }

    // MARK: - Part A

    private var partA: some View {
        Group {
            section("A1", "A1. Chúng tôi và bạn", "A1. Us and you") {
                bi("banbe do CÔNG TY TNHH CÓMPANY (“chúng tôi”) vận hành, trụ sở [registered address], mã số doanh nghiệp [enterprise code]. Tạo tài khoản hoặc dùng banbe là bạn chấp nhận các điều khoản này. Bản tiếng Việt được ưu tiên áp dụng.",
                   "banbe is operated by CÓMPANY CO., LTD (“we”), [registered address], enterprise code [enterprise code]. Creating an account or using banbe means you accept these terms. The Vietnamese text prevails.")
            }
            section("A2", "A2. banbe là trung gian", "A2. banbe is an intermediary") {
                bi("banbe là dịch vụ trung gian kết nối người tổ chức (host) với khách: ghi nhận đặt chỗ cùng trạng thái thanh toán và hoàn tiền do hai bên xác nhận, chuyển thông tin giữa hai bên và cho hai bên nhắn tin. Khi đặt chỗ, bạn thoả thuận trực tiếp với host chứ không phải với banbe. Chúng tôi không tổ chức sự kiện, không bán vé, không giữ hay chuyển tiền của ai, và không phải trung gian thanh toán. Dùng banbe không mất phí. Nếu sau này banbe thu phí dịch vụ của mình, chúng tôi sẽ báo trước và không áp dụng cho những gì bạn đã đặt.",
                   "banbe is an intermediary service connecting hosts with guests: it records bookings and the payment and refund status the two sides confirm, passes information between them and lets them message. When you book, the agreement is directly between you and the host, not with banbe. We do not run events, sell tickets, or hold or transfer anyone's money, and we are not a payment intermediary. Using banbe costs you nothing. If banbe later charges a fee for its own service, we will say so in advance and nothing you have already booked is charged.")
            }
            section("A3", "A3. Tài khoản", "A3. Your account") {
                bi("Từ 16 tuổi để dùng, 18 tuổi để tổ chức; dưới 18 tuổi nên dùng banbe với sự giám sát của cha mẹ hoặc người giám hộ. Mỗi người một tài khoản, trên số điện thoại thật đã xác minh của chính bạn (tài khoản tạo trước khi yêu cầu này áp dụng có thể được yêu cầu bổ sung sau), kèm một địa chỉ email để nhận vé và ngày sinh để xác nhận độ tuổi. Mọi việc làm từ tài khoản của bạn được coi là do bạn làm, cho đến khi bạn báo cho chúng tôi rằng tài khoản bị người khác sử dụng. Tài khoản được coi là không hoạt động khi bạn không đăng nhập và không có đặt chỗ nào đang hiệu lực. [Kế hoạch, chưa triển khai] Chúng tôi dự định tự động xoá tài khoản không hoạt động liên tục 6 tháng (14 tháng với hồ sơ tổ chức), có email nhắc trước; hiện tại tính năng này CHƯA hoạt động — xoá tài khoản hôm nay luôn do bạn chủ động thực hiện trong Tuỳ chọn.",
                   "16 or older to use banbe, 18 to host; under 18 should use banbe with a parent's or guardian's supervision. One account per person, on your own verified phone number (accounts created before this requirement may be asked to add it later), with an email address where tickets are sent and a date of birth to confirm your age. Anything done from your account is treated as done by you, until you tell us someone else used your account. An account counts as inactive when you have not signed in and hold no live booking. [Planned, not yet built] We intend to automatically delete accounts left inactive for 6 months (14 months with an organizer profile), with reminder emails beforehand; this is NOT active yet — today, deleting an account is always something you do yourself in Preferences.")
            }
            section("A4", "A4. Giữ chỗ, và chuyện tiền nong", "A4. Holding a seat, and money") {
                bi("Bấm “Giữ chỗ” tạo một đặt chỗ với mã sáu ký tự. Sự kiện miễn phí được xác nhận ngay. Với sự kiện thu tiền, chỗ được giữ 30 phút để bạn chuyển tiền cho host và gửi bằng chứng chuyển khoản; hết 30 phút mà chưa thanh toán thì chỗ được nhả. Host được yêu cầu xác nhận đã nhận tiền trong 1 giờ; banbe không tự xác nhận thay host, và vé có mã QR chỉ được cấp sau khi host xác nhận. Một số sự kiện cần host duyệt trước khi đặt chỗ được xác nhận. Một đặt chỗ có thể gồm nhiều vé (tối đa 6), mỗi vé ghi tên và ngày sinh của một người tham dự và có mã QR riêng; vé có thể được tặng cho người khác. Mỗi khách một đặt chỗ đang hiệu lực cho mỗi sự kiện. Số chỗ do host đặt ra; hết chỗ thì không giữ thêm được.",
                   "Tapping “Hold seat” creates a booking with a six-character code. A free event confirms it at once. At a paid event the seat is held for 30 minutes while you pay the host and submit proof of transfer; if you have not paid by then the seat is released. The host is expected to confirm receipt within 1 hour; banbe does not confirm on the host's behalf, and your QR ticket is issued only after the host confirms. Some events need the host's approval before a booking is confirmed. One booking can cover several tickets (up to 6), each naming one attendee with their date of birth and carrying its own QR code; tickets can be gifted to someone else. One live booking per guest per event. Capacity is set by the host; when it is full, no further seats can be held.")
                bi("banbe không thu, giữ hay chuyển tiền của ai. banbe hiển thị thông tin nhận tiền (ngân hàng, mã QR) do host cung cấp, ghi nhận trạng thái thanh toán, bằng chứng chuyển khoản bạn gửi và hoá đơn/biên nhận host tải lên, và, nếu host kết nối nguồn thông báo chuyển khoản ngân hàng, đối chiếu các thông báo đó với đặt chỗ. Nếu sự kiện có thu tiền, host tự thu ngoài banbe và tự chịu trách nhiệm về việc đó: giá, điều kiện hoàn tiền, hoá đơn và thuế đều là việc của host, và phải được công bố trên trang sự kiện trước khi bạn giữ chỗ. Chúng tôi không đứng ra thu, giữ hay chuyển tiền của ai, không phải trung gian thanh toán, và nếu host không kết nối thông báo chuyển khoản thì chúng tôi không tự kiểm chứng được bạn đã trả hay chưa; việc xác nhận đã nhận tiền do host (hoặc admin khi có tranh chấp) thực hiện. Hãy thận trọng: không chuyển tiền cho tài khoản do người lạ nhắn riêng, và nếu có thể thì trả tại chỗ thay vì chuyển trước. Giá, số chỗ, nội dung, giờ và địa điểm do host công bố và host chịu trách nhiệm.",
                   "banbe does not collect, hold or transfer anyone's money. banbe displays the payment details (bank account, QR code) the host provides, records payment status, the transfer proof you submit and the invoices/receipts a host uploads, and, if a host connects a bank transfer-notification feed, matches those notifications to bookings. If an event charges, the host collects it outside banbe and answers for it: price, refund terms, invoices and tax are the host's, and must be published on the event page before you hold a seat. We do not collect, hold or transfer anyone's money, we are not a payment intermediary, and unless a host connects such a feed we cannot ourselves verify whether you paid; the host (or an admin, in a dispute) confirms receipt. Take care: never transfer to an account someone sends you privately, and where you can, pay at the door rather than in advance. Price, capacity, contents, time and venue are the host's statements and the host's responsibility.")
            }
            section("A5", "A5. Huỷ và có mặt", "A5. Cancelling and showing up") {
                bi("Bạn huỷ chỗ bất kỳ lúc nào trước giờ sự kiện, ngay trong ứng dụng. Host có thể huỷ sự kiện; chúng tôi báo trong ứng dụng cho những người đang giữ chỗ, và host có thể soạn email xin lỗi để gửi từ hộp thư của chính host. Nếu bạn đã trả tiền cho host, việc hoàn tiền theo đúng điều kiện host đã công bố và được giải quyết trực tiếp giữa bạn và host: banbe không giữ tiền nên không hoàn tiền thay host; banbe chỉ ghi nhận yêu cầu hoàn tiền, nơi nhận hoàn tiền bạn chọn và trạng thái do bạn và host xác nhận. Quyền đòi host theo pháp luật của bạn không đổi, và bạn có thể báo cho chúng tôi qua [contact email] để chúng tôi xem xét hồ sơ host.",
                   "You can cancel a seat any time before the event, in the app. A host may cancel an event; we notify everyone holding a seat in the app, and the host can draft an apology email to send from their own mailbox. If you have paid the host, any refund follows the terms the host published and is settled directly between you and the host: banbe holds no money, so we cannot refund in a host's place; banbe only records the refund request, the refund destination you choose and the status that you and the host confirm. Your legal claim against the host is unchanged, and you can report a host to us at [contact email] so we can review their profile.")
                bi("Khi host cho biết đã hoàn tiền qua banbe, bạn có 7 ngày kể từ lúc đó để bấm “Đã nhận tiền” hoặc báo chưa nhận được. Nếu bạn không làm gì, khoản hoàn sẽ được tự động xác nhận sau 7 ngày. Nếu quá hạn hoàn tiền mà bạn chưa nhận được tiền, bạn có thể nhắn cho host qua banbe; nếu vẫn chưa được, bạn có thể báo tranh chấp và admin banbe sẽ xem xét trong mục “Tranh chấp thanh toán”. banbe vẫn không giữ tiền và không chuyển tiền thay host. Khi báo tranh chấp, bạn và host trao đổi trong một cuộc trò chuyện tranh chấp riêng và có thể đính kèm tệp làm bằng chứng; admin banbe đọc cuộc trò chuyện và các tệp đó để quyết định. Khi tranh chấp hoàn tiền đã đóng, ở những nơi ứng dụng hỗ trợ bạn có thể xuất bản ghi cuộc trò chuyện, và chọn “đóng và xoá bản của tôi”: bản của bạn bị ẩn ngay, còn bản của host được giữ đến hạn xoá nêu ở Điều B7.",
                   "When a host reports having sent a refund through banbe, you have 7 days from that moment to press “Confirm received” or report that you have not received it. If you do nothing, the refund is confirmed automatically after 7 days. If the refund deadline passes and you have not received the money, you can message the host through banbe; if that does not resolve it, you can raise a dispute and a banbe admin will review it under “Payment disputes”. banbe still holds no money and does not transfer money in a host's place. When you raise a dispute, you and the host talk in a separate dispute chat and can attach files as evidence; a banbe admin reads that chat and those files to decide. Once a refund dispute is closed, where the app supports it you can export a transcript, and choose “close and delete my copy”: your copy is hidden at once, while the host's copy is kept until the deletion deadline in Section B7.")
                bi("Tại cửa, host ghi nhận bạn đã đến theo mã QR hoặc mã trên vé, hoặc theo tên nếu bạn không mở được vé. Không đến mà không huỷ có thể bị ghi vắng mặt; số lần tham dự và vắng mặt hiện cho host của các sự kiện bạn đặt sau; các số này được tính cho người thực sự giữ vé.",
                   "At the door the host marks you arrived by the QR or code on your ticket, or by name if you cannot open it. Not turning up without cancelling may be marked a no-show; your attended and no-show counts are visible to hosts you book later; these counts are credited to the person who actually holds the ticket.")
            }
            section("A6", "A6. Tổ chức", "A6. Hosting") {
                bi("Đăng sự kiện là bạn cam kết: từ 18 tuổi và có quyền dùng địa điểm; thông tin chính xác và được cập nhật; chịu trách nhiệm về an toàn, giấy phép, thuế thu nhập và tuân thủ pháp luật, gồm không phục vụ đồ uống có cồn cho người dưới 18 tuổi; nếu có thu tiền thì công bố rõ giá và điều kiện hoàn tiền trên trang sự kiện, tự thu và tự hoàn tiền ngoài banbe (bạn có thể dùng banbe để ghi nhận trạng thái thanh toán, hoàn tiền và tải lên hoá đơn/biên nhận); chỉ nhắn quảng bá cho khách đã bật đồng ý riêng và chỉ dùng số điện thoại của họ cho việc đó; ảnh là của bạn và không có mặt khách chưa đồng ý.",
                   "Publishing an event is your promise that: you are 18 or older with the right to use the venue; the listing is accurate and kept current; you answer for safety, permits, tax on your income and legal compliance, including no alcohol for anyone under 18; if you charge, you publish the price and refund terms on the event page and collect and refund outside banbe yourself (you may use banbe to record payment and refund status and to upload invoices/receipts); you send promotional messages only to guests who opted in separately and use their phone number only for that; photos are yours and show no guest's face without consent.")
                bi("Đồng tổ chức thấy đặt chỗ, làm cửa và nhắn tin; chỉ chủ hồ sơ sửa nội dung sự kiện, huỷ sự kiện và quản lý thành viên; bạn chịu trách nhiệm về họ. Huy hiệu “host thường xuyên” do banbe gắn thủ công theo lịch sử tổ chức; đó không phải là việc kiểm tra giấy tờ tuỳ thân hay giấy phép. Sự kiện mới được admin banbe xét duyệt trước khi hiển thị công khai. Chúng tôi có thể gỡ huy hiệu, gỡ sự kiện hoặc tạm ngưng hồ sơ khi có khiếu nại chưa giải quyết.",
                   "Co-hosts see bookings, run the door and chat; only the profile owner edits the listing, cancels events and manages members; you answer for them. The regular host badge is set manually by banbe from hosting history; it is not a check of identity documents or permits. New events are reviewed by a banbe admin before they go public. We may remove the badge, unlist events or suspend a profile while a complaint is open.")
            }
            section("A7", "A7. Cư xử và an toàn", "A7. Conduct and safety") {
                bi("Không quấy rối, đe doạ, lừa đảo, gửi tin rác hay chia sẻ thông tin cá nhân của người khác. Tin đã gửi không sửa được; bạn xoá được tin nhắn thường của chính mình nhưng không xoá được tin nhắn trong tranh chấp. Ảnh, câu chuyện (stories), hồ sơ và nội dung khác bạn đăng vẫn thuộc về bạn, nhưng bạn cho chúng tôi quyền hiển thị, chia sẻ và xếp hạng chúng trong banbe; bạn cam đoan có quyền đăng và không đăng nội dung trái pháp luật hoặc xâm phạm quyền của người khác; chúng tôi có thể gỡ nội dung vi phạm hoặc khi có yêu cầu hợp lệ. Hồ sơ bạn chia sẻ qua liên kết có thể được người có liên kết xem. Nhân viên banbe chỉ đọc trò chuyện khi có báo cáo gửi tới [contact email], tranh chấp hoặc yêu cầu của pháp luật. Chúng tôi không kiểm tra giấy tờ tuỳ thân, giấy phép hay lý lịch của host và khách, và không có mặt tại sự kiện: hãy đọc hồ sơ host, báo cho bạn bè biết bạn đi đâu, rời đi nếu thấy không an toàn, và báo cho chúng tôi qua [contact email]; khẩn cấp gọi 113 hoặc 115.",
                   "No harassment, threats, fraud, spam or sharing other people's personal information. Sent messages cannot be edited; you can delete your own ordinary messages but not dispute messages. Photos, stories, profile and other content you post remain yours, but you grant us the right to display, share and rank them within banbe; you promise you have the right to post them and that they are not unlawful or infringing; we may remove content that breaches these terms or on a valid request. A profile you share by link can be viewed by anyone with the link. banbe staff read chats only on a report sent to [contact email], a dispute or a legal demand. We do not check the identity documents, permits or background of hosts or guests, and we are not at events: read the host's profile, tell a friend where you are going, leave if it feels wrong, and report to us at [contact email]; in an emergency call 113 or 115.")
            }
            section("A8", "A8. Trách nhiệm, chấm dứt, thay đổi, luật áp dụng", "A8. Liability, ending, changes, law") {
                bi("Chúng tôi chịu trách nhiệm cung cấp banbe như mô tả và bảo vệ dữ liệu theo Phần B; không chịu trách nhiệm về sự kiện, địa điểm, hành vi của host hay khách, hay tiền bạn chuyển cho host, trừ khi thiệt hại do lỗi của chúng tôi. Không điều khoản nào hạn chế quyền của bạn theo pháp luật bảo vệ quyền lợi người tiêu dùng. Chúng tôi có thể tạm ngưng tài khoản vi phạm hoặc có dấu hiệu lừa đảo. Bạn xoá tài khoản bất kỳ lúc nào trong Tuỳ chọn, miễn là đã huỷ sự kiện đang mở (dữ liệu: Điều B7).",
                   "We are responsible for providing banbe as described and protecting your data under Part B; not for events, venues, the conduct of hosts or guests, or money you send a host, unless the loss is our fault. Nothing here limits your rights under consumer protection law. We may suspend accounts that breach these terms or show signs of fraud. You can delete your account any time in Preferences, as long as open events are cancelled (data: Section B7).")
                bi("Thay đổi ảnh hưởng đến quyền của bạn được báo trong ứng dụng 7 ngày trước và cần bạn đồng ý lại. Áp dụng pháp luật Việt Nam. Có tranh chấp với banbe, liên hệ [contact email] trước (trả lời trong 7 ngày làm việc), sau đó là Toà án có thẩm quyền tại Việt Nam. Tranh chấp với host là giữa bạn và host; chúng tôi hỗ trợ bằng lịch sử đặt chỗ và trò chuyện khi có yêu cầu hợp lệ.",
                   "Changes affecting your rights are announced in the app 7 days ahead and need your renewed agreement. Vietnamese law applies. For a dispute with banbe, contact [contact email] first (reply within 7 working days), then the competent courts of Vietnam. Disputes with a host are between you and the host; we assist with booking and chat history on a lawful request.")
            }
        }
    }

    // MARK: - Part B

    private var partB: some View {
        Group {
            section("B1", "B1. Bên kiểm soát dữ liệu", "B1. Who controls your data") {
                bi("CÔNG TY TNHH CÓMPANY là bên kiểm soát và xử lý dữ liệu cá nhân của bạn trên banbe theo Luật Bảo vệ dữ liệu cá nhân số 91/2025/QH15 và các văn bản hướng dẫn. Liên hệ về dữ liệu: [contact email]. Host là bên kiểm soát độc lập đối với những gì họ tự ghi chép về khách ngoài banbe.",
                   "CÓMPANY CO., LTD controls and processes your personal data on banbe under the Law on Personal Data Protection No. 91/2025/QH15 and its guiding decrees. Data contact: [contact email]. Hosts are independent controllers of whatever records they keep about guests outside banbe.")
            }
            section("B2", "B2. Dữ liệu chúng tôi thu thập", "B2. What we collect") {
                policyTable(
                    columns: ["Nhóm · Group", "Gồm · Includes", "Dùng để · Used for"],
                    rows: [
                        ["Tài khoản\nAccount", "Số điện thoại, email, tên hiển thị, ảnh đại diện, ngôn ngữ\nPhone number, email, display name, avatar, language", "Đăng nhập; gửi vé; hiển thị tên cho host\nSign-in; sending tickets; showing your name to hosts"],
                        ["Xác minh\nVerification", "Mã OTP, trạng thái xác minh số điện thoại\nOTP codes, phone-verified status", "Ngăn tài khoản giả và đặt chỗ ảo\nStopping fake accounts and bogus bookings"],
                        ["Đặt chỗ\nBookings", "Sự kiện, số chỗ, mã đặt chỗ, trạng thái, ghi chú cho host, thời điểm\nEvent, seats, booking code, status, note to host, timestamps", "Giữ chỗ và gửi vé\nHolding seats and sending tickets"],
                        ["Vào cửa và lịch sử\nCheck-in and history", "Đã đến hoặc vắng mặt cho từng đặt chỗ; tổng số lần\nAttended or no-show per booking; running totals", "Tin cậy giữa host và khách\nTrust between hosts and guests"],
                        ["Trò chuyện\nChat", "Tin nhắn giữa bạn và host, thời điểm gửi và đọc\nMessages between you and the host, sent and read times", "Liên lạc; bằng chứng khi tranh chấp\nCommunication; the record in a dispute"],
                        ["Hồ sơ và sự kiện (host)\nProfile and events (hosts)", "Tên tổ chức, Instagram, giới thiệu, ảnh sự kiện, địa điểm và toạ độ sự kiện\nOrganizer name, Instagram, bio, event photos, event venue and coordinates", "Trang sự kiện công khai\nThe public event page"],
                        ["Lời mời\nInvites", "Số điện thoại khách mời do host nhập cho sự kiện riêng tư\nPhone numbers hosts enter for invite-only events", "Mở sự kiện riêng tư cho đúng người\nUnlocking a private event for the right people"],
                        ["Yêu thích, theo dõi\nFavorites, follows", "Sự kiện bạn lưu, host bạn theo dõi\nEvents you saved, hosts you follow", "Danh sách của riêng bạn\nYour own lists"],
                        ["Hoá đơn, biên nhận\nInvoices, receipts", "Tệp do host tải lên cho một khoản đã thanh toán\nFiles a host uploads for a paid booking", "Bằng chứng thanh toán giữa bạn và host\nProof of payment between you and the host"],
                        ["Người tham dự trên vé\nAttendees on tickets", "Tên và ngày sinh của từng người tham dự, mã vé và mã QR, người nhận nếu vé được tặng\nName and date of birth of each attendee, ticket code and QR, recipient if a ticket is gifted", "Cấp vé từng người, kiểm tra tuổi và vào cửa\nPer-person tickets, age checks and entry"],
                        ["Ngày sinh tài khoản\nAccount date of birth", "Ngày sinh bạn nhập (ứng dụng không đọc lại được), xác nhận theo từng phiên đăng nhập\nThe date of birth you enter (not readable back by the apps), confirmed per sign-in session", "Xác nhận độ tuổi\nConfirming your age"],
                        ["Thanh toán và hoàn tiền\nPayments and refunds", "Trạng thái thanh toán, bằng chứng chuyển khoản bạn gửi, thông báo chuyển khoản do host kết nối (số tiền, nội dung, dữ liệu gốc của nhà cung cấp), yêu cầu hoàn tiền và nơi nhận hoàn tiền bạn chọn (ngân hàng, số tài khoản, tên chủ tài khoản)\nPayment status, the transfer proof you submit, transfer notifications a host connects (amount, memo, the provider's raw payload), refund requests and the refund destination you choose (bank, account number, account holder name)", "Đối chiếu thanh toán và hoàn tiền giữa bạn và host\nReconciling payments and refunds between you and the host"],
                        ["Tranh chấp\nDisputes", "Tin nhắn và tệp đính kèm trong cuộc trò chuyện tranh chấp, quyết định của admin\nMessages and attachments in the dispute chat, the admin's decision", "Giải quyết tranh chấp\nResolving disputes"],
                        ["Thông tin xuất hoá đơn\nBilling details", "Tên, địa chỉ, số điện thoại, mã số thuế nếu bạn nhập\nName, address, phone, tax code if you enter them", "Hoá đơn, biên nhận\nInvoices and receipts"],
                        ["Thiết bị nhận thông báo\nNotification devices", "Mã thiết bị nhận thông báo đẩy; đăng ký thẻ Apple Wallet\nPush-notification device token; Apple Wallet pass registrations", "Gửi thông báo đẩy và cập nhật thẻ Wallet\nSending push notifications and updating Wallet passes"],
                        ["Khảo sát quan tâm\nInterest surveys", "Câu trả lời khảo sát: mức quan tâm, ngày, khu vực, ngân sách, hoạt động, quy mô nhóm\nSurvey answers: interest level, dates, areas, budget, activities, group size", "Giúp host quyết định có tổ chức sự kiện hay không\nHelping hosts decide whether to run an event"],
                        ["Stories và hồ sơ công khai\nStories and public profile", "Stories và lượt xem, lượt thích và chia sẻ ảnh, sở thích, thành phố, tên người dùng\nStories and views, photo likes and shares, interests, city, handle", "Hiển thị và xếp hạng nội dung trong banbe\nDisplaying and ranking content in banbe"],
                        ["Đồng ý nhận quảng bá từ host\nHost promotion opt-in", "Lựa chọn đồng ý (mặc định tắt) và nhật ký mỗi lần host soạn tin\nYour opt-in choice (off by default) and a log each time a host composes a message", "Chỉ cho phép host nhắn quảng bá khi bạn đồng ý\nLetting hosts send promotions only with your consent"],
                        ["Ghi nhận đồng ý\nConsent record", "Thời điểm và phiên bản điều khoản bạn đã đồng ý\nWhen and to which version of these terms you agreed", "Chứng minh sự đồng ý\nProof of consent"],
                        ["Yêu cầu xoá tài khoản\nAccount-deletion requests", "Lý do bạn nhập và các bước xử lý\nThe reason you enter and the processing steps", "Chứng minh yêu cầu đã được xử lý\nShowing the request was handled"],
                        ["Đăng nhập qua Google/Facebook\nGoogle/Facebook sign-in", "Email, tên hiển thị và ảnh đại diện do Google/Facebook cung cấp khi bạn chọn đăng nhập bằng dịch vụ đó\nEmail, display name and avatar that Google/Facebook provide when you choose to sign in that way", "Tạo và đăng nhập tài khoản\nCreating and signing in to your account"],
                        ["Thông báo trong ứng dụng\nIn-app notifications", "Thông báo về đặt chỗ, thanh toán, tranh chấp, sự kiện\nNotices about your bookings, payments, disputes, events", "Báo cho bạn biết diễn biến; bạn xoá được từng thông báo bất kỳ lúc nào\nKeeping you informed; you can delete each one at any time"],
                        ["Kỹ thuật\nTechnical", "Địa chỉ IP, loại thiết bị và trình duyệt, nhật ký truy cập và lỗi\nIP address, device and browser type, access and error logs", "Bảo mật, giới hạn tần suất, sửa lỗi\nSecurity, rate limiting, fixing bugs"],
                    ]
                )
                bi("Chúng tôi không thu thập: danh bạ, giấy tờ tuỳ thân, số thẻ thanh toán hay thông tin đăng nhập ngân hàng của bạn (số tài khoản nhận hoàn tiền bạn nhập và tài khoản nhận tiền của host được lưu như nêu ở bảng trên). Với vị trí thiết bị: nếu bạn cho phép, ứng dụng đọc vị trí hiện tại để tính khoảng cách tới sự kiện và định vị bản đồ gần bạn; toạ độ này xử lý ngay trên thiết bị của bạn và không được gửi về máy chủ hay lưu trữ. Giao dịch diễn ra trong ứng dụng ngân hàng hoặc ví của bạn; phần chúng tôi nhận được là thông báo chuyển khoản từ tài khoản host đã kết nối, gồm số tiền, nội dung và dữ liệu gốc do nhà cung cấp thông báo gửi (có thể gồm tên và số tài khoản người chuyển), như nêu ở bảng trên.",
                   "We do not collect: contacts, identity documents, payment card numbers or your banking credentials (the refund account number you enter and a host's receiving account are stored, as set out in the table above). Device location: if you grant permission, the app reads your current position to show distance to events and to center the nearby map; this happens on your device only and is never sent to or stored on our servers. The transfer happens in your bank or wallet app; what reaches us is the transfer notification from the host's connected account, with the amount, memo and the notification provider's raw payload (which may include the sender's name and account number), as set out in the table above.")
            }
            section("B3", "B3. Mục đích và cơ sở xử lý", "B3. Purposes and legal basis") {
                bi("Chúng tôi xử lý dữ liệu để: (1) cung cấp dịch vụ đặt chỗ và trò chuyện bạn yêu cầu, gồm gửi vé, tức thực hiện hợp đồng với bạn; (2) giữ nền tảng an toàn và chống gian lận, gồm xác minh số điện thoại và thống kê vắng mặt, trên cơ sở sự đồng ý bạn đưa ra khi đăng ký; (3) tuân thủ nghĩa vụ pháp luật, gồm lưu trữ và cung cấp thông tin khi cơ quan có thẩm quyền yêu cầu đúng luật; (4) gửi thông báo về đặt chỗ và sự kiện của bạn.",
                   "We process data to: (1) provide the reservation and chat service you asked for, including sending tickets, that is, perform our contract with you; (2) keep the platform safe and prevent fraud, including phone verification and no-show counts, on the basis of the consent you give at sign-up; (3) meet legal obligations, including retaining and disclosing information when a competent authority lawfully requires it; (4) send you notices about your bookings and events.")
                bi("Chúng tôi không dùng dữ liệu cho quảng cáo của banbe (host chỉ nhắn quảng bá cho khách đã bật đồng ý riêng, mỗi lần một người nhận và có ghi nhật ký), không phân tích nội dung trò chuyện, và không ra quyết định tự động ảnh hưởng đến bạn ngoài việc đếm số lần vắng mặt như nêu tại Điều A5.",
                   "We do not use data for banbe's own advertising (hosts may send promotions only to guests who opted in separately, one recipient at a time, with a log), analyze chat content, or make automated decisions about you other than counting no-shows as described in Section A5.")
                bi("Khi tranh chấp được giải quyết, chúng tôi luôn gửi email xác nhận cho cả khách và host. Khi host tải lên hoặc thay hoá đơn/biên nhận: bạn luôn được thông báo trong ứng dụng; email chỉ được gửi nếu bạn đã bật mục “tự động gửi email hoá đơn” trong Tuỳ chọn, trừ khi hoá đơn/biên nhận bị thay thế — trường hợp đó luôn có email để bạn kịp tải bản cũ trước khi bị xoá.",
                   "When a dispute is resolved, we always email a confirmation to both the guest and the host. When a host uploads or replaces an invoice/receipt: you are always notified in the app; an email is sent only if you turned on “auto-email documents” in Preferences — except when a document is replaced, which always emails you so you have time to download the old one before it's gone.")
            }
            section("B4", "B4. Ai nhìn thấy gì", "B4. Who sees what") {
                policyTable(
                    columns: ["Dữ liệu · Data", "Ai thấy · Who sees it"],
                    rows: [
                        ["Số điện thoại, email\nPhone number, email", "Bạn, banbe, và host của sự kiện bạn đặt. Email: bạn và banbe; host chỉ thấy email của người giữ chỗ khi soạn email huỷ sự kiện gửi khách.\nYou, banbe, and the host of an event you book. Email: you and banbe; a host sees ticket-holders' emails only when drafting an event-cancellation email to guests."],
                        ["Tên, ảnh, số lần tham dự và vắng mặt\nName, avatar, attended and no-show counts", "Host và đồng tổ chức của sự kiện bạn đặt; người bạn trò chuyện.\nHosts and co-hosts of events you book; people you chat with."],
                        ["Đặt chỗ, vào cửa\nBookings, check-ins", "Bạn, host và đồng tổ chức của sự kiện đó.\nYou, and the host and co-hosts of that event."],
                        ["Trò chuyện\nChat", "Hai bên trong cuộc trò chuyện; nhân viên banbe khi có báo cáo hoặc tranh chấp.\nThe two parties; banbe staff when there is a report or dispute."],
                        ["Hoá đơn, biên nhận\nInvoices, receipts", "Bạn và host của sự kiện đó. banbe (kể cả nhân viên) không xem được các tệp này.\nYou and the host of that event. banbe (including staff) cannot view these files."],
                        ["Hồ sơ host, sự kiện công khai, ảnh, địa điểm\nHost profile, public events, photos, venue", "Mọi người, kể cả chưa đăng nhập. Host tổ chức tại nhà riêng có thể chọn chỉ hiện khu vực.\nEveryone, including without an account. Hosts using their own home can choose to show only the area."],
                        ["Sự kiện riêng tư\nInvite-only events", "Người có đường dẫn, hoặc có số điện thoại đã xác minh nằm trong danh sách mời.\nPeople with the link, or whose verified phone number is on the invite list."],
                        ["Tên và ngày sinh người tham dự trên vé\nAttendee name and date of birth on tickets", "Người mua vé thấy cả nhóm; host và đồng tổ chức thấy tên và ngày sinh khi vào cửa (giới hạn tần suất, có ghi nhật ký); admin banbe khi xử lý tranh chấp.\nThe buyer sees the whole party; the host and co-hosts see name and date of birth at check-in (rate-limited and logged); banbe admins when handling a dispute."],
                        ["Thanh toán, hoàn tiền\nPayments, refunds", "Bạn, host và đồng tổ chức của sự kiện đó; admin banbe khi có tranh chấp. Dữ liệu gốc của thông báo chuyển khoản chỉ máy chủ banbe đọc được.\nYou, and the host and co-hosts of that event; banbe admins in a dispute. The raw transfer-notification data is readable only by banbe's servers."],
                        ["Tranh chấp, tệp đính kèm\nDisputes, attachments", "Bạn, host và admin banbe.\nYou, the host and banbe admins."],
                        ["Stories, hồ sơ cá nhân, câu trả lời khảo sát\nStories, personal profile, survey answers", "Người dùng banbe; hồ sơ bạn chia sẻ qua liên kết xem được bởi người có liên kết. Câu trả lời khảo sát: host của khảo sát và banbe.\nbanbe users; a profile you share by link can be viewed by anyone with the link. Survey answers: the survey's host and banbe."],
                    ]
                )
            }
            section("B5", "B5. Bên xử lý thay chúng tôi", "B5. Who processes data for us") {
                bi("Chúng tôi dùng: Supabase (cơ sở dữ liệu, xác thực, lưu trữ tệp); Vercel (lưu trữ ứng dụng web); [Vietnamese SMS provider] để gửi mã OTP; Google để gửi email đăng nhập, email vé và email thông báo, và (cùng với Meta/Facebook) để xác thực nếu bạn chọn đăng nhập bằng Google hoặc Facebook. Chúng tôi cũng dùng nhà cung cấp thông báo chuyển khoản ngân hàng mà host chọn kết nối (như Casso, PayOS), OpenFreeMap (bản đồ), OpenStreetMap Nominatim (tìm địa chỉ) và Google Fonts (phông chữ trên web); các bên này có thể thấy địa chỉ IP của bạn. Các bên xử lý thay chúng tôi chỉ xử lý theo chỉ dẫn của chúng tôi và không được dùng dữ liệu cho mục đích riêng; riêng Google và Meta khi bạn chọn đăng nhập bằng họ là bên cung cấp danh tính độc lập, theo chính sách riêng của họ.",
                   "We use: Supabase (database, authentication, file storage); Vercel (web app hosting); [Vietnamese SMS provider] to deliver OTP codes; Google to deliver sign-in, ticket and notice emails, and (together with Meta/Facebook) to authenticate you if you choose to sign in with Google or Facebook. We also use the bank transfer-notification providers a host chooses to connect (such as Casso, PayOS), OpenFreeMap (maps), OpenStreetMap Nominatim (address search) and Google Fonts (web fonts); these may see your IP address. Those who process data for us do so only on our instructions and may not use the data for their own purposes; Google and Meta, when you choose to sign in with them, are independent identity providers under their own policies.")
                bi("Chúng tôi không bán, cho thuê hay trao đổi dữ liệu cá nhân. Chúng tôi cung cấp dữ liệu cho cơ quan nhà nước khi có yêu cầu hợp pháp bằng văn bản, và thông báo cho bạn khi pháp luật cho phép.",
                   "We do not sell, rent or trade personal data. We disclose data to state agencies on a lawful written request, and tell you when the law allows.")
            }
            section("B6", "B6. Dữ liệu ra khỏi Việt Nam", "B6. Data leaving Vietnam") {
                bi("Dữ liệu banbe được lưu trên máy chủ của Supabase đặt ngoài Việt Nam, và Vercel có thể xử lý tại nhiều quốc gia. Đây là việc chuyển dữ liệu cá nhân ra nước ngoài theo Luật Bảo vệ dữ liệu cá nhân; chúng tôi lập hồ sơ đánh giá tác động chuyển dữ liệu và thực hiện nghĩa vụ với Bộ Công an theo quy định. Ô đánh dấu ở màn hình đăng ký là sự đồng ý của bạn cho việc chuyển này.",
                   "banbe data is stored on Supabase servers outside Vietnam, and Vercel may process it in several countries. This is a cross-border transfer of personal data under the PDPL; we maintain a transfer impact assessment dossier and meet our duties to the Ministry of Public Security as required. The box on the sign-up screen is your consent to that transfer.")
            }
            section("B7", "B7. Lưu bao lâu, và khi bạn xoá tài khoản", "B7. How long we keep it, and what deletion does") {
                policyTable(
                    columns: ["Dữ liệu · Data", "Lưu đến khi · Kept until"],
                    rows: [
                        ["Tài khoản, hồ sơ, yêu thích, theo dõi\nAccount, profile, favorites, follows", "Khi bạn tự xoá tài khoản trong Tuỳ chọn; xoá ngay lập tức. (Xoá tự động sau một thời gian không hoạt động là kế hoạch, chưa triển khai — xem Điều A3.)\nWhen you delete your account yourself in Preferences; removed immediately. (Automatic deletion after a period of inactivity is planned, not yet built — see Section A3.)"],
                        ["Mã OTP\nOTP codes", "Một ngày sau khi hết hạn.\nOne day after expiry."],
                        ["Đặt chỗ, vào cửa\nBookings, check-ins", "Giữ làm sổ sách của host cho đến khi bạn xoá tài khoản; khi bạn xoá tài khoản, các đặt chỗ của bạn bị xoá cùng.\nKept as the host's ledger until you delete your account; deleting your account deletes your bookings with it."],
                        ["Trò chuyện\nChat", "Trò chuyện thường: không tự động xoá theo thời gian; bạn xoá được từng tin nhắn của mình bất kỳ lúc nào. Trò chuyện tranh chấp: sau khi tranh chấp được giải quyết, toàn bộ nội dung bị xoá vĩnh viễn trong vòng 72 giờ (7 ngày với tranh chấp hoàn tiền; “đóng và xoá bản của tôi” chỉ ẩn ngay bản của bạn, bản của host giữ đến hạn đó); bạn không tự xoá được tin nhắn tranh chấp trước đó.\nOrdinary chat: not erased automatically by time; you can delete your own individual messages at any time. Dispute chat: once a dispute is resolved, its full content is permanently deleted within 72 hours (7 days for refund disputes; “close and delete my copy” hides only your copy at once, the host's copy stays until that deadline); you cannot delete dispute messages yourself beforehand."],
                        ["Hoá đơn, biên nhận\nInvoices, receipts", "12 tháng sau ngày sự kiện. Nếu bị thay thế, bản cũ bị xoá sau 24 giờ.\n12 months after the event date. If replaced, the old file is deleted after 24 hours."],
                        ["Thông báo trong ứng dụng\nIn-app notifications", "Không tự động xoá theo thời gian; bạn xoá bất kỳ lúc nào.\nNot erased automatically by time; you delete them yourself, any time."],
                        ["Danh sách mời\nInvite lists", "30 ngày sau sự kiện.\n30 days after the event."],
                        ["Ảnh sự kiện\nEvent photos", "Cùng với sự kiện; host xoá được bất kỳ lúc nào.\nWith the event; hosts can delete any time."],
                        ["Nhật ký kỹ thuật\nTechnical logs", "30 ngày.\n30 days."],
                        ["Người tham dự trên vé\nTicket attendees", "Cùng với đặt chỗ.\nWith the booking."],
                        ["Thanh toán và hoàn tiền\nPayments and refunds", "Cùng với đặt chỗ; dữ liệu gốc của thông báo chuyển khoản hiện chưa có thời hạn xoá tự động.\nWith the booking; the raw transfer-notification data currently has no automatic deletion deadline."],
                        ["Yêu cầu xoá tài khoản\nAccount-deletion requests", "Giữ lại sau khi xoá để chứng minh yêu cầu đã được xử lý.\nKept after deletion to show the request was handled."],
                        ["Hồ sơ sự cố dữ liệu\nData-breach records", "5 năm theo quy định pháp luật.\n5 years, as the law requires."],
                    ]
                )
                bi("Xoá tài khoản là tự phục vụ trong Tuỳ chọn — không cần gửi yêu cầu hỗ trợ, chỉ cần xác nhận vài bước ngay trong ứng dụng. Việc xoá bị từ chối trong khi bạn còn sở hữu sự kiện đang mở; hãy huỷ hoặc kết thúc sự kiện trước. Sau khi xoá, chúng tôi không thể khôi phục tài khoản. Một số tệp (như chứng từ thanh toán) bị xoá theo thời hạn riêng nêu trong bảng trên chứ không phải ngay khi xoá tài khoản. (Việc tự động xoá do không hoạt động lâu ngày, nêu tại Điều A3, là kế hoạch và chưa được triển khai trong phiên bản hiện tại.)",
                   "Deleting your account is self-service in Preferences — no support request needed, just a few in-app confirmation steps. Deletion is refused while you still own an open event; cancel or end it first. After deletion we cannot restore the account. Some files (such as payment documents) are deleted on their own schedule in the table above, not at the moment you delete the account. (Automatic deletion for long inactivity, described in Section A3, is planned and not yet implemented in the current version.)")
            }
            section("B8", "B8. Quyền của bạn", "B8. Your rights") {
                bi("Theo Luật Bảo vệ dữ liệu cá nhân, bạn có quyền: được biết về việc xử lý; đồng ý hoặc không đồng ý; truy cập và xem dữ liệu; chỉnh sửa; rút lại sự đồng ý; xoá dữ liệu; hạn chế xử lý; được cung cấp bản sao dữ liệu; phản đối xử lý; khiếu nại, tố cáo, khởi kiện; yêu cầu bồi thường thiệt hại; và tự bảo vệ.",
                   "Under the PDPL you have the right to: be informed about processing; consent or refuse; access and view your data; correct it; withdraw consent; have it deleted; restrict processing; obtain a copy; object; complain, denounce or sue; claim damages; and protect yourself.")
                bi("Bạn xem và sửa tên, ảnh, ngôn ngữ trong Tuỳ chọn, và xoá tài khoản tại đó. Với các yêu cầu khác (bản sao dữ liệu, hạn chế, phản đối), gửi tới [contact email] từ số điện thoại hoặc email đã đăng ký; chúng tôi xác nhận trong 2 ngày làm việc và xử lý xong trong 7 ngày. Rút lại đồng ý không ảnh hưởng đến việc xử lý đã diễn ra trước đó, và một số dữ liệu vẫn được giữ theo Điều B7 do nghĩa vụ với host hoặc theo pháp luật.",
                   "You can view and edit your name, photo and language in Preferences, and delete your account there. For other requests (a copy of your data, restriction, objection), write to [contact email] from your registered phone number or email; we acknowledge within 2 working days and complete the request within 7 days. Withdrawing consent does not undo processing already done, and some data is still kept under Section B7 because of obligations to hosts or the law.")
                bi("Bạn có quyền khiếu nại tới Cục An ninh mạng và phòng, chống tội phạm sử dụng công nghệ cao (A05), Bộ Công an.",
                   "You may complain to the Department of Cyber Security and High-Tech Crime Prevention (A05), Ministry of Public Security.")
            }
            section("B9", "B9. Trẻ em", "B9. Children") {
                bi("banbe không dành cho người dưới 16 tuổi và chúng tôi không cố ý thu thập dữ liệu của họ. Nếu phát hiện tài khoản của người dưới 16 tuổi, chúng tôi xoá tài khoản và dữ liệu. Phụ huynh có thể liên hệ [contact email].",
                   "banbe is not for anyone under 16 and we do not knowingly collect their data. If we find an account belonging to someone under 16, we delete the account and its data. Parents may contact [contact email].")
            }
            section("B10", "B10. Bảo mật và sự cố", "B10. Security and incidents") {
                bi("Dữ liệu được mã hoá khi truyền. Quyền truy cập được kiểm soát theo từng dòng ngay trong cơ sở dữ liệu, nên host chỉ thấy khách của mình và khách chỉ thấy đặt chỗ của mình. Số nhân viên có quyền truy cập được giữ ở mức tối thiểu và các truy cập nhạy cảm (như xem ngày sinh khi vào cửa) được ghi lại.",
                   "Data is encrypted in transit. Access is controlled row by row inside the database itself, so hosts see only their own guests and guests only their own bookings. The number of staff with access is kept minimal and sensitive accesses (such as viewing a date of birth at check-in) are logged.")
                bi("Nếu xảy ra sự cố dữ liệu có thể gây hại cho bạn, chúng tôi thông báo cho Bộ Công an trong 72 giờ kể từ khi phát hiện, và thông báo cho bạn qua ứng dụng hoặc số điện thoại đã đăng ký, nêu rõ điều gì đã xảy ra và bạn nên làm gì.",
                   "If a data incident occurs that could harm you, we notify the Ministry of Public Security within 72 hours of detection, and notify you through the app or your registered phone number, saying what happened and what you should do.")
            }
            section("B11", "B11. Lưu trữ trên thiết bị", "B11. On-device storage") {
                bi("banbe lưu phiên đăng nhập và tuỳ chọn ngôn ngữ trên thiết bị của bạn để bạn không phải đăng nhập lại mỗi lần. Chúng tôi không dùng cookie quảng cáo hay công cụ theo dõi của bên thứ ba (ngoài các dịch vụ bản đồ và phông chữ nêu ở Điều B5).",
                   "banbe stores your sign-in session and language preference on your device so you do not have to sign in every time. We use no advertising cookies or third-party trackers (beyond the map and font services in Section B5).")
            }
            section("B12", "B12. Thay đổi thông báo này", "B12. Changes to this notice") {
                bi("Khi thay đổi mục đích xử lý hoặc loại dữ liệu thu thập, chúng tôi xin lại sự đồng ý của bạn trong ứng dụng trước khi áp dụng. Các thay đổi khác được đăng kèm ngày hiệu lực.",
                   "If we change the purposes of processing or the kinds of data collected, we ask for your consent again in the app before the change applies. Other changes are posted with their effective date.")
            }
        }
    }

    // MARK: - Building blocks

    private func bi(_ vi: String, _ en: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(vi).opacity(0.92)
            Text(en).opacity(0.68)
        }
        .font(.system(size: 13)).lineSpacing(4)
        .padding(.bottom, 8)
    }

    private func summaryItem(_ vi: String, _ en: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(vi).opacity(0.92)
            Text(en).opacity(0.68)
        }
        .font(.system(size: 13)).lineSpacing(3)
    }

    private func partHeading(_ vi: String, _ en: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(vi).font(BanbeTheme.display(19))
            Text(en).font(BanbeTheme.display(15)).opacity(0.7)
        }
        .padding(.top, 26)
    }

    private func section<Content: View>(_ id: String, _ titleVi: String, _ titleEn: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(titleVi).font(.system(size: 14, weight: .semibold))
            Text(titleEn).font(.system(size: 12.5, weight: .semibold)).opacity(0.65)
                .padding(.bottom, 8)
            content()
        }
        .padding(.top, 14)
        .overlay(alignment: .top) { Rectangle().fill(app.palette.rule).frame(height: 1) }
        .padding(.top, 18)
        .accessibilityIdentifier("policy-section-\(id)")
    }

    // Each cell packs "Vietnamese\nEnglish" (matching the source markdown
    // table's own bilingual cells) — split and stacked rather than shortened.
    private func policyTable(columns: [String], rows: [[String]]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(columns, id: \.self) { col in
                    Text(col).font(.system(size: 12, weight: .semibold)).opacity(0.6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) { Rectangle().fill(app.palette.rule).frame(height: 1) }

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(cell).font(.system(size: 12)).lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) { Rectangle().fill(app.palette.rule).frame(height: 1) }
            }
        }
        .padding(.bottom, 12)
    }
}
