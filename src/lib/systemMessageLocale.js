// System messages in a chat are written once, by SQL, and read by BOTH people in
// the thread — so unlike a notification they cannot be stored in "the
// recipient's" language. Each viewer's app translates the known wordings at
// display time instead, following their own language setting.
// Mirrors apps/ios/BanbeApp/Lib/SystemMessageLocale.swift — keep the two in step.
// Anything unrecognised (a user's own message, a future wording) is returned untouched.

const REASON_PAIRS = [
  ['Nhầm người', 'Wrong person'], ['Bấm nhầm', 'Tapped by mistake'],
  ['Khách chưa thực sự có mặt', "Guest hasn't actually arrived"], ['Khác', 'Other'],
  ['Sự kiện đổi lịch hoặc huỷ', 'Event rescheduled or cancelled'],
  ['Không thanh toán đúng hạn', 'Payment not completed in time'], ['Vi phạm quy định', 'Policy violation'],
  ['Hết chỗ thật sự', 'Actually out of seats'], ['Không khớp với sao kê', "Doesn't match the statement"],
  ['Nghi ngờ gian lận', 'Suspected fraud'],
  ['Sự kiện bị huỷ do hoàn cảnh bất khả kháng', 'Cancelled due to unforeseen circumstances'],
  ['Sự kiện bị huỷ vì địa điểm không còn khả dụng', 'Cancelled because the venue is no longer available'],
  ['Sự kiện bị huỷ vì chưa đủ số lượng đăng ký', 'Cancelled because there were not enough sign-ups'],
  ['Sự kiện bị huỷ vì lý do an toàn hoặc thời tiết', 'Cancelled for safety or weather reasons'],
  ['Không có lý do', 'No reason provided'], ['Người tổ chức đã huỷ', 'Cancelled by organizer'],
  ['chuyển khoản trực tiếp', 'direct transfer'],
];

// [regex over the Vietnamese wording, English template using $1.. ]
const VI_TO_EN = [
  [/^Khách báo đã chuyển khoản ▪︎ mã (.*), mã giao dịch (.*)\. Chỗ được giữ cho tới khi bạn xác nhận\.$/s, 'Guest reported a transfer ▪︎ code $1, transaction ID $2. The spot is held until you confirm.'],
  [/^Người tổ chức chưa tìm thấy khoản chuyển khoản này(?:: (.*?))?\. Chỗ của bạn vẫn được giữ trong lúc banbe xem xét\.$/s, (m, r) => `The organizer couldn't find this transfer${r ? `: ${r}` : ''}. Your spot is still held while banbe reviews it.`],
  [/^Người tổ chức chưa tìm thấy khoản chuyển khoản này(?:: (.*?))?\. Vui lòng kiểm tra lại thông tin chuyển khoản hoặc gửi thêm bằng chứng — chỗ của bạn vẫn được giữ\.$/s, (m, r) => `The organizer couldn't find this transfer${r ? `: ${r}` : ''}. Please re-check the transfer details or send more proof — your spot is still held.`],
  [/^Người tổ chức và bạn chưa thống nhất được về khoản chuyển khoản này, nên đã chuyển cho banbe xem xét\. Chỗ của bạn vẫn được giữ trong lúc chờ\.$/, "The organizer and you couldn't agree on this transfer, so it was passed to banbe for review. Your spot is still held meanwhile."],
  [/^Đã xác nhận thanh toán ▪︎ (tự động đối soát qua ngân hàng|người tổ chức xác nhận)(?:\. Biên nhận (.*))?\.$/s, (m, how, receipt) => `Payment confirmed ▪︎ ${how === 'người tổ chức xác nhận' ? 'confirmed by the organizer' : 'automatically matched with the bank'}${receipt ? `. Receipt ${receipt}` : ''}.`],
  [/^Người tổ chức không nhận yêu cầu đặt chỗ này(?:: (.*?))?\. Chỗ đã được mở lại cho người khác\.$/s, (m, r) => `The organizer declined this booking request${r ? `: ${r}` : ''}. The spot has been released to others.`],
  [/^Đặt chỗ thành công ▪︎ số tiền cần thanh toán (\S+) \(mã (.+?)\)\. Người tổ chức sẽ gửi thông tin chuyển khoản sớm\.$/s, 'Reservation confirmed ▪︎ amount due $1 (code $2). The organizer will send the transfer details soon.'],
  [/^Đặt chỗ thành công ▪︎ số tiền cần thanh toán (\S+) \(mã (.+?)\)\. Chuyển khoản tới: (.*?)Xem chi tiết và gửi ảnh xác nhận trong mục Thanh toán\.$/s,
    (m, amount, code, lines) => `Reservation confirmed ▪︎ amount due ${amount} (code ${code}). Transfer to: ${lines.replace('Ngân hàng:', 'Bank:').replace(', STK ', ', account no. ')}See the details and upload your transfer proof under Payments.`],
];

// English wordings the SQL writes → Vietnamese for a Vietnamese viewer.
const EN_TO_VI = [
  [/^Host marked payment received via (.*?)\.(?: Biên nhận ▪︎ Receipt (.*))?$/s, (m, how, receipt) => `Người tổ chức đã xác nhận nhận thanh toán qua ${how}.${receipt ? ` Biên nhận ${receipt}` : ''}`],
  [/^Booking cancelled\. Reason: (.*)\.$/s, 'Đặt chỗ đã bị huỷ. Lý do: $1.'],
  [/^Event was cancelled by host\. Reason: (.*)\.$/s, 'Sự kiện đã bị người tổ chức huỷ. Lý do: $1.'],
];

// Bilingual bodies the SQL wrote as "<vi> <sep> <en>": show the viewer's half.
const BILINGUAL = [
  /^(.*?) \/ (Dispute resolved.*)$/s,
  /^(Khách báo đã chuyển khoản) ▪︎ (Guest reported a transfer for booking .*)$/s,
  /^(Đặt chỗ thành công ▪︎ sự kiện miễn phí, không cần thanh toán\.) (Reservation confirmed ▪︎ this event is free, nothing to pay\.)$/s,
];

function swapReason(text, lang) {
  for (const [vi, en] of REASON_PAIRS) {
    const from = lang === 'en' ? vi : en;
    const to = lang === 'en' ? en : vi;
    for (const sep of [': ', 'qua ']) {
      if (text.includes(`${sep}${from}`)) text = text.replace(`${sep}${from}`, `${sep}${to}`);
    }
  }
  return text;
}

export function localizeSystemMessage(body, lang) {
  if (!body || typeof body !== 'string') return body;
  for (const re of BILINGUAL) {
    const m = body.match(re);
    if (m) return lang === 'en' ? m[2] : m[1];
  }
  const rules = lang === 'en' ? VI_TO_EN : EN_TO_VI;
  for (const [re, rep] of rules) {
    if (re.test(body)) return swapReason(body.replace(re, rep), lang);
  }
  return body;
}
