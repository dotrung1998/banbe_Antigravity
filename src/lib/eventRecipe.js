// "Recipe for success" for event creation: ingredient checks, score, outcome estimate, per-option hints.
// Web twin of apps/ios/BanbeApp/Lib/EventRecipe.swift — keep both and their tests in sync
// (.claude/notes/50-discovery-home-host-recipe.md). Pure: no React, no network, no Date.now() inside.
//
// Honesty rules (the whole point of this file):
// - A number is shown only when it came from get_host_benchmarks (migration 186), which already refuses
//   slices under 5 events / 3 organizers. Each ingredient says whether it is `data` (with its n) or a `tip`.
// - Without data an ingredient never judges a choice as bad on a guess: e.g. a Tuesday is "good" with a
//   general tip, not "improve". Only objective gaps (empty field, < 3 photos) are flagged without data.
// - The recipe NEVER blocks submitting.
//
// Draft shape (normalized by the caller):
//   { name, description, intro, includedCount, keywords: string[], priceVnd: number|null (null/0 = free),
//     seats: number|null, startsAt: number|null (ms), photos: number, chatGreeting,
//     timeZone?: IANA (the venue's, default Asia/Ho_Chi_Minh), currency?: 'VND'|'USD' (default VND) }
// Migration 195: `priceVnd` is in the minor unit of `currency` (cents for USD) and the benchmarks are
// fetched for that same currency, so prices are only ever compared like with like.
// Benchmarks: the raw get_host_benchmarks jsonb (or null while loading / offline / cold start).
// Goal: null | 'fill_seats' | 'regular_crowd' | 'try_idea' | 'small_premium'.

import { VN_TIME_ZONE, zonedParts, formatMoneyShort } from './eventMarket.js';

export const HOST_GOALS = ['fill_seats', 'regular_crowd', 'try_idea', 'small_premium'];
export const RECIPE_STEPS = { basics: 1, when: 2, tickets: 3, photos: 4 };
const DAY = 86400000;
const MIN_PHOTOS = 3;
const TIP_PHOTOS = 5;
const TIP_LEAD_DAYS = 14;
const DESC_GOOD_CHARS = 120;

const words = (s) => (s || '').trim().split(/\s+/).filter(Boolean);

/** ISO weekday + benchmark slot of an instant in the event's zone (same cells as SQL benchmark_slot, migration 195). */
export function localParts(ms, timeZone = VN_TIME_ZONE) {
  const p = zonedParts(ms, timeZone);
  const dow = ((p.weekday + 6) % 7) + 1; // ISO: 1 = Monday ... 7 = Sunday (matches extract(isodow))
  const h = p.hour;
  return { dow, slot: h < 17 ? 'afternoon' : h < 21 ? 'evening' : 'late' };
}

/** Benchmarks are usable only when the RPC answered with a level (null level = cold start). */
export function hasBenchmarks(b) {
  return !!(b && b.success !== false && b.level);
}

function slotCell(b, dow, slot) {
  return (b?.slots || []).find(c => c.dow === dow && c.slot === slot) || null;
}
function bestSlot(b) {
  const cells = b?.slots || [];
  return cells.length ? cells.reduce((best, c) => (c.median_fill > best.median_fill ? c : best), cells[0]) : null;
}

/** Each ingredient: { id, status: 'good'|'improve'|'missing', source: 'data'|'tip', n, fix: {step, field}, ...facts } */
export function recipeChecks(draft, benchmarks, goal, now) {
  const d = draft || {};
  const b = hasBenchmarks(benchmarks) ? benchmarks : null;
  const out = [];

  // 1. Title — says what it is, not shouting.
  {
    const w = words(d.name);
    const letters = (d.name || '').replace(/[^\p{L}]/gu, '');
    const shouting = letters.length > 4 && letters === letters.toUpperCase();
    const status = !w.length ? 'missing' : (w.length < 3 || w.length > 10 || shouting) ? 'improve' : 'good';
    out.push({ id: 'title', status, source: 'tip', fix: { step: RECIPE_STEPS.basics, field: 'name' }, words: w.length, shouting });
  }

  // 2. Photos — what well-filled similar events had, else a general 5.
  {
    const dataTarget = b?.well_filled?.median_photos;
    const target = dataTarget != null ? Math.max(MIN_PHOTOS, Math.ceil(dataTarget)) : TIP_PHOTOS;
    const n = d.photos || 0;
    out.push({
      id: 'photos', status: n < MIN_PHOTOS ? 'missing' : n >= target ? 'good' : 'improve',
      source: dataTarget != null ? 'data' : 'tip', n: dataTarget != null ? b.well_filled.n : null,
      fix: { step: RECIPE_STEPS.photos, field: 'photos' }, target, have: n,
    });
  }

  // 3. Description.
  {
    const len = (d.description || '').trim().length;
    out.push({
      id: 'description', status: len === 0 ? 'missing' : len >= DESC_GOOD_CHARS ? 'good' : 'improve',
      source: 'tip', fix: { step: RECIPE_STEPS.basics, field: 'description' }, chars: len, target: DESC_GOOD_CHARS,
    });
  }

  // 4. Included items.
  {
    const share = b?.well_filled?.included_share;
    out.push({
      id: 'included', status: (d.includedCount || 0) > 0 ? 'good' : 'missing',
      source: share != null ? 'data' : 'tip', n: share != null ? b.well_filled.n : null,
      fix: { step: RECIPE_STEPS.basics, field: 'included' }, share,
    });
  }

  // 5. Keywords (+ suggestions other hosts in this slice actually use).
  {
    const have = (d.keywords || []).map(k => k.trim().toLowerCase()).filter(Boolean);
    const suggestions = (b?.keywords || []).filter(k => !have.includes(String(k).toLowerCase())).slice(0, 5);
    out.push({
      id: 'keywords', status: have.length >= 3 ? 'good' : have.length > 0 ? 'improve' : 'missing',
      source: (b?.keywords || []).length ? 'data' : 'tip', n: b ? b.n : null,
      fix: { step: RECIPE_STEPS.basics, field: 'keywords' }, have: have.length, suggestions,
    });
  }

  // 6. Price — within the typical band of similar events (premium goal relaxes the top).
  {
    const price = d.priceVnd || 0;
    const p = b?.price;
    let status = 'good';
    let position = null;
    if (p && price > 0) {
      position = pricePosition(price, p);
      if (position === 'premium' && goal !== 'small_premium') status = 'improve';
    } else if (p && price === 0) {
      position = 'free';
    }
    out.push({
      id: 'price', status, source: p ? 'data' : 'tip', n: p ? p.n : null,
      fix: { step: RECIPE_STEPS.tickets, field: 'price' }, position, median: p?.median ?? null, p25: p?.p25 ?? null, p75: p?.p75 ?? null,
      currency: d.currency === 'USD' ? 'USD' : 'VND',
    });
  }

  // 7. Seats — compared with how many guests similar events actually welcome.
  {
    const seats = d.seats || 0;
    const f = b?.fill;
    let status = seats > 0 ? 'good' : 'missing';
    if (f && seats > 0 && f.median_booked != null) {
      const typical = f.median_booked;
      const limit = goal === 'fill_seats' ? Math.max(typical * 1.5, typical + 5) : Math.max(typical * 2, typical + 10);
      if (seats > limit) status = 'improve';
    }
    out.push({
      id: 'seats', status, source: f ? 'data' : 'tip', n: f ? f.n : null,
      fix: { step: RECIPE_STEPS.tickets, field: 'seats' }, typicalGuests: f?.median_booked ?? null, medianFill: f?.median_fill ?? null,
    });
  }

  // 8. Day & time — this slot's fill vs the best slot, only where both cells cleared the k-threshold.
  {
    if (d.startsAt == null) {
      out.push({ id: 'timing', status: 'missing', source: 'tip', fix: { step: RECIPE_STEPS.when, field: 'date' } });
    } else {
      const { dow, slot } = localParts(d.startsAt, d.timeZone || VN_TIME_ZONE);
      const own = slotCell(b, dow, slot);
      const best = bestSlot(b);
      let status = 'good';
      if (own && best && best.median_fill - own.median_fill > 0.1) status = 'improve';
      out.push({
        id: 'timing', status, source: own ? 'data' : 'tip', n: own ? own.n : null,
        fix: { step: RECIPE_STEPS.when, field: 'date' }, dow, slot,
        ownFill: own?.median_fill ?? null, best: best && (!own || best !== own) ? { dow: best.dow, slot: best.slot, fill: best.median_fill } : null,
      });
    }
  }

  // 9. Lead time — how far ahead well-filled events were submitted.
  {
    const dataDays = b?.well_filled?.median_lead_days;
    const target = dataDays != null ? Math.round(dataDays) : TIP_LEAD_DAYS;
    if (d.startsAt == null) {
      out.push({ id: 'lead', status: 'missing', source: dataDays != null ? 'data' : 'tip', fix: { step: RECIPE_STEPS.when, field: 'date' }, target });
    } else {
      const days = Math.floor((d.startsAt - now) / DAY);
      out.push({
        id: 'lead', status: days >= target ? 'good' : 'improve',
        source: dataDays != null ? 'data' : 'tip', n: dataDays != null ? b.well_filled.n : null,
        fix: { step: RECIPE_STEPS.when, field: 'date' }, days, target,
      });
    }
  }

  // 10. Opening message.
  out.push({
    id: 'greeting', status: (d.chatGreeting || '').trim() ? 'good' : 'improve', source: 'tip',
    fix: { step: RECIPE_STEPS.basics, field: 'greeting' },
  });

  return out;
}

export function recipeScore(checks) {
  const list = checks || [];
  return { good: list.filter(c => c.status === 'good').length, total: list.length };
}

/** Where a paid price sits in the similar-events band. */
export function pricePosition(price, p) {
  if (!p || !(price > 0)) return price === 0 ? 'free' : null;
  if (price < p.p25) return 'below';
  if (price > p.p75) return 'premium';
  return 'typical';
}

/**
 * Turns price × seats into outcomes ("~11 guests, ~3.3M₫"). Uses the similar-events median fill when there
 * is one; otherwise reports the full-house figure and says so (basis: 'full'), never an invented rate.
 */
export function estimateOutcome(priceVnd, seats, medianFill) {
  if (!(seats > 0)) return null;
  const fill = medianFill != null && medianFill > 0 ? Math.min(medianFill, 1) : null;
  const guests = fill != null ? Math.max(1, Math.round(seats * fill)) : seats;
  const price = priceVnd > 0 ? priceVnd : 0;
  return { guests, revenueVnd: guests * price, basis: fill != null ? 'similar' : 'full', fill };
}

// ---- copy (shared wording; T(vi, en) is the caller's translator) ---------------------
const DOW_VI = ['', 'Thứ 2', 'Thứ 3', 'Thứ 4', 'Thứ 5', 'Thứ 6', 'Thứ 7', 'Chủ nhật'];
const DOW_EN = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const SLOT_VI = { afternoon: 'ban ngày', evening: 'buổi tối', late: 'đêm muộn' };
const SLOT_EN = { afternoon: 'daytime', evening: 'evening', late: 'late night' };
export function slotLabel(dow, slot, T) {
  return T(`${DOW_VI[dow]} ${SLOT_VI[slot]}`, `${DOW_EN[dow]} ${SLOT_EN[slot]}`);
}
const pct = (x) => `${Math.round((x || 0) * 100)}%`;
// Draggable price slider over the market histogram (owner, 2026-10-21). The track spans the market's min…max;
// a price outside it pins to the nearer edge. iOS twin: EventRecipe.priceToFraction / fractionToPrice.
export const PRICE_SLIDER_STEP = 10000;
/** Slider step in the currency's minor unit: 10.000₫, or $1 (100 cents). */
export const priceSliderStep = (currency) => (currency === 'USD' ? 100 : PRICE_SLIDER_STEP);

/** Where `v` sits on the market track, 0…1 (null without a usable range). */
export function priceToFraction(v, p) {
  if (!p || p.min == null || p.max == null) return null;
  const span = p.max - p.min;
  if (!(span > 0)) return 0.5;
  return Math.max(0, Math.min(1, (v - p.min) / span));
}

/** The price at track position `f` (0…1), snapped to `step`, kept inside min…max. */
export function fractionToPrice(f, p, step = PRICE_SLIDER_STEP) {
  const lo = p.min; const hi = p.max;
  const raw = lo + Math.max(0, Math.min(1, f)) * (hi - lo);
  const lowest = Math.ceil(lo / step) * step; const highest = Math.floor(hi / step) * step;
  if (lowest > highest) return Math.round(raw); // a market narrower than one step
  return Math.max(lowest, Math.min(highest, Math.round(raw / step) * step));
}

export function formatVndShort(v) {
  if (v == null) return '';
  return formatMoneyShort(v, 'VND');
}

/** { title, detail } for one ingredient. `detail` is the "Why?" text; it names its evidence. */
export function recipeCopy(c, T) {
  const evidence = c.source === 'data' && c.n
    ? T(`Dựa trên ${c.n} sự kiện tương tự.`, `Based on ${c.n} similar events.`)
    : T('Mẹo chung của banbe.', 'General banbe tip.');
  switch (c.id) {
    case 'title':
      return {
        title: T('Tên nói rõ đây là gì', 'A title that says what it is'),
        detail: c.status === 'missing' ? T('Thêm tên sự kiện.', 'Add an event name.')
          : c.shouting ? T('Tránh viết HOA toàn bộ. Khó đọc hơn.', 'Avoid ALL CAPS. It reads harder.')
            : T('3–10 từ, nói rõ khách sẽ làm gì (vd. "Supper club 6 món, Quận 3").', '3–10 words that say what guests will do (e.g. "6-course supper club, District 3").') + ' ' + evidence,
      };
    case 'photos':
      return {
        title: T(`Ít nhất ${c.target} ảnh`, `At least ${c.target} photos`),
        detail: (c.source === 'data'
          ? T(`Sự kiện kín chỗ thường có ${c.target}+ ảnh. Bạn có ${c.have}.`, `Events that filled well had ${c.target}+ photos. You have ${c.have}.`)
          : T(`Ảnh cho khách thấy không khí. Bạn có ${c.have}.`, `Photos show guests the vibe. You have ${c.have}.`)) + ' ' + evidence,
      };
    case 'description':
      return {
        title: T('Mô tả đủ để khách quyết định', 'A description guests can decide on'),
        detail: T(`Khoảng ${c.target}+ ký tự: diễn ra thế nào, dành cho ai, cần mang gì. Hiện có ${c.chars}.`, `About ${c.target}+ characters: how it goes, who it's for, what to bring. Now ${c.chars}.`),
      };
    case 'included':
      return {
        title: T('Ghi rõ những gì bao gồm', "List what's included"),
        detail: (c.share != null
          ? T(`${pct(c.share)} sự kiện kín chỗ có ghi mục bao gồm.`, `${pct(c.share)} of well-filled events listed what's included.`)
          : T('Khách đặt chỗ dễ hơn khi biết giá đã gồm những gì.', 'Guests book more easily when they know what the price covers.')) + ' ' + evidence,
      };
    case 'keywords':
      return {
        title: T('3+ từ khoá tìm kiếm', '3+ search keywords'),
        detail: T('Từ khoá giúp khách tìm thấy bạn trên Bản đồ và Tìm kiếm.', 'Keywords help guests find you in Map and Search.')
          + (c.suggestions?.length ? ' ' + T(`Host khác hay dùng: ${c.suggestions.join(', ')}.`, `Other hosts use: ${c.suggestions.join(', ')}.`) : ''),
      };
    case 'price': {
      const band = c.p25 != null ? `${formatMoneyShort(c.p25, c.currency)}–${formatMoneyShort(c.p75, c.currency)}` : '';
      const title = T('Giá phù hợp', 'A price that fits');
      if (c.source !== 'data') return { title, detail: T('Sự kiện giá thấp thường được đặt sát ngày. Hãy chia sẻ sớm và nhắc lại tuần cuối.', 'Low-priced events tend to book late. Share early and again in the final week.') + ' ' + evidence };
      const pos = {
        free: T('Miễn phí, khách đặt dễ, nhưng tỉ lệ vắng cao hơn.', 'Free, easy to book, but more no-shows.'),
        below: T(`Thấp hơn mức thường gặp (${band}), dễ kín chỗ.`, `Below the typical ${band}, easier to fill.`),
        typical: T(`Trong mức thường gặp ${band}.`, `Within the typical ${band}.`),
        premium: T(`Cao hơn mức thường gặp ${band}. Nói rõ vì sao đáng giá.`, `Above the typical ${band}. Say clearly why it's worth it.`),
      }[c.position] || T(`Mức thường gặp: ${band}.`, `Typical: ${band}.`);
      return { title, detail: pos + ' ' + evidence };
    }
    case 'seats':
      return {
        title: T('Số chỗ vừa sức', 'Seats you can fill'),
        detail: (c.typicalGuests != null
          ? T(`Sự kiện tương tự thường đón khoảng ${c.typicalGuests} khách.`, `Similar events usually welcome about ${c.typicalGuests} guests.`)
          : T('Nhóm nhỏ (10–20) nhanh kín chỗ hơn và tạo cảm giác đông vui.', 'Small groups (10–20) fill sooner and feel lively.')) + ' ' + evidence,
      };
    case 'timing': {
      const title = T('Ngày & giờ', 'Day & time');
      if (c.status === 'missing') return { title, detail: T('Chọn ngày và giờ.', 'Pick a date and time.') };
      if (c.source === 'data') {
        const own = T(`${slotLabel(c.dow, c.slot, T)} thường kín ${pct(c.ownFill)}.`, `${slotLabel(c.dow, c.slot, T)} usually fills ${pct(c.ownFill)}.`);
        const best = c.best ? ' ' + T(`Tốt nhất: ${slotLabel(c.best.dow, c.best.slot, T)} (${pct(c.best.fill)}).`, `Best: ${slotLabel(c.best.dow, c.best.slot, T)} (${pct(c.best.fill)}).`) : '';
        return { title, detail: own + best + ' ' + evidence };
      }
      return { title, detail: T('Tối thứ 6 và thứ 7 thường bán vé tốt nhất, nhưng chênh lệch giữa các ngày không lớn.', 'Friday and Saturday evenings tend to sell best, but the gap between days is small.') + ' ' + evidence };
    }
    case 'lead':
      return {
        title: T(`Đăng trước ${c.target}+ ngày`, `Post ${c.target}+ days ahead`),
        detail: (c.source === 'data'
          ? T(`Sự kiện kín chỗ thường được đăng trước khoảng ${c.target} ngày.`, `Events that filled were posted about ${c.target} days ahead.`)
          : T('Phần lớn vé bán trong tuần cuối, nhưng có thời gian chia sẻ sớm vẫn giúp ích.', 'Most tickets sell in the final week, but time to share early still helps.'))
          + (c.days != null ? ' ' + T(`Còn ${Math.max(c.days, 0)} ngày.`, `${Math.max(c.days, 0)} days to go.`) : '') + ' ' + evidence,
      };
    case 'greeting':
      return {
        title: T('Lời chào khi khách nhắn', 'An opening message'),
        detail: T('Khách nhắn tin hỏi trước khi đặt. Một lời chào sẵn giúp họ yên tâm.', 'Guests often message before booking. A ready greeting reassures them.'),
      };
    default:
      return { title: c.id, detail: '' };
  }
}
