// Quick-announcement catalogue for hosts (send_event_announcement, migration 166).
// iOS copy is generated: `node scripts/gen-announcement-templates-ios.mjs`.
// Category ids must match the RPC's allow-list: timing|arrival|venue|safety|wrapup|custom.
export const ANNOUNCEMENT_MAX = 300;

export const ANNOUNCEMENT_CATEGORIES = [
  { id: 'timing', vi: 'Giờ giấc', en: 'Timing' },
  { id: 'arrival', vi: 'Đến & vào cửa', en: 'Arrival & entry' },
  { id: 'venue', vi: 'Địa điểm & chuẩn bị', en: 'Venue & prep' },
  { id: 'safety', vi: 'Quy định & an toàn', en: 'Rules & safety' },
  { id: 'wrapup', vi: 'Kết thúc', en: 'Wrap-up' },
];

export const ANNOUNCEMENT_TEMPLATES = [
  { id: 'starting-soon', category: 'timing', vi: 'Sự kiện sắp bắt đầu, vui lòng đến đúng giờ nhé!', en: 'The event is starting soon, please arrive on time!', keywords: 'sắp bắt đầu đúng giờ starting soon on time' },
  { id: 'started', category: 'timing', vi: 'Sự kiện đã bắt đầu. Mời bạn vào chỗ nhé!', en: 'The event has started. Please take your seat!', keywords: 'bắt đầu started begin' },
  { id: 'delay-15', category: 'timing', vi: 'Sự kiện sẽ trễ khoảng 15 phút. Cảm ơn bạn đã thông cảm!', en: 'The event is delayed by about 15 minutes. Thanks for your patience!', keywords: 'trễ chậm delay late 15' },
  { id: 'delay-30', category: 'timing', vi: 'Sự kiện sẽ trễ khoảng 30 phút. Cảm ơn bạn đã thông cảm!', en: 'The event is delayed by about 30 minutes. Thanks for your patience!', keywords: 'trễ chậm delay late 30' },
  { id: 'last-call', category: 'timing', vi: 'Còn ít phút nữa là đóng cửa vào. Bạn nhanh chân nhé!', en: 'Doors close in a few minutes. Please hurry!', keywords: 'đóng cửa last call doors close hurry' },
  { id: 'doors-open', category: 'arrival', vi: 'Cửa đã mở, mời bạn check-in.', en: 'Doors are open, come on in to check in.', keywords: 'mở cửa check-in doors open' },
  { id: 'bring-qr', category: 'arrival', vi: 'Nhớ mang mã QR vé của bạn để check-in nhé.', en: 'Please have your ticket QR code ready for check-in.', keywords: 'qr vé ticket check-in' },
  { id: 'bring-id', category: 'arrival', vi: 'Vui lòng mang theo giấy tờ tùy thân để đối chiếu khi vào cửa.', en: 'Please bring a photo ID to show at the door.', keywords: 'giấy tờ cccd id tuổi age' },
  { id: 'where-checkin', category: 'arrival', vi: 'Quầy check-in ở ngay cửa vào. Bạn cứ báo tên là được.', en: 'Check-in is right at the entrance. Just tell us your name.', keywords: 'quầy check-in cửa vào entrance desk' },
  { id: 'late-entry', category: 'arrival', vi: 'Đến trễ vẫn vào được, nhưng vui lòng nhắn host trước nhé.', en: "Late arrivals are welcome, but please message the host first.", keywords: 'đến trễ late arrival' },
  { id: 'venue-changed', category: 'venue', vi: 'Địa điểm có thay đổi. Vui lòng xem lại trang sự kiện hoặc nhắn host.', en: 'The venue has changed. Please check the event page or message the host.', keywords: 'đổi địa điểm venue changed location' },
  { id: 'parking', category: 'venue', vi: 'Có chỗ gửi xe gần địa điểm. Bạn nhớ để ý biển báo nhé.', en: 'Parking is available near the venue. Look out for the signs.', keywords: 'gửi xe đậu xe parking' },
  { id: 'weather', category: 'venue', vi: 'Trời có thể mưa, bạn mang theo áo mưa/ô nhé.', en: 'It may rain, so bring a raincoat or umbrella.', keywords: 'mưa thời tiết weather rain umbrella' },
  { id: 'dress-code', category: 'venue', vi: 'Nhắc nhẹ về dress code của buổi hôm nay, bạn xem lại mô tả sự kiện nhé.', en: "A reminder about today's dress code, see the event description.", keywords: 'trang phục dress code outfit' },
  { id: 'bring-items', category: 'venue', vi: 'Đừng quên mang theo những thứ cần thiết như đã ghi trong mô tả sự kiện.', en: 'Remember to bring what the event description asks for.', keywords: 'mang theo bring items' },
  { id: 'house-rules', category: 'safety', vi: 'Nhắc nhẹ về quy tắc của buổi hôm nay: tôn trọng nhau và giữ gìn không gian chung.', en: "A reminder of today's house rules: be respectful and look after the space.", keywords: 'quy tắc rules respect' },
  { id: 'no-photos', category: 'safety', vi: 'Vui lòng xin phép trước khi chụp ảnh hoặc quay phim người khác.', en: 'Please ask before photographing or filming other guests.', keywords: 'chụp ảnh quay phim photo film privacy' },
  { id: 'drink-safe', category: 'safety', vi: 'Uống có trách nhiệm và không lái xe sau khi uống rượu bia nhé.', en: "Please drink responsibly and don't drive after drinking.", keywords: 'rượu bia uống alcohol drink drive' },
  { id: 'need-help', category: 'safety', vi: 'Cần hỗ trợ gì cứ tìm host hoặc nhân viên ở hiện trường nhé.', en: 'If you need anything, find the host or a team member on site.', keywords: 'hỗ trợ help support' },
  { id: 'thanks', category: 'wrapup', vi: 'Cảm ơn bạn đã đến! Hy vọng bạn có một buổi tối thật vui.', en: 'Thanks for coming! We hope you had a great time.', keywords: 'cảm ơn thanks thank you' },
  { id: 'feedback', category: 'wrapup', vi: 'Bạn thấy buổi hôm nay thế nào? Nhắn lại host để góp ý nhé.', en: 'How was it? Message the host with your feedback.', keywords: 'góp ý feedback review' },
  { id: 'lost-found', category: 'wrapup', vi: 'Nếu bạn để quên đồ, vui lòng nhắn host để được hỗ trợ.', en: 'If you left something behind, message the host and we will help.', keywords: 'để quên đồ lost found' },
  { id: 'event-ended', category: 'wrapup', vi: 'Sự kiện đã kết thúc. Chúc bạn về nhà an toàn!', en: 'The event has ended. Get home safe!', keywords: 'kết thúc ended over' },
];

// Accent/case-insensitive match over both languages + keywords, within an optional category.
const fold = (s) => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/g, 'd').replace(/Đ/g, 'D').toLowerCase();

export function filterAnnouncementTemplates(query, categoryId) {
  const q = fold(query).trim();
  const words = q ? q.split(/\s+/) : [];
  return ANNOUNCEMENT_TEMPLATES.filter(t => {
    if (categoryId && categoryId !== 'all' && t.category !== categoryId) return false;
    if (!words.length) return true;
    const hay = fold(`${t.vi} ${t.en} ${t.keywords}`);
    return words.every(w => hay.includes(w));
  });
}

export const ANNOUNCEMENT_ERRORS = {
  OUTSIDE_WINDOW: ['Chỉ gửi được từ 24 giờ trước đến 12 giờ sau giờ bắt đầu.', 'You can only send from 24h before to 12h after the start.'],
  RATE_LIMITED: ['Bạn đã gửi quá nhiều thông báo. Thử lại sau ít phút.', "You've sent too many announcements. Try again in a few minutes."],
  NOT_AUTHORIZED: ['Bạn không có quyền gửi thông báo cho sự kiện này.', "You can't send announcements for this event."],
  INVALID_BODY: ['Nội dung phải từ 1 đến 300 ký tự.', 'Message must be 1 to 300 characters.'],
};
