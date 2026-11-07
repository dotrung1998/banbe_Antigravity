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

/** The streak number the Home capsule shows: weeks under Rewards v2 (when the server sends them), else days. */
export function capsuleStreak(summary, weekly) {
  if (weekly && Number.isFinite(summary?.weekStreak)) return { value: summary.weekStreak, unit: 'week' };
  return { value: summary?.streak ?? 0, unit: 'day' };
}

/** Accessible label for the Home shortcut pair. */
export function shortcutLabels(T, summary, weekly = false) {
  const { value: streak, unit } = capsuleStreak(summary, weekly);
  const balance = summary?.balance ?? 0;
  return {
    streak: unit === 'week'
      ? T(`Chuỗi ${streak} tuần. Mở phần thưởng`, `${streak}-week streak. Open rewards`)
      : T(`Chuỗi ${streak} ngày. Mở phần thưởng`, `${streak}-day streak. Open rewards`),
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
  return {
    balance: Number(data.balance) || 0, streak: Number(data.streak) || 0, activeToday: data.active_today === true,
    // Migration 192 (Rewards v2). Absent on an older server: null, so the Home capsule falls back to days.
    weekStreak: Number.isFinite(data.week_streak) ? data.week_streak : null, weekActive: data.week_active === true,
  };
}

const REASONS = {
  onboarding_preferences: ['Hoàn thành câu hỏi sở thích', 'Completed the preference questions'],
  attendance: ['Tham dự sự kiện', 'Attended an event'],
  attendance_cap: ['Tham dự sự kiện (đã đạt giới hạn xu tháng này)', 'Attended an event (monthly coin cap reached)'],
  off_window: ['Tham dự sự kiện (điểm danh ngoài khung giờ sự kiện, không tính xu)', 'Attended an event (checked in outside the event time, no coins)'],
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
    // Rules v2 (migration 191). An older server has no window: no line.
    Number.isFinite(rules?.attendance_window_before_hours) && Number.isFinite(rules?.attendance_window_after_hours)
      ? T(`Xu được tính khi người tổ chức điểm danh bạn trong khoảng ${rules.attendance_window_before_hours} giờ trước đến ${rules.attendance_window_after_hours} giờ sau giờ bắt đầu. Ngoài khoảng đó vẫn được tính huy hiệu và chuỗi, nhưng không có xu.`,
          `Coins are paid when the host checks you in between ${rules.attendance_window_before_hours} hours before and ${rules.attendance_window_after_hours} hours after the start. Outside that you still progress badges and your streak, without coins.`)
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

export function redemptionTermsLines(T, weekly = false) {
  return [
    T('Xu không thể mua, chuyển nhượng hay đổi thành tiền. Không có rút thăm hay giải thưởng ngẫu nhiên.', 'Coins cannot be bought, transferred or cashed out. There are no random prizes or draws.'),
    T('Xu và huy hiệu không ảnh hưởng đến việc đặt chỗ, thứ tự ưu tiên hay điều kiện tham gia.', 'Coins and badges never affect booking, priority or eligibility.'),
    T('Đổi thưởng chỉ mở khoá mẫu móc khoá (tuỳ chọn). Các mẫu miễn phí luôn dùng được.', 'Redeeming only unlocks an optional keychain design. The free charms always stay available.'),
    T('Nếu một lần điểm danh bị huỷ sau khi bạn đã dùng xu, số xu đó vẫn bị trừ lại, số dư có thể âm cho tới khi bạn kiếm lại. Phần thưởng đã mở khoá không bị thu hồi.',
      'If a check-in is undone after you spent those coins, the coins are still reversed and your balance can go negative until you earn it back. Unlocked rewards are never taken away.'),
    weekly
      ? T('Chuỗi tuần chỉ là thống kê: bỏ lỡ một tuần không bao giờ bị trừ xu hay khoá tính năng.', 'Your streak is just a counter: missing a week never costs coins or blocks anything.')
      : T('Chuỗi ngày chỉ là thống kê: bỏ lỡ ngày nào cũng không bị trừ xu hay khoá tính năng.', 'Your streak is just a counter: missing a day never costs coins or blocks anything.'),
  ];
}

/** Short, always-visible explanation for the Streak card. Mirrors iOS RewardsView.streakHint. */
export function streakHint(T, activeToday) {
  return {
    status: activeToday
      ? T('✓ Hôm nay đã được tính', "✓ Today's counted")
      : T('Hôm nay chưa được tính', "Today isn't counted yet"),
    how: activeToday
      ? T('Quay lại ngày mai để giữ chuỗi.', 'Come back tomorrow to keep it going.')
      : T('Lưu 1 sự kiện hoặc đi 1 sự kiện để được +1 ngày. Chỉ mở app thì chưa tính.', 'Save an event or attend one to earn +1 day. Just opening the app does not count.'),
  };
}

export function streakLines(T, streak, tz) {
  const zone = tz || 'Asia/Ho_Chi_Minh';
  return [
    T('Một ngày được tính khi bạn lưu một sự kiện (đã được máy chủ xác minh) hoặc được xác nhận tham dự. Mở ứng dụng hay tìm kiếm không được tính.',
      'A day counts when you save an event (verified by the server) or are confirmed as attending. Opening the app or searching does not count.'),
    T(`Ngày và tháng được tính theo múi giờ ${zone}, mỗi ngày tối đa một lần.`, `Days and months follow the ${zone} time zone, at most once per day.`),
  ];
}

// Zones offered in the picker. Only a suggestion list: nothing is assigned automatically, a user who never
// chooses keeps Asia/Ho_Chi_Minh (the original behaviour).
export const SUGGESTED_TIMEZONES = [
  ['Asia/Ho_Chi_Minh', 'Việt Nam (UTC+7)', 'Vietnam (UTC+7)'],
  ['America/Los_Angeles', 'Mỹ – Thái Bình Dương', 'US – Pacific'],
  ['America/Denver', 'Mỹ – Miền núi', 'US – Mountain'],
  ['America/Chicago', 'Mỹ – Trung tâm', 'US – Central'],
  ['America/New_York', 'Mỹ – Miền Đông', 'US – Eastern'],
];

/** The device's IANA zone if it is one we know how to label; used only to highlight a suggestion. */
export function deviceTimezoneHint(resolve = () => Intl.DateTimeFormat().resolvedOptions().timeZone) {
  try { const z = resolve(); return SUGGESTED_TIMEZONES.some(x => x[0] === z) ? z : null; } catch { return null; }
}

/** Normalises get_my_rewards().timezone_settings; tolerates an older server that lacks the key. */
export function normalizeTzSettings(raw) {
  if (!raw || typeof raw !== 'object') return null;
  return {
    effective: raw.effective_tz || 'Asia/Ho_Chi_Minh', chosen: raw.chosen === true,
    pending: raw.pending_tz || null, pendingFrom: raw.pending_from || null,
    changesLeft: Number.isFinite(raw.changes_left) ? raw.changes_left : 0, nextChangeAt: raw.next_change_at || null,
  };
}

export const TZ_ERRORS = {
  INVALID_TIMEZONE: ['Múi giờ không hợp lệ.', 'That time zone is not valid.'],
  TZ_CHANGE_LIMIT: ['Bạn đã đổi múi giờ 2 lần trong 30 ngày. Vui lòng thử lại sau.', 'You changed your time zone twice in the last 30 days. Please try again later.'],
  NETWORK: ['Lỗi mạng. Chưa thay đổi gì.', 'Network error. Nothing was changed.'],
};

/** Items the signed-in user can't afford yet, with the exact shortfall. */
export function shortfall(balance, price) { return Math.max(0, price - balance); }

/**
 * Splits a get_my_rewards() payload into keychain designs and partner offers (migration 179).
 * Works against every server version:
 *  - before 179: no `kind`/`offers` -> every catalog row is a keychain design, offers = [].
 *  - 179+: `catalog` holds designs only and `offers` is [] while the partner_offers flag is off.
 * A row is only a design when it has a string design_id, so an offer can never land in the keychain list even if a
 * server ever put one in `catalog`. Offers are display-only (no redemption path in 179).
 */
export function splitRewardCatalog(rewards) {
  const catalog = Array.isArray(rewards?.catalog) ? rewards.catalog : [];
  const designs = catalog.filter(c => c && (c.kind === undefined || c.kind === 'keychain_design') && typeof c.design_id === 'string');
  const raw = Array.isArray(rewards?.offers) ? rewards.offers : [];
  const offers = raw.filter(o => o && typeof o.code === 'string' && (o.kind === undefined || o.kind === 'partner_offer'))
    .map(o => ({ code: o.code, title_vi: o.title_vi || o.code, title_en: o.title_en || o.title_vi || o.code,
                 desc_vi: o.desc_vi || '', desc_en: o.desc_en || o.desc_vi || '', price: Number(o.price) || 0, status: o.status || 'unavailable' }));
  return { designs, offers, showOffers: offers.length > 0 };
}

// ============ Rewards v2 (migration 192): weekly streak, grace weeks, repair, tiers, next badge, monthly goal ============
// Mirrors iOS RewardsLogic (AppState+Rewards.swift). Copy rules: no guilt, no fake urgency, no "you'll lose";
// a repair date is shown only because it is real.

/** get_my_rewards().week_streak -> camelCase; null on a server without 192. */
export function normalizeWeekStreak(raw) {
  if (!raw || typeof raw !== 'object' || raw.unit !== 'week') return null;
  const n = (v) => (Number.isFinite(v) ? v : 0);
  const rep = raw.repair && Number.isFinite(raw.repair.weeks) && typeof raw.repair.until === 'string' ? { weeks: raw.repair.weeks, until: raw.repair.until } : null;
  return {
    current: n(raw.current), longest: n(raw.longest), thisWeekActive: raw.this_week_active === true, weekStart: raw.week_start || null,
    graceHeld: n(raw.grace_held), graceMax: n(raw.grace_max), graceEvery: n(raw.grace_every), graceUsed: n(raw.grace_used),
    nextGraceIn: Number.isFinite(raw.next_grace_in) ? raw.next_grace_in : null, repair: rep, repaired: n(raw.repaired),
    timezone: raw.timezone || 'Asia/Ho_Chi_Minh',
  };
}

/** "25 Nov" / "25 thg 11" for a YYYY-MM-DD date, without a timezone shift. */
export function shortDate(iso, lang) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso || '');
  if (!m) return '';
  const d = new Date(Date.UTC(+m[1], +m[2] - 1, +m[3]));
  return d.toLocaleDateString(lang === 'en' ? 'en-US' : 'vi-VN', { day: 'numeric', month: 'short', timeZone: 'UTC' });
}

export function weeksLabel(T, n) {
  return T(`${n} tuần`, `${n} ${n === 1 ? 'week' : 'weeks'}`);
}

/** Status + how-to for the weekly streak card (and the Home capsule label). */
export function weekStreakHint(T, ws, lang) {
  if (!ws) return { status: '', how: '' };
  if (ws.thisWeekActive) {
    return { status: T('✓ Tuần này đã được tính', '✓ This week counts'),
             how: T('Tuần sau: lưu 1 sự kiện hoặc đi 1 sự kiện là đủ.', 'Next week: one save or one event is all it takes.') };
  }
  if (ws.current === 0 && ws.repair) {
    return { status: T(`Lấy lại chuỗi ${ws.repair.weeks} tuần`, `Bring back your ${ws.repair.weeks}-week streak`),
             how: T(`Tham dự một sự kiện trước hết ngày ${shortDate(ws.repair.until, lang)} để khôi phục.`, `Attend an event by ${shortDate(ws.repair.until, lang)} to restore it.`) };
  }
  if (ws.current > 0) {
    return { status: T('Tuần này vẫn đang mở', 'This week is still open'),
             how: ws.graceHeld > 0
               ? T('Lưu hoặc đi 1 sự kiện trước Chủ nhật để thêm 1 tuần. Lỡ tuần này cũng không sao: bạn có tuần nghỉ.', 'Save or attend an event before Sunday to add a week. Missing it is fine too: you have a grace week.')
               : T('Lưu hoặc đi 1 sự kiện trước Chủ nhật để thêm 1 tuần.', 'Save or attend an event before Sunday to add a week.') };
  }
  return { status: T('Bắt đầu chuỗi tuần này', 'Start a streak this week'),
           how: T('Một tuần chỉ cần 1 lần lưu hoặc 1 sự kiện. Chỉ mở app thì chưa tính.', 'A week needs just one save or one event. Opening the app alone does not count.') };
}

/** One line about grace weeks: what you hold and when the next one comes. */
export function graceLine(T, ws) {
  if (!ws || ws.graceMax <= 0) return '';
  const held = T(`Tuần nghỉ: ${ws.graceHeld}/${ws.graceMax}`, `Grace weeks: ${ws.graceHeld}/${ws.graceMax}`);
  if (ws.nextGraceIn === null) return `${held} ▪︎ ${T('đã đầy', 'full')}`;
  return `${held} ▪︎ ${T(`thêm 1 sau ${ws.nextGraceIn} tuần hoạt động`, `next after ${ws.nextGraceIn} more active ${ws.nextGraceIn === 1 ? 'week' : 'weeks'}`)}`;
}

export function weekStreakLines(T, ws) {
  const zone = ws?.timezone || 'Asia/Ho_Chi_Minh';
  const every = ws?.graceEvery || 4; const max = ws?.graceMax || 2;
  return [
    T('Một tuần (thứ Hai–Chủ nhật) được tính khi bạn lưu một sự kiện (máy chủ xác minh) hoặc được xác nhận tham dự ít nhất một lần.',
      'A week (Monday–Sunday) counts when you save an event (verified by the server) or are confirmed as attending at least once.'),
    T(`Cứ ${every} tuần hoạt động bạn nhận 1 tuần nghỉ (giữ tối đa ${max}). Tuần nghỉ tự che một tuần bạn bỏ lỡ. Không thể mua.`,
      `Every ${every} active weeks earn a grace week (hold up to ${max}). It covers a week you miss, automatically. It can't be bought.`),
    T('Nếu chuỗi từ 4 tuần trở lên bị ngắt, tham dự một sự kiện trong 14 ngày sau đó sẽ khôi phục chuỗi.',
      'If a streak of 4 weeks or more breaks, attending an event within 14 days brings it back.'),
    T(`Tuần được tính theo múi giờ ${zone}. Chuỗi và mục tiêu không bao giờ tạo ra xu.`, `Weeks follow the ${zone} time zone. Streaks and goals never pay coins.`),
  ];
}

export const BADGE_FAMILIES = {
  start: ['Bắt đầu', 'Getting started'],
  outings: ['Sự kiện đã tham dự', 'Events attended'],
  explorer: ['Khám phá danh mục', 'Categories explored'],
  months: ['Tháng có sự kiện', 'Months out'],
  host: ['Người tổ chức', 'Hosting'],
  season: ['Theo mùa', 'Seasonal'],
};

/**
 * Groups badges by family (192), tiers in order. A payload without `family` (older server, or rewards_v2 off on a
 * server that still sends it) gives one group per badge so nothing disappears.
 */
export function groupBadgesByFamily(badges) {
  const list = Array.isArray(badges) ? badges : [];
  const groups = [];
  const byKey = new Map();
  for (const b of list) {
    const key = typeof b.family === 'string' ? b.family : `solo:${b.code}`;
    if (!byKey.has(key)) { const g = { family: key, badges: [] }; byKey.set(key, g); groups.push(g); }
    byKey.get(key).badges.push(b);
  }
  for (const g of groups) {
    g.badges.sort((a, b) => (a.tier ?? 0) - (b.tier ?? 0));
    g.earnedCount = g.badges.filter(b => b.earned).length;
    g.next = g.badges.find(b => !b.earned) || null;
    g.top = [...g.badges].reverse().find(b => b.earned) || null;
  }
  return groups;
}

/** Goal-gradient line for the next badge ("One event away from Regular"). */
export function nextBadgeLine(T, nb, lang) {
  if (!nb || !Number.isFinite(nb.remaining)) return '';
  const title = lang === 'en' ? nb.title_en : nb.title_vi;
  const n = nb.remaining;
  switch (nb.family) {
    case 'outings':
    case 'season':
      return n === 1 ? T(`Còn 1 sự kiện nữa là đạt “${title}”`, `One event away from “${title}”`)
                     : T(`Còn ${n} sự kiện nữa là đạt “${title}”`, `${n} events away from “${title}”`);
    case 'explorer':
      return T(`Thêm ${n} danh mục mới để đạt “${title}”`, `${n} new ${n === 1 ? 'category' : 'categories'} to “${title}”`);
    case 'months':
      return T(`Thêm ${n} tháng có sự kiện để đạt “${title}”`, `${n} more ${n === 1 ? 'month' : 'months'} with an event to “${title}”`);
    case 'host':
      return T(`Thêm ${n} sự kiện hoàn thành để đạt “${title}”`, `${n} more completed ${n === 1 ? 'event' : 'events'} to “${title}”`);
    case 'start':
      return T(`Trả lời câu hỏi sở thích để đạt “${title}”`, `Answer the preference questions to earn “${title}”`);
    default:
      return T(`Còn ${n} bước nữa là đạt “${title}”`, `${n} to go for “${title}”`);
  }
}

export const GOAL_CHOICES = [1, 2, 4];

/** get_my_rewards().goal -> { target|null, progress, done }; null on a server without 192. */
export function normalizeGoal(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const target = GOAL_CHOICES.includes(raw.target) ? raw.target : null;
  const progress = Number.isFinite(raw.progress) ? raw.progress : 0;
  return { target, progress, done: target !== null && progress >= target, month: raw.month || null };
}

export function goalLine(T, goal) {
  if (!goal || goal.target === null) return T('Chọn số sự kiện bạn muốn đi mỗi tháng. Không có xu, chỉ để bạn theo dõi.', 'Pick how many events you want to go to each month. No coins, just for you.');
  if (goal.done) return T(`Đã đạt mục tiêu tháng này (${goal.progress}/${goal.target}) ✓`, `Goal met for this month (${goal.progress}/${goal.target}) ✓`);
  const left = goal.target - goal.progress;
  return T(`${goal.progress}/${goal.target} sự kiện tháng này ▪︎ còn ${left}`, `${goal.progress} of ${goal.target} events this month ▪︎ ${left} to go`);
}

export const GOAL_ERRORS = {
  NOT_AVAILABLE: ['Tính năng này đang tắt.', 'This is switched off right now.'],
  INVALID_GOAL: ['Mục tiêu không hợp lệ.', 'That goal is not valid.'],
  NETWORK: ['Lỗi mạng. Chưa thay đổi gì.', 'Network error. Nothing was changed.'],
};

export const WEEK_MILESTONES = [4, 8, 12, 26, 52];

/**
 * Which earned badges / streak milestones to celebrate now. `celebrated` is the per-account, per-device set of keys
 * already shown (null = first time on this device: celebrate nothing, just remember what is already there, so an
 * existing collection never bursts on a new phone). Returns { show: [{kind, code?, weeks?, key}], keys: next set }.
 */
export function celebrationDiff(badges, ws, celebrated) {
  const items = [];
  for (const b of Array.isArray(badges) ? badges : []) {
    if (b && b.earned && b.earned_at) items.push({ kind: 'badge', code: b.code, key: `b:${b.code}:${b.earned_at}` });
  }
  if (ws && ws.current > 0 && ws.weekStart) {
    const m = [...WEEK_MILESTONES].reverse().find(x => ws.current >= x);
    if (m) {
      const start = new Date(`${ws.weekStart}T00:00:00Z`); start.setUTCDate(start.getUTCDate() - (ws.current - 1) * 7);
      items.push({ kind: 'weeks', weeks: m, key: `w:${m}:${start.toISOString().slice(0, 10)}` });
    }
  }
  const all = items.map(i => i.key);
  if (!Array.isArray(celebrated)) return { show: [], keys: all };
  const seen = new Set(celebrated);
  return { show: items.filter(i => !seen.has(i.key)), keys: [...new Set([...celebrated, ...all])].slice(-200) };
}

const CELEBRATED_KEY = (uid) => `banbe_rewards_celebrated_v1:${uid}`;
export function readCelebrated(uid, storage = typeof localStorage !== 'undefined' ? localStorage : null) {
  try { const v = JSON.parse(storage?.getItem(CELEBRATED_KEY(uid)) || 'null'); return Array.isArray(v) ? v : null; } catch { return null; }
}
export function writeCelebrated(uid, keys, storage = typeof localStorage !== 'undefined' ? localStorage : null) {
  try { storage?.setItem(CELEBRATED_KEY(uid), JSON.stringify(keys)); } catch { /* private mode: worst case a repeat */ }
}
