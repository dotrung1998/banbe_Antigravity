// Event Detail presentation rules (note 68): the seat status beside the price, and how the event type's facts are
// laid out. Pure logic, mirrored by apps/ios/BanbeApp/Lib/EventDetailPresentation.swift through the shared
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
 *   few/open → "N left", bar = booked share of capacity when capacity is known
 *   unknown  → the catalogue's own seats text, no bar
 */
export function seatStatus({ capacity = null, remaining = null, soldOut = false, going = false } = {}) {
  if (going) return { kind: 'going', left: remaining, ratio: null };
  if (soldOut || (remaining != null && remaining <= 0)) return { kind: 'soldOut', left: 0, ratio: null };
  if (remaining == null) return { kind: 'unknown', left: null, ratio: null };
  const cap = capacity > 0 ? capacity : null;
  const ratio = cap ? Math.min(1, Math.max(0, (cap - remaining) / cap)) : null;
  const few = cap ? remaining <= Math.max(FEW_MIN, Math.ceil(cap * FEW_SHARE)) : remaining <= FEW_MIN;
  return { kind: few ? 'few' : 'open', left: remaining, ratio };
}

// Facts that become chips under the tiles (short, icon-led); minimum age becomes a pill beside the category.
export const CHIP_FACTS = ['alcohol', 'dietary'];
export const PILL_FACT = 'min_age';

/** detailFacts() output → { minAge, chips, rows }: minimum age first (a restriction), then icon chips, then the rest. */
export function splitFacts(facts = []) {
  let minAge = null;
  const chips = [], rows = [];
  for (const f of facts) {
    if (f.id === PILL_FACT) minAge = f;
    else if (CHIP_FACTS.includes(f.id)) chips.push(f);
    else rows.push(f);
  }
  chips.sort((a, b) => CHIP_FACTS.indexOf(a.id) - CHIP_FACTS.indexOf(b.id));
  return { minAge, chips, rows };
}

// The About section: its body is the description (else the intro's first paragraph), clamped to 3 lines, then the
// included line. It is never a heading with nothing under it (the old "About … More ›" block for an intro-only event).
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
    visible: body.length > 0 || includedCount > 0,
    body,
    clampable: body.length > ABOUT_CLAMP_CHARS,
    hasSheet: includedCount > 0 || paragraphs.length > 0,
  };
}
