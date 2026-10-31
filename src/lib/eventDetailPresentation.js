// Event Detail presentation rules (note 68, story-first follow-up note 70): the seat status beside the price, how the
// event type's facts are laid out, the place distance, the date tile, the menu section and the photo strip. Pure logic, mirrored by apps/ios/BanbeApp/Lib/EventDetailPresentation.swift through the shared
// tests/fixtures/event-detail-presentation.json (tests: tests/unit/eventDetailPresentation.test.mjs and
// apps/ios/BanbeAppTests/EventDetailPresentationTests.swift) — change both together.

// "N left" turns honey at or under this share of capacity (and never above 2 seats for tiny tables).
export const FEW_SHARE = 0.2;
export const FEW_MIN = 2;

/**
 * The seat status pill beside the price, and the bar ratio (null = no bar).
 * `going` = the viewer holds a ticket; `remaining` = seats still free (null when unknown).
 *   going    → "You're going", no bar
 *   soldOut  → "Sold out", no bar (also when nothing is left but the row has not been marked sold out yet)
 *   few/open → "N left", bar = booked share of capacity when capacity is known and at least one seat is booked
 *              (an unbooked table drew an empty 4pt bar beside "3 left", which read as a contradiction: note 70)
 *   unknown  → the catalogue's own seats text, no bar
 */
export function seatStatus({ capacity = null, remaining = null, soldOut = false, going = false } = {}) {
  if (going) return { kind: 'going', left: remaining, ratio: null };
  if (soldOut || (remaining != null && remaining <= 0)) return { kind: 'soldOut', left: 0, ratio: null };
  if (remaining == null) return { kind: 'unknown', left: null, ratio: null };
  const cap = capacity > 0 ? capacity : null;
  const booked = cap ? cap - remaining : 0;
  const ratio = cap && booked > 0 ? Math.min(1, booked / cap) : null;
  const few = cap ? remaining <= Math.max(FEW_MIN, Math.ceil(cap * FEW_SHARE)) : remaining <= FEW_MIN;
  return { kind: few ? 'few' : 'open', left: remaining, ratio };
}

// Facts that become chips under the tiles (short, icon-led); minimum age becomes a pill beside the category.
export const CHIP_FACTS = ['alcohol', 'dietary'];
export const PILL_FACT = 'min_age';

/**
 * detailFacts() output → { minAge, chips, rows }: minimum age first (a restriction), then icon chips, then the rest.
 * A multi-choice chip fact becomes one chip per choice ("Vegetarian-friendly" · "Can adjust on request", note 70).
 */
export function splitFacts(facts = []) {
  let minAge = null;
  const chips = [], rows = [];
  for (const f of facts) {
    if (f.id === PILL_FACT) minAge = f;
    else if (CHIP_FACTS.includes(f.id)) {
      if (Array.isArray(f.values) && f.values.length > 1) f.values.forEach(v => chips.push({ ...f, value: v, values: [v] }));
      else chips.push(f);
    }
    else rows.push(f);
  }
  chips.sort((a, b) => CHIP_FACTS.indexOf(a.id) - CHIP_FACTS.indexOf(b.id));
  return { minAge, chips, rows };
}

// The About section: its body is the description (else the intro's first paragraph), clamped to 3 lines. The included
// items have their own section ("On the menu" / "Included", note 70). Never a heading with nothing under it.
export const ABOUT_LINES = 3;
export const ABOUT_CLAMP_CHARS = 140; // ~3 lines at 15pt on a 390pt-wide phone

/**
 * { visible, body, clampable, hasSheet }: `clampable` = the body is long enough to clamp, with "Read more" expanding it
 * in place (the sheet never repeats the description); `hasSheet` = the About & Included sheet has an intro or items
 * ("More ›" on the heading opens it).
 */
export function aboutSection({ desc = '', intro = '', includedCount = 0 } = {}) {
  const d = String(desc || '').trim();
  const paragraphs = String(intro || '').split(/\n\s*\n/).map(p => p.trim()).filter(Boolean);
  // The intro's first paragraph stands in only when there is no description; the sheet still shows all of it.
  const body = d || paragraphs[0] || '';
  return {
    visible: body.length > 0,
    body,
    clampable: body.length > ABOUT_CLAMP_CHARS,
    hasSheet: includedCount > 0 || paragraphs.length > 0,
  };
}

/** The included items' own section under About: visible only with at least one item. */
export function includedSection(items = []) {
  const list = (items || []).map(s => String(s || '').trim()).filter(Boolean);
  return { visible: list.length > 0, items: list };
}

// Distance under the place: only when it helps choose (same metro); far away it is noise (a viewer in Europe saw
// "9662,0 km away", note 70).
export const DISTANCE_MAX_KM = 50;

/** "850 m" / "2.4 km" (EN) · "2,4 km" (VI) / "12 km", or null when unknown or farther than DISTANCE_MAX_KM. */
export function distanceLabel(km, en = false) {
  if (km == null || !Number.isFinite(km) || km < 0 || km > DISTANCE_MAX_KM) return null;
  if (km < 1) return `${Math.max(50, Math.round(km * 1000 / 50) * 50)} m`;
  const text = km < 10 ? km.toFixed(1) : String(Math.round(km));
  return `${en ? text : text.replace('.', ',')} km`;
}

const WD_EN = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTH_EN = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/**
 * The date tile in the app's language, from the same "Th 4, 04.11" text the Time tile is split from (`ev.when`, already
 * in the venue's zone), so date and time can never disagree: EN "Wed 4 Nov", VI unchanged. Unrecognised text is
 * returned as is. Note 70: English screens showed "Th 4, 04.11".
 */
export function dateTileLabel(raw, en = false) {
  const text = String(raw || '').trim();
  if (!en) return text;
  const m = text.match(/^(CN|Th ([2-7])),\s*(\d{1,2})\.(\d{1,2})$/);
  if (!m) return text;
  const wd = m[1] === 'CN' ? 0 : Number(m[2]) - 1;
  const month = Number(m[4]);
  if (month < 1 || month > 12) return text;
  return `${WD_EN[wd]} ${Number(m[3])} ${MONTH_EN[month - 1]}`;
}

/** The photo strip under the hero: never the cover again, never the same URL twice. `urlOf` reads a row's URL. */
export function stripPhotos(photos = [], heroUrl = null, urlOf = (p) => p?.url) {
  const seen = new Set(heroUrl ? [heroUrl] : []);
  return (photos || []).filter(p => {
    const u = urlOf(p);
    if (!u || seen.has(u)) return false;
    seen.add(u);
    return true;
  });
}

// Story-first hero (note 70): the title and pills sit on the photo over this bottom scrim (stops as shares of the hero
// height, alpha of near-black). The text band starts at or below `full`, so its weakest backing is `alpha`.
export const HERO_SCRIM = { start: 0.2, full: 0.55, alpha: 0.7, end: 0.78 };

const lin = (c) => { const v = c / 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; };
const lum = ([r, g, b]) => 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);

/** Contrast of white text over the scrim at `alpha` laid on a photo pixel (the worst case is a white photo). */
export function scrimContrast(alpha, pixel = [255, 255, 255], scrim = [12, 10, 8]) {
  const mixed = pixel.map((c, i) => c * (1 - alpha) + scrim[i] * alpha);
  return (1.05) / (lum(mixed) + 0.05);
}
