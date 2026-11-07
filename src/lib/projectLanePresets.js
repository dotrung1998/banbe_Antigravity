// Ready-made Event Project Hub lanes with their icons (note 76, 2026-11-05). Mirrors iOS `ProjectLanePresets`
// (Views/Project/ProjectComponents.swift): same 36 presets, same order and groups. The icon comes from the lane's name
// on the client (Vietnamese or English, any case or accents), so no column or migration is needed; a custom name gets
// the generic grid glyph. Web icons are emoji matching the meaning of the iOS SF Symbol.

export const PRESETS = [
  // Place and set-up
  { vi: 'Địa điểm', en: 'Venue', icon: '📍' },
  { vi: 'Bàn ghế & bố trí', en: 'Seating & layout', icon: '🪑' },
  { vi: 'Trang trí', en: 'Decor', icon: '✨' },
  { vi: 'Hoa', en: 'Flowers', icon: '💐' },
  { vi: 'Âm thanh & ánh sáng', en: 'Sound & light', icon: '🔊' },
  { vi: 'Sân khấu', en: 'Stage', icon: '🎭' },
  { vi: 'Điện & thiết bị', en: 'Power & equipment', icon: '🔌' },
  { vi: 'Giấy phép', en: 'Permits', icon: '📄' },
  { vi: 'An toàn', en: 'Safety', icon: '⛑️' },
  // Food and drink
  { vi: 'Thực đơn & đồ uống', en: 'Food & drinks', icon: '🍽️' },
  { vi: 'Bếp', en: 'Kitchen', icon: '🍳' },
  { vi: 'Quầy bar', en: 'Bar', icon: '🍷' },
  { vi: 'Cà phê & trà', en: 'Coffee & tea', icon: '☕' },
  { vi: 'Bánh & tráng miệng', en: 'Cake & dessert', icon: '🎂' },
  // Programme
  { vi: 'Chương trình', en: 'Programme', icon: '📋' },
  { vi: 'Nghệ sĩ & diễn giả', en: 'Artists & speakers', icon: '🎤' },
  { vi: 'DJ & nhạc', en: 'DJ & music', icon: '🎵' },
  { vi: 'Workshop', en: 'Workshop', icon: '🎨' },
  { vi: 'Trò chơi & hoạt động', en: 'Games & activities', icon: '🎮' },
  { vi: 'Trẻ em', en: 'Kids', icon: '🧒' },
  // People
  { vi: 'Khách mời', en: 'Guests', icon: '👥' },
  { vi: 'Vé & cổng', en: 'Tickets & door', icon: '🎟️' },
  { vi: 'Tình nguyện viên', en: 'Volunteers', icon: '🙋' },
  { vi: 'Nhà tài trợ', en: 'Sponsors', icon: '⭐' },
  { vi: 'Đối tác', en: 'Partners', icon: '🤝' },
  { vi: 'Nhà cung cấp', en: 'Suppliers', icon: '📦' },
  // Getting the word out
  { vi: 'Truyền thông', en: 'Marketing', icon: '📣' },
  { vi: 'Mạng xã hội', en: 'Social media', icon: '💬' },
  { vi: 'Thiết kế', en: 'Design', icon: '📐' },
  { vi: 'Chụp ảnh & quay phim', en: 'Photo & video', icon: '📷' },
  { vi: 'Báo chí', en: 'Press', icon: '📰' },
  // Money and running it
  { vi: 'Ngân sách', en: 'Budget', icon: '💵' },
  { vi: 'Hậu cần', en: 'Logistics', icon: '🚗' },
  { vi: 'Đi lại & chỗ ở', en: 'Travel & stay', icon: '🛏️' },
  { vi: 'Quà tặng', en: 'Gifts & merch', icon: '🎁' },
  { vi: 'Dọn dẹp', en: 'Clean-up', icon: '🗑️' },
];

export const CUSTOM_ICON = '▦';

/** Case- and accent-insensitive key ("Truyền Thông " → "truyen thong"; đ → d). */
export function key(s) {
  return String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/đ/g, 'd').trim();
}

export function presetNamed(name) {
  const k = key(name);
  if (!k) return null;
  return PRESETS.find(p => key(p.vi) === k || key(p.en) === k) || null;
}

export const iconFor = (name) => presetNamed(name)?.icon || CUSTOM_ICON;

/** Presets whose Vietnamese or English name contains the query (accent- and case-insensitive); all of them when empty. */
export function search(query) {
  const q = key(query);
  if (!q) return PRESETS;
  return PRESETS.filter(p => key(p.vi).includes(q) || key(p.en).includes(q));
}
