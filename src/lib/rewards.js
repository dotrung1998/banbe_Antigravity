// Rewards & badges: pure helpers shared by the Home shortcut and Account > Rewards & badges.
// Everything numeric (balance, streak, progress, prices, rule values) comes from the server
// (migration 165); nothing here computes an award. Coins are cosmetic only: no cash value, not
// purchasable or transferable, never an advantage in booking or eligibility.

/** Compact balance for tight spaces (Home header): 1234 -> "1234", 12500 -> "12.5k". */
export function compactCoins(n) {
  const v = Number.isFinite(n) ? Math.trunc(n) : 0;
  const a = Math.abs(v);
  if (a < 10000) return String(v);
  const k = Math.round(a / 100) / 10;
  return `${v < 0 ? '-' : ''}${Number.isInteger(k) ? k : k.toFixed(1)}k`;
}

/** Accessible label for the Home shortcut pair. */
export function shortcutLabels(T, summary) {
  const streak = summary?.streak ?? 0;
  const balance = summary?.balance ?? 0;
  return {
    streak: T(`Chuỗi ${streak} ngày. Mở phần thưởng`, `${streak}-day streak. Open rewards`),
    coins: T(`${balance} xu. Mở phần thưởng và huy hiệu`, `${balance} coins. Open rewards and badges`),
  };
}

/** A missing RPC (migration 165 not applied) must hide the feature, never show fake numbers. */
export function isRewardsUnavailable(error) {
  if (!error) return false;
  const code = error.code || '';
  const msg = String(error.message || '');
  return code === 'PGRST202' || code === '42883' || /could not find the function|does not exist/i.test(msg);
}

export function normalizeSummary(data) {
  if (!data || data.success !== true) return null;
  return { balance: Number(data.balance) || 0, streak: Number(data.streak) || 0, activeToday: data.active_today === true };
}

const REASONS = {
  onboarding_preferences: ['Hoàn thành câu hỏi sở thích', 'Completed the preference questions'],
  attendance: ['Tham dự sự kiện', 'Attended an event'],
  attendance_cap: ['Tham dự sự kiện (đã đạt giới hạn xu tháng này)', 'Attended an event (monthly coin cap reached)'],
  attendance_reversed: ['Điều chỉnh: điểm danh bị huỷ', 'Adjustment: attendance was undone'],
  redemption: ['Đổi phần thưởng', 'Redeemed a reward'],
};
export function historyLabel(entry, T) {
  const r = REASONS[entry?.reason];
  const base = r ? T(r[0], r[1]) : T('Hoạt động', 'Activity');
  return entry?.event_name ? `${base} ▪︎ ${entry.event_name}` : base;
}

/** Earning-rule lines built from the ACTIVE server rules (so a rules change flows through). */
export function ruleLines(rules, T) {
  const on = rules?.onboarding_coins ?? 0;
  const at = rules?.attendance_coins ?? 0;
  const cap = rules?.attendance_coin_cap_per_month ?? 0;
  return [
    T(`Hoàn thành câu hỏi sở thích một lần: +${on} xu.`, `Complete the preference questions once: +${on} coins.`),
    T(`Mỗi sự kiện khác nhau mà người tổ chức xác nhận bạn đã tham dự: +${at} xu.`, `Each different event the host confirms you attended: +${at} coins.`),
    cap > 0
      ? T(`Giới hạn: tối đa ${cap} sự kiện được tính xu mỗi tháng (${cap * at} xu). Vượt giới hạn vẫn được tính huy hiệu và chuỗi ngày nhưng không có xu.`,
          `Cap: at most ${cap} events pay coins per month (${cap * at} coins). Beyond it you still progress badges and your streak, just without coins.`)
      : '',
  ].filter(Boolean);
}

export function noCoinLines(T) {
  return [
    T('Không có xu cho: mở ứng dụng, chi tiêu, thích, theo dõi, lưu lặp lại, tải lên, huỷ, hay đồng ý nhận tin/cấp quyền.',
      'No coins for: opening the app, spending, likes, follows, repeated saves, uploads, cancellations, or marketing/permission consent.'),
    T('Chủ sự kiện, thành viên Team và tự điểm danh không được tính xu cho sự kiện của chính mình.',
      "Event owners, team members and self check-ins don't earn at their own events."),
    T('Vé tặng: xu thuộc về người nhận đã nhận vé và thực sự tham dự, không phải người mua. Vé tặng chưa được nhận thì chưa ai được tính.',
      'Gifted tickets: coins go to the recipient who claimed the ticket and attended, not the buyer. A gift that was never claimed credits nobody.'),
  ];
}

export function redemptionTermsLines(T) {
  return [
    T('Xu không thể mua, chuyển nhượng hay đổi thành tiền. Không có rút thăm hay giải thưởng ngẫu nhiên.', 'Coins cannot be bought, transferred or cashed out. There are no random prizes or draws.'),
    T('Xu và huy hiệu không ảnh hưởng đến việc đặt chỗ, thứ tự ưu tiên hay điều kiện tham gia.', 'Coins and badges never affect booking, priority or eligibility.'),
    T('Đổi thưởng chỉ mở khoá mẫu móc khoá (tuỳ chọn). Các mẫu miễn phí luôn dùng được.', 'Redeeming only unlocks an optional keychain design. The free charms always stay available.'),
    T('Nếu một lần điểm danh bị huỷ sau khi bạn đã dùng xu, số xu đó vẫn bị trừ lại, số dư có thể âm cho tới khi bạn kiếm lại. Phần thưởng đã mở khoá không bị thu hồi.',
      'If a check-in is undone after you spent those coins, the coins are still reversed and your balance can go negative until you earn it back. Unlocked rewards are never taken away.'),
    T('Chuỗi ngày chỉ là thống kê: bỏ lỡ ngày nào cũng không bị trừ xu hay khoá tính năng.', 'Your streak is just a counter: missing a day never costs coins or blocks anything.'),
  ];
}

export function streakLines(T, streak, tz) {
  return [
    T('Một ngày được tính khi bạn lưu một sự kiện (đã được máy chủ xác minh) hoặc được xác nhận tham dự. Mở ứng dụng hay tìm kiếm không được tính.',
      'A day counts when you save an event (verified by the server) or are confirmed as attending. Opening the app or searching does not count.'),
    T(`Ngày được tính theo giờ cố định ${tz || 'Asia/Ho_Chi_Minh'}, mỗi ngày tối đa một lần.`, `Days follow the fixed ${tz || 'Asia/Ho_Chi_Minh'} time zone, at most once per day.`),
  ];
}

/** Items the signed-in user can't afford yet, with the exact shortfall. */
export function shortfall(balance, price) { return Math.max(0, price - balance); }
