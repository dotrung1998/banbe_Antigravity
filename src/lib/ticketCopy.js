// "What's next" strip copy (note 78), one language per call. The owner approved this table on 2026-11-05; every line is
// either a plain fact about the booking or the meaning of an existing app string (refund responsibility, expired hold,
// dispute). Nothing here is policy text and no time, door or reply-speed claim is made that the data does not hold.
// The link kind names an EXISTING action; the screen wires it (and drops the link when its data is missing).

/**
 * @param {string} key  a ticketCase key
 * @param {{en?: boolean, eventCancelled?: boolean, dateText?: string, timeText?: string, areaText?: string,
 *          daysUntil?: number|null, typicalWait?: {vi: string, en: string}|null, verifyOverdue?: boolean,
 *          hasReceipt?: boolean, hasRefund?: boolean, hasDirections?: boolean}} ctx
 * @returns {{label: string, heading: string, sub: string|null, detail: string|null,
 *            link: {kind: string, label: string}|null}|null}
 */
export function ticketCopy(key, ctx = {}) {
  const { en = false, eventCancelled = false, dateText = '', timeText = '', areaText = '', daysUntil = null,
    typicalWait = null, verifyOverdue = false, hasReceipt = false, hasRefund = false, hasDirections = false } = ctx;
  const T = (vi, e) => (en ? e : vi);
  const link = (kind, vi, e) => ({ kind, label: T(vi, e) });
  const receipt = hasReceipt ? link('receipt', 'Xem biên nhận', 'View receipt') : null;
  switch (key) {
    case 'cancelled':
      return {
        label: T('Đã hủy', 'Cancelled'),
        heading: eventCancelled ? T('Sự kiện đã bị hủy', 'This event was cancelled') : T('Đặt chỗ đã bị hủy', 'This booking was cancelled'),
        sub: T('Vé không còn dùng để vào cửa', 'This ticket no longer works for entry'),
        // Refund responsibility is about the HOST cancelling; a booking cancelled on its own does not get this sentence.
        detail: eventCancelled ? T('Nếu bạn đã chuyển tiền, người tổ chức có trách nhiệm hoàn tiền cho bạn.', 'If you already paid, the organizer is responsible for your refund.') : null,
        link: hasRefund ? link('refunds', 'Theo dõi hoàn tiền', 'Track refund') : null,
      };
    case 'expired':
      return {
        label: T('Hết hạn', 'Expired'),
        heading: T('Chỗ giữ đã hết hạn', 'Your hold ran out'),
        sub: T('Chỗ đã được mở lại', 'The seat was released'),
        detail: T('Bạn chưa chuyển khoản trước khi hết giờ giữ chỗ, nên chỗ đã được mở lại cho người khác. Bạn có thể giữ chỗ lại nếu vẫn còn chỗ trống.', "You didn't complete payment before the hold ran out, so the seat was released back. You can reserve again if there's still room."),
        link: link('reserve', 'Đặt lại', 'Reserve again'),
      };
    case 'review':
      return {
        label: T('Đang xem xét', 'Under review'),
        heading: T('banbe đang xem xét', 'banbe is reviewing this'),
        sub: null,
        detail: T('Chỗ của bạn vẫn được giữ trong lúc chờ xem xét.', 'Your seat stays held while this is reviewed.'),
        link: null,
      };
    case 'holding':
      return {
        label: T('Đang giữ chỗ', 'Holding'),
        heading: T('Chuyển khoản trước khi hết giờ', 'Pay before time runs out'),
        sub: null,
        detail: T('Chuyển khoản trực tiếp cho người tổ chức theo hướng dẫn trong tin nhắn. Mã QR mở khi họ xác nhận.', 'Pay the organizer directly using the instructions in chat. Your QR unlocks once they confirm.'),
        link: link('pay', 'Xem thông tin chuyển khoản', 'See payment details'),
      };
    case 'awaiting':
      return {
        label: T('Chờ host', 'Awaiting host'),
        heading: T('Host đang kiểm tra chuyển khoản', 'The host is checking your transfer'),
        sub: verifyOverdue
          ? T('Người tổ chức đang xử lý, có thể mất thêm chút thời gian', 'The organizer is on it, it may take a little longer')
          : T('Bạn sẽ nhận thông báo khi vé sẵn sàng', "We'll notify you when your ticket is ready"),
        detail: typicalWait ? T(typicalWait.vi, typicalWait.en) : null,
        link: link('chat', 'Nhắn host', 'Message host'),
      };
    case 'ended':
      return {
        label: T('Đã kết thúc', 'Ended'),
        heading: T('Sự kiện đã kết thúc', 'This event has ended'),
        sub: T('Vé không còn dùng để vào cửa', 'Ticket no longer valid for entry'),
        detail: T('Biên nhận (nếu có) vẫn nằm trong Thêm tuỳ chọn.', 'Any receipt stays under More options.'),
        link: receipt,
      };
    case 'checkedIn':
      return {
        label: T('Đã check-in', 'Checked in'),
        heading: T('Bạn đã vào cửa', "You're in"),
        sub: T('Chúc bạn một buổi vui', 'Enjoy the event'),
        detail: null,
        link: receipt,
      };
    case 'today':
      return {
        label: T('Hôm nay', 'Today'),
        heading: timeText ? T(`Hôm nay lúc ${timeText}`, `Today at ${timeText}`) : T('Hôm nay', 'Today'),
        sub: areaText || null,
        detail: T('Mở sẵn trang này tại cửa và tăng độ sáng màn hình.', 'Keep this page open at the door and raise your screen brightness.'),
        link: hasDirections ? link('directions', 'Chỉ đường', 'Directions') : null,
      };
    case 'upcoming':
      return {
        label: T('Sắp diễn ra', 'Upcoming'),
        heading: daysUntil != null && daysUntil >= 1
          ? T(`Còn ${daysUntil} ngày nữa`, `${daysUntil} ${daysUntil === 1 ? 'day' : 'days'} to go`)
          : T('Sắp diễn ra', 'Upcoming'),
        sub: [dateText, timeText].filter(Boolean).join(' ▪︎ ') || null,
        detail: T('Vé đã sẵn sàng. Mã QR dùng để vào cửa vào ngày diễn ra.', 'Your ticket is ready. The QR is what you show at the door on the day.'),
        link: link('calendar', 'Thêm vào lịch', 'Add to calendar'),
      };
    default:
      return null;
  }
}
